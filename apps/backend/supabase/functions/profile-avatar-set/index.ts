// profile-avatar-set — HTTP (app)
//
// Fija el avatar del usuario, que es UNA de dos cosas excluyentes:
//   · `{ photo_path }` — una foto suya ya subida a R2 (confirma la subida);
//   · `{ preset }`     — uno de los 8 avatares predeterminados, que son assets locales de Flutter
//                        y NO existen en R2.
//
// Antes se llamaba `profile-photo-update` y solo sabía de fotos. Se renombró al añadir los
// predeterminados porque **una sola función tiene que ser dueña del invariante**: si la
// exclusividad la pudieran romper dos endpoints distintos, habría dos sitios donde violarla, y el
// que encola la foto vieja para borrarla es este.
//
// POR QUÉ ELEGIR UN PRESET BORRA LA FOTO
// No es limpieza: es privacidad. En una app de apoyo entre iguales, quien cambia su cara por un
// dibujo casi siempre lo hace para dejar de enseñarla. Conservarle la foto viva en R2 traicionaría
// esa intención y guardaría un dato personal que creía haber quitado.
//
// Seguridad: exige JWT. La clave se comprueba contra `avatars/{user_id}/` antes de escribirla — es
// lo único que impide reclamar la clave de otro, y `profile-photo-view-url` se apoya en ello para
// firmar. Usa `service_role` para escribir en `profiles`, `photo_audit_log` y `storage_gc_queue`.
import { GetObjectCommand } from "npm:@aws-sdk/client-s3@3.614.0";
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { createR2Client, requireAvatarBucket } from "../_shared/r2.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { assertPathOwnership, parseAvatarRequest } from "../_shared/avatar-set.ts";
import { assertValidImageBytes, formatFromPath } from "../_shared/image-format.ts";
import { MAX_FILE_SIZE } from "../_shared/photo-upload.ts";

interface AvatarSetResponse {
  success: boolean;
  /** Clave de la foto que queda desplazada, ya encolada para borrado. `null` si no había. */
  old_path: string | null;
}

/**
 * Descarga el objeto recién subido para poder mirarlo.
 *
 * Se lee entero y no solo la cabecera: son ≤200 KB (el `PUT` se firmó con ese `ContentLength`, así
 * que R2 lo impone) y en un JPEG el marcador SOF puede caer más allá del primer KB, de modo que un
 * `Range` corto se quedaría sin dimensiones en ficheros perfectamente válidos.
 */
async function fetchUploadedBytes(photoPath: string): Promise<Uint8Array> {
  const s3Client = createR2Client();

  let result;
  try {
    result = await s3Client.send(
      new GetObjectCommand({ Bucket: requireAvatarBucket(), Key: photoPath }),
    );
  } catch (err) {
    // Confirmar una clave a la que nunca se subió nada es culpa del cliente (400), no nuestra.
    // Antes de 0013 esto escribía en `photo_path` una clave que no apunta a ningún objeto.
    const name = (err as { name?: string }).name ?? "";
    if (name === "NoSuchKey" || name === "NotFound") {
      throw new AppError(400, "invalid_input", "No hay ningún objeto subido en esa clave", {
        field: "photo_path",
      });
    }
    throw new AppError(500, "internal_error", "No se pudo leer el objeto de R2", {
      cause: name || String(err),
    });
  }

  if ((result.ContentLength ?? 0) > MAX_FILE_SIZE) {
    throw new AppError(400, "invalid_input", `El objeto excede ${MAX_FILE_SIZE / 1024} KB`, {
      field: "photo_path",
    });
  }

  if (!result.Body) {
    throw new AppError(500, "internal_error", "R2 devolvió un objeto sin cuerpo");
  }

  return await result.Body.transformToByteArray();
}

/** Encola un objeto para que `media-gc-cron` lo borre. Best-effort, como el resto de la cola. */
async function queueForGc(
  // deno-lint-ignore no-explicit-any
  service: any,
  userId: string,
  photoPath: string,
): Promise<void> {
  const { error } = await service
    .from("storage_gc_queue")
    .insert({ user_id: userId, photo_path: photoPath, status: "pending" });
  if (error) {
    console.warn("Failed to queue photo for GC:", error.message);
  }
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    const { userId } = await requireAuthUser(req);

    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      throw new AppError(400, "invalid_input", "Body no es JSON válido");
    }

    const request = parseAvatarRequest(rawBody);
    const service = getServiceRoleClient();

    // VALIDACIÓN DE LOS BYTES (decisión 0013). Solo en el camino de la foto: elegir un avatar
    // predeterminado no toca R2, porque los predeterminados son assets locales de Flutter.
    //
    // Va ANTES de escribir nada: si los bytes no son una imagen del formato que declara la clave,
    // `photo_path` no se toca y el objeto se encola para que el barrido lo borre. Fallar aquí deja
    // el perfil exactamente como estaba.
    if (request.kind === "photo") {
      assertPathOwnership(request.photoPath, userId);

      const declaredFormat = formatFromPath(request.photoPath);
      if (declaredFormat === null) {
        // No debería llegar: `parseAvatarRequest` ya lo filtra. Se comprueba igual porque de aquí
        // en adelante el formato se da por conocido.
        throw new AppError(400, "invalid_input", "photo_path con extensión no admitida", {
          field: "photo_path",
        });
      }

      const bytes = await fetchUploadedBytes(request.photoPath);
      try {
        assertValidImageBytes(bytes, declaredFormat);
      } catch (err) {
        await queueForGc(service, userId, request.photoPath);
        throw err;
      }
    }

    // Paso 1: la foto que había, para encolarla si queda desplazada.
    const { data: profile, error: selectError } = await service
      .from("profiles")
      .select("photo_path")
      .eq("user_id", userId)
      .single();

    if (selectError) {
      throw new AppError(500, "internal_error", "No se pudo consultar profiles", {
        cause: selectError.message,
      });
    }

    const oldPath = profile?.photo_path ?? null;

    // Paso 2: escribir las DOS columnas en una sola sentencia. Por separado, el estado intermedio
    // violaría `profiles_avatar_exclusive` y el update fallaría.
    const patch = request.kind === "photo"
      ? { photo_path: request.photoPath, preset_avatar: null }
      : { photo_path: null, preset_avatar: request.preset };

    const { error: updateError } = await service
      .from("profiles")
      .update(patch)
      .eq("user_id", userId);

    if (updateError) {
      throw new AppError(500, "internal_error", "No se pudo actualizar el avatar", {
        cause: updateError.message,
      });
    }

    // Paso 3: auditoría (best-effort). Se registra la vida de las FOTOS: subir una, y dejar de
    // mostrarla al pasarse a un predeterminado. Elegir un preset sin foto previa no se audita —
    // el avatar prediseñado no es dato personal (decisión 0009/0010) y no hay nada que justificar.
    const auditEntry = request.kind === "photo"
      ? { user_id: userId, photo_path: request.photoPath, action: "uploaded" }
      : oldPath
      ? { user_id: userId, photo_path: oldPath, action: "removed" }
      : null;

    if (auditEntry) {
      const { error: auditError } = await service.from("photo_audit_log").insert(auditEntry);
      if (auditError) {
        console.warn("Failed to insert photo audit log:", auditError.message);
        // No se lanza: fallar la auditoría no puede bloquear el cambio de avatar.
      }
    }

    // Paso 4: encolar la foto desplazada (best-effort). `media-gc-cron` la borra de R2 en menos de
    // 5 minutos. Si esto falla, el objeto queda huérfano y lo recoge `media-reconcile-cron`.
    if (oldPath && oldPath !== (request.kind === "photo" ? request.photoPath : null)) {
      await queueForGc(service, userId, oldPath);
    }

    const response: AvatarSetResponse = { success: true, old_path: oldPath };
    return jsonResponse(response, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
