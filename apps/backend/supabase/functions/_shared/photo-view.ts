// Lógica pura de `profile-photo-view-url`: validación del body y construcción del mapa de
// respuesta. Aquí no se firma nada ni se habla con R2 — el firmador entra como parámetro para que
// todo esto se pueda testear sin red ni credenciales, igual que `reconcile.ts` y `digest.ts`.
//
// Diseño: docs/superpowers/specs/2026-08-12-servir-foto-de-perfil-design.md
import { AppError } from "./http.ts";
import { formatFromPath, formatMime } from "./image-format.ts";
import { isUuid } from "./validation.ts";

/**
 * Tope de ids por petición.
 *
 * NO lo subas sin leer esto: `config.toml:18` fija `max_rows = 1000` y PostgREST trunca ahí
 * **devolviendo `error: null`**. Con 50 la consulta `.in()` no se acerca al límite; con un tope
 * mayor que 1000 la respuesta se truncaría en silencio y habría que paginar la consulta.
 */
export const MAX_USER_IDS = 50;

/**
 * Caducidad de la URL firmada, en segundos.
 *
 * `media-storage`: una URL firmada es un secreto portador, «minutos, no días». Cinco minutos bastan
 * para pintar una pantalla en una conexión mala y no dejan nada útil en el historial de nadie.
 */
export const EXPIRES_IN_SECONDS = 300;

export interface PhotoEntry {
  url: string;
  expires_at: string;
}

/** Cabeceras de respuesta que se imponen al firmar el GET. Van al `GetObjectCommand`. */
export interface ResponseTypeOverride {
  ResponseContentType: string;
  ResponseContentDisposition: string;
}

/**
 * Decide con qué `Content-Type` debe responder R2, a partir de la extensión de la clave.
 *
 * Existe porque **el `Content-Type` almacenado lo elige quien sube el objeto**: el SDK saca
 * `content-type` de la firma por defecto (`unsignableHeaders`), así que se puede guardar un
 * polyglot RIFF/WEBP+HTML declarado como `text/html`, pasar la validación de cabecera de
 * `profile-avatar-set` —que mira los bytes, no la cabecera HTTP— y conseguir que R2 sirva contenido
 * activo bajo una URL que reparte la propia aplicación.
 *
 * La clave la acuña el servidor (`buildObjectKey`), así que su extensión sí es de fiar; el
 * `Content-Type` que el cliente declaró, no. De ahí que el tipo se derive de la primera.
 *
 * Extensión desconocida: no se adivina. `octet-stream` + `attachment` no lo renderiza ningún
 * navegador. Llegar ahí significa que `photo_path` contiene algo que `profile-avatar-set` no
 * debería haber escrito nunca, y la respuesta correcta a eso es servirlo inerte.
 */
export function responseTypeFor(photoPath: string): ResponseTypeOverride {
  const format = formatFromPath(photoPath);
  return format === null
    ? {
      ResponseContentType: "application/octet-stream",
      ResponseContentDisposition: "attachment",
    }
    : {
      ResponseContentType: formatMime(format),
      ResponseContentDisposition: "inline",
    };
}

/** `null` = ese usuario no tiene foto, o no existe. No se distinguen a propósito. */
export type PhotoMap = Record<string, PhotoEntry | null>;

export interface ProfilePhotoRow {
  user_id: string;
  photo_path: string | null;
}

/** Firma un GET para una clave de R2. Lo inyecta el handler; en los tests es un doble. */
export type SignerFn = (photoPath: string) => Promise<string>;

/**
 * Valida el body y devuelve las `user_ids` únicas, en orden de primera aparición.
 *
 * El body acepta `user_ids` y nada más. Un `photo_path` mandado por el cliente no se mira: la
 * petición se rechaza por no traer `user_ids`. Es deliberado — firmar una clave elegida por el
 * cliente convertiría la función en una máquina de firmar cualquier objeto del bucket (la foto
 * anterior de cualquiera mientras espera en `storage_gc_queue`, cualquier huérfano de una subida
 * abandonada, y mañana los prefijos de voz y pánico).
 */
export function parseViewRequest(raw: unknown): string[] {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new AppError(400, "invalid_input", "El body debe ser un objeto JSON");
  }
  const body = raw as Record<string, unknown>;

  if (!Array.isArray(body.user_ids)) {
    throw new AppError(400, "invalid_input", "user_ids requerido: array de UUIDs", {
      field: "user_ids",
    });
  }
  if (body.user_ids.length === 0) {
    throw new AppError(400, "invalid_input", "user_ids no puede estar vacío", {
      field: "user_ids",
    });
  }
  if (body.user_ids.length > MAX_USER_IDS) {
    throw new AppError(
      400,
      "invalid_input",
      `Máximo ${MAX_USER_IDS} user_ids por petición`,
      { field: "user_ids" },
    );
  }
  for (const item of body.user_ids) {
    if (!isUuid(item)) {
      throw new AppError(400, "invalid_input", "Cada elemento de user_ids debe ser un UUID", {
        field: "user_ids",
      });
    }
  }

  // Dedup sin distinguir mayúsculas/minúsculas (Postgres siempre serializa `uuid` en minúsculas,
  // así que "A…" y "a…" son la misma fila) pero conservando la primera aparición tal cual la mandó
  // el cliente: pasar todo a minúsculas aquí cambiaría las claves que el cliente recibe respecto a
  // las que pidió.
  const seen = new Set<string>();
  const uniqueIds: string[] = [];
  for (const id of body.user_ids as string[]) {
    const key = id.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      uniqueIds.push(id);
    }
  }
  return uniqueIds;
}

/**
 * Construye el mapa de respuesta.
 *
 * Recorre las ids **pedidas**, no las filas devueltas. Así toda id pedida aparece como clave (con
 * `null` si no hay foto o no hay fila) y ninguna fila inesperada de la consulta se cuela en la
 * respuesta. Solo se firma lo que existe: firmar es barato pero no gratis.
 */
export async function buildPhotoMap(
  requestedIds: string[],
  rows: ProfilePhotoRow[],
  sign: SignerFn,
  expiresAt: string,
): Promise<PhotoMap> {
  // Postgres serializa `uuid` siempre en minúsculas; el cliente puede pedir en cualquier casing (la
  // API lo documenta como válido). Comparar en minúsculas evita que "AAAA…" y "aaaa…" — la misma
  // fila — se traten como dos usuarios distintos y uno de los dos reciba `null` en silencio.
  const pathById = new Map<string, string>();
  for (const row of rows) {
    if (row.photo_path) pathById.set(row.user_id.toLowerCase(), row.photo_path);
  }

  const photos: PhotoMap = {};
  for (const id of requestedIds) {
    const photoPath = pathById.get(id.toLowerCase());
    photos[id] = photoPath ? { url: await sign(photoPath), expires_at: expiresAt } : null;
  }
  return photos;
}
