import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { isUuid } from "./validation.ts";

Deno.test("isUuid: un uuid canonico es valido", () => {
  assertEquals(isUuid("11111111-1111-4111-8111-111111111111"), true);
});

Deno.test("isUuid: las mayusculas son validas", () => {
  assertEquals(isUuid("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"), true);
});

Deno.test("isUuid: cadena vacia no es uuid", () => {
  assertEquals(isUuid(""), false);
});

Deno.test("isUuid: sin guiones no es uuid", () => {
  assertEquals(isUuid("11111111111141118111111111111111"), false);
});

Deno.test("isUuid: con un caracter de mas no es uuid", () => {
  assertEquals(isUuid("11111111-1111-4111-8111-111111111111x"), false);
});

Deno.test("isUuid: con espacios alrededor no es uuid", () => {
  assertEquals(isUuid(" 11111111-1111-4111-8111-111111111111 "), false);
});

Deno.test("isUuid: un numero no es uuid", () => {
  assertEquals(isUuid(42), false);
});

Deno.test("isUuid: null no es uuid", () => {
  assertEquals(isUuid(null), false);
});
