// Lógica pura de `profile-photo-upload-url`: validación del body y construcción de la clave.
// PURA: sin red, sin R2, sin credenciales — el firmado se queda en el `index.ts`.
//
// El `mime_type` que manda el cliente SE HONRA (decisión 0012). Antes se validaba y se descartaba:
// la clave y el `ContentType` firmado eran siempre WebP, así que un cliente que declarase JPEG
// recibía un 200 y después un `SignatureDoesNotMatch` de R2 al hacer el PUT — el fallo aparecía en
// el sitio equivocado, lo emitía otro sistema y el mensaje no decía lo que pasaba.
import { AppError } from "./http.ts";
import {
  ALLOWED_MIME_TYPES,
  extensionForFormat,
  formatFromMime,
  type ImageFormat,
} from "./image-format.ts";

/** Tope de tamaño del objeto. Se firma como `ContentLength`, así que R2 lo impone de verdad. */
export const MAX_FILE_SIZE = 200 * 1024;

/**
 * Validez de la URL de subida.
 *
 * Eran 3600 s, y la ventana era el fallo: la validación de bytes (decisión 0013) ocurre al
 * CONFIRMAR, en `profile-avatar-set`, así que durante el resto de la hora se podía repetir el PUT
 * sobre la misma URL firmada y dejar en `photo_path` bytes que nadie validó. Como
 * `photo_audit_log` guarda la ruta y no un hash, el cambiazo no dejaba rastro.
 *
 * 120 s es margen de sobra para subir 200 KB y no es un vale con el que volver más tarde. NO cierra
 * el fallo —dentro de la ventana sigue siendo posible—, solo lo estrecha: cerrarlo por construcción
 * exige copiar a una clave que el cliente no pueda escribir, o guardar el hash de lo validado.
 */
export const EXPIRES_IN = 120;

export interface UploadRequest {
  fileSize: number;
  format: ImageFormat;
}

export function parseUploadRequest(raw: unknown): UploadRequest {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new AppError(400, "invalid_input", "El body debe ser un objeto JSON");
  }
  const body = raw as Record<string, unknown>;

  if (
    typeof body.file_size !== "number" || !Number.isFinite(body.file_size) || body.file_size <= 0
  ) {
    throw new AppError(400, "invalid_input", "file_size debe ser un número positivo", {
      field: "file_size",
    });
  }

  if (body.file_size > MAX_FILE_SIZE) {
    throw new AppError(400, "invalid_input", `File too large (max ${MAX_FILE_SIZE / 1024} KB)`, {
      field: "file_size",
    });
  }

  if (typeof body.mime_type !== "string") {
    throw new AppError(400, "invalid_input", "mime_type debe ser un string", {
      field: "mime_type",
    });
  }

  const format = formatFromMime(body.mime_type);
  if (format === null) {
    throw new AppError(
      400,
      "invalid_input",
      `Invalid MIME type (allowed: ${ALLOWED_MIME_TYPES.join(", ")})`,
      { field: "mime_type" },
    );
  }

  return { fileSize: body.file_size, format };
}

/**
 * Acuña la clave del objeto.
 *
 * El prefijo `avatars/<user_id>/` no es organización: es lo que comprueba `assertPathOwnership` en
 * la confirmación, y lo único que impide que alguien reclame la clave de otro.
 */
export function buildObjectKey(userId: string, format: ImageFormat, uuid: string): string {
  return `avatars/${userId}/${uuid}${extensionForFormat(format)}`;
}
