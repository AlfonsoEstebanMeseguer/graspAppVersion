// profile-photo-view-url — HTTP (app)
//
// Firma URLs de LECTURA (GET) contra Cloudflare R2 para las fotos de perfil. Es la contraparte de
// `profile-photo-upload-url`: sin esta función una foto subida no se puede mostrar.
//
// SEGURIDAD — acepta `user_ids`, NUNCA `photo_path`. La clave se resuelve en el servidor desde
// `profiles`, así que lo único firmable es la foto ACTUAL de alguien. Aceptar la clave que manda el
// cliente permitiría firmar cualquier objeto del bucket: la foto anterior de cualquier usuario
// mientras espera en `storage_gc_queue`, un huérfano de una subida abandonada, y mañana los
// prefijos de voz y pánico.
//
// Ese invariante lo sostienen DOS funciones, no una: aquí se resuelve la clave desde `photo_path`,
// pero es `profile-avatar-set` quien limita lo que puede llegar a esa columna. Si el día de mañana
// se relaja esa escritura, este comentario deja de ser cierto sin que nada aquí lo delate.
//
// Cualquier usuario autenticado puede pedir la foto de cualquier otro. No es laxitud:
// `profiles_read_public` usa `using (true)` y `authenticated` tiene `select` sobre
// `profiles.photo_path`, así que restringir aquí no cerraría nada que PostgREST no exponga ya.
//
// Diseño: docs/superpowers/specs/2026-08-12-servir-foto-de-perfil-design.md
import { GetObjectCommand } from "npm:@aws-sdk/client-s3@3.614.0";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3.614.0";
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { createR2Client, requireAvatarBucket } from "../_shared/r2.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import {
  buildPhotoMap,
  EXPIRES_IN_SECONDS,
  parseViewRequest,
  type ProfilePhotoRow,
  responseTypeFor,
} from "../_shared/photo-view.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    // El userId no se usa: cualquier autenticado puede pedir la foto de cualquiera. La llamada
    // sigue siendo obligatoria — es lo que exige un JWT válido y no la `anon key` sin sesión.
    await requireAuthUser(req);

    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      throw new AppError(400, "invalid_input", "Body no es JSON válido");
    }

    const userIds = parseViewRequest(rawBody);

    const service = getServiceRoleClient();
    const { data, error } = await service
      .from("profiles")
      .select("user_id, photo_path")
      .in("user_id", userIds);

    // Falla cerrado en los DOS casos. Un `data` nulo sin `error` produciría un mapa entero de
    // `null`s indistinguible de "ninguno de estos usuarios tiene foto". Precedente: eeb07d6.
    if (error || !data) {
      throw new AppError(500, "internal_error", "No se pudo consultar profiles", {
        cause: error?.message ?? "data nulo sin error",
      });
    }

    const bucket = requireAvatarBucket();
    const s3Client = createR2Client();

    const expiresAt = new Date(Date.now() + EXPIRES_IN_SECONDS * 1000).toISOString();

    // Firmar es criptografía local: no hay llamada a R2. Por eso el lote de 50 cuesta
    // prácticamente lo mismo que uno solo, y por eso no se hace `HEAD` para comprobar que el
    // objeto existe — serían N llamadas de red para no cerrar la carrera con el GC de todas
    // formas. Si la clave apunta a nada, R2 devuelve 404 y el cliente cae al placeholder.
    const photos = await buildPhotoMap(
      userIds,
      data as ProfilePhotoRow[],
      (photoPath) =>
        getSignedUrl(
          s3Client,
          new GetObjectCommand({
            Bucket: bucket,
            Key: photoPath,
            // El `Content-Type` ALMACENADO lo eligió quien subió el objeto, y R2 lo devuelve tal
            // cual: un objeto guardado como `text/html` se renderiza en el navegador que abra esta
            // URL, que es una URL que reparte la propia aplicación. `ResponseContentType` lo
            // sobrescribe en la respuesta, así que el tipo lo decide el servidor a partir de la
            // extensión de una clave que el servidor acuñó.
            //
            // Esta es la mitad de la defensa que NO depende del SDK. La otra —firmar
            // `content-type` en la subida— sí, y por eso existen las dos: si una actualización
            // menor del SDK vuelve a sacar la cabecera de la firma, esto sigue en pie.
            //
            // Extensión desconocida: no se adivina. `octet-stream` + `attachment` no se renderiza
            // en ningún navegador. Llegar aquí significa que `photo_path` tiene algo que
            // `profile-avatar-set` no debería haber escrito, así que se sirve inerte en vez de
            // romper el lote entero de fotos.
            ...responseTypeFor(photoPath),
          }),
          { expiresIn: EXPIRES_IN_SECONDS },
        ),
      expiresAt,
    );

    return jsonResponse({ photos, expires_in: EXPIRES_IN_SECONDS }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
