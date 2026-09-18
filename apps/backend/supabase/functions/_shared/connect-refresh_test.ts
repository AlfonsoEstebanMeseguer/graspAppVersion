import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { evaluateRefreshLimit, nextUtcMidnight } from "./connect-refresh.ts";
import { MAX_REFRESHES_PER_DAY } from "./connect-scoring.config.ts";

const MEDIODIA = new Date("2026-08-25T12:00:00.000Z");

// =================================================================================================
// RN-46 — máximo 5 pull-to-refresh al día.
// =================================================================================================

Deno.test("RN-46 sin refrescos gastados se puede refrescar", () => {
  const v = evaluateRefreshLimit(0, MEDIODIA);
  assertEquals(v.allowed, true);
  assertEquals(v.used, 0);
  assertEquals(v.limit, MAX_REFRESHES_PER_DAY);
  assertEquals(v.retryAt, null); // no depende del reloj mientras quede cupo
});

Deno.test("RN-46 el QUINTO refresco todavia pasa, el SEXTO no", () => {
  // El off-by-one clasico de un tope, y el que la spec subraya: «maximo 5», no «menos de 5».
  const quinto = evaluateRefreshLimit(MAX_REFRESHES_PER_DAY - 1, MEDIODIA);
  assertEquals(quinto.allowed, true, "el quinto refresco debe pasar");

  const sexto = evaluateRefreshLimit(MAX_REFRESHES_PER_DAY, MEDIODIA);
  assertEquals(sexto.allowed, false, "el sexto debe rechazarse");
});

Deno.test("RN-21 el rechazo trae el limite concreto y CUANDO se recupera", () => {
  // «Cada limite alcanzado devuelve un 422 con el limite concreto y cuando se recupera». Nunca un
  // fallo mudo: el usuario tiene que poder leer que le quedan horas, no que «algo fallo».
  const v = evaluateRefreshLimit(MAX_REFRESHES_PER_DAY, MEDIODIA);
  assertEquals(v.allowed, false);
  assertEquals(v.limit, MAX_REFRESHES_PER_DAY);
  assertEquals(v.used, MAX_REFRESHES_PER_DAY);
  assert(v.retryAt !== null, "un tope que se recupera con el reloj DEBE decir cuando");
  assertEquals(v.retryAt.toISOString(), "2026-08-26T00:00:00.000Z");
});

Deno.test("RN-46 un contador por encima del tope sigue rechazando, no da la vuelta", () => {
  const v = evaluateRefreshLimit(99, MEDIODIA);
  assertEquals(v.allowed, false);
  assert(v.retryAt !== null);
});

// =================================================================================================
// El instante de recuperación: medianoche UTC, porque `ran_on` es `current_date` y la base va en UTC.
// =================================================================================================

Deno.test("el cupo se recupera en la medianoche UTC SIGUIENTE, no a las 24 h", () => {
  // No es una ventana movil como RN-19: el contador vive en `connect_feed_runs (user_id, ran_on)`
  // con `ran_on = current_date`, asi que se reinicia con el calendario. Comprobado que la base
  // corre en UTC (`show timezone`), que es lo que hace correcta esta cuenta.
  assertEquals(
    nextUtcMidnight(new Date("2026-08-25T23:59:59.999Z")).toISOString(),
    "2026-08-26T00:00:00.000Z",
  );
  assertEquals(
    nextUtcMidnight(new Date("2026-08-25T00:00:00.000Z")).toISOString(),
    "2026-08-26T00:00:00.000Z",
  );
});

Deno.test("la medianoche siguiente cruza bien fin de mes y fin de ano", () => {
  assertEquals(
    nextUtcMidnight(new Date("2026-08-31T18:00:00.000Z")).toISOString(),
    "2026-09-01T00:00:00.000Z",
  );
  assertEquals(
    nextUtcMidnight(new Date("2026-12-31T23:00:00.000Z")).toISOString(),
    "2027-01-01T00:00:00.000Z",
  );
});
