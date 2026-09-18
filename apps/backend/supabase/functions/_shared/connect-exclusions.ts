// Exclusiones del pool de Conectar (RN-47, RN-48) y la resolución de RN-49.
// PURA: sin red y sin Postgres — recibe conjuntos de ids ya consultados y devuelve quién queda.
//
// Quién llena los conjuntos es `connect-feed` (Tarea 16). Aquí no se consulta nada a propósito:
// así las seis exclusiones se pueden probar una a una, que es donde se rompen.
import { BATCH_SIZE } from "./connect-scoring.config.ts";

/**
 * Los conjuntos que RN-47 enumera, **uno por cada mitad direccional**.
 *
 * El bloqueo y las solicitudes van en DOS conjuntos cada uno en vez de en uno ya unido, y es
 * deliberado: RN-47(2) dice «en cualquier dirección», y si la unión la hiciera quien consulta,
 * olvidarse de una mitad sería un cambio invisible aquí y sin ningún test que lo viera. Partido
 * en dos, cada dirección tiene su test y su motivo propio.
 *
 * La mitad que se olvida siempre es `blockedTheViewer`: no se ve desde la tabla del espectador,
 * porque `blocks` solo lo lee su `blocker_id` (RN-23). Se consulta por `blocked_id`, con el índice
 * que la Tarea 6 creó exactamente para esto.
 */
export interface ConnectExclusionSets {
  viewerId: string;
  /** RN-47(2), mitad A: el espectador bloqueó a estos. */
  blockedByViewer: ReadonlySet<string>;
  /** RN-47(2), mitad B: estos bloquearon al espectador. */
  blockedTheViewer: ReadonlySet<string>;
  /** RN-47(3): conversación existente en **cualquier** estado, `ignored` incluido. */
  conversations: ReadonlySet<string>;
  /** RN-47(4), mitad A: solicitudes de mensaje que envió el espectador. */
  pendingRequestsSent: ReadonlySet<string>;
  /** RN-47(4), mitad B: solicitudes de mensaje que recibió. */
  pendingRequestsReceived: ReadonlySet<string>;
  /** RN-47(5): a quien ya sigue (`user_follows`, en cualquier estado). */
  following: ReadonlySet<string>;
  /** RN-47(6): `connect_dismissals`. RN-48: no caducan nunca. */
  dismissed: ReadonlySet<string>;
  /**
   * **RN-46, y NO es una de las seis de RN-47**: a quien ya se le enseñó **hoy**.
   *
   * Va aparte de `dismissed` a propósito, aunque las dos «esconden» a alguien: un «No mostrar más»
   * es para siempre (`RN-48`) y una impresión **caduca a medianoche** —la fecha va dentro de la PK
   * de `connect_impressions`, así que mañana vuelve a ser elegible sin que nadie borre nada, y la
   * purga diaria solo toca una de las dos tablas. Compartir cubo haría indistinguibles dos cosas
   * que se comportan distinto.
   *
   * Es también lo que **pagina** el scroll infinito: cada tanda registra sus impresiones, y la
   * siguiente las excluye.
   */
  shownToday: ReadonlySet<string>;
}

/**
 * Por qué se excluyó a alguien. Es para **logs y depuración del feed**, nunca para la respuesta:
 * decir «bloqueado» al cliente delataría el bloqueo que RN-23 esconde, y decir «ya tienes
 * conversación» delataría una `ignored` que RN-06 esconde. La respuesta de `connect-feed` no
 * explica ausencias — simplemente esa persona no está en la lista.
 */
export type ExclusionReason =
  | "self"
  | "blocked_by_viewer"
  | "blocked_the_viewer"
  | "conversation"
  | "pending_request_sent"
  | "pending_request_received"
  | "following"
  | "dismissed"
  | "shown_today";

/** El motivo por el que `userId` queda fuera del pool, o `null` si es elegible. */
export function exclusionReason(
  userId: string,
  sets: ConnectExclusionSets,
): ExclusionReason | null {
  if (userId === sets.viewerId) return "self"; // RN-47(1)
  if (sets.blockedByViewer.has(userId)) return "blocked_by_viewer"; // RN-47(2a)
  if (sets.blockedTheViewer.has(userId)) return "blocked_the_viewer"; // RN-47(2b)
  if (sets.conversations.has(userId)) return "conversation"; // RN-47(3)
  if (sets.pendingRequestsSent.has(userId)) return "pending_request_sent"; // RN-47(4a)
  if (sets.pendingRequestsReceived.has(userId)) return "pending_request_received"; // RN-47(4b)
  if (sets.following.has(userId)) return "following"; // RN-47(5)
  if (sets.dismissed.has(userId)) return "dismissed"; // RN-47(6) + RN-48
  if (sets.shownToday.has(userId)) return "shown_today"; // RN-46, no es de RN-47
  return null;
}

/**
 * El pool sin los excluidos. Conserva el orden y **los objetos originales** (no clona): el
 * candidato lleva más campos que el `userId` y `connect-feed` los necesita para pintar la tarjeta.
 */
export function applyExclusions<T extends { userId: string }>(
  pool: readonly T[],
  sets: ConnectExclusionSets,
): T[] {
  return pool.filter((candidate) => exclusionReason(candidate.userId, sets) === null);
}

/**
 * RN-49 en tres desenlaces. `candidates` ya viene **sin excluidos** en los tres.
 *
 * `relaxed` no es «hay más gente»: es «puntúa sin el cuadrado de RN-42». Ver la nota de abajo.
 */
export type PoolResolution<T> =
  | { kind: "full"; candidates: T[] }
  | { kind: "relaxed"; candidates: T[] }
  | { kind: "empty"; candidates: [] };

/**
 * Aplica RN-47 y decide el desenlace de RN-49.
 *
 * ────────────────────────────────────────────────────────────────────────────────────────────
 * **RN-49 SE APOYA EN ALGO QUE RN-41 NIEGA, y por eso «relajar» significa aquí menos de lo que
 * su texto promete.** RN-49 dice: «si tras aplicar exclusiones no hay suficientes candidatos,
 * relajar primero (ignorar el filtro activo y muestrear del pool completo)». Pero RN-41 dice que
 * «ningún filtro excluye a nadie, solo redistribuye probabilidad»: el filtro es un **peso puro**,
 * así que el conjunto de elegibles es idéntico con filtro y sin él, y relajarlo **no puede añadir
 * ni un candidato**. Y como el muestreo es *sin reposición* y la tanda es de 20, cuando quedan ≤20
 * elegibles entran todos igualmente, pesen lo que pesen.
 *
 * O sea: en el escenario exacto del que habla RN-49, relajar solo puede cambiar **el orden**.
 * Se implementa así —`relaxed` deja de elevar al cuadrado el multiplicador del filtro (RN-42)—
 * porque es la única lectura que cumple la letra de RN-49 sin contradecir a RN-41. Decidido con
 * el usuario el 2026-08-25; alternativa descartada: hacer que el filtro restrinja de verdad, que
 * daría sentido pleno a RN-49 pero exigiría enmendar RN-41, que es explícita.
 *
 * Lo que **sí** es carne de RN-49 y se cumple entero: nunca una lista vacía sin explicación —
 * de ahí `empty`, que la UI convierte en el empty state.
 * ────────────────────────────────────────────────────────────────────────────────────────────
 *
 * **Relajar NO relaja las exclusiones**, y es el atajo peligroso que este tipo cierra: «no hay
 * bastantes, tiro del pool completo» devolvería a un bloqueado a Conectar justo cuando escasean
 * los candidatos, rompiendo RN-24. Por eso las exclusiones se aplican **antes** de decidir el
 * desenlace y los tres lo comparten.
 */
export function resolvePool<T extends { userId: string }>(
  pool: readonly T[],
  sets: ConnectExclusionSets,
  batchSize: number = BATCH_SIZE,
): PoolResolution<T> {
  const eligible = applyExclusions(pool, sets);

  if (eligible.length === 0) return { kind: "empty", candidates: [] };
  // `<` y no `<=`: una tanda de 20 con 20 elegibles justos ya es «suficientes». Con `<=` se
  // relajaría el filtro que el usuario acaba de elegir en el caso normal de una base pequeña.
  if (eligible.length < batchSize) return { kind: "relaxed", candidates: eligible };
  return { kind: "full", candidates: eligible };
}
