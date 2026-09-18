import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { AppError } from "./http.ts";
import { evaluateTagRotation, TAG_ROTATION_COOLDOWN_MS } from "./tag-rotate.ts";

const AHORA = new Date("2026-08-25T12:00:00.000Z");

/** Un instante desplazado `ms` milisegundos HACIA ATRÁS desde `AHORA`. */
function haceMs(ms: number): string {
  return new Date(AHORA.getTime() - ms).toISOString();
}

Deno.test("evaluateTagRotation: quien nunca ha rotado puede rotar", () => {
  assertEquals(evaluateTagRotation(null, AHORA), { allowed: true, retryAt: null });
});

Deno.test("evaluateTagRotation: undefined se trata como 'nunca ha rotado'", () => {
  // La columna es nullable y PostgREST puede devolver la clave ausente en vez de null.
  assertEquals(evaluateTagRotation(undefined, AHORA), { allowed: true, retryAt: null });
});

Deno.test("evaluateTagRotation: exactamente 24 h despues SI se puede rotar", () => {
  // El borde: "1 cada 24 h" significa que a las 24 h en punto ya hay cupo. Es el clasico
  // off-by-one de un tope, y por eso va con su propio test.
  const r = evaluateTagRotation(haceMs(TAG_ROTATION_COOLDOWN_MS), AHORA);
  assertEquals(r, { allowed: true, retryAt: null });
});

Deno.test("evaluateTagRotation: un milisegundo antes de las 24 h NO se puede", () => {
  const r = evaluateTagRotation(haceMs(TAG_ROTATION_COOLDOWN_MS - 1), AHORA);
  assertEquals(r.allowed, false);
});

Deno.test("evaluateTagRotation: recien rotado no se puede", () => {
  const r = evaluateTagRotation(haceMs(0), AHORA);
  assertEquals(r.allowed, false);
});

Deno.test("evaluateTagRotation: el retryAt es exactamente la ultima rotacion + 24 h", () => {
  // RN-21 exige decir CUANDO se recupera, no solo que se ha agotado. Si este calculo se
  // desviara, el cliente pintaria una cuenta atras que no coincide con la del servidor.
  const ultima = haceMs(3 * 60 * 60 * 1000); // hace 3 h
  const r = evaluateTagRotation(ultima, AHORA);
  assertEquals(r.allowed, false);
  assertEquals(
    r.retryAt?.toISOString(),
    new Date(new Date(ultima).getTime() + TAG_ROTATION_COOLDOWN_MS).toISOString(),
  );
});

Deno.test("evaluateTagRotation: el retryAt cae en el futuro cuando se rechaza", () => {
  const r = evaluateTagRotation(haceMs(60 * 1000), AHORA);
  assertEquals(r.allowed, false);
  assertEquals((r.retryAt as Date).getTime() > AHORA.getTime(), true);
});

Deno.test("evaluateTagRotation: una marca en el FUTURO tambien bloquea", () => {
  // Desfase de reloj entre nodos, o una fila tocada a mano. Falla cerrado: bloquear de mas es
  // molesto, permitir de mas anula el tope entero.
  const futuro = new Date(AHORA.getTime() + 60 * 60 * 1000).toISOString();
  const r = evaluateTagRotation(futuro, AHORA);
  assertEquals(r.allowed, false);
});

Deno.test("evaluateTagRotation: acepta un Date, no solo una cadena", () => {
  const r = evaluateTagRotation(new Date(AHORA.getTime() - TAG_ROTATION_COOLDOWN_MS), AHORA);
  assertEquals(r.allowed, true);
});

Deno.test("evaluateTagRotation: una fecha ilegible NO se ignora, revienta", () => {
  // Ni permitir ni bloquear en silencio: los dos esconden una fila corrupta. Se levanta un 500
  // para que se vea. Es el freno que duda de los datos con los que decide (CLAUDE.md).
  assertThrows(
    () => evaluateTagRotation("no es una fecha", AHORA),
    AppError,
  );
});

Deno.test("evaluateTagRotation: cadena vacia tambien revienta", () => {
  assertThrows(() => evaluateTagRotation("", AHORA), AppError);
});

Deno.test("TAG_ROTATION_COOLDOWN_MS: son 24 horas exactas", () => {
  assertEquals(TAG_ROTATION_COOLDOWN_MS, 86_400_000);
});
