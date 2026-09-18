// Tope diario de búsquedas por tag (ADR 0028 §5) y su instante de recuperación (RN-21).
// PURA: sin red, sin Postgres y sin reloj propio — `now` entra por parámetro.
//
// POR QUÉ ESTE FICHERO NO RECIBE EL DESENLACE DE LA BÚSQUEDA, Y NO PUEDE RECIBIRLO
//
// Un tope que contara solo los fallos —solo los `404`— sería peor que no tener tope: el contador se
// convertiría él mismo en el oráculo que `RN-23` quiere cerrar, porque gastar cupo distinguiría un
// tag inexistente de uno encontrado. Aquí solo entran `used` y `now`, así que no hay ningún
// parámetro por el que el desenlace pueda colarse, y quien llama incrementa **antes** de resolver.
import { MAX_TAG_LOOKUPS_PER_DAY } from "./connect-scoring.config.ts";
// `nextUtcMidnight` NO se reescribe aquí: es la misma primitiva, ya probada, que usa el tope de
// refrescos. Duplicar el cálculo de la medianoche sería exactamente el fallo del punto 4d de
// `db-schema` — dos copias que se tunean en una y divergen en la otra sin que nada lo delate.
import { nextUtcMidnight } from "./connect-refresh.ts";

export interface TagLookupVerdict {
  allowed: boolean;
  /** El número del límite alcanzado (RN-21). */
  limit: number;
  used: number;
  /** Cuándo vuelve a haber cupo. `null` mientras quede: no hay nada que esperar. */
  retryAt: Date | null;
}

/**
 * ADR 0028: máximo `MAX_TAG_LOOKUPS_PER_DAY` búsquedas por tag al día.
 *
 * Se reinicia con el calendario, no con una ventana móvil, porque la fecha va dentro de la clave de
 * `connect_tag_lookups`. Por eso el `retryAt` es una medianoche y no «24 h desde la más antigua».
 *
 * `>=` y no `>`: con el cupo gastado, la siguiente se rechaza. «Máximo N» significa que la N-ésima
 * pasa.
 */
export function evaluateTagLookupLimit(used: number, now: Date): TagLookupVerdict {
  if (used >= MAX_TAG_LOOKUPS_PER_DAY) {
    return {
      allowed: false,
      limit: MAX_TAG_LOOKUPS_PER_DAY,
      used,
      retryAt: nextUtcMidnight(now),
    };
  }

  return { allowed: true, limit: MAX_TAG_LOOKUPS_PER_DAY, used, retryAt: null };
}
