// profile-photo-upload-url — HTTP (app)
//
// Firma una URL de SUBIDA (PUT) contra Cloudflare R2 para la foto de perfil. El cliente sube los
// bytes directamente a R2; el backend no los ve nunca. Quien comprueba que lo subido es de verdad
// una imagen es `profile-avatar-set`, en la confirmación (decisión 0013).
//
// EL `mime_type` SE HONRA (decisión 0012). Determina el `ContentType` firmado y la extensión de la
// clave. Antes se validaba y se descartaba —se firmaba siempre WebP— y un cliente que declarase
// JPEG recibía un 200 seguido de un `SignatureDoesNotMatch` de R2 al hacer el PUT.
//
// Seguridad: exige JWT. La clave se acuña bajo `avatars/{user_id}/`, nunca la elige el cliente.
import { PutObjectCommand } from "npm:@aws-sdk/client-s3@3.614.0";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3.614.0";
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { createR2Client, requireAvatarBucket } from "../_shared/r2.ts";
import { requireAuthUser } from "../_shared/supabase-client.ts";
import { formatMime } from "../_shared/image-format.ts";
import { buildObjectKey, EXPIRES_IN, parseUploadRequest } from "../_shared/photo-upload.ts";

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

    const { fileSize, format } = parseUploadRequest(rawBody);
    const path = buildObjectKey(userId, format, crypto.randomUUID());

    const s3Client = createR2Client();

    // `ContentLength` y `ContentType` van FIRMADOS, pero el segundo SOLO porque se pide
    // explícitamente en `signableHeaders`. El SDK hace `unsignableHeaders.add("content-type")` en
    // `S3RequestPresigner.prepareRequest`, así que por defecto la cabecera queda FUERA de la firma:
    // aquí decía que R2 rechazaba el PUT con otro `Content-Type` y era falso. Se podía subir un
    // polyglot RIFF/WEBP+HTML declarándolo `text/html`, pasar la validación de cabecera de
    // `profile-avatar-set` y hacer que R2 sirviera contenido activo bajo una URL que reparte la
    // propia aplicación.
    //
    // Es una propiedad del SDK, no del protocolo, así que puede cambiar en una actualización menor:
    // el test comprueba que `X-Amz-SignedHeaders` la contiene, y la defensa que NO depende del SDK
    // está en la lectura (`profile-photo-view-url` impone `ResponseContentType`).
    const uploadUrl = await getSignedUrl(
      s3Client,
      new PutObjectCommand({
        Bucket: requireAvatarBucket(),
        Key: path,
        ContentType: formatMime(format),
        ContentLength: fileSize,
      }),
      { expiresIn: EXPIRES_IN, signableHeaders: new Set(["content-type"]) },
    );

    return jsonResponse({ upload_url: uploadUrl, path, expires_in: EXPIRES_IN }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
