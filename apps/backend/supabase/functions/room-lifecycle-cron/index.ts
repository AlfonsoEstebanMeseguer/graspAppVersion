// room-lifecycle-cron — Cron job (interno)
//
// Cierra las salas de voz muertas sin que nadie intervenga (Fase 5, Tarea 5): 2h alcanzadas
// ('expired'), vacía 10 min ('empty'), sin actividad 10 min ('idle'). Toda la lógica de negocio —
// qué sala se cierra y por qué, incluido el reloj de cada condición — vive en la función de
// Postgres `room_lifecycle_sweep(p_limit)` (20260901130000_rooms_cron.sql), la misma autoridad
// que ya usan las siete funciones de escritura de `room-actions` (aforo dentro de la transacción
// que escribe). Esta función solo autentica al llamador, invoca el RPC con `service_role` y
// traduce la respuesta.
//
// El borrado de los mensajes de una sala terminada NO ocurre aquí: vive en un TRIGGER sobre
// `rooms` (`room_messages_purge_on_end`, misma migración), porque una sala también puede morir
// por `room_leave` (host ausente) o `room_end` (el host termina) — ninguno de los cuales pasa por
// este cron. Un borrado colocado aquí solo cubriría uno de los tres caminos.
//
// Quién lo invoca: pg_cron cada minuto, vía `private.invoke_room_lifecycle_cron()`
// (20260901130000_rooms_cron.sql). NO se programa desde config.toml: esa clave no existe en el
// CLI y su presencia rompía `supabase db reset` (mismo precedente que `media-gc-cron`).
//
// Autorización: token dedicado comparado por SHA-256 (`requireInternalCaller`). NO se usa la
// `service_role key` para autenticar la llamada entrante (su contenido lo decide la plataforma y
// puede cambiar sin avisar, como ya le pasó a `media-gc-cron` el 2026-08-10) ni `verify_jwt` (lo
// cumple igual la `anon key`, embebida en la app — no distingue al cron de un usuario cualquiera).
// `service_role` sí se usa, pero SOLO para llamar al RPC una vez ya autenticado el llamador.
//
// Idempotente: `room_lifecycle_sweep` solo toca filas con `status = 'live'`; repetir una pasada
// sobre una sala ya cerrada no hace nada (no vuelve a escribir `ended_at`/`ended_reason`, el
// `where r.status = 'live'` de la CTE la excluye).
//
// El freno ACOTA, no aborta: si hay más salas que cerrar de las que caben en `p_limit`, el RPC
// procesa el tope y devuelve `capped: true`; esta función nunca reintenta ni agranda el lote — la
// siguiente pasada (un minuto después) recoge el resto.
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireInternalCaller } from "../_shared/supabase-client.ts";

const SWEEP_LIMIT = 200;

interface SweepRow {
  closed: number;
  capped: boolean;
}

interface CronResponse {
  /** Salas cerradas en esta pasada. */
  closed: number;
  /** true si había más salas vencidas de las que caben en el lote — la próxima pasada sigue. */
  capped: boolean;
}

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    // POST y no GET: la llamada muta estado (cierra salas, escribe `left_at`). Un GET que muta es
    // reintentable por cualquier proxy o precargador.
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    await requireInternalCaller(req);

    const supabase = getServiceRoleClient();

    const { data, error } = await supabase
      .rpc("room_lifecycle_sweep", { p_limit: SWEEP_LIMIT })
      .single();

    if (error) {
      console.error("room_lifecycle_sweep failed:", error);
      return jsonResponse(
        { error: "internal_error", message: "No se pudo barrer las salas" },
        500,
      );
    }

    const row = data as SweepRow;
    const response: CronResponse = { closed: row.closed, capped: row.capped };

    return jsonResponse(response, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
