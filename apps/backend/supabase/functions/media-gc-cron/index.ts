// media-gc-cron — Cron job (interno)
//
// Drena `storage_gc_queue`: coge las filas con status='pending', borra cada objeto de Cloudflare
// R2 y marca la fila como 'deleted' o 'failed'. Es el último eslabón de la cascada de borrado
// exigida por la Sección 24 del documento maestro — sin él, los objetos de R2 sobreviven al
// borrado de la cuenta y el RGPD no se cumple.
//
// Quién lo invoca: pg_cron cada 5 minutos, vía `private.invoke_media_gc_cron()`
// (migración 20260810120000_schedule_media_gc_cron.sql). NO se programa desde config.toml: esa
// clave no existe en el CLI y su presencia rompía `supabase db reset`.
//
// Autorización: token dedicado comparado por SHA-256 (`requireInternalCaller`). NO se usa la
// `service_role key`: su contenido lo decide la plataforma y cambió solo el 2026-08-10, tumbando el
// cron con 401 sin que nadie tocara el código. Ver 20260810170000.
//
// Idempotente: cada fila se relee por status antes de tocarla, así que repetir una ejecución no
// borra nada dos veces de forma observable. Lote máximo de 100 filas para no agotar el tiempo.
// Versión FIJADA, como en el resto de funciones. Estaba como `@3`, que es un pin flotante: el día
// que el SDK publique una menor con otro comportamiento, esta función lo estrena sola y en
// producción, sin que ningún fichero del repositorio cambie. Precedente en el propio SDK: que
// `content-type` esté en `unsignableHeaders` es una decisión suya, no del protocolo.
import { DeleteObjectCommand } from "npm:@aws-sdk/client-s3@3.614.0";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { createR2Client, requireAvatarBucket } from "../_shared/r2.ts";
import { getServiceRoleClient, requireInternalCaller } from "../_shared/supabase-client.ts";

// Tras 5 intentos (≈25 minutos con el cron cada 5) la fila pasa a 'failed', que es
// TERMINAL: nada la vuelve a tocar y necesita que la mire una persona. Ver la cabecera de
// 20260810150000_add_retry_to_storage_gc_queue.sql.
const MAX_ATTEMPTS = 5;
const BATCH_SIZE = 100;

interface StorageGcQueueItem {
  id: string;
  photo_path: string;
  attempts: number;
}

interface CronResponse {
  /** Objetos efectivamente borrados de R2 en esta pasada. */
  deleted: number;
  /** Filas cogidas del lote. */
  attempted: number;
  /** Filas que han agotado los reintentos y quedan en 'failed' (incumplimiento activo). */
  failed: number;
  /** Filas que han fallado pero siguen en 'pending' y se reintentarán. */
  retrying: number;
}

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    // POST y no GET: la llamada muta estado (borra objetos de R2 y reescribe la cola). Un GET
    // que muta es reintentable por cualquier proxy o precargador.
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    await requireInternalCaller(req);

    const supabase = getServiceRoleClient();

    // Las más antiguas primero: son las que llevan más tiempo incumpliendo el borrado.
    const { data: items, error: queryError } = await supabase
      .from("storage_gc_queue")
      .select("id, photo_path, attempts")
      .eq("status", "pending")
      .order("created_at", { ascending: true })
      .limit(BATCH_SIZE);

    if (queryError) {
      console.error("Failed to query storage_gc_queue:", queryError);
      return jsonResponse(
        { error: "internal_error", message: "No se pudo consultar storage_gc_queue" },
        500,
      );
    }

    if (!items || items.length === 0) {
      return jsonResponse({ deleted: 0, attempted: 0, failed: 0, retrying: 0 }, 200);
    }

    // Las cuatro variables se exigen de verdad (`_shared/r2.ts`). Antes se leían con `!`, que no
    // comprueba nada: sin `CLOUDFLARE_R2_ENDPOINT` el SDK no fallaba, resolvía a Amazon S3. En la
    // función que borra ficheros.
    const s3Client = createR2Client();
    const bucketName = requireAvatarBucket();
    let deleted = 0;
    let failed = 0;
    let retrying = 0;

    for (const item of items as StorageGcQueueItem[]) {
      try {
        // DeleteObject de S3/R2 es idempotente: borrar una clave que ya no está
        // devuelve 204, no error. Por eso repetir una pasada es seguro.
        await s3Client.send(
          new DeleteObjectCommand({ Bucket: bucketName, Key: item.photo_path }),
        );

        const { error: updateError } = await supabase
          .from("storage_gc_queue")
          .update({ status: "deleted", last_attempt_at: new Date().toISOString() })
          .eq("id", item.id);

        // El objeto ya no está en R2 aunque no hayamos podido anotarlo. Se cuenta como
        // borrado; la fila se queda en 'pending' y la próxima pasada la cerrará (el
        // borrado repetido no falla, ver arriba).
        if (updateError) {
          console.error(`No se pudo marcar ${item.id} como deleted:`, updateError.message);
        }
        deleted++;
      } catch (e) {
        const reason = e instanceof Error ? e.message : String(e);
        const attempts = (item.attempts ?? 0) + 1;
        const exhausted = attempts >= MAX_ATTEMPTS;

        console.error(
          `Fallo al borrar ${item.photo_path} de R2 (intento ${attempts}/${MAX_ATTEMPTS}):`,
          reason,
        );

        const { error: updateError } = await supabase
          .from("storage_gc_queue")
          .update({
            // Solo se marca 'failed' al agotar los reintentos. Marcarlo al primer fallo
            // era el bug: la fila quedaba fuera del alcance del cron para siempre y el
            // objeto sobrevivía en R2 sin que nada avisara.
            status: exhausted ? "failed" : "pending",
            attempts,
            last_error: reason.slice(0, 500),
            last_attempt_at: new Date().toISOString(),
          })
          .eq("id", item.id);

        if (updateError) {
          console.error(`Tampoco se pudo anotar el fallo de ${item.id}:`, updateError.message);
        }

        if (exhausted) {
          // Una fila terminal es un objeto de R2 que sobrevive al borrado de la cuenta:
          // incumplimiento de RGPD activo, no una anomalía menor.
          console.error(
            `AGOTADOS los reintentos de ${item.photo_path}: sigue en R2 y ya no se reintentará.`,
          );
          failed++;
        } else {
          retrying++;
        }
      }
    }

    const response: CronResponse = {
      deleted,
      attempted: items.length,
      failed,
      retrying,
    };

    return jsonResponse(response, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
