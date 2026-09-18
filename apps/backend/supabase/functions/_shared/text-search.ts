// Búsqueda dentro de una conversación (§9.4). PURA: sin red y sin Postgres.
//
// POR QUÉ ESTO NO ES UN `ILIKE` EN POSTGRES
// §9.4 pide una búsqueda insensible a mayúsculas **y a diacríticos**, y además los **offsets** de
// cada coincidencia para resaltar dentro de la burbuja. Un `ilike` daría lo primero y nada de lo
// otro: habría que volver a buscar en el cliente para saber dónde resaltar, y ahí está la trampa —
// **dos normalizaciones distintas a cada lado desplazan el resaltado**. Se calcula una vez, en un
// sitio, y viaja el resultado.
//
// LA DECISIÓN QUE GOBIERNA EL FICHERO: los offsets son del TEXTO ORIGINAL, no del normalizado.
// Normalizar puede acortar la cadena —un texto ya descompuesto pierde sus acentos combinantes— así
// que un offset del normalizado señala el sitio equivocado, y se desvía más cuantos más acentos
// haya antes. Por eso se normaliza carácter a carácter llevando un mapa de vuelta al original.
import { stripDiacritics } from "./validation.ts";

/** Insensible a mayúsculas y a diacríticos, que es lo que pide §9.4. */
export function normalizeForSearch(value: string): string {
  return stripDiacritics(value).toLowerCase();
}

/** Rango en unidades UTF-16 del texto ORIGINAL: `[start, end)`, como `String.slice`. */
export interface MatchOffset {
  start: number;
  end: number;
}

interface NormalizedText {
  text: string;
  /** Por cada unidad UTF-16 de `text`, dónde empieza y acaba su carácter en el original. */
  starts: number[];
  ends: number[];
  /**
   * Caracteres del original que normalizan a NADA (los acentos combinantes), indexados por dónde
   * empiezan. Sirven para que una coincidencia se trague el acento que le sigue — ver más abajo.
   */
  vanished: Map<number, number>;
}

/**
 * Normaliza llevando la cuenta de dónde estaba cada cosa.
 *
 * Se recorre por PUNTOS DE CÓDIGO (`for...of` sobre la cadena) pero el mapa se indexa por UNIDADES
 * UTF-16, que es como indexa `indexOf`, `slice` y las cadenas de Dart. Mezclar las dos unidades es
 * el fallo clásico aquí: todo cuadra hasta que aparece un emoji.
 *
 * Normalizar carácter a carácter y concatenar da el mismo resultado que normalizar la cadena entera
 * **porque se descartan todos los combinantes**: sin ellos no queda nada cuyo orden canónico pueda
 * cambiar al juntarlo.
 */
function normalizeWithMap(value: string): NormalizedText {
  let text = "";
  const starts: number[] = [];
  const ends: number[] = [];
  const vanished = new Map<number, number>();

  let at = 0;
  for (const char of value) {
    const from = at;
    const to = at + char.length; // `char.length` son unidades UTF-16: 2 para un emoji.
    const normalized = normalizeForSearch(char);

    if (normalized.length === 0) {
      vanished.set(from, to);
    } else {
      for (let k = 0; k < normalized.length; k++) {
        text += normalized[k];
        starts.push(from);
        ends.push(to);
      }
    }

    at = to;
  }

  return { text, starts, ends, vanished };
}

/**
 * Todas las coincidencias de `needle` en `haystack`, con sus offsets en el texto ORIGINAL.
 *
 * No se solapan: el cliente resalta rangos, y dos rangos solapados se pintarían uno encima del otro.
 */
export function findMatches(haystack: string, needle: string): MatchOffset[] {
  const target = normalizeForSearch(needle).trim();

  // Sin esto, `indexOf("")` devuelve la posición de partida SIEMPRE y el bucle no termina nunca.
  // Pasa con una búsqueda de solo espacios o de un acento suelto, que normaliza a nada.
  if (target.length === 0 || haystack.length === 0) return [];

  const { text, starts, ends, vanished } = normalizeWithMap(haystack);
  const matches: MatchOffset[] = [];

  let from = 0;
  while (from <= text.length - target.length) {
    const found = text.indexOf(target, from);
    if (found === -1) break;

    const start = starts[found];
    let end = ends[found + target.length - 1];

    // El acento que sigue a la última letra se traga. "café" descompuesto es c-a-f-e-´: el final
    // "natural" caería en la `e` y dejaría la tilde fuera del resaltado, así que el cliente pintaría
    // "cafe" resaltado y una tilde suelta sin resaltar justo encima. El `while` cubre los
    // combinantes apilados (varios diacríticos sobre la misma letra).
    let next = vanished.get(end);
    while (next !== undefined) {
      end = next;
      next = vanished.get(end);
    }

    matches.push({ start, end });
    from = found + target.length;
  }

  return matches;
}
