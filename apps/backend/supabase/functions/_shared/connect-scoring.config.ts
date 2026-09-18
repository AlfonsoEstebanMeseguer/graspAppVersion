// Constantes del algoritmo de recomendación de Conectar (§7 de la spec).
//
// TODAS viven aquí y ninguna se repite en el código. No es una preferencia de estilo: el propio §7
// abre con el aviso de que estos números «se van a tunear», y una constante repartida por tres
// ficheros se tunea en dos y diverge en el tercero sin que nada lo delate — es el mismo fallo que
// `db-schema` punto 4d describe para la validación duplicada, y que la Tarea 12 ya tuvo que
// deshacer factorizando `normalizeMessageContent`.
//
// Este fichero no tiene lógica a propósito: es la tabla del §7.1 escrita en TypeScript.

/**
 * `M_edad` (§7.1): tramos por diferencia de edad en años, del más estrecho al más ancho.
 *
 * Se evalúa **en orden** y gana el primero que encaje, así que los tramos tienen que estar
 * ordenados de menor a mayor. Al revés, `≤10` se comería a `≤2` y todo el mundo pesaría 1.3.
 */
export const AGE_MULTIPLIER_TIERS = [
  { maxDifferenceYears: 2, multiplier: 3.0 },
  { maxDifferenceYears: 5, multiplier: 2.0 },
  { maxDifferenceYears: 10, multiplier: 1.3 },
] as const;

/**
 * Fuera de todos los tramos (§7.1, «resto»).
 *
 * Es también lo que se aplica cuando **falta** una de las dos edades. Nunca 0: RN-41 dice que todo
 * el mundo es elegible, y un multiplicador de 0 sacaría a esa persona del muestreo para siempre —
 * que es justo lo que RN-41 prohíbe. Un dato ausente pondera neutro, no excluye.
 */
export const AGE_MULTIPLIER_FALLBACK = 1.0;

/**
 * Los tres ejes de coincidencia del §7.1: `1 + paso × (nº en común)`, con tope.
 *
 * Los tres son **categoría especial del Art. 9 RGPD** y por eso el scoring vive entero en servidor:
 * de aquí sale un número y nada más. Ni un slug viaja al cliente ([ADR 0020]).
 *
 *   · `interests` → `onboarding_responses.responses`
 *   · `suffered`  → `user_experiences` / `experience_cases` (la situación que se pasó)
 *   · `current`   → `profiles_private.primary_category_id` + `secondary_categories` (la de ahora)
 */
export const OVERLAP_MULTIPLIERS = {
  interests: { step: 0.5, cap: 3.0 },
  suffered: { step: 0.8, cap: 3.0 },
  current: { step: 1.0, cap: 3.5 },
} as const;

/**
 * Multiplicador de un eje sin ninguna coincidencia (§7.1: «sin ninguna coincidencia, todos valen
 * 1.0 → score = 1»). Es el elemento neutro del producto, así que un eje vacío no penaliza.
 */
export const NEUTRAL_MULTIPLIER = 1.0;

/**
 * RN-42: el filtro activo **eleva su propio multiplicador al cuadrado**; los demás intactos.
 *
 * Se aplica **después** del tope, no antes: `M_intereses` con 6 coincidencias es 3.0 (tope), y con
 * el filtro puesto es 3.0² = 9.0, no `min(4.0², 3.0)`. El ejemplo del §7.2 lo escribe así.
 */
export const ACTIVE_FILTER_EXPONENT = 2;

/** RN-46: perfiles por tanda. */
export const BATCH_SIZE = 20;

/** RN-46: `pull-to-refresh` diarios. El tope lo cuenta `connect_feed_runs` (Tarea 5/16). */
export const MAX_REFRESHES_PER_DAY = 5;

/**
 * Búsquedas por tag al día ([ADR 0028](../../../../../docs/decisions/0028-el-bloqueo-es-detectable-por-quien-lo-sufre.md)).
 * El tope lo cuenta `connect_tag_lookups`.
 *
 * **No cierra el canal temporal de `connect-tag-lookup`; lo acota por volumen**, que es lo que un
 * ataque de latencia necesita — sin muchas muestras no hay estadística. De paso frena la
 * enumeración de tags por fuerza bruta, que era el problema peor y no estaba anotado en ningún
 * sitio: sin tope, un atacante puede recorrer el espacio de tags a ritmo de red.
 *
 * **Por qué 30 y no 5 como los refrescos.** Son cosas distintas: refrescar pide una tanda nueva de
 * candidatos, mientras que buscar un tag que alguien te ha pasado es **la única forma de encontrar
 * a una persona a propósito** (§6.2, y no hay búsqueda difusa ni la habrá). Un tope estrecho aquí
 * no acota un ataque: rompe la función. 30 deja holgura de sobra para el uso legítimo —incluido
 * teclear mal un tag varias veces— y aun así convierte en inviable cualquier medición estadística.
 */
export const MAX_TAG_LOOKUPS_PER_DAY = 30;
