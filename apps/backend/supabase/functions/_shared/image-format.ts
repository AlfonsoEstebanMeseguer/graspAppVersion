// Autoridad única de los formatos de imagen que Grasp acepta como foto de perfil.
//
// POR QUÉ ESTÁ TODO EN UN SOLO FICHERO
// Dos sitios necesitan saber lo mismo: `profile-photo-upload-url` (para firmar el `ContentType` y
// acuñar la clave) y `profile-avatar-set` (para comprobar que los bytes subidos son de ese
// formato). Con dos listas separadas, añadir un formato en una y no en la otra produce una subida
// que firma algo que la confirmación rechaza — un fallo que solo aparece en el segundo paso.
//
// Decisiones: docs/decisions/0012-honrar-el-mime-type-de-la-subida.md (qué se admite) y
//             docs/decisions/0013-validar-los-bytes-en-la-confirmacion.md (cómo se comprueba).
import { AppError } from "./http.ts";

/** Formatos admitidos. PNG salió del conjunto en 0012: no lo produce ningún cliente. */
export type ImageFormat = "webp" | "jpeg";

interface FormatSpec {
  mime: string;
  /** Extensión canónica, y única: la clave la acuña el servidor. */
  extension: string;
}

const SPECS: Record<ImageFormat, FormatSpec> = {
  webp: { mime: "image/webp", extension: ".webp" },
  jpeg: { mime: "image/jpeg", extension: ".jpg" },
};

const FORMATS = Object.keys(SPECS) as ImageFormat[];

export const ALLOWED_MIME_TYPES: readonly string[] = FORMATS.map((f) => SPECS[f].mime);

/**
 * Lado máximo admitido, en píxeles.
 *
 * No es una manía estética: un WebP de 60 KB puede declarar 16384×16384 en su cabecera y reventar
 * la memoria del móvil que intente pintarlo. El tamaño del fichero no acota las dimensiones.
 */
export const MAX_DIMENSION = 2048;

export function formatFromMime(mime: string): ImageFormat | null {
  return FORMATS.find((f) => SPECS[f].mime === mime) ?? null;
}

export function extensionForFormat(format: ImageFormat): string {
  return SPECS[format].extension;
}

/** El `Content-Type` que se firma para este formato. */
export function formatMime(format: ImageFormat): string {
  return SPECS[format].mime;
}

/** Resuelve el formato por la extensión de una clave de R2. Sensible a mayúsculas a propósito. */
export function formatFromPath(path: string): ImageFormat | null {
  return FORMATS.find((f) => path.endsWith(SPECS[f].extension)) ?? null;
}

// --- Reconocimiento por cabecera --------------------------------------------
//
// AQUÍ NO SE DECODIFICA NADA, y es deliberado (decisión 0013). Decodificar la imagen entera
// parecería más seguro y no lo es: una imagen maliciosa diseñada contra un decodificador
// DECODIFICA BIEN, así que pasaría igual y llegaría a los móviles de todos los que abran el
// perfil; y para comprobarlo habría que dárselos precisamente a un decodificador, metiendo en el
// backend la misma superficie que se quiere cerrar.
//
// Lo que esto SÍ cierra: que el bucket se use como almacenamiento de ficheros arbitrarios.

function startsWith(bytes: Uint8Array, prefix: number[], offset = 0): boolean {
  if (bytes.length < offset + prefix.length) return false;
  return prefix.every((b, i) => bytes[offset + i] === b);
}

const RIFF = [0x52, 0x49, 0x46, 0x46]; // "RIFF"
const WEBP = [0x57, 0x45, 0x42, 0x50]; // "WEBP"
const JPEG_SOI = [0xff, 0xd8, 0xff];

/** Formato real según los primeros bytes, o `null` si no es ninguno de los admitidos. */
export function sniffFormat(bytes: Uint8Array): ImageFormat | null {
  if (startsWith(bytes, RIFF) && startsWith(bytes, WEBP, 8)) return "webp";
  if (startsWith(bytes, JPEG_SOI)) return "jpeg";
  return null;
}

export interface Dimensions {
  width: number;
  height: number;
}

/**
 * Dimensiones leídas del contenedor. `null` si la cabecera no se puede interpretar.
 *
 * WebP tiene tres formas de decirlo y hay que soportar las tres: "VP8 " (con pérdida), "VP8L" (sin
 * pérdida) y "VP8X" (extendido, el que usa un WebP con transparencia o animación).
 */
export function readDimensions(bytes: Uint8Array, format: ImageFormat): Dimensions | null {
  return format === "webp" ? readWebpDimensions(bytes) : readJpegDimensions(bytes);
}

function readWebpDimensions(bytes: Uint8Array): Dimensions | null {
  // Lo justo para leer el identificador del chunk (12-15). Cada variante comprueba después su
  // propia longitud: un VP8L completo ocupa 25 bytes, así que exigir 30 para todas rechazaría
  // ficheros perfectamente válidos.
  if (bytes.length < 16) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const chunk = String.fromCharCode(bytes[12], bytes[13], bytes[14], bytes[15]);

  if (chunk === "VP8 ") {
    // Tras la cabecera del chunk (12-19) van 3 bytes de frame tag y el start code 9D 01 2A.
    if (bytes.length < 30) return null;
    if (!startsWith(bytes, [0x9d, 0x01, 0x2a], 23)) return null;
    return {
      width: view.getUint16(26, true) & 0x3fff,
      height: view.getUint16(28, true) & 0x3fff,
    };
  }

  if (chunk === "VP8L") {
    if (bytes.length < 25 || bytes[20] !== 0x2f) return null;
    const packed = view.getUint32(21, true);
    return {
      width: (packed & 0x3fff) + 1,
      height: ((packed >>> 14) & 0x3fff) + 1,
    };
  }

  if (chunk === "VP8X") {
    // Payload: 1 byte de flags, 3 reservados, y el lienzo en dos enteros de 24 bits (menos uno).
    if (bytes.length < 30) return null;
    const read24 = (o: number) => bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16);
    return { width: read24(24) + 1, height: read24(27) + 1 };
  }

  return null;
}

function readJpegDimensions(bytes: Uint8Array): Dimensions | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 2; // se salta el SOI (FF D8)

  while (offset + 9 < bytes.length) {
    if (bytes[offset] !== 0xff) return null; // fuera de sincronía: no nos lo inventamos
    const marker = bytes[offset + 1];

    // Marcadores SOF: llevan las dimensiones. Se excluyen C4 (DHT), C8 (JPG) y CC (DAC), que caen
    // dentro del rango pero no son SOF.
    const isSof = marker >= 0xc0 && marker <= 0xcf &&
      marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isSof) {
      return {
        height: view.getUint16(offset + 5, false),
        width: view.getUint16(offset + 7, false),
      };
    }

    // Marcadores sin payload: relleno, SOI/EOI y los RSTn.
    if (marker === 0xff || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd9)) {
      offset += 2;
      continue;
    }

    const length = view.getUint16(offset + 2, false);
    if (length < 2) return null;
    offset += 2 + length;
  }

  return null;
}

/**
 * Comprueba que los bytes son una imagen del formato esperado y de un tamaño razonable.
 *
 * **Falla cerrado**: si la cabecera no se puede leer, se rechaza. Un fichero cuya cabecera no
 * entendemos es o malformado o exótico, y el cliente que controlamos no produce ninguno de los dos.
 */
export function assertValidImageBytes(bytes: Uint8Array, expected: ImageFormat): void {
  const actual = sniffFormat(bytes);

  if (actual === null) {
    throw new AppError(400, "invalid_input", "El fichero subido no es una imagen", {
      field: "photo_path",
    });
  }

  if (actual !== expected) {
    throw new AppError(
      400,
      "invalid_input",
      `Los bytes son ${actual} pero la clave declara ${expected}`,
      { field: "photo_path" },
    );
  }

  const dimensions = readDimensions(bytes, actual);
  if (dimensions === null) {
    throw new AppError(400, "invalid_input", "No se pudo leer la cabecera de la imagen", {
      field: "photo_path",
    });
  }

  if (dimensions.width > MAX_DIMENSION || dimensions.height > MAX_DIMENSION) {
    throw new AppError(
      400,
      "invalid_input",
      `Imagen demasiado grande (máx ${MAX_DIMENSION}×${MAX_DIMENSION}, recibida ${dimensions.width}×${dimensions.height})`,
      { field: "photo_path" },
    );
  }
}
