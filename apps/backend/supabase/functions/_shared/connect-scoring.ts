// Algoritmo de recomendación de Conectar (§7): puntuación (§7.1), efecto del filtro (§7.2) y
// muestreo (§7.3). PURA: sin red, sin Postgres y **sin `Math.random`** — el azar entra por
// parámetro, que es lo único que hace que un test de muestreo signifique algo.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// ESTA ES LA FRONTERA DEL ART. 9 RGPD. Los tres ejes de coincidencia son el catálogo de salud
// mental (`onboarding_responses`, `user_experiences`, `profiles_private`), y aquí entran para
// salir convertidos en **un número**. Ni un slug, ni un id de categoría, ni el desglose de
// `ScoreBreakdown` pueden viajar en la respuesta de `connect-feed`: el desglose diría qué eje
// coincidió, que es la categoría de salud mental dicha de otra forma. [ADR 0020].
// ─────────────────────────────────────────────────────────────────────────────────────────────
import {
  ACTIVE_FILTER_EXPONENT,
  AGE_MULTIPLIER_FALLBACK,
  AGE_MULTIPLIER_TIERS,
  BATCH_SIZE,
  NEUTRAL_MULTIPLIER,
  OVERLAP_MULTIPLIERS,
} from "./connect-scoring.config.ts";
import { type ConnectExclusionSets, resolvePool } from "./connect-exclusions.ts";

/** Los tres ejes de coincidencia del §7.1. */
export type ConnectAxis = "interests" | "suffered" | "current";

/** Los chips del §6.3, menos `Todos`, que es el conjunto vacío (RN-35). */
export type ConnectFilter = "age" | ConnectAxis;

export interface ConnectAxes {
  /** `null` cuando falta: pondera neutro, nunca excluye (RN-41). */
  ageYears: number | null;
  interests: readonly string[];
  suffered: readonly string[];
  current: readonly string[];
}

export interface ConnectCandidate extends ConnectAxes {
  userId: string;
}

/** Desglose por eje. **Interno**: nunca se serializa — ver la nota del Art. 9 en la cabecera. */
export interface ScoreBreakdown {
  age: number;
  interests: number;
  suffered: number;
  current: number;
  score: number;
}

/** El azar, inyectado. Devuelve [0, 1). */
export type RandomSource = () => number;

const SIN_FILTROS: ReadonlySet<ConnectFilter> = new Set();

/** §7.1, `M_edad`. Simétrico: solo importa la distancia, no quién es mayor. */
function ageMultiplier(a: number | null, b: number | null): number {
  if (a === null || b === null || !Number.isFinite(a) || !Number.isFinite(b)) {
    return AGE_MULTIPLIER_FALLBACK;
  }
  const difference = Math.abs(a - b);
  // Los tramos están ordenados de menor a mayor y gana el primero que encaje (ver el config).
  for (const tier of AGE_MULTIPLIER_TIERS) {
    if (difference <= tier.maxDifferenceYears) return tier.multiplier;
  }
  return AGE_MULTIPLIER_FALLBACK;
}

/**
 * Coincidencias **distintas** entre dos listas.
 *
 * Cuenta valores únicos, no ocurrencias: si contara ocurrencias, repetir una etiqueta inflaría el
 * score propio. El scoring corre en servidor, pero el dato de origen lo escribe el usuario.
 */
function commonCount(a: readonly string[], b: readonly string[]): number {
  if (a.length === 0 || b.length === 0) return 0;
  const other = new Set(b);
  let common = 0;
  for (const value of new Set(a)) {
    if (other.has(value)) common++;
  }
  return common;
}

/** §7.1: `1 + paso × (nº en común)`, con tope. Sin coincidencias, el neutro del producto. */
function overlapMultiplier(axis: ConnectAxis, a: readonly string[], b: readonly string[]): number {
  const common = commonCount(a, b);
  if (common === 0) return NEUTRAL_MULTIPLIER;
  const { step, cap } = OVERLAP_MULTIPLIERS[axis];
  return Math.min(1 + step * common, cap);
}

/**
 * §7.1 y §7.2: `score = 1 × M_edad × M_intereses × M_sufrida × M_actual`, con el multiplicador de
 * cada filtro activo elevado al cuadrado (RN-42).
 *
 * El cuadrado se aplica **después** del tope: `M_intereses` con 6 coincidencias es 3.0, y con el
 * filtro puesto 9.0 — no `min(4.0², 3.0)`. Es el ejemplo literal del §7.2.
 *
 * El score mínimo es **1, nunca 0** (RN-41): todo el mundo es elegible, y un peso 0 no se elegiría
 * jamás mientras quedara otro candidato — sería una exclusión disfrazada de ponderación.
 */
export function scoreCandidate(
  viewer: ConnectAxes,
  candidate: ConnectAxes,
  activeFilters: ReadonlySet<ConnectFilter> = SIN_FILTROS,
): ScoreBreakdown {
  const raw: Record<ConnectFilter, number> = {
    age: ageMultiplier(viewer.ageYears, candidate.ageYears),
    interests: overlapMultiplier("interests", viewer.interests, candidate.interests),
    suffered: overlapMultiplier("suffered", viewer.suffered, candidate.suffered),
    current: overlapMultiplier("current", viewer.current, candidate.current),
  };

  const weighted = (axis: ConnectFilter): number =>
    activeFilters.has(axis) ? raw[axis] ** ACTIVE_FILTER_EXPONENT : raw[axis];

  const age = weighted("age");
  const interests = weighted("interests");
  const suffered = weighted("suffered");
  const current = weighted("current");

  return { age, interests, suffered, current, score: age * interests * suffered * current };
}

/**
 * RN-44: **muestreo aleatorio ponderado sin reposición**, no ordenación por score.
 *
 * La diferencia no es cosmética. Una ordenación por score haría el feed idéntico en cada tanda y
 * dejaría a los perfiles de score bajo sin aparecer **nunca**, que en una app de apoyo entre
 * iguales significa que quien menos encaja con el algoritmo no conoce a nadie. El muestreo les da
 * probabilidad baja, no probabilidad cero.
 *
 * Ruleta con recálculo del total en cada extracción, que es O(n·k). Con `n` de unos miles y `k`
 * de 20 no compensa nada más sofisticado, y esta versión se lee de un vistazo.
 */
export function weightedSampleWithoutReplacement<T>(
  items: readonly T[],
  weightOf: (item: T) => number,
  count: number,
  random: RandomSource,
): T[] {
  const remaining = items.slice();
  // Los pesos se calculan UNA vez: `weightOf` puntúa, y repuntuar en cada vuelta multiplicaría el
  // trabajo por 20 sin cambiar el resultado.
  const weights = remaining.map((item) => {
    const w = weightOf(item);
    // Un peso no finito o ≤ 0 no puede existir por RN-41, pero si llegara envenenaría el total y
    // dejaría el muestreo devolviendo `undefined`. Cae al neutro en vez de reventar.
    return Number.isFinite(w) && w > 0 ? w : NEUTRAL_MULTIPLIER;
  });

  const take = Math.min(count, remaining.length);
  const picked: T[] = [];

  for (let drawn = 0; drawn < take; drawn++) {
    let total = 0;
    for (const w of weights) total += w;

    // Por defecto el ÚLTIMO, no el primero: si el sorteo devuelve exactamente 1.0, o si la suma
    // acumulada se queda una ulp corta del total por redondeo, el recorrido termina sin elegir.
    // Empezar por el último convierte ese borde en «sale el último», nunca en `undefined`.
    let index = remaining.length - 1;
    const roll = random() * total;
    let cumulative = 0;
    for (let i = 0; i < remaining.length; i++) {
      cumulative += weights[i];
      if (cumulative > roll) {
        index = i;
        break;
      }
    }

    picked.push(remaining[index]);
    remaining.splice(index, 1);
    weights.splice(index, 1);
  }

  return picked;
}

/**
 * La tanda del §7.3: excluir (RN-47) → resolver RN-49 → puntuar → muestrear.
 *
 * `kind` distingue los tres desenlaces de RN-49, y `relaxed` **no** es un error: es una tanda
 * buena servida sin el cuadrado del filtro. La UI usa `empty` para el empty state explícito.
 *
 * Las tres piezas se componen **aquí dentro**, y no en el handler de `connect-feed`, a propósito:
 * honrar `relaxed` es lo que un handler puede olvidar sin que nada se queje, y entonces RN-49
 * quedaría implementada en un tipo que nadie consulta.
 */
export type ConnectBatch =
  | { kind: "batch"; candidates: ConnectCandidate[] }
  | { kind: "relaxed"; candidates: ConnectCandidate[] }
  | { kind: "empty"; candidates: [] };

export function selectConnectBatch(
  viewer: ConnectAxes,
  pool: readonly ConnectCandidate[],
  sets: ConnectExclusionSets,
  activeFilters: ReadonlySet<ConnectFilter>,
  random: RandomSource,
  batchSize: number = BATCH_SIZE,
): ConnectBatch {
  const resolution = resolvePool(pool, sets, batchSize);
  if (resolution.kind === "empty") return { kind: "empty", candidates: [] };

  // RN-49: relajar es dejar de elevar al cuadrado. Nunca es tocar `resolution.candidates`, que ya
  // viene sin excluidos — relajar el filtro no relaja las exclusiones.
  const filters = resolution.kind === "relaxed" ? SIN_FILTROS : activeFilters;

  const candidates = weightedSampleWithoutReplacement(
    resolution.candidates,
    (candidate) => scoreCandidate(viewer, candidate, filters).score,
    batchSize,
    random,
  );

  return { kind: resolution.kind === "relaxed" ? "relaxed" : "batch", candidates };
}
