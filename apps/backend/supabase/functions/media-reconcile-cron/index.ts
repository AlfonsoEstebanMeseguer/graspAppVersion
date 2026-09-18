// media-reconcile-cron — Cron job (interno)
//
// Compara el inventario de Cloudflare R2 bajo `avatars/` contra la base de datos y ENCOLA en
// `storage_gc_queue` los objetos que ningún registro referencia. NO BORRA NADA: quien borra sigue
// siendo `media-gc-cron`, con su camino ya probado (reintentos, last_error, idempotencia).
//
// Por qué existe: `storage_gc_queue` solo se alimenta de `profiles.photo_path`, así que un objeto
// subido con una URL prefirmada y nunca confirmado con `profile-avatar-set` no entra jamás en la
// cola y sobrevive al borrado de la cuenta (Art. 17 RGPD).
//
// Quién lo invoca: pg_cron a diario, vía `private.invoke_media_reconcile_cron()`.
// Autorización: token dedicado comparado por hash (`requireInternalCaller`). Lleva verify_jwt = false
// en config.toml porque el token no es un JWT y el gateway lo rechazaría antes de llegar aquí.
// Versión FIJADA, como en el resto de funciones. Estaba como `@3`, un pin flotante que deja que
// una menor del SDK entre sola en producción sin que cambie ningún fichero del repositorio.
import {
  ListObjectsV2Command,
  type ListObjectsV2CommandOutput,
  type S3Client,
} from "npm:@aws-sdk/client-s3@3.614.0";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { createR2Client, requireAvatarBucket } from "../_shared/r2.ts";
import { getServiceRoleClient, requireInternalCaller } from "../_shared/supabase-client.ts";
import {
  decideReconcile,
  DEFAULT_GRACE_HOURS,
  type PagedQueryOutcome,
  type R2Object,
  truncatedSources,
  unknownPrefixes,
} from "../_shared/reconcile.ts";

const AVATARS_PREFIX = "avatars/";

/**
 * Tamaño de página del conjunto referenciado. No puede superar `max_rows` de config.toml (1000):
 * PostgREST recorta ahí en silencio, así que pedir más devolvería lo mismo creyendo que es todo.
 */
const REFERENCED_PAGE_SIZE = 1000;

/** Se resuelve por entorno SOLO porque R2 no deja falsear LastModified y el E2E exigiría esperar 24h
 *  de reloj. En producción la variable no se define. */
function graceHours(): number {
  const raw = Deno.env.get("RECONCILE_GRACE_HOURS");
  if (raw === undefined) return DEFAULT_GRACE_HOURS;

  const parsed = Number(raw);
  const effective = Number.isFinite(parsed) && parsed >= 0 ? parsed : DEFAULT_GRACE_HOURS;

  // Se avisa SIEMPRE que la variable esté definida, no solo cuando vale 0. Es una variable de prueba
  // que solo debería existir en local, y su único guardián era un comentario en el código: si se
  // cuela en producción con valor 0, la ventana entre «el barrido lee la base de datos» y «el usuario
  // confirma la foto» deja de estar protegida y una subida en curso se encola para borrado. Un
  // despliegue así tiene que dejar rastro en los logs desde la primera ejecución.
  console.warn(
    `RECONCILE_GRACE_HOURS definida (valor "${raw}"): gracia efectiva ${effective} h en vez de las ` +
      `${DEFAULT_GRACE_HOURS} h por defecto.` +
      (effective === 0
        ? " CON GRACIA 0 NO HAY PROTECCION para las subidas en curso: esto NO debe estar en produccion."
        : ""),
  );

  return effective;
}

// El cliente lo construye `_shared/r2.ts`, que exige las tres variables de verdad. Aquí se leían
// con `!`, que es una aserción de tipos y no una comprobación: sin `CLOUDFLARE_R2_ENDPOINT` el SDK
// resolvía a Amazon S3 en lugar de fallar, y este cron es el que decide qué se encola para borrar.

/**
 * Prefijos de primer nivel. Delimiter agrupa por "/" y devuelve CommonPrefixes en vez de claves.
 *
 * Pagina igual que `listAvatars`: S3 corta en 1000 entradas y, sin recorrer las páginas, un bucket
 * con más de 1000 prefijos dejaría de reportar los últimos. Esos prefijos no se tocan nunca, así que
 * el daño no es un borrado, sino silencio: el aviso de «hay un tipo de medio sin cablear al barrido»
 * —lo único que delata que los huérfanos de otro bucket no se están mirando— desaparecería del
 * digest sin que nada fallase.
 */
async function listRootPrefixes(s3: S3Client, bucket: string): Promise<string[]> {
  const prefixes: string[] = [];
  let token: string | undefined = undefined;

  do {
    const out: ListObjectsV2CommandOutput = await s3.send(
      new ListObjectsV2Command({ Bucket: bucket, Delimiter: "/", ContinuationToken: token }),
    );
    for (const p of out.CommonPrefixes ?? []) {
      if (p.Prefix) prefixes.push(p.Prefix);
    }
    token = out.IsTruncated ? out.NextContinuationToken : undefined;
  } while (token !== undefined);

  return prefixes;
}

/** Lo que devuelve una página de PostgREST, reducido a lo que este handler necesita. */
interface PhotoPathPage {
  data: { photo_path: string | null }[] | null;
  error: { message: string } | null;
  count: number | null;
}

/**
 * Recorre TODAS las páginas de una consulta de `photo_path` y devuelve, además de las claves, con qué
 * se compara luego el truncamiento: cuántas filas se leyeron de verdad y cuántas decía haber.
 *
 * `rowsFetched` cuenta FILAS, no claves: si alguna viniera con `photo_path` null, contar claves
 * fingiría un truncamiento que no existe y abortaría el barrido cada noche.
 */
async function fetchAllPhotoPaths(
  page: (from: number, to: number) => PromiseLike<PhotoPathPage>,
): Promise<{ paths: string[]; rowsFetched: number; reportedTotal: number | null; error: string | null }> {
  const paths: string[] = [];
  let rowsFetched = 0;
  let reportedTotal: number | null = null;

  for (let from = 0;; from += REFERENCED_PAGE_SIZE) {
    const { data, error, count } = await page(from, from + REFERENCED_PAGE_SIZE - 1);
    if (error) return { paths, rowsFetched, reportedTotal, error: error.message };

    if (count !== null) reportedTotal = count;
    const rows = data ?? [];
    rowsFetched += rows.length;
    for (const row of rows) {
      if (row.photo_path) paths.push(row.photo_path);
    }

    // Una página corta es la última. Si el total es múltiplo exacto del tamaño de página se gasta
    // una petición de más que devuelve 0 filas; es el precio de no fiarse de ningún contador.
    if (rows.length < REFERENCED_PAGE_SIZE) break;
  }

  return { paths, rowsFetched, reportedTotal, error: null };
}

/** Inventario completo bajo avatars/, paginado. Nunca lista fuera de ese prefijo. */
async function listAvatars(s3: S3Client, bucket: string): Promise<R2Object[]> {
  const objects: R2Object[] = [];
  let token: string | undefined = undefined;

  do {
    const out: ListObjectsV2CommandOutput = await s3.send(
      new ListObjectsV2Command({
        Bucket: bucket,
        Prefix: AVATARS_PREFIX,
        ContinuationToken: token,
      }),
    );
    for (const item of out.Contents ?? []) {
      if (item.Key && item.LastModified) {
        objects.push({ key: item.Key, lastModified: new Date(item.LastModified) });
      }
    }
    token = out.IsTruncated ? out.NextContinuationToken : undefined;
  } while (token !== undefined);

  return objects;
}

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    await requireInternalCaller(req);

    const supabase = getServiceRoleClient();
    const bucket = requireAvatarBucket();

    // Se abre la fila ANTES de trabajar: si la función revienta a mitad, queda una fila con
    // finished_at null y el digest la ve como barrido que no terminó.
    const { data: run, error: runError } = await supabase
      .from("media_reconcile_runs")
      .insert({})
      .select("id")
      .single();

    if (runError || !run) {
      console.error("No se pudo abrir la fila de media_reconcile_runs:", runError?.message);
      return jsonResponse({ error: "internal_error", message: "Error interno" }, 500);
    }

    const runId: string = run.id;

    const finish = async (fields: Record<string, unknown>) => {
      const { error } = await supabase
        .from("media_reconcile_runs")
        .update({ ...fields, finished_at: new Date().toISOString() })
        .eq("id", runId);
      if (error) console.error(`No se pudo cerrar la ejecucion ${runId}:`, error.message);
    };

    const s3 = createR2Client();

    // --- Inventario de R2 --------------------------------------------------
    let rootPrefixes: string[];
    let objects: R2Object[];
    try {
      rootPrefixes = await listRootPrefixes(s3, bucket);
      objects = await listAvatars(s3, bucket);
    } catch (e) {
      const reason = e instanceof Error ? e.message : String(e);
      console.error("Fallo al listar R2:", reason);
      await finish({ aborted_reason: `r2_list_failed: ${reason.slice(0, 200)}` });
      return jsonResponse({ run_id: runId, aborted_reason: "r2_list_failed" }, 200);
    }

    const unknown = unknownPrefixes(rootPrefixes);
    if (unknown.length > 0) {
      // No se tocan: son medios de otra fase que nadie ha cableado a este barrido.
      console.warn("Prefijos desconocidos en el bucket, NO se reconcilian:", unknown.join(", "));
    }

    // --- Conjunto referenciado --------------------------------------------
    // F1 del freno: si cualquiera de estas consultas falla, un conjunto incompleto convertiría
    // fotos vivas en huérfanas. Se aborta sin encolar.
    //
    // Las dos van PAGINADAS y piden el total exacto. Una consulta sin rango la recorta PostgREST en
    // `max_rows` (1000, config.toml) devolviendo `error: null`: el conjunto llega incompleto, las
    // fotos que se quedaron fuera parecen huérfanas y `media-gc-cron` las borra de R2 en 5 minutos.
    // El inventario de R2 sí se paginaba desde el principio, así que el descuadre solo aparecía en
    // el lado de Postgres y ningún freno lo veía (ver `truncatedSources` en _shared/reconcile.ts).
    // `.order("photo_path")` NO es cosmético: sin un orden determinista, Postgres no garantiza que dos
    // consultas OFFSET/LIMIT separadas vean las filas en el mismo orden. Un UPDATE concurrente (este
    // proyecto toca `profiles` constantemente: level, xp, contadores), una reubicación HOT o autovacuum
    // entre una página y la siguiente puede hacer que una fila aparezca en dos páginas y otra en
    // ninguna. `truncatedSources()` no lo detecta: un salto más un duplicado cuadran el mismo total, y
    // el `Set` que dedup deja el conjunto referenciado corto en una clave — cuyo avatar vivo se encola y
    // se borra sin que ningún freno lo vea venir. No "limpiar" este `.order()` aunque parezca redundante
    // (ver `.claude/skills/supabase-postgres-best-practices/SKILL.md`, que empareja todo ejemplo de
    // OFFSET con un orden explícito por esta misma razón).
    const profilesPage = await fetchAllPhotoPaths((from, to) =>
      supabase
        .from("profiles")
        .select("photo_path", { count: "exact" })
        .not("photo_path", "is", null)
        .order("photo_path")
        .range(from, to)
    );

    const queuePage = await fetchAllPhotoPaths((from, to) =>
      supabase
        .from("storage_gc_queue")
        .select("photo_path", { count: "exact" })
        .in("status", ["pending", "failed"])
        .order("photo_path")
        .range(from, to)
    );

    if (profilesPage.error || queuePage.error) {
      const reason = profilesPage.error ?? queuePage.error ?? "desconocido";
      console.error("Fallo al construir el conjunto referenciado:", reason);
      await finish({
        objects_scanned: objects.length,
        aborted_reason: "query_failed",
        unknown_prefixes: unknown,
      });
      return jsonResponse({ run_id: runId, aborted_reason: "query_failed" }, 200);
    }

    const outcomes: PagedQueryOutcome[] = [
      {
        source: "profiles",
        rowsFetched: profilesPage.rowsFetched,
        reportedTotal: profilesPage.reportedTotal,
      },
      {
        source: "storage_gc_queue",
        rowsFetched: queuePage.rowsFetched,
        reportedTotal: queuePage.reportedTotal,
      },
    ];
    const truncated = truncatedSources(outcomes);

    // Las filas 'deleted' se excluyen a propósito: si una clave marcada como borrada sigue en R2,
    // el borrado no surtió efecto y merece volver a la cola.
    const referenced = new Set<string>([...profilesPage.paths, ...queuePage.paths]);

    if (truncated.length > 0) {
      console.error(
        `Conjunto referenciado incompleto en: ${truncated.join(", ")} ` +
          `(profiles ${profilesPage.rowsFetched}/${profilesPage.reportedTotal}, ` +
          `storage_gc_queue ${queuePage.rowsFetched}/${queuePage.reportedTotal}). ` +
          "NO se ha encolado nada: cada fila que falta convierte una foto viva en huerfana.",
      );
    }

    // --- Decisión (pura, testeada en _shared/reconcile_test.ts) -------------
    // El truncamiento entra como freno (F5) en vez de cortar aquí: así el único sitio que decide si
    // se encola sigue siendo la función pura, y la garantía de "abortar ⇒ enqueue vacío" es la misma
    // que ya cubren los tests para F2, F3 y F4.
    const decision = decideReconcile({
      objects,
      referenced,
      now: new Date(),
      graceHours: graceHours(),
      referencedTruncated: truncated.length > 0,
    });

    if (decision.abortedReason !== null) {
      console.error(
        `Freno de emergencia: ${decision.abortedReason} ` +
          `(escaneados=${decision.objectsScanned}, huerfanos=${decision.orphansFound}, ` +
          `referenciados=${referenced.size}). NO se ha encolado nada.`,
      );
      await finish({
        objects_scanned: decision.objectsScanned,
        orphans_found: decision.orphansFound,
        aborted_reason: decision.abortedReason,
        unknown_prefixes: unknown,
      });
      return jsonResponse(
        {
          run_id: runId,
          objects_scanned: decision.objectsScanned,
          orphans_found: decision.orphansFound,
          orphans_enqueued: 0,
          aborted_reason: decision.abortedReason,
          // Vacío salvo con `referenced_set_truncated`: dice QUÉ consulta se leyó a medias, que es lo
          // primero que hay que mirar y lo que `aborted_reason` por sí solo no cuenta.
          truncated_sources: truncated,
          unknown_prefixes: unknown,
        },
        200,
      );
    }

    // Pasada ACOTADA (H-S-03): no es un aborto — se encola el tope y el resto espera a mañana. Se
    // registra como error y no como aviso porque, si se repite día tras día, significa que los
    // huérfanos entran más deprisa de lo que el barrido los drena, y eso ya no se corrige solo.
    if (decision.cappedReason !== null) {
      console.error(
        `Pasada ACOTADA por ${decision.cappedReason}: encolados los ${decision.enqueue.length} ` +
          `mas antiguos de ${decision.orphansFound} huerfanos (escaneados=${decision.objectsScanned}). ` +
          "El resto se reintenta en la proxima pasada.",
      );
    }

    if (decision.malformedKeys.length > 0) {
      console.warn(
        "Claves huerfanas sin user_id valido (no se encolan):",
        decision.malformedKeys.join(", "),
      );
    }

    // --- Encolar -----------------------------------------------------------
    let enqueued = 0;
    if (decision.enqueue.length > 0) {
      const { error: insertError } = await supabase.from("storage_gc_queue").insert(
        decision.enqueue.map((o) => ({
          user_id: o.userId,
          photo_path: o.key,
          status: "pending",
        })),
      );

      if (insertError) {
        console.error("No se pudieron encolar los huerfanos:", insertError.message);
        await finish({
          objects_scanned: decision.objectsScanned,
          orphans_found: decision.orphansFound,
          aborted_reason: "enqueue_failed",
          unknown_prefixes: unknown,
        });
        return jsonResponse({ run_id: runId, aborted_reason: "enqueue_failed" }, 200);
      }
      enqueued = decision.enqueue.length;
    }

    await finish({
      objects_scanned: decision.objectsScanned,
      orphans_found: decision.orphansFound,
      orphans_enqueued: enqueued,
      capped_reason: decision.cappedReason,
      unknown_prefixes: unknown,
    });

    return jsonResponse(
      {
        run_id: runId,
        objects_scanned: decision.objectsScanned,
        orphans_found: decision.orphansFound,
        orphans_enqueued: enqueued,
        malformed_keys: decision.malformedKeys,
        unknown_prefixes: unknown,
        aborted_reason: null,
        capped_reason: decision.cappedReason,
      },
      200,
    );
  } catch (err) {
    return errorResponse(err);
  }
});
