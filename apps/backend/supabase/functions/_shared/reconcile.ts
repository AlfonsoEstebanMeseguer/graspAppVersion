// Lógica de decisión del barrido de huérfanos. PURA: sin red, sin Postgres, sin R2.
//
// Está separada del handler porque R2 no existe en el stack local, y sin esta frontera el freno de
// emergencia —lo único que impide que un fallo de comparación vacíe el bucket— no sería testeable.
//
// Importa `validation.ts` (→ `http.ts` → `cors.ts`) para reusar `isUuid`. Es deliberado y los tres
// son declarativos, sin efectos secundarios, así que no rompe la pureza de arriba. Pero es la razón
// por la que nadie debe meter un helper con I/O en `validation.ts` sin darse cuenta de que este
// barrido de huérfanos lo importa.

import { isUuid } from "./validation.ts";

/** Prefijos de primer nivel que este barrido sabe reconciliar. */
export const KNOWN_PREFIXES = ["avatars/"] as const;

/** Horas que un objeto recién subido está protegido. Ver RECONCILE_GRACE_HOURS en el handler. */
export const DEFAULT_GRACE_HOURS = 24;

/** F3: tope absoluto de huérfanos por pasada. */
export const MAX_ORPHANS_PER_RUN = 500;

/**
 * F5: motivo de aborto cuando el conjunto referenciado se leyó incompleto. Es un motivo aparte y no
 * un `query_failed` porque aquí **ninguna consulta falla**: devuelven `error: null` y filas de menos.
 */
export const REFERENCED_SET_TRUNCATED = "referenced_set_truncated";

/** F4: proporción máxima de huérfanos sobre lo escaneado. */
export const ORPHAN_RATIO_LIMIT = 0.5;

/**
 * F4 solo se evalúa a partir de este número de objetos. Un porcentaje sobre una muestra diminuta no
 * mide nada: con 4 objetos y 3 abandonados, el 75 % haría abortar el barrido a diario y no limpiaría
 * nunca.
 */
export const RATIO_FLOOR_OBJECTS = 50;

export interface R2Object {
  key: string;
  lastModified: Date;
}

export interface OrphanCandidate {
  key: string;
  userId: string;
}

export interface ReconcileDecision {
  objectsScanned: number;
  orphansFound: number;
  /** Vacío si `abortedReason` no es null. Acotado a `MAX_ORPHANS_PER_RUN` si `cappedReason` no lo es. */
  enqueue: OrphanCandidate[];
  /** Claves huérfanas cuyo user_id no es un UUID: se cuentan pero no se encolan. */
  malformedKeys: string[];
  abortedReason: string | null;
  /**
   * Motivo por el que la pasada se acotó, o null. **Distinto de `abortedReason`**: aquí sí se ha
   * encolado trabajo (los más antiguos), solo que no todo. Una pasada acotada es sana pero
   * incompleta, y la siguiente sigue por donde esta lo dejó.
   */
  cappedReason: string | null;
}

/**
 * Veredicto de un freno.
 *
 * `abort` — la COMPARACIÓN no es fiable, así que ningún huérfano lo es: encolar cualquier cosa
 *   podría borrar un avatar vivo. No se encola nada, y eso no es negociable.
 * `cap` — la comparación es fiable y simplemente hay mucho: se encola el tope y se marca la pasada.
 */
export type BrakeVerdict =
  | { kind: "abort"; reason: string }
  | { kind: "cap"; reason: string };

/**
 * Extrae el user_id de `avatars/{user_id}/{fichero}`. Devuelve null si la clave no tiene la forma que
 * genera `profile-photo-upload-url` — en ese caso nadie puede saber de quién es el objeto.
 */
export function extractUserId(key: string): string | null {
  const parts = key.split("/");
  if (parts.length < 3) return null;
  if (parts[0] !== "avatars") return null;
  if (parts[2].length === 0) return null;
  return isUuid(parts[1]) ? parts[1] : null;
}

/** Un objeto dentro de la gracia puede ser una subida en curso, no un abandono. */
export function isWithinGrace(obj: R2Object, now: Date, graceHours: number): boolean {
  return obj.lastModified.getTime() > now.getTime() - graceHours * 3600_000;
}

/** Prefijos de la raíz que este barrido no sabe reconciliar. Se reportan; nunca se tocan. */
export function unknownPrefixes(rootPrefixes: string[]): string[] {
  const known = new Set<string>(KNOWN_PREFIXES);
  return rootPrefixes.filter((p) => !known.has(p));
}

/** Resultado de una consulta paginada del conjunto referenciado, ya acumulada por el handler. */
export interface PagedQueryOutcome {
  /** Tabla consultada. Solo para el log: dice CUÁL de las dos se leyó a medias. */
  source: string;
  /** Filas realmente acumuladas al recorrer todas las páginas. */
  rowsFetched: number;
  /** Total exacto que reportó PostgREST (`count: "exact"`), o null si no llegó a reportarlo. */
  reportedTotal: number | null;
}

/**
 * Detecta que una consulta del conjunto referenciado se leyó incompleta. Devuelve los nombres de las
 * fuentes que no cuadran (vacío = todas completas).
 *
 * POR QUÉ HACE FALTA ESTA COMPROBACIÓN
 * PostgREST recorta toda respuesta sin rango a `db-max-rows` (`max_rows = 1000` en config.toml) y eso
 * **no es un error**: llega `error: null` y 1000 filas. Un conjunto referenciado recortado convierte
 * en «huérfana» cada foto viva que se quedó fuera, y `media-gc-cron` las borra de R2 en 5 minutos.
 * Con 1500 avatares vivos, el barrido encolaba 500 borrados legítimos e irrecuperables sin que
 * ninguno de los otros frenos lo viese: F2 no (referenciados = 1000, no 0), F3 no (500 no supera
 * 500) y F4 no (500 no supera el 50 % de 1500). Empieza a doler a partir de la fila 1001.
 *
 * POR QUÉ SE COMPARA POR DESIGUALDAD Y NO POR «SE LEYÓ DE MENOS»
 * La dirección peligrosa es `rowsFetched < reportedTotal` (faltan referencias → sobran huérfanos),
 * pero leer de más solo puede pasar si la tabla cambió entre páginas, y en cuanto cambió tampoco se
 * puede afirmar que no faltara nada: 5 filas insertadas y 5 borradas a la vez cuadran el total y
 * dejan huecos. Cualquier descuadre significa «esta foto del conjunto no es fiable», y ante la duda
 * se aborta: un barrido perdido se repite mañana, un avatar borrado no vuelve.
 *
 * `reportedTotal === null` falla cerrado por lo mismo: sin total no hay nada que verificar.
 */
export function truncatedSources(outcomes: PagedQueryOutcome[]): string[] {
  return outcomes
    .filter((o) => o.reportedTotal === null || o.rowsFetched !== o.reportedTotal)
    .map((o) => o.source);
}

/**
 * Freno de emergencia. Devuelve el veredicto, o null si se puede encolar sin reservas.
 * F1 (error de consulta) lo maneja el handler: aquí no hay E/S que pueda fallar.
 *
 * `referencedTruncated` es obligatorio a propósito, no opcional con default `false`: un parámetro
 * que se puede omitir se omite, y omitirlo aquí equivale a afirmar «el conjunto está completo»
 * justo en el fallo que este freno existe para atrapar. Quien llame tiene que declararlo.
 *
 * POR QUÉ DOS CLASES DE FRENO Y NO UNA (H-S-03, auditoría del 2026-08-15)
 * Los cuatro frenos abortaban por igual, y eso convertía a F3/F4 en un interruptor de apagado
 * accesible desde cualquier cuenta: `profile-photo-upload-url` no tiene cuota, así que subir 501
 * objetos sin confirmar (~100 MB) hacía que cada pasada encontrase >500 huérfanos, abortase y
 * encolara CERO. El estado es absorbente —los huérfanos nunca bajan solos de 500— así que el
 * barrido quedaba inutilizado para siempre y con él el único recolector que cumple el Art. 17.
 * Y no hacía falta un atacante: a 10.000 usuarios, un 5 % de abandono mensual son ~500/mes.
 *
 * La distinción que lo arregla no es «cuánto de grave es» sino **¿de quién me estoy fiando?**:
 *   · F5/F2 dudan del CONJUNTO REFERENCIADO — si está incompleto, un objeto no referenciado puede
 *     ser perfectamente un avatar vivo. Encolar aunque sea uno es arriesgarse a un borrado
 *     irreversible: siguen abortando, y eso no se toca.
 *   · F3/F4 no dudan de nada: el conjunto está completo y verificado (F5 y F2 ya pasaron), los
 *     huérfanos son huérfanos de verdad y solo son muchos. Ahí abortar no protege de nada — deja el
 *     trabajo sin hacer y regala el interruptor. Se acota: se encola el tope y se marca la pasada.
 *
 * Un tope que procesa parte del trabajo no es armable: por muchos huérfanos que suba un atacante,
 * cada pasada drena `MAX_ORPHANS_PER_RUN` y el barrido nunca se para.
 */
export function evaluateBrake(params: {
  objectsScanned: number;
  orphansFound: number;
  referencedCount: number;
  referencedTruncated: boolean;
}): BrakeVerdict | null {
  const { objectsScanned, orphansFound, referencedCount, referencedTruncated } = params;

  // F5 — va PRIMERO: si el conjunto está incompleto, `orphansFound` mide otra cosa y los frenos que
  // dependen de él (F3, F4) estarían opinando sobre un número inventado.
  if (referencedTruncated) return { kind: "abort", reason: REFERENCED_SET_TRUNCATED };

  // F2 — el escenario catastrófico: la consulta devuelve vacío en silencio y TODO parece huérfano.
  if (referencedCount === 0 && objectsScanned > 0) {
    return { kind: "abort", reason: "referenced_set_empty" };
  }

  // F3 — tope absoluto. Acota: ver la cabecera.
  if (orphansFound > MAX_ORPHANS_PER_RUN) return { kind: "cap", reason: "too_many_orphans" };

  // F4 — proporción anómala, solo con muestra suficiente. Acota por lo mismo que F3.
  if (objectsScanned >= RATIO_FLOOR_OBJECTS && orphansFound > objectsScanned * ORPHAN_RATIO_LIMIT) {
    return { kind: "cap", reason: "orphan_ratio_too_high" };
  }

  return null;
}

export function decideReconcile(params: {
  objects: R2Object[];
  referenced: Set<string>;
  now: Date;
  graceHours: number;
  /** true si alguna consulta del conjunto referenciado se leyó incompleta (ver `truncatedSources`). */
  referencedTruncated: boolean;
}): ReconcileDecision {
  const { objects, referenced, now, graceHours, referencedTruncated } = params;

  const candidates = objects.filter(
    (o) => !referenced.has(o.key) && !isWithinGrace(o, now, graceHours),
  );

  const verdict = evaluateBrake({
    objectsScanned: objects.length,
    orphansFound: candidates.length,
    referencedCount: referenced.size,
    referencedTruncated,
  });

  if (verdict?.kind === "abort") {
    return {
      objectsScanned: objects.length,
      orphansFound: candidates.length,
      enqueue: [],
      malformedKeys: [],
      abortedReason: verdict.reason,
      cappedReason: null,
    };
  }

  // Acotar = los MÁS ANTIGUOS primero, igual que `media-gc-cron` drena su cola: son los que llevan
  // más tiempo incumpliendo. El orden hay que imponerlo — `objects` viene como lo lista S3, que es
  // lexicográfico por clave, y una clave empieza por el user_id, así que sin esto el corte
  // favorecería sistemáticamente a los usuarios con el UUID más bajo y los del final no se
  // limpiarían jamás.
  const selected = verdict?.kind === "cap"
    ? [...candidates]
      .sort((a, b) => a.lastModified.getTime() - b.lastModified.getTime())
      .slice(0, MAX_ORPHANS_PER_RUN)
    : candidates;

  const enqueue: OrphanCandidate[] = [];
  const malformedKeys: string[] = [];
  for (const candidate of selected) {
    const userId = extractUserId(candidate.key);
    if (userId === null) malformedKeys.push(candidate.key);
    else enqueue.push({ key: candidate.key, userId });
  }

  return {
    objectsScanned: objects.length,
    orphansFound: candidates.length,
    enqueue,
    malformedKeys,
    abortedReason: null,
    cappedReason: verdict?.kind === "cap" ? verdict.reason : null,
  };
}
