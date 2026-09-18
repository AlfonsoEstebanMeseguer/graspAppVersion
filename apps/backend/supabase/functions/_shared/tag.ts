// Acunado y validacion del tag publico de un usuario (`profiles.tag`, RN-11). PURA: sin red,
// sin Postgres.
//
// Un tag es `alfon#K7M2QX9F`: parte local derivada del nombre + '#' + 8 caracteres de alfabeto
// Crockford base32. Se teclea A MANO en un movil, porque segun la spec (§6.2) es la unica forma
// de encontrar a alguien a proposito.
//
// **La autoridad de este formato es la migracion `20260823120000_profiles_tag_bio_activity.sql`**
// (`public.mint_user_tag` y `public.mint_tag_suffix`), no este fichero — el mismo reparto que
// `avatar-set.ts` tiene con el `check` `profiles_preset_avatar_valid`. El tag lo acuna SIEMPRE el
// servidor dentro de la base de datos; esto existe para validar y previsualizar en el borde sin
// una ida y vuelta, y para que los tests de este comportamiento no necesiten Postgres. Si los dos
// divergen, gana el SQL.

/**
 * Parte local del tag a partir del nombre visible.
 *
 * Espejo exacto de la mitad local de `public.mint_user_tag`:
 *
 * ```sql
 * coalesce(
 *   nullif(left(lower(regexp_replace(normalize(display_name, NFD), '[^a-zA-Z0-9]', '', 'g')), 12), ''),
 *   'grasp')
 * ```
 *
 * `NFD` separa la tilde de la letra y el reemplazo se la lleva junto con todo lo que no sea
 * alfanumerico ASCII, en una sola pasada — el mismo truco que `toSlug` en `validation.ts`, para
 * que el SQL y este fichero compartan una idea en vez de tener dos.
 *
 * Se diferencia de `toSlug` en dos cosas, y las dos son deliberadas: la puntuacion interna
 * **desaparece** en vez de convertirse en '-' (un guion no es tecleable de forma fiable en un
 * teclado movil), y nunca devuelve cadena vacia — un nombre entero en cirilico o en emoji es un
 * caso real, y sin el fallback acunaria un tag que empieza por '#'.
 */
export function normalizeTagLocalPart(name: string): string {
  const local = name
    .normalize("NFD")
    .replace(/[^a-zA-Z0-9]/g, "")
    .toLowerCase()
    .slice(0, 12);

  return local === "" ? TAG_LOCAL_FALLBACK : local;
}

/** Parte local de reserva cuando el nombre no aporta ni un caracter alfanumerico ASCII. */
export const TAG_LOCAL_FALLBACK = "grasp";

/**
 * Alfabeto Crockford base32 del sufijo: **sin I, L, O ni U**. Sin I/L/O no se confunde un 1 con
 * una l ni un 0 con una O al teclear; sin U no sale ninguna palabra malsonante por azar.
 * 32 simbolos ^ 8 posiciones = 1,1 x 10^12 combinaciones.
 *
 * Duplicado a proposito en la migracion (`mint_tag_suffix`), que es la autoridad.
 */
export const TAG_SUFFIX_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/**
 * `^[a-z0-9]{1,12}#[0-9A-HJKMNP-TV-Z]{8}$`
 *
 * Se ancla con `\n?$` NEGADO, es decir: se usa el flag por defecto y se comprueba ademas que no
 * haya salto de linea final, porque en JavaScript `$` sin `m` acepta un '\n' al final de la
 * cadena. `[0-9A-HJKMNP-TV-Z]` es el alfabeto de arriba escrito como rangos: 0-9, A-H, J, K, M,
 * N, P-T y V-Z — exactamente 32 simbolos, sin I, L, O ni U.
 */
const TAG_RE = /^[a-z0-9]{1,12}#[0-9A-HJKMNP-TV-Z]{8}$/;

export function isValidTag(value: unknown): value is string {
  return typeof value === "string" && !value.includes("\n") && TAG_RE.test(value);
}
