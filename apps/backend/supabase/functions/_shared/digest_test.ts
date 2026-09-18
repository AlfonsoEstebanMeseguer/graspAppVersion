import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type DigestFacts,
  hasIncidents,
  isHeartbeatDay,
  renderDigest,
  shouldSend,
} from "./digest.ts";

// 2026-08-12 es miércoles; 2026-08-10 es lunes.
const WEDNESDAY = new Date("2026-08-12T08:00:00Z");
const MONDAY = new Date("2026-08-10T08:00:00Z");

// `now` es parámetro para que el ultimo barrido quede SIEMPRE en el pasado respecto al instante que
// evalua cada test. Fijarlo al miercoles dejaba un timestamp en el futuro en los tests del lunes.
function healthy(now: Date = WEDNESDAY): DigestFacts {
  return {
    failedCount: 0,
    failedOldest: null,
    failedSamples: [],
    stalePendingCount: 0,
    stalePendingOldest: null,
    lastSuccessfulSweepAt: new Date(now.getTime() - 5 * 3600_000),
    abortedRuns: [],
    cappedRuns: [],
    unknownPrefixes: [],
    orphansEnqueued: 0,
    staleAuditRows: 0,
    // Sano de partida: hoy la base es mucho mas pequena que la muestra, asi que el tope del pool ni
    // siquiera existe (ADR 0030).
    eligibleProfiles: 3,
  };
}

// =====================================================================================
// La cobertura del pool de Conectar (ADR 0030)
// =====================================================================================
// Lo que estos tests protegen no es el calculo —eso vive en `connect-pool_test.ts`— sino que el
// aviso LLEGUE: el numero anterior dependia de que alguien se acordara de revisarlo.

Deno.test("cobertura del pool: por debajo del umbral ES una incidencia", () => {
  assertEquals(hasIncidents({ ...healthy(), eligibleProfiles: 2001 }, WEDNESDAY), true);
});

Deno.test("cobertura del pool: en el umbral exacto NO es incidencia", () => {
  // Una alerta que salta en el valor aceptable se deja de leer.
  assertEquals(hasIncidents({ ...healthy(), eligibleProfiles: 2000 }, WEDNESDAY), false);
});

Deno.test("cobertura del pool: baja, sale en el ASUNTO", () => {
  // El correo se ojea desde la lista de la bandeja: si solo estuviera en el cuerpo, no se veria.
  const { subject } = renderDigest({ ...healthy(), eligibleProfiles: 4000 }, WEDNESDAY);
  assertStringIncludes(subject, "cobertura");
});

Deno.test("cobertura del pool: el numero se emite SIEMPRE, tambien sin incidencias", () => {
  // Incondicional, como `orphansEnqueued`: un valor que solo aparece cuando esta disparado no tiene
  // con que compararse el dia que aparece.
  const { text } = renderDigest(healthy(), WEDNESDAY);
  assertStringIncludes(text, "Perfiles elegibles");
});

Deno.test("cobertura del pool: al avisar dice QUE hacer, no solo que pasa", () => {
  const { text } = renderDigest({ ...healthy(), eligibleProfiles: 5000 }, WEDNESDAY);
  assertStringIncludes(text, "MAX_POOL");
});

Deno.test("isHeartbeatDay: lunes si", () => {
  assertEquals(isHeartbeatDay(MONDAY), true);
});

Deno.test("isHeartbeatDay: miercoles no", () => {
  assertEquals(isHeartbeatDay(WEDNESDAY), false);
});

Deno.test("hasIncidents: todo sano es false", () => {
  assertEquals(hasIncidents(healthy(), WEDNESDAY), false);
});

Deno.test("hasIncidents: una fila failed es incidencia", () => {
  const facts = { ...healthy(), failedCount: 1 };
  assertEquals(hasIncidents(facts, WEDNESDAY), true);
});

Deno.test("hasIncidents: pending viejo es incidencia", () => {
  const facts = { ...healthy(), stalePendingCount: 3 };
  assertEquals(hasIncidents(facts, WEDNESDAY), true);
});

Deno.test("hasIncidents: barrido abortado es incidencia", () => {
  const facts = { ...healthy(), abortedRuns: [{ startedAt: WEDNESDAY, reason: "query_failed" }] };
  assertEquals(hasIncidents(facts, WEDNESDAY), true);
});

// Acotar no es una averia, pero SI tiene que verse: sin esto, la correccion de H-S-03 habria dejado
// el freno tan silencioso como el aborto que sustituyo.
Deno.test("hasIncidents: barrido acotado es incidencia", () => {
  const facts = {
    ...healthy(),
    cappedRuns: [{
      startedAt: WEDNESDAY,
      reason: "too_many_orphans",
      orphansFound: 900,
      orphansEnqueued: 500,
    }],
  };
  assertEquals(hasIncidents(facts, WEDNESDAY), true);
});

Deno.test("renderDigest: un barrido acotado sale en el asunto", () => {
  const facts = {
    ...healthy(),
    cappedRuns: [{
      startedAt: WEDNESDAY,
      reason: "too_many_orphans",
      orphansFound: 900,
      orphansEnqueued: 500,
    }],
  };
  const { subject, text } = renderDigest(facts, WEDNESDAY);
  assertStringIncludes(subject, "1 acotados");
  assertStringIncludes(text, "encolados 500 de 900");
});

Deno.test("hasIncidents: prefijo desconocido es incidencia", () => {
  const facts = { ...healthy(), unknownPrefixes: ["panic-buffer/"] };
  assertEquals(hasIncidents(facts, WEDNESDAY), true);
});

// El caso que justifica la tabla: el barrido dejo de correr y nada mas lo delata.
Deno.test("hasIncidents: barrido con mas de 48h es incidencia", () => {
  const facts = {
    ...healthy(),
    lastSuccessfulSweepAt: new Date(WEDNESDAY.getTime() - 49 * 3600_000),
  };
  assertEquals(hasIncidents(facts, WEDNESDAY), true);
});

Deno.test("hasIncidents: barrido que no ha corrido nunca es incidencia", () => {
  const facts = { ...healthy(), lastSuccessfulSweepAt: null };
  assertEquals(hasIncidents(facts, WEDNESDAY), true);
});

Deno.test("shouldSend: sano en miercoles NO envia", () => {
  assertEquals(shouldSend(healthy(), WEDNESDAY), false);
});

// El latido: la AUSENCIA del email del lunes es la senal de que el canal esta roto.
Deno.test("shouldSend: sano en lunes SI envia (latido)", () => {
  assertEquals(shouldSend(healthy(MONDAY), MONDAY), true);
});

Deno.test("shouldSend: con incidencia envia cualquier dia", () => {
  assertEquals(shouldSend({ ...healthy(), failedCount: 2 }, WEDNESDAY), true);
});

Deno.test("renderDigest: el latido dice explicitamente que no hay incidencias", () => {
  const { subject, text } = renderDigest(healthy(MONDAY), MONDAY);
  assert(subject.includes("sin incidencias"));
  assert(text.includes("Ultimo barrido"));
});

Deno.test("renderDigest: acota la muestra a MAX_SAMPLE_ROWS filas", () => {
  const samples = Array.from({ length: 25 }, (_, i) => ({
    id: `id-${i}`,
    photoPath: `avatars/u/${i}.webp`,
    lastError: "boom",
  }));
  const { text } = renderDigest({ ...healthy(), failedCount: 25, failedSamples: samples }, WEDNESDAY);
  assertEquals(text.includes("avatars/u/9.webp"), true);
  assertEquals(text.includes("avatars/u/10.webp"), false);
});

Deno.test("renderDigest: barrido muerto como unica incidencia aparece en subject", () => {
  const facts = {
    ...healthy(),
    lastSuccessfulSweepAt: new Date(WEDNESDAY.getTime() - 49 * 3600_000),
  };
  const { subject } = renderDigest(facts, WEDNESDAY);
  assertEquals(subject.includes("barrido muerto"), true);
  assertEquals(subject.includes("sin incidencias"), false);
});

Deno.test("renderDigest: pending atascados como unica incidencia aparece en subject", () => {
  const facts = { ...healthy(), stalePendingCount: 3 };
  const { subject } = renderDigest(facts, WEDNESDAY);
  assertEquals(subject.includes("3 pending atascados"), true);
  assertEquals(subject.includes("sin incidencias"), false);
});

// --- orphansEnqueued -------------------------------------------------------
// Encolar NO es una incidencia (es el trabajo del barrido), pero es la unica medida del volumen de
// borrado. Sin ella, un barrido que encola 499 objetos —uno por debajo del freno F3— mandaba un
// correo identico al de un barrido que no encolo nada, y esos 499 ficheros ya no existen en R2.

Deno.test("hasIncidents: encolar objetos NO es por si mismo una incidencia", () => {
  assertEquals(hasIncidents({ ...healthy(), orphansEnqueued: 499 }, WEDNESDAY), false);
});

Deno.test("shouldSend: encolar objetos no fuerza envio en un dia sano", () => {
  assertEquals(shouldSend({ ...healthy(), orphansEnqueued: 499 }, WEDNESDAY), false);
});

Deno.test("renderDigest: el cuerpo dice los encolados aunque sean 0", () => {
  const { text } = renderDigest(healthy(), WEDNESDAY);
  assert(text.includes("Objetos encolados para borrado en las ultimas 24 h: 0"));
});

Deno.test("renderDigest: el cuerpo dice los encolados cuando los hay", () => {
  const { text } = renderDigest({ ...healthy(), orphansEnqueued: 499 }, WEDNESDAY);
  assert(text.includes("Objetos encolados para borrado en las ultimas 24 h: 499"));
});

// El caso del hallazgo: dia sano, ningun freno disparado, 499 ficheros borrados. El asunto es lo
// unico que se lee desde la bandeja, asi que el numero tiene que estar ahi.
Deno.test("renderDigest: los encolados aparecen en el subject de un dia sin incidencias", () => {
  const { subject } = renderDigest({ ...healthy(MONDAY), orphansEnqueued: 499 }, MONDAY);
  assertEquals(subject.includes("499 encolados"), true);
  assertEquals(subject.includes("sin incidencias"), true);
});

Deno.test("renderDigest: sin encolados el subject sano no menciona el contador", () => {
  const { subject } = renderDigest(healthy(MONDAY), MONDAY);
  assertEquals(subject.includes("encolados"), false);
});

Deno.test("renderDigest: los encolados acompanan a las incidencias en el subject", () => {
  const facts = { ...healthy(), stalePendingCount: 3, orphansEnqueued: 12 };
  const { subject } = renderDigest(facts, WEDNESDAY);
  assertEquals(subject.includes("3 pending atascados"), true);
  assertEquals(subject.includes("12 encolados"), true);
});

Deno.test("renderDigest: barrido muerto y failed en subject con barrido primero", () => {
  const facts = {
    ...healthy(),
    failedCount: 2,
    failedSamples: [{ id: "id-1", photoPath: "avatars/u/1.webp", lastError: "boom" }],
    lastSuccessfulSweepAt: new Date(WEDNESDAY.getTime() - 49 * 3600_000),
  };
  const { subject } = renderDigest(facts, WEDNESDAY);
  assertEquals(subject.includes("barrido muerto"), true);
  assertEquals(subject.includes("2 failed"), true);
  const deadIdx = subject.indexOf("barrido muerto");
  const failedIdx = subject.indexOf("2 failed");
  assertEquals(deadIdx < failedIdx, true);
});

Deno.test("hasIncidents: filas de auditoria sin purgar es incidencia", () => {
  assertEquals(hasIncidents({ ...healthy(), staleAuditRows: 3 }, WEDNESDAY), true);
});

Deno.test("hasIncidents: cero filas sin purgar no es incidencia", () => {
  assertEquals(hasIncidents({ ...healthy(), staleAuditRows: 0 }, WEDNESDAY), false);
});

Deno.test("renderDigest: las auditorias sin purgar salen en el subject", () => {
  const { subject } = renderDigest({ ...healthy(), staleAuditRows: 4 }, WEDNESDAY);
  assertEquals(subject.includes("4 auditorias sin purgar"), true);
  assertEquals(subject.includes("sin incidencias"), false);
});

// Incondicional como el resto de contadores: un numero que solo aparece cuando esta
// disparado no tiene con que compararse el dia que aparece.
Deno.test("renderDigest: el cuerpo imprime las auditorias sin purgar aunque sean 0", () => {
  const { text } = renderDigest(healthy(), WEDNESDAY);
  assertEquals(text.includes("Filas de auditoria sin purgar"), true);
});
