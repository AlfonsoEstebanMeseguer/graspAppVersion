// Lógica del digest de salud. PURA: sin red, sin Postgres.
//
// El handler recoge los hechos; este módulo decide si merecen un email y cómo se redacta.
import { MAX_POOL, poolCoverage, poolCoverageIsLow } from "./connect-pool.ts";

/** Una fila 'pending' más vieja que esto delata un GC atascado. */
export const STALE_PENDING_HOURS = 1;

/** Sin un barrido sano en este tiempo, el barrido está muerto. */
export const DEAD_SWEEP_HOURS = 48;

/** Minimización de datos: un photo_path contiene el user_id y sale hacia una bandeja de correo. */
export const MAX_SAMPLE_ROWS = 10;

/** Lo que borra `photo-audit-retention` cada noche. Decisión 0009. */
export const AUDIT_RETENTION_DAYS = 90;

/**
 * A partir de aquí el digest considera que la retención NO se está aplicando.
 *
 * El día de diferencia con `AUDIT_RETENTION_DAYS` es deliberado, no un error de cálculo: la retención
 * corre a las 04:00 y el digest a las 08:00, así que cada mañana hay filas que ya han cumplido 90 días
 * y todavía no han tenido su turno de borrado. Comprobando 90 el correo alertaría TODOS los días sobre
 * un sistema sano, y una alerta que siempre salta se deja de leer. Una fila que sobrevive a 91 días sí
 * significa que la retención lleva más de 24 h sin correr.
 */
export const AUDIT_STALE_DAYS = 91;

export interface FailedSample {
  id: string;
  photoPath: string;
  lastError: string | null;
}

export interface AbortedRun {
  startedAt: Date;
  reason: string;
}

/** Una pasada que encoló el tope y dejó el resto para mañana. Ver `CappedRun` en DigestFacts. */
export interface CappedRun {
  startedAt: Date;
  reason: string;
  orphansFound: number;
  orphansEnqueued: number;
}

export interface DigestFacts {
  failedCount: number;
  failedOldest: Date | null;
  failedSamples: FailedSample[];
  stalePendingCount: number;
  stalePendingOldest: Date | null;
  lastSuccessfulSweepAt: Date | null;
  abortedRuns: AbortedRun[];
  /**
   * Pasadas de las últimas 24 h que se ACOTARON (H-S-03): encolaron `MAX_ORPHANS_PER_RUN` y dejaron
   * el resto para la siguiente.
   *
   * No es lo mismo que `abortedRuns` y por eso va aparte: una pasada acotada **hizo su trabajo**,
   * solo que no todo, así que por sí sola no es una avería. Se vigila porque el fallo que importa es
   * el ACUMULATIVO: si se acota día tras día, los huérfanos entran más rápido de lo que el barrido
   * los drena y la diferencia no se recupera sola — o alguien está subiendo objetos sin confirmar a
   * propósito, o `MAX_ORPHANS_PER_RUN` se quedó corto para el volumen real. Sin esta señal, acotar
   * sería exactamente igual de silencioso que el aborto que sustituyó.
   */
  cappedRuns: CappedRun[];
  unknownPrefixes: string[];
  /**
   * Objetos que el barrido mandó borrar en las últimas 24 h (suma de `orphans_enqueued`).
   *
   * NO es una incidencia: encolar es el trabajo del barrido. Se reporta porque era el único número
   * del sistema que no dejaba rastro en ningún sitio, y es justo el que mide el daño cuando algo va
   * mal: encolar es irreversible en la práctica, porque `media-gc-cron` borra de R2 en los 5 minutos
   * siguientes y trata la fila como una orden incondicional. Un barrido que encolaba 499 objetos
   * —uno por debajo del freno F3, el peor caso que NO aborta— mandaba un correo idéntico byte a byte
   * al de un barrido que no encoló nada.
   */
  orphansEnqueued: number;
  /**
   * Filas de `photo_audit_log` con más de `AUDIT_STALE_DAYS` días.
   *
   * Vigila el SÍNTOMA, no la ejecución del job: detecta igual un cron que dejó de correr, uno que
   * corre bajo un rol sin `DELETE`, y uno que corre y no borra nada por un bug en el `where`. Son
   * datos personales conservados fuera del plazo que la propia decisión 0009 fija.
   */
  staleAuditRows: number;
  /**
   * Perfiles elegibles para el feed de Conectar (`profiles` con `tag not null`), para vigilar qué
   * fracción de ellos cabe en una muestra de `MAX_POOL` (ADR 0030).
   *
   * **No es una incidencia de medios**, y aun así vive en este digest: es el único canal de aviso
   * que este proyecto tiene y que ya funciona. Un número que hay que revisar «cuando la base
   * crezca» depende de que alguien se acuerde, y nadie se acuerda — es el patrón del *mecanismo sin
   * puerta de entrada*, aquí en su versión de vigilancia.
   */
  eligibleProfiles: number;
}

function sweepIsDead(facts: DigestFacts, now: Date): boolean {
  if (facts.lastSuccessfulSweepAt === null) return true;
  return facts.lastSuccessfulSweepAt.getTime() < now.getTime() - DEAD_SWEEP_HOURS * 3600_000;
}

export function hasIncidents(facts: DigestFacts, now: Date): boolean {
  return (
    facts.failedCount > 0 ||
    facts.stalePendingCount > 0 ||
    facts.abortedRuns.length > 0 ||
    facts.cappedRuns.length > 0 ||
    facts.unknownPrefixes.length > 0 ||
    facts.staleAuditRows > 0 ||
    poolCoverageIsLow(facts.eligibleProfiles) ||
    sweepIsDead(facts, now)
  );
}

/** Lunes en UTC. getUTCDay(): 0 = domingo, 1 = lunes. */
export function isHeartbeatDay(now: Date): boolean {
  return now.getUTCDay() === 1;
}

/**
 * Un digest que solo escribe cuando hay problemas es indistinguible de un digest muerto. El latido de
 * los lunes convierte la AUSENCIA del email en la señal de que el canal de correo se rompió.
 */
export function shouldSend(facts: DigestFacts, now: Date): boolean {
  return hasIncidents(facts, now) || isHeartbeatDay(now);
}

function formatAge(from: Date | null, now: Date): string {
  if (from === null) return "nunca";
  const hours = Math.floor((now.getTime() - from.getTime()) / 3600_000);
  return `hace ${hours} h (${from.toISOString()})`;
}

export function renderDigest(facts: DigestFacts, now: Date): { subject: string; text: string } {
  const incidents = hasIncidents(facts, now);
  let subject: string;

  // El volumen de borrado va en el ASUNTO, no solo en el cuerpo: un correo se ojea desde la lista de
  // la bandeja, y ahí es donde tiene que verse que anoche se mandaron borrar 499 ficheros. Va también
  // en el asunto "sin incidencias", porque el caso peligroso es precisamente el que no dispara
  // ninguna alarma.
  const enqueuedTag = facts.orphansEnqueued > 0 ? `${facts.orphansEnqueued} encolados` : null;

  if (!incidents) {
    subject = enqueuedTag === null
      ? "[Grasp] Salud del GC de medios: sin incidencias"
      : `[Grasp] Salud del GC de medios: sin incidencias, ${enqueuedTag}`;
  } else {
    const parts: string[] = [];
    if (sweepIsDead(facts, now)) parts.push("barrido muerto");
    if (facts.failedCount > 0) parts.push(`${facts.failedCount} failed`);
    if (facts.stalePendingCount > 0) parts.push(`${facts.stalePendingCount} pending atascados`);
    if (facts.abortedRuns.length > 0) parts.push(`${facts.abortedRuns.length} abortados`);
    if (facts.cappedRuns.length > 0) parts.push(`${facts.cappedRuns.length} acotados`);
    if (facts.unknownPrefixes.length > 0) parts.push(`${facts.unknownPrefixes.length} prefijos sin cablear`);
    if (facts.staleAuditRows > 0) {
      parts.push(`${facts.staleAuditRows} auditorias sin purgar`);
    }
    if (poolCoverageIsLow(facts.eligibleProfiles)) {
      parts.push(`cobertura del pool ${Math.round(poolCoverage(facts.eligibleProfiles) * 100)}%`);
    }
    if (enqueuedTag !== null) parts.push(enqueuedTag);
    subject = `[Grasp] Salud del GC de medios: ${parts.join(", ")}`;
  }

  const lines: string[] = [];
  lines.push(`Fecha: ${now.toISOString()}`);
  lines.push(`Ultimo barrido sano: ${formatAge(facts.lastSuccessfulSweepAt, now)}`);
  // Incondicional, incluso a 0: el valor solo sirve como referencia si se ve TODOS los dias. Un
  // numero que solo aparece cuando es distinto de cero no tiene con que compararse el dia que
  // aparece disparado.
  lines.push(`Objetos encolados para borrado en las ultimas 24 h: ${facts.orphansEnqueued}`);
  lines.push("");

  if (sweepIsDead(facts, now)) {
    lines.push(`!! El barrido no completa una pasada sana desde hace mas de ${DEAD_SWEEP_HOURS} h.`);
    lines.push("   Sin barrido, los huerfanos de R2 dejan de detectarse (Art. 17 RGPD).");
    lines.push("");
  }

  lines.push(`Filas en 'failed' (terminal, incumplimiento activo): ${facts.failedCount}`);
  if (facts.failedCount > 0) {
    lines.push(`  Mas antigua: ${formatAge(facts.failedOldest, now)}`);
    for (const sample of facts.failedSamples.slice(0, MAX_SAMPLE_ROWS)) {
      lines.push(`  - ${sample.id} ${sample.photoPath} :: ${sample.lastError ?? "sin motivo"}`);
    }
    if (facts.failedCount > MAX_SAMPLE_ROWS) {
      lines.push(`  ... y ${facts.failedCount - MAX_SAMPLE_ROWS} mas (muestra acotada a proposito)`);
    }
  }
  lines.push("");

  lines.push(`Filas en 'pending' con mas de ${STALE_PENDING_HOURS} h: ${facts.stalePendingCount}`);
  if (facts.stalePendingCount > 0) {
    lines.push(`  Mas antigua: ${formatAge(facts.stalePendingOldest, now)}`);
  }
  lines.push("");

  lines.push(`Barridos abortados en las ultimas 24 h: ${facts.abortedRuns.length}`);
  for (const run of facts.abortedRuns.slice(0, MAX_SAMPLE_ROWS)) {
    lines.push(`  - ${run.startedAt.toISOString()} :: ${run.reason}`);
  }
  lines.push("");

  lines.push(`Barridos ACOTADOS en las ultimas 24 h: ${facts.cappedRuns.length}`);
  for (const run of facts.cappedRuns.slice(0, MAX_SAMPLE_ROWS)) {
    lines.push(
      `  - ${run.startedAt.toISOString()} :: ${run.reason} ` +
        `(encolados ${run.orphansEnqueued} de ${run.orphansFound})`,
    );
  }
  if (facts.cappedRuns.length > 0) {
    lines.push("  Acotar NO es una averia: la pasada encolo el tope y el resto espera a la");
    lines.push("  siguiente. Lo que hay que mirar es si se repite: si se acota varios dias");
    lines.push("  seguidos, los huerfanos entran mas rapido de lo que el barrido los drena y la");
    lines.push("  diferencia no se recupera sola. Revisar si alguien esta subiendo objetos sin");
    lines.push("  confirmar, o si MAX_ORPHANS_PER_RUN se quedo corto.");
  }
  lines.push("");

  lines.push(
    `Filas de auditoria sin purgar (mas de ${AUDIT_STALE_DAYS} dias): ${facts.staleAuditRows}`,
  );
  if (facts.staleAuditRows > 0) {
    lines.push(`  La retencion de ${AUDIT_RETENTION_DAYS} dias no se esta aplicando. Son datos`);
    lines.push("  personales conservados fuera de plazo (decision 0009).");
  }
  lines.push("");

  // Incondicional, como el volumen encolado: un numero que solo aparece cuando esta disparado no
  // tiene con que compararse el dia que aparece. Y es el unico sitio donde se ve crecer la base.
  lines.push(
    `Perfiles elegibles para Conectar: ${facts.eligibleProfiles} ` +
      `(cobertura de la muestra: ${Math.round(poolCoverage(facts.eligibleProfiles) * 100)}% ` +
      `de MAX_POOL=${MAX_POOL})`,
  );
  if (poolCoverageIsLow(facts.eligibleProfiles)) {
    lines.push("  Menos de la mitad de los elegibles entra en una tanda, asi que el tope decide");
    lines.push("  tanto como el score: alguien con score alto queda fuera por no entrar en la");
    lines.push("  muestra. NO es una averia y no hay nada roto — es la senal que el ADR 0030 pide");
    lines.push("  para volver a decidir sobre MAX_POOL con datos: subirlo, pasar a tablesample, o");
    lines.push("  materializar los candidatos con un cron. Ver el punto 16 de pending-messaging.");
  }
  lines.push("");

  if (facts.unknownPrefixes.length > 0) {
    lines.push(`Prefijos del bucket SIN cablear al barrido: ${facts.unknownPrefixes.join(", ")}`);
    lines.push("   No se han tocado. Hay que darlos de alta en KNOWN_PREFIXES o dejarlos fuera a proposito.");
    lines.push("");
  }

  if (!incidents) {
    lines.push("Sin incidencias. Este correo es el latido semanal: si un lunes no llega, el canal");
    lines.push("de email esta roto y las alertas reales tampoco llegarian.");
  }

  return { subject, text: lines.join("\n") };
}
