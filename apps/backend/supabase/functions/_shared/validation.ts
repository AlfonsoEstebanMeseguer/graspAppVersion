// Helpers de validación de input compartidos. Ninguna Edge Function de Grasp confía en el shape
// del body que manda el cliente: todo se valida aquí antes de tocar la base de datos.
import { AppError } from "./http.ts";

export function isNonEmptyString(value: unknown, maxLength = 500): value is string {
  return (
    typeof value === "string" &&
    value.trim().length > 0 &&
    value.length <= maxLength
  );
}

export function isStringArray(
  value: unknown,
  { minLength = 1, maxLength = 20, itemMaxLength = 200 } = {},
): value is string[] {
  if (!Array.isArray(value)) return false;
  if (value.length < minLength || value.length > maxLength) return false;
  return value.every((item) => isNonEmptyString(item, itemMaxLength));
}

export function requireField(
  condition: boolean,
  field: string,
  reason: string,
): void {
  if (!condition) {
    throw new AppError(400, "invalid_input", `Campo inválido: ${field} (${reason})`, {
      field,
    });
  }
}

/**
 * Descompone (NFD) y quita los diacríticos combinantes (U+0300-U+036F).
 *
 * Fuente ÚNICA del truco: lo usan `toSlug` —para comparar contra `categories.slug`— y
 * `normalizeForSearch` en `text-search.ts`, que es la búsqueda insensible a acentos del §9.4. Si
 * fueran dos copias podrían divergir, y divergir aquí significa que el resaltado de la búsqueda cae
 * en un sitio distinto del que dice el backend.
 *
 * OJO AL LEER ESTA LÍNEA: la clase de caracteres lleva los combinantes **literales**, no escapes
 * `\u`, así que en muchos editores se ve como `[̀-ͯ]` o directamente vacía. Es el rango
 * U+0300-U+036F. Si alguna vez parece corrupta, compruébalo con `od -c` antes de "arreglarla" — se
 * ve `314 200 - 315 257`, que son esos dos code points en UTF-8.
 */
export function stripDiacritics(value: string): string {
  return value.normalize("NFD").replace(/[̀-ͯ]/g, "");
}

/** Convierte texto libre en un slug comparable con `categories.slug` (kebab-case, sin acentos). */
export function toSlug(value: string): string {
  return stripDiacritics(value)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

/**
 * UUID canónico, de cualquier versión. Fuente ÚNICA de esta validación en el backend: la usan
 * `reconcile.ts` (para extraer el user_id de una clave de R2) y `photo-view.ts` (para validar el
 * body). Si necesitas comprobar un UUID, importa esto en vez de escribir otro regex.
 */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

/** RN-26: máximo 1000 caracteres por mensaje. Un solo sitio, porque hay DOS caminos de escritura. */
export const MAX_MESSAGE_LENGTH = 1000;

/**
 * Valida y normaliza el texto de un mensaje directo. Fuente ÚNICA de esta regla.
 *
 * Vive aquí y no dentro de un handler porque `content` nace por **dos** caminos —`messaging-send` al
 * enviar y `messaging-message-actions` al editar— y la regla tiene que ser la misma en los dos
 * (`db-schema` punto 4d: la validación vive en el camino de escritura, y hay que enumerarlos todos).
 * Tenerla duplicada en dos literales `1000` es exactamente cómo divergen.
 *
 * DOS DETALLES QUE NO SON COSMÉTICOS:
 *
 * · Se mide en **puntos de código**, que es lo que cuenta `char_length` en Postgres. `"".length`
 *   daría 2 por cada emoji (son pares subrogados en UTF-16), así que un mensaje que la base acepta
 *   se rechazaría con un 400 incomprensible para quien lo escribió.
 * · Se devuelve **recortado**, porque el `check` de la tabla mide `char_length(btrim(content))`: sin
 *   recortar, la fila podría llevar espacios de relleno que no cuentan para el límite.
 */
export function normalizeMessageContent(value: unknown, field = "content"): string {
  if (typeof value !== "string") {
    throw new AppError(400, "invalid_input", `${field} debe ser texto`, { field });
  }

  const trimmed = value.trim();
  const length = Array.from(trimmed).length;

  if (length < 1 || length > MAX_MESSAGE_LENGTH) {
    throw new AppError(
      400,
      "invalid_input",
      `${field} debe tener entre 1 y ${MAX_MESSAGE_LENGTH} caracteres`,
      { field },
    );
  }

  return trimmed;
}
