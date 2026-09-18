import { assertEquals, assertNotEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type TagLookupInput,
  type TagLookupOutcome,
  resolveTagLookup,
} from "./connect-lookup.ts";

const YO = "11111111-0016-4000-8000-00000000000a";
const OTRO = "22222222-0016-4000-8000-00000000000b";

function input(over: Partial<TagLookupInput> = {}): TagLookupInput {
  return {
    viewerId: YO,
    profileUserId: OTRO,
    blocked: false,
    followStatus: null,
    ...over,
  };
}

// =================================================================================================
// §6.2 — los cuatro desenlaces de la búsqueda por tag.
// =================================================================================================

Deno.test("§6.2 un tag que no existe devuelve not_found", () => {
  assertEquals(resolveTagLookup(input({ profileUserId: null })), { kind: "not_found" });
});

Deno.test("§6.2 tu propio tag tiene su error propio, distinto de not_found", () => {
  // Es el unico de los cuatro que SI puede ser especifico: no revela nada de nadie, porque quien
  // pregunta ya sabe cual es su tag.
  const r = resolveTagLookup(input({ profileUserId: YO }));
  assertEquals(r, { kind: "self" });
  assertNotEquals(r.kind, "not_found");
});

Deno.test("§6.2 un tag valido y libre devuelve found sin follow", () => {
  assertEquals(resolveTagLookup(input()), {
    kind: "found",
    userId: OTRO,
    followState: "none",
  });
});

Deno.test("§6.2 a quien ya sigues sale como `following`", () => {
  assertEquals(resolveTagLookup(input({ followStatus: "accepted" })), {
    kind: "found",
    userId: OTRO,
    followState: "following",
  });
});

Deno.test("§6.2 una solicitud de follow pendiente sale como `pending`", () => {
  assertEquals(resolveTagLookup(input({ followStatus: "pending" })), {
    kind: "found",
    userId: OTRO,
    followState: "pending",
  });
});

// =================================================================================================
// La regla que sostiene RN-23 en esta pantalla.
// =================================================================================================

Deno.test("§6.2 CON BLOQUEO, LA RESPUESTA ES EXACTAMENTE LA DE UN TAG QUE NO EXISTE", () => {
  // Comparados como VALORES y no campo a campo a mano: si alguien anade manana una variante
  // `{ kind: "not_found", reason: "blocked" }` creyendo que ayuda a depurar, este test cae.
  const inexistente = resolveTagLookup(input({ profileUserId: null }));
  const bloqueado = resolveTagLookup(input({ blocked: true }));
  assertEquals(bloqueado, inexistente);
  assertEquals(JSON.stringify(bloqueado), JSON.stringify(inexistente));
});

Deno.test("§6.2 el bloqueo tapa el resultado en LAS DOS direcciones y con follow puesto", () => {
  // `blocked` llega ya unido por el handler (consulta las dos direcciones). Lo que se fija aqui es
  // que ningun otro dato se cuele por encima: un follow aceptado con bloqueo NO puede devolver
  // `following`, porque eso confirmaria que la cuenta existe.
  const inexistente: TagLookupOutcome = { kind: "not_found" };
  for (const followStatus of [null, "pending", "accepted"] as const) {
    assertEquals(resolveTagLookup(input({ blocked: true, followStatus })), inexistente);
  }
});

Deno.test("§6.2 el bloqueo NO tapa tu propio tag: nadie puede bloquearse a si mismo", () => {
  // `blocks_no_self` lo impide en la base (Tarea 6), asi que este caso no puede darse; se fija el
  // orden igualmente para que quede escrito cual gana si alguien relaja esa constraint.
  assertEquals(resolveTagLookup(input({ profileUserId: YO, blocked: true })), { kind: "self" });
});
