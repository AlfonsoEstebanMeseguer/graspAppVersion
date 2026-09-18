// ops-digest-cron — Cron job (interno)
//
// Consulta el estado del GC de medios y manda un email si hay incidencias o si es lunes (latido).
// No toca R2 ni borra nada: solo lee Postgres y escribe un correo.
//
// Por qué existe: `storage_gc_queue.status = 'failed'` es TERMINAL y significa un incumplimiento de
// RGPD activo, pero su única observabilidad era una consulta SQL escrita en un comentario de
// migración, que exige que alguien se acuerde de ejecutarla.
//
// Quién lo invoca: pg_cron a diario, vía `private.invoke_ops_digest_cron()`. Además acepta
// `{"force": true}` para enviar el correo ignorando la decisión: es el paso de despliegue que
// prueba que el canal de Resend funciona (ver la sección de despliegue del plan).
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireInternalCaller } from "../_shared/supabase-client.ts";
import {
  AUDIT_STALE_DAYS,
  type DigestFacts,
  MAX_SAMPLE_ROWS,
  renderDigest,
  shouldSend,
  STALE_PENDING_HOURS,
} from "../_shared/digest.ts";

const RESEND_ENDPOINT = "https://api.resend.com/emails";

/**
 * Tope de ejecuciones que se suman para el contador de encolados. El barrido es diario: 200 filas
 * cubren 200 días o un bucle de reintentos absurdo. Si alguna vez se alcanzara, la suma sería una
 * cota inferior — nunca un cero engañoso, que es lo único que había que evitar.
 */
const RUNS_24H_LIMIT = 200;

/**
 * Lee `{"force": true}` del body. Tolerante a propósito: `pg_cron` manda `{"invoked_at": ...}` y un
 * despliegue puede invocarla sin body; ninguno de esos casos debe romper el digest.
 */
async function readForceFlag(req: Request): Promise<boolean> {
  try {
    const body = await req.json();
    return body !== null && typeof body === "object" && (body as { force?: unknown }).force === true;
  } catch {
    return false;
  }
}

async function sendEmail(subject: string, text: string): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const to = Deno.env.get("OPS_ALERT_EMAIL");
  // `onboarding@resend.dev` es el remitente de pruebas de Resend: no exige verificar un dominio,
  // pero solo entrega al email del titular de la cuenta. Suficiente para alertas de operación.
  const from = Deno.env.get("OPS_ALERT_FROM") ?? "Grasp Ops <onboarding@resend.dev>";

  // Falla cerrado y ruidoso: un digest que no puede enviar debe constar como error, no salir en 200.
  if (!apiKey || !to) {
    throw new AppError(500, "internal_error", "Error interno");
  }

  const res = await fetch(RESEND_ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from, to: [to], subject, text }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Resend devolvio ${res.status}: ${body.slice(0, 300)}`);
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    await requireInternalCaller(req);

    // Envío forzado, SIEMPRE detrás de `requireInternalCaller`: sin el token del cron no se llega
    // hasta aquí, así que nadie de fuera puede usarlo para llenar la bandeja de alertas.
    //
    // POR QUÉ EXISTE
    // El día del despliegue, si todo está sano y no es lunes, esta función responde
    // `200 {"sent":false}` sin tocar Resend: no prueba absolutamente nada del canal de correo. Si la
    // clave estuviera mal, el fallo aparecería semanas después como un 500 dentro de
    // `net._http_response`, que no lee nadie. Y el latido de los lunes solo funciona como señal para
    // quien ya ha recibido un correo antes: no se puede echar en falta lo que nunca llegó.
    const forced = await readForceFlag(req);

    if (!Deno.env.get("RESEND_API_KEY") || !Deno.env.get("OPS_ALERT_EMAIL")) {
      console.error("RESEND_API_KEY u OPS_ALERT_EMAIL ausentes: el digest no puede avisar de nada");
      throw new AppError(500, "internal_error", "Error interno");
    }

    const supabase = getServiceRoleClient();
    const now = new Date();
    const stalePendingCutoff = new Date(now.getTime() - STALE_PENDING_HOURS * 3600_000).toISOString();
    const abortedCutoff = new Date(now.getTime() - 24 * 3600_000).toISOString();
    const auditStaleCutoff = new Date(
      now.getTime() - AUDIT_STALE_DAYS * 24 * 3600_000,
    ).toISOString();

    const results = await Promise.all([
      supabase
        .from("storage_gc_queue")
        .select("id, photo_path, last_error, created_at", { count: "exact" })
        .eq("status", "failed")
        .order("created_at", { ascending: true })
        .limit(MAX_SAMPLE_ROWS),
      supabase
        .from("storage_gc_queue")
        .select("created_at", { count: "exact" })
        .eq("status", "pending")
        .lt("created_at", stalePendingCutoff)
        .order("created_at", { ascending: true })
        .limit(1),
      supabase
        .from("media_reconcile_runs")
        .select("finished_at")
        .is("aborted_reason", null)
        .not("finished_at", "is", null)
        .order("finished_at", { ascending: false })
        .limit(1),
      supabase
        .from("media_reconcile_runs")
        .select("started_at, aborted_reason")
        .not("aborted_reason", "is", null)
        .gte("started_at", abortedCutoff)
        .order("started_at", { ascending: false })
        .limit(MAX_SAMPLE_ROWS),
      // Pasadas ACOTADAS (H-S-03). Van en su propia consulta y no filtradas del bloque de abortadas
      // porque son estados excluyentes en la fila y significan cosas opuestas: una abortada no hizo
      // nada, una acotada sí drenó trabajo. Misma ventana que las abortadas para que el correo hable
      // siempre del mismo periodo.
      supabase
        .from("media_reconcile_runs")
        .select("started_at, capped_reason, orphans_found, orphans_enqueued")
        .not("capped_reason", "is", null)
        .gte("started_at", abortedCutoff)
        .order("started_at", { ascending: false })
        .limit(MAX_SAMPLE_ROWS),
      supabase
        .from("media_reconcile_runs")
        .select("unknown_prefixes")
        .order("started_at", { ascending: false })
        .limit(1),
      // SUMA de las 24 h, no el `orphans_enqueued` de la última ejecución. Con la última bastaría
      // mientras haya exactamente un barrido al día, pero una invocación manual posterior —o un
      // segundo barrido tras un fallo— dejaría una fila con 0 encima y taparía la cifra de la
      // ejecución que sí borró. La ventana es la misma que la de los abortados, así que el correo
      // habla siempre del mismo periodo.
      supabase
        .from("media_reconcile_runs")
        .select("orphans_enqueued")
        .gte("started_at", abortedCutoff)
        .limit(RUNS_24H_LIMIT),
      // Solo se pide `created_at`: es la única columna sobre la que `service_role` tiene SELECT
      // (grant de columna en 20260812090000). Pedir `*` daría "permission denied", y con razón: el
      // backend no tiene por qué poder leer el user_id de la tabla de auditoría.
      supabase
        .from("photo_audit_log")
        .select("created_at", { count: "exact" })
        .lt("created_at", auditStaleCutoff)
        .limit(1),
      // ADR 0030: cuántos perfiles son elegibles para Conectar, para vigilar qué fracción cabe en
      // una muestra de `MAX_POOL`. `head: true` porque solo interesa el recuento: no se trae ni una
      // fila, y menos aún un `user_id` — este correo sale hacia una bandeja.
      //
      // El `tag not null` es el mismo criterio que usa `connect_eligible_sample`: si contara los
      // perfiles a secas, incluiría a quien no ha terminado el alta y el número vigilado sería otro
      // distinto del que aplica el feed.
      supabase
        .from("profiles")
        .select("user_id", { count: "exact", head: true })
        .not("tag", "is", null),
    ]);

    const [failed, stale, lastSweep, aborted, capped, lastRun, runs24h, auditStale, eligible] =
      results;

    const firstError = failed.error ?? stale.error ?? lastSweep.error ?? aborted.error ??
      capped.error ?? lastRun.error ?? runs24h.error ?? auditStale.error ?? eligible.error;
    if (firstError) {
      console.error("El digest no pudo leer el estado:", firstError.message);
      throw new AppError(500, "internal_error", "Error interno");
    }

    // `auditStale.count` es la UNICA senal de esta consulta: se pide `.limit(1)` a proposito y el
    // `data` que trae se descarta, así que no hay fila de muestra que sirva de testigo — a
    // diferencia de `failedCount`/`stalePendingCount`, que tienen `failed.data`/`stale.data` de
    // respaldo si el conteo alguna vez desentona. Un `count: null` sin `error` (PostgREST lo devuelve
    // así si la cabecera `Prefer: count=exact` no llega a aplicarse) es el UNICO camino por el que
    // "la retencion se rompio" podria leerse como "0 filas sin purgar" en el correo: precisamente el
    // fallo silencioso que esta señal existe para evitar. Se trata como fallo cerrado, no como cero.
    if (auditStale.count === null) {
      console.error("El digest no pudo contar photo_audit_log: count vino null sin error");
      throw new AppError(500, "internal_error", "Error interno");
    }

    const facts: DigestFacts = {
      failedCount: failed.count ?? 0,
      failedOldest: failed.data?.[0] ? new Date(failed.data[0].created_at as string) : null,
      failedSamples: (failed.data ?? []).map((r) => ({
        id: r.id as string,
        photoPath: r.photo_path as string,
        lastError: (r.last_error as string | null) ?? null,
      })),
      stalePendingCount: stale.count ?? 0,
      stalePendingOldest: stale.data?.[0]
        ? new Date(stale.data[0].created_at as string)
        : null,
      lastSuccessfulSweepAt: lastSweep.data?.[0]?.finished_at
        ? new Date(lastSweep.data[0].finished_at as string)
        : null,
      abortedRuns: (aborted.data ?? []).map((r) => ({
        startedAt: new Date(r.started_at as string),
        reason: r.aborted_reason as string,
      })),
      cappedRuns: (capped.data ?? []).map((r) => ({
        startedAt: new Date(r.started_at as string),
        reason: r.capped_reason as string,
        orphansFound: (r.orphans_found as number | null) ?? 0,
        orphansEnqueued: (r.orphans_enqueued as number | null) ?? 0,
      })),
      unknownPrefixes: (lastRun.data?.[0]?.unknown_prefixes as string[] | null) ?? [],
      orphansEnqueued: (runs24h.data ?? []).reduce(
        (total, r) => total + ((r.orphans_enqueued as number | null) ?? 0),
        0,
      ),
      // Sin `?? 0`: si `auditStale.count` fuera null, el guard de arriba ya habria lanzado el 500
      // antes de llegar aqui. Poner un `?? 0` aqui otra vez volveria a esconder ese caso.
      staleAuditRows: auditStale.count,
      // `?? 0` aquí SÍ, y no es el caso de `staleAuditRows`: un recuento ausente se traduce a «base
      // vacía», que da cobertura 1 y **no dispara nada**. Fallar hacia el silencio es lo correcto
      // para una señal que solo pide replantear un número: una alerta falsa diaria se deja de leer,
      // y con ella se dejarían de leer las de verdad. El caso contrario —una base que crece sin
      // avisar— lo cubre el latido de los lunes, que trae este número todas las semanas.
      eligibleProfiles: eligible.count ?? 0,
    };

    if (!forced && !shouldSend(facts, now)) {
      return jsonResponse({ sent: false, forced: false, subject: null }, 200);
    }

    const { subject, text } = renderDigest(facts, now);
    await sendEmail(subject, text);

    return jsonResponse({ sent: true, forced, subject }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
