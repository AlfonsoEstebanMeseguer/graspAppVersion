// Tope de `pull-to-refresh` de Conectar (RN-46) y su instante de recuperación (RN-21).
// PURA: sin red, sin Postgres y sin reloj propio — `now` entra por parámetro.
import { MAX_REFRESHES_PER_DAY } from "./connect-scoring.config.ts";

export interface RefreshVerdict {
  allowed: boolean;
  /** El número del límite alcanzado (RN-21). */
  limit: number;
  used: number;
  /** Cuándo vuelve a haber cupo. `null` mientras quede: no hay nada que esperar. */
  retryAt: Date | null;
}

/**
 * La medianoche UTC **siguiente** a `now`.
 *
 * UTC y no la zona del usuario porque el contador vive en `connect_feed_runs (user_id, ran_on)`
 * con `ran_on = current_date`, y la base corre en UTC (comprobado con `show timezone`, no
 * supuesto). Si esta cuenta usara otra zona, prometería un cupo que la base aún no habría
 * reiniciado — o al revés, escondería uno ya disponible.
 *
 * `Date.UTC` con `día + 1` normaliza solo el fin de mes y el fin de año; no hay que tratarlos.
 */
export function nextUtcMidnight(now: Date): Date {
  return new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + 1,
  ));
}

/**
 * RN-46: máximo 5 `pull-to-refresh` al día.
 *
 * **No es una ventana móvil** como RN-19: este cupo se reinicia con el calendario, porque la fecha
 * va dentro de la clave de `connect_feed_runs`. Por eso el `retryAt` es una medianoche y no
 * «24 h desde el más antiguo».
 *
 * `>=` y no `>`: con 5 gastados el sexto se rechaza. «Máximo 5» significa que el quinto pasa.
 */
export function evaluateRefreshLimit(used: number, now: Date): RefreshVerdict {
  if (used >= MAX_REFRESHES_PER_DAY) {
    return {
      allowed: false,
      limit: MAX_REFRESHES_PER_DAY,
      used,
      retryAt: nextUtcMidnight(now),
    };
  }

  return { allowed: true, limit: MAX_REFRESHES_PER_DAY, used, retryAt: null };
}
