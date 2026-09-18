import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  applyExclusions,
  type ConnectExclusionSets,
  exclusionReason,
  resolvePool,
} from "./connect-exclusions.ts";

const YO = "yo";

function sets(over: Partial<ConnectExclusionSets> = {}): ConnectExclusionSets {
  return {
    viewerId: YO,
    blockedByViewer: new Set(),
    blockedTheViewer: new Set(),
    conversations: new Set(),
    pendingRequestsSent: new Set(),
    pendingRequestsReceived: new Set(),
    following: new Set(),
    dismissed: new Set(),
    shownToday: new Set(),
    ...over,
  };
}

function pool(...ids: string[]) {
  return ids.map((userId) => ({ userId }));
}

// =================================================================================================
// RN-47 — las seis exclusiones, cada una con su test. El bloqueo va en DOS, uno por dirección.
// =================================================================================================

Deno.test("RN-47(1) uno mismo queda fuera del pool", () => {
  assertEquals(exclusionReason(YO, sets()), "self");
  assertEquals(applyExclusions(pool(YO, "otro"), sets()).map((c) => c.userId), ["otro"]);
});

Deno.test("RN-47(2a) a quien YO bloquee queda fuera", () => {
  const s = sets({ blockedByViewer: new Set(["b"]) });
  assertEquals(exclusionReason("b", s), "blocked_by_viewer");
});

Deno.test("RN-47(2b) quien me bloqueo A MI queda fuera — la mitad que se olvida", () => {
  // Es la direccion que no se ve desde la tabla `blocks` del espectador: `blocks` solo lo lee su
  // `blocker_id` (RN-23), asi que esta consulta va por `blocked_id` y usa el indice
  // `blocks (blocked_id)` de la Tarea 6. Sin esta mitad, el bloqueado sigue viendo al bloqueador
  // en Conectar y puede tocar «chat»: RN-24 roto, y el bloqueador recibiendo lo que pidio no ver.
  const s = sets({ blockedTheViewer: new Set(["b"]) });
  assertEquals(exclusionReason("b", s), "blocked_the_viewer");
});

Deno.test("RN-47(2) las dos direcciones excluyen, y el pool no distingue cual fue", () => {
  const porMi = applyExclusions(pool("b"), sets({ blockedByViewer: new Set(["b"]) }));
  const aMi = applyExclusions(pool("b"), sets({ blockedTheViewer: new Set(["b"]) }));
  assertEquals(porMi, []);
  assertEquals(aMi, []);
});

Deno.test("RN-47(3) una conversacion existente EN CUALQUIER ESTADO excluye", () => {
  // «cualquier estado» incluye `ignored`, y ahi esta RN-06: si una ignorada NO excluyera, el
  // emisor volveria a ver en Conectar a quien le ignoro, y esa reaparicion le diria que pasó algo.
  const s = sets({ conversations: new Set(["c"]) });
  assertEquals(exclusionReason("c", s), "conversation");
});

Deno.test("RN-47(4) las solicitudes de mensaje pendientes excluyen en las dos direcciones", () => {
  assertEquals(
    exclusionReason("d", sets({ pendingRequestsSent: new Set(["d"]) })),
    "pending_request_sent",
  );
  assertEquals(
    exclusionReason("d", sets({ pendingRequestsReceived: new Set(["d"]) })),
    "pending_request_received",
  );
});

Deno.test("RN-47(5) a quien ya sigo queda fuera", () => {
  assertEquals(exclusionReason("e", sets({ following: new Set(["e"]) })), "following");
});

Deno.test("RN-47(6) quien esta en connect_dismissals queda fuera", () => {
  assertEquals(exclusionReason("f", sets({ dismissed: new Set(["f"]) })), "dismissed");
});

Deno.test("RN-46 a quien ya se le enseno HOY queda fuera — no es de RN-47", () => {
  // Esta septima exclusion no esta en la lista de RN-47: es de RN-46, «pull-to-refresh no debe
  // volver a muestrear los usuarios anteriores», y es tambien lo que pagina el scroll infinito.
  // Se distingue de las seis en que CADUCA: la PK de `connect_impressions` lleva la fecha dentro,
  // asi que manana este mismo usuario vuelve a ser elegible sin que nadie borre nada.
  assertEquals(exclusionReason("g", sets({ shownToday: new Set(["g"]) })), "shown_today");
  assertEquals(applyExclusions(pool("g", "libre"), sets({ shownToday: new Set(["g"]) })).length, 1);
});

Deno.test("RN-46 `shown_today` NO se confunde con `dismissed`: son motivos distintos", () => {
  // Importa que no compartan cubo: un «No mostrar mas» es para siempre (RN-48) y una impresion
  // caduca a medianoche. Meterlos en el mismo conjunto haria indistinguibles dos cosas que se
  // borran de forma distinta — y la purga diaria solo toca una de las dos tablas.
  assertEquals(exclusionReason("g", sets({ shownToday: new Set(["g"]) })), "shown_today");
  assertEquals(exclusionReason("g", sets({ dismissed: new Set(["g"]) })), "dismissed");
});

Deno.test("RN-47 quien no esta en ninguna lista NO se excluye", () => {
  assertEquals(exclusionReason("libre", sets()), null);
  assertEquals(applyExclusions(pool("libre"), sets()).map((c) => c.userId), ["libre"]);
});

Deno.test("RN-47 las seis se aplican a la vez, no solo la primera", () => {
  // Un `else if` mal puesto, o un `return` temprano, deja pasar a los de las listas siguientes.
  const s = sets({
    blockedByViewer: new Set(["b1"]),
    blockedTheViewer: new Set(["b2"]),
    conversations: new Set(["c"]),
    pendingRequestsSent: new Set(["d1"]),
    pendingRequestsReceived: new Set(["d2"]),
    following: new Set(["e"]),
    dismissed: new Set(["f"]),
  });
  const resultado = applyExclusions(pool(YO, "b1", "b2", "c", "d1", "d2", "e", "f", "libre"), s);
  assertEquals(resultado.map((c) => c.userId), ["libre"]);
});

Deno.test("RN-48 los rechazados no reaparecen nunca: no hay caducidad que los devuelva", () => {
  // `connect_dismissals` no tiene columna de fecha a proposito (Tarea 5): no hay nada que mirar
  // para decidir que «ya ha pasado bastante». Este test fija esa ausencia como comportamiento.
  const s = sets({ dismissed: new Set(["f"]) });
  assertEquals(applyExclusions(pool("f"), s), []);
  assertEquals(exclusionReason("f", s), "dismissed");
});

Deno.test("RN-47 el pool conserva el orden y los objetos originales", () => {
  const original = pool("a", "b", "c");
  const r = applyExclusions(original, sets({ following: new Set(["b"]) }));
  assertEquals(r.map((c) => c.userId), ["a", "c"]);
  assert(r[0] === original[0], "no debe clonar: el candidato lleva mas campos que el userId");
});

// =================================================================================================
// RN-49 — relajar primero, empty state despues. Nunca una lista vacía sin explicación.
// =================================================================================================

Deno.test("RN-49 con candidatos de sobra la resolucion es `full`", () => {
  const grande = pool(...Array.from({ length: 25 }, (_, i) => `u${i}`));
  const r = resolvePool(grande, sets(), 20);
  assertEquals(r.kind, "full");
  assertEquals(r.candidates.length, 25);
});

Deno.test("RN-49 justo en el tamano de tanda todavia es `full`", () => {
  // El borde: 20 elegibles para una tanda de 20 es «suficientes», no «pocos». Un `<=` aqui
  // relajaria el filtro del usuario en el caso normal de una base pequena.
  const r = resolvePool(pool(...Array.from({ length: 20 }, (_, i) => `u${i}`)), sets(), 20);
  assertEquals(r.kind, "full");
});

Deno.test("RN-49 por debajo del tamano de tanda la resolucion es `relaxed`", () => {
  const r = resolvePool(pool(...Array.from({ length: 19 }, (_, i) => `u${i}`)), sets(), 20);
  assertEquals(r.kind, "relaxed");
  assertEquals(r.candidates.length, 19);
});

Deno.test("RN-49 sin ningun elegible la resolucion es `empty`", () => {
  const r = resolvePool(pool("a", "b"), sets({ dismissed: new Set(["a", "b"]) }), 20);
  assertEquals(r.kind, "empty");
  assertEquals(r.candidates, []);
});

Deno.test("RN-49 un pool vacio de entrada tambien es `empty`, no `relaxed`", () => {
  assertEquals(resolvePool([], sets(), 20).kind, "empty");
});

Deno.test("RN-49 RELAJAR NO RELAJA LAS EXCLUSIONES, en las tres resoluciones", () => {
  // El invariante recorrido sobre los tres desenlaces: da igual como se resuelva el pool, un
  // excluido NUNCA sale. Escrito asi porque el atajo peligroso —tirar del pool completo cuando
  // escasean— solo se manifiesta en `relaxed`, y un test que solo mire `full` no lo veria.
  const excluido = new Set(["malo"]);
  for (const n of [30, 5, 1]) {
    const p = pool(...Array.from({ length: n }, (_, i) => `u${i}`), "malo");
    const r = resolvePool(p, sets({ blockedTheViewer: excluido }), 20);
    assert(
      !r.candidates.some((c) => c.userId === "malo"),
      `con ${n} elegibles (${r.kind}) se ha colado un excluido`,
    );
  }
});
