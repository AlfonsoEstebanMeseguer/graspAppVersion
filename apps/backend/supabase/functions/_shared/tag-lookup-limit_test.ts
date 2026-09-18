// Tope diario de `connect-tag-lookup` (ADR 0028, §5).
//
// LO QUE ESTOS TESTS FIJAN, y es lo que hace que el tope sirva de algo: el veredicto **no depende
// del desenlace de la búsqueda**. Un tope que solo contara los 404 sería peor que no tener tope: el
// contador mismo pasaría a ser el oráculo que `RN-23` quiere cerrar. Por eso la función pura solo
// recibe `used` y `now` — no hay ningún parámetro por el que el desenlace pueda entrar.
import { assertEquals } from "jsr:@std/assert@1";
import { MAX_TAG_LOOKUPS_PER_DAY } from "./connect-scoring.config.ts";
import { evaluateTagLookupLimit } from "./tag-lookup-limit.ts";

const NOW = new Date("2026-08-30T14:00:00.000Z");

Deno.test("con cero gastados deja pasar y no promete ninguna espera", () => {
  const v = evaluateTagLookupLimit(0, NOW);
  assertEquals(v.allowed, true);
  assertEquals(v.retryAt, null);
  assertEquals(v.limit, MAX_TAG_LOOKUPS_PER_DAY);
});

Deno.test("el ultimo del cupo pasa: «maximo N» significa que el N-esimo entra", () => {
  const v = evaluateTagLookupLimit(MAX_TAG_LOOKUPS_PER_DAY - 1, NOW);
  assertEquals(v.allowed, true);
  assertEquals(v.retryAt, null);
});

Deno.test("el siguiente al cupo se rechaza", () => {
  const v = evaluateTagLookupLimit(MAX_TAG_LOOKUPS_PER_DAY, NOW);
  assertEquals(v.allowed, false);
  assertEquals(v.limit, MAX_TAG_LOOKUPS_PER_DAY);
  assertEquals(v.used, MAX_TAG_LOOKUPS_PER_DAY);
});

Deno.test("RN-21: al rechazar dice CUANDO se recupera, y es la medianoche UTC siguiente", () => {
  const v = evaluateTagLookupLimit(MAX_TAG_LOOKUPS_PER_DAY + 5, NOW);
  assertEquals(v.allowed, false);
  // Medianoche UTC y no la zona del usuario: el contador vive con `looked_on = current_date` y la
  // base corre en UTC. Otra zona prometeria un cupo que la base aun no ha reiniciado.
  assertEquals(v.retryAt?.toISOString(), "2026-08-31T00:00:00.000Z");
});

Deno.test("el retryAt cruza el fin de mes sin tratarlo aparte", () => {
  const v = evaluateTagLookupLimit(MAX_TAG_LOOKUPS_PER_DAY, new Date("2026-08-31T23:59:59.000Z"));
  assertEquals(v.retryAt?.toISOString(), "2026-09-01T00:00:00.000Z");
});

Deno.test("el tope es MAS GENEROSO que el de refrescos: son cosas distintas", async () => {
  // Buscar un tag que alguien te ha pasado es una accion legitima y repetible; refrescar el feed
  // es una tanda nueva de candidatos. Si este tope fuera 5, la busqueda por tag —la UNICA forma
  // de encontrar a alguien a proposito (§6.2)— quedaria inutilizable, y el ADR 0028 pide acotar
  // el volumen del ataque, no romper la funcion.
  const { MAX_REFRESHES_PER_DAY } = await import("./connect-scoring.config.ts");
  assertEquals(MAX_TAG_LOOKUPS_PER_DAY > MAX_REFRESHES_PER_DAY, true);
});
