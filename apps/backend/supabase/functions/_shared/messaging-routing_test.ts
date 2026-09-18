import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { type RoutingContext, routeConversation } from "./messaging-routing.ts";

const EMISOR = "aaaaaaaa-0009-4000-8000-00000000000a";
const RECEPTOR = "bbbbbbbb-0009-4000-8000-00000000000b";

function ctx(over: Partial<RoutingContext> = {}): RoutingContext {
  return {
    senderId: EMISOR,
    recipientId: RECEPTOR,
    existing: null,
    recipientFollowsSender: false,
    senderFollowsRecipient: false,
    ...over,
  };
}

// =================================================================================================
// Los cuatro casos de la tabla del §4.2, uno por test y en su orden.
// =================================================================================================

Deno.test("§4.2 caso 1: se siguen mutuamente -> accepted directo", () => {
  const d = routeConversation(ctx({ recipientFollowsSender: true, senderFollowsRecipient: true }));
  assertEquals(d, { kind: "create", status: "accepted", initiatorId: EMISOR });
});

Deno.test("§4.2 caso 2: nadie sigue a nadie -> pending", () => {
  const d = routeConversation(ctx());
  assertEquals(d, { kind: "create", status: "pending", initiatorId: EMISOR });
});

Deno.test("§4.2 caso 3: el EMISOR sigue al receptor pero no al reves -> pending", () => {
  // ESTE ES EL QUE SE IMPLEMENTA MAL, porque parece que seguir deberia bastar. No basta: RN-09
  // dice que el follow del EMISOR es irrelevante. Seguir a alguien no te da derecho a colarte en
  // su bandeja de Contactos; lo que abre la puerta es que el RECEPTOR ya mostrara interes.
  const d = routeConversation(ctx({ senderFollowsRecipient: true, recipientFollowsSender: false }));
  assertEquals(d, { kind: "create", status: "pending", initiatorId: EMISOR });
});

Deno.test("§4.2 caso 4: el RECEPTOR sigue al emisor -> accepted directo", () => {
  const d = routeConversation(ctx({ recipientFollowsSender: true }));
  assertEquals(d, { kind: "create", status: "accepted", initiatorId: EMISOR });
});

Deno.test("RN-09: el follow del emisor no cambia NADA, con o sin el", () => {
  // La regla unica, dicha como invariante: fijado el follow del receptor, el del emisor es ruido.
  for (const recipientFollowsSender of [true, false]) {
    const con = routeConversation(ctx({ recipientFollowsSender, senderFollowsRecipient: true }));
    const sin = routeConversation(ctx({ recipientFollowsSender, senderFollowsRecipient: false }));
    assertEquals(con, sin);
  }
});

// =================================================================================================
// RN-10: el enrutado se evalúa UNA SOLA VEZ, al crear.
// =================================================================================================

Deno.test("RN-10: un follow posterior NO reconvierte una pendiente en aceptada", () => {
  // El receptor ha pasado a seguir al emisor DESPUES de que naciera la conversacion. La
  // conversacion sigue pendiente: reconvertirla aqui seria evaluar el enrutado dos veces.
  // Quien la reanuda es RN-17, y solo al ACEPTAR el follow (eso vive en `follow-toggle`).
  const d = routeConversation(ctx({
    existing: { status: "pending", initiatorId: EMISOR },
    recipientFollowsSender: true,
  }));
  assertEquals(d, { kind: "reuse", status: "pending", upgradedToAccepted: false });
});

Deno.test("RN-10: mensaje 2..5 en la propia pendiente la deja pendiente", () => {
  const d = routeConversation(ctx({ existing: { status: "pending", initiatorId: EMISOR } }));
  assertEquals(d.kind, "reuse");
  assertEquals(d.kind === "reuse" && d.status, "pending");
});

// =================================================================================================
// RN-08: dos primeros mensajes cruzados -> accepted, y UN SOLO HILO.
// =================================================================================================

Deno.test("RN-08: si ya existe una pendiente iniciada por EL OTRO, se acepta y se reutiliza", () => {
  // B escribio primero y quedo pendiente; ahora A le contesta. Contestar es aceptar de hecho.
  const d = routeConversation(ctx({ existing: { status: "pending", initiatorId: RECEPTOR } }));
  assertEquals(d, { kind: "reuse", status: "accepted", upgradedToAccepted: true });
});

Deno.test("RN-08: nunca se crea un segundo hilo para el mismo par", () => {
  // La forma de la decision lo garantiza: con `existing` no nulo NUNCA se devuelve `create`.
  for (
    const existing of [
      { status: "pending" as const, initiatorId: EMISOR },
      { status: "pending" as const, initiatorId: RECEPTOR },
      { status: "accepted" as const, initiatorId: EMISOR },
      { status: "ignored" as const, initiatorId: EMISOR },
    ]
  ) {
    assertEquals(routeConversation(ctx({ existing })).kind, "reuse");
  }
});

// =================================================================================================
// Estados ya resueltos
// =================================================================================================

Deno.test("una conversacion aceptada se reutiliza sin tocar el estado", () => {
  const d = routeConversation(ctx({ existing: { status: "accepted", initiatorId: RECEPTOR } }));
  assertEquals(d, { kind: "reuse", status: "accepted", upgradedToAccepted: false });
});

Deno.test("RN-06: una ignorada sigue ignorada, y el enrutado no la delata", () => {
  // Para el emisor su conversacion "sigue pendiente para siempre". El enrutado no la asciende ni
  // la degrada: devuelve el estado real, y quien construye lo que ve el emisor es la proyeccion
  // por espectador (Tarea 11). Aqui lo importante es que NO se convierta en accepted por escribir.
  const d = routeConversation(ctx({
    existing: { status: "ignored", initiatorId: EMISOR },
    recipientFollowsSender: true,
  }));
  assertEquals(d, { kind: "reuse", status: "ignored", upgradedToAccepted: false });
});

Deno.test("RN-07: escribir en una ignorada NO la resucita ni con follow mutuo", () => {
  const d = routeConversation(ctx({
    existing: { status: "ignored", initiatorId: RECEPTOR },
    recipientFollowsSender: true,
    senderFollowsRecipient: true,
  }));
  assertEquals(d.kind === "reuse" && d.status, "ignored");
  assertEquals(d.kind === "reuse" && d.upgradedToAccepted, false);
});
