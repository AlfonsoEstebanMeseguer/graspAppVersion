// El tope de la muestra del feed de Conectar, y su vigilancia (ADR 0030).
// PURA: sin red, sin Postgres.
//
// POR QUÉ `MAX_POOL` VIVE AQUÍ Y NO EN `connect-feed/index.ts`, QUE ES QUIEN LO USA
//
// Porque desde el ADR 0030 lo usan DOS: el handler, que lo pasa como `p_limit` al RPC, y el digest
// diario, que lo compara con el tamaño de la base para avisar cuando la muestra deje de cubrirla.
// Dos copias del mismo número se tunean en una y divergen en la otra sin que nada lo delate —el
// punto 4d de `db-schema`—, y aquí la divergencia sería peor que un bug: el digest vigilaría un tope
// distinto del que aplica el feed, y su silencio sería una mentira tranquilizadora.

/**
 * Tope de la muestra de elegibles que `connect-feed` trae a memoria antes de puntuar.
 *
 * **Ya no sesga.** Hasta el 2026-08-30 esto era un `limit` sobre `profiles` sin ordenar, así que la
 * muestra era siempre la misma y el feed se inclinaba hacia quien estuviera antes en el índice.
 * Ahora `connect_eligible_sample` devuelve una muestra **aleatoria** y **ya excluida**.
 *
 * Lo que este número sigue significando: alguien con score alto puede quedar fuera de la tanda por
 * no haber entrado en la muestra. Eso pasaba antes también — la diferencia es que antes le pasaba
 * siempre a las mismas personas. Ver el punto 16 de `docs/pending-messaging.md`.
 */
export const MAX_POOL = 1000;

/**
 * Por debajo de esta cobertura, el digest avisa (ADR 0030).
 *
 * A la mitad, el tope empieza a decidir tanto como el score: uno de cada dos perfiles elegibles no
 * llega siquiera a puntuarse. Con `MAX_POOL = 1000` eso son **2000 perfiles** en la base.
 */
export const POOL_COVERAGE_MIN = 0.5;

/**
 * Qué fracción de la base cabe en una muestra.
 *
 * **Nunca más de 1**: mientras la base sea más pequeña que la muestra, el tope sencillamente no
 * existe —`connect_eligible_sample` devuelve la tabla entera y el scoring decide sobre todos—, y
 * decir «cobertura 5.0» no significaría nada. Esa es también la situación de hoy.
 *
 * Un recuento absurdo (negativo, o cero) devuelve 1 y no dispara nada: el número viene de un
 * `count` de Postgres, y si algún día llega raro, una alerta diaria sobre un sistema sano se deja
 * de leer — el mismo motivo por el que `AUDIT_STALE_DAYS` es 91 y no 90.
 */
export function poolCoverage(eligibleProfiles: number): number {
  if (!Number.isFinite(eligibleProfiles) || eligibleProfiles <= MAX_POOL) return 1;
  return MAX_POOL / eligibleProfiles;
}

/**
 * `<` y no `<=`: con la cobertura **exactamente** en el umbral todavía se cubre lo prometido. Una
 * alerta que salta en el valor aceptable es una alerta que se deja de leer.
 */
export function poolCoverageIsLow(eligibleProfiles: number): boolean {
  return poolCoverage(eligibleProfiles) < POOL_COVERAGE_MIN;
}
