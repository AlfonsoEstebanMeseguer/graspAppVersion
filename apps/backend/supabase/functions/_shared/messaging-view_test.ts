import { assertEquals, assertNotEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type ConversationViewInput,
  INPUT_NOTICE_QUOTA,
  type MessageInput,
  projectInbox,
  projectMessages,
  resolveInputState,
} from "./messaging-view.ts";
import { evaluateSendLimits, MAX_PENDING_MESSAGES } from "./messaging-limits.ts";

const YO = "aaaaaaaa-0011-4000-8000-00000000000a";
const OTRO = "bbbbbbbb-0011-4000-8000-00000000000b";
const CONV = "cccccccc-0011-4000-8000-0000000000c1";
const AHORA = new Date("2026-08-25T12:00:00.000Z");

function conversacion(over: Partial<ConversationViewInput> = {}): ConversationViewInput {
  return {
    id: CONV,
    userAId: YO,
    userBId: OTRO,
    status: "pending",
    initiatorId: YO,
    lastMessageAt: "2026-08-25T11:00:00.000Z",
    viewerHidden: false,
    viewerUnreadCount: 0,
    viewerClearedAt: null,
    lastMessage: {
      senderId: YO,
      content: "Hola",
      createdAt: "2026-08-25T11:00:00.000Z",
      deletedFor: [],
      deletedForAll: false,
    },
    ...over,
  };
}

function mensaje(over: Partial<MessageInput> = {}): MessageInput {
  return {
    id: "dddddddd-0011-4000-8000-00000000000d",
    senderId: YO,
    content: "Hola",
    deletedFor: [],
    deletedForAllAt: null,
    editedAt: null,
    replyToId: null,
    createdAt: "2026-08-25T11:00:00.000Z",
    ...over,
  };
}

// =================================================================================================
// RN-06 — la conversación ignorada, vista por quien la inició
// =================================================================================================

Deno.test("RN-06: una ignorada se le presenta al EMISOR campo a campo igual que una pendiente", () => {
  const pendiente = projectInbox([conversacion({ status: "pending" })], YO);
  const ignorada = projectInbox([conversacion({ status: "ignored" })], YO);

  // Comparación del JSON entero, no campo elegido: si algún día se añade una clave que dependa del
  // estado, este test la caza sin que nadie tenga que acordarse de ampliarlo.
  assertEquals(JSON.stringify(ignorada), JSON.stringify(pendiente));
});

Deno.test("RN-06: la ignorada NO aparece en ninguna de las dos pestañas del RECEPTOR", () => {
  const vista = projectInbox([conversacion({ status: "ignored" })], OTRO);

  assertEquals(vista.contacts.length, 0);
  assertEquals(vista.requests.length, 0);
});

Deno.test("RN-06: y la pendiente equivalente SÍ le aparece, en Solicitudes", () => {
  // El contraste importa: sin él, el test de arriba pasaría también con una función que devolviera
  // siempre listas vacías.
  const vista = projectInbox([conversacion({ status: "pending" })], OTRO);

  assertEquals(vista.contacts.length, 0);
  assertEquals(vista.requests.length, 1);
});

// =================================================================================================
// RN-02, RN-03, RN-29 — a qué pestaña va cada conversación
// =================================================================================================

Deno.test("RN-02: mi solicitud enviada aparece en MIS Contactos, no en mis Solicitudes", () => {
  const vista = projectInbox([conversacion({ status: "pending", initiatorId: YO })], YO);

  assertEquals(vista.contacts.length, 1);
  assertEquals(vista.requests.length, 0);
  assertEquals(vista.contacts[0].pending_acceptance, true);
});

Deno.test("RN-03: la solicitud recibida aparece en Solicitudes, nunca en Contactos", () => {
  const vista = projectInbox([conversacion({ status: "pending", initiatorId: OTRO })], YO);

  assertEquals(vista.requests.length, 1);
  assertEquals(vista.contacts.length, 0);
});

Deno.test("una conversación aceptada va a Contactos y no está pendiente de aceptación", () => {
  const vista = projectInbox([conversacion({ status: "accepted" })], YO);

  assertEquals(vista.contacts.length, 1);
  assertEquals(vista.contacts[0].pending_acceptance, false);
});

Deno.test("RN-29: Contactos se ordena por last_message_at DESCENDENTE", () => {
  const vieja = conversacion({
    id: "11111111-0011-4000-8000-000000000011",
    lastMessageAt: "2026-08-20T10:00:00.000Z",
    status: "accepted",
  });
  const nueva = conversacion({
    id: "22222222-0011-4000-8000-000000000022",
    lastMessageAt: "2026-08-25T10:00:00.000Z",
    status: "accepted",
  });

  const vista = projectInbox([vieja, nueva], YO);

  assertEquals(vista.contacts[0].conversation_id, nueva.id);
  assertEquals(vista.contacts[1].conversation_id, vieja.id);
});

// =================================================================================================
// RN-22 y RN-27 — lo oculto no se lista
// =================================================================================================

Deno.test("RN-22: una conversación oculta no aparece en ninguna pestaña", () => {
  const vista = projectInbox([conversacion({ viewerHidden: true, status: "accepted" })], YO);

  assertEquals(vista.contacts.length, 0);
  assertEquals(vista.requests.length, 0);
});

Deno.test("RN-27: tras borrar el historial no se enseña como último un mensaje anterior al borrado", () => {
  const vista = projectInbox([
    conversacion({
      status: "accepted",
      viewerClearedAt: "2026-08-25T11:30:00.000Z",
      lastMessage: {
        senderId: OTRO,
        content: "Mensaje viejo",
        createdAt: "2026-08-25T11:00:00.000Z",
        deletedFor: [],
        deletedForAll: false,
      },
    }),
  ], YO);

  assertEquals(vista.contacts.length, 1);
  assertEquals(vista.contacts[0].last_message, null);
});

Deno.test("RN-28: si borré el último mensaje para mí, no se me enseña en la bandeja", () => {
  const vista = projectInbox([
    conversacion({
      status: "accepted",
      lastMessage: {
        senderId: OTRO,
        content: "Secreto",
        createdAt: "2026-08-25T11:00:00.000Z",
        deletedFor: [YO],
        deletedForAll: false,
      },
    }),
  ], YO);

  assertEquals(vista.contacts[0].last_message, null);
});

// =================================================================================================
// RN-31 — lo que NO puede salir en la respuesta
// =================================================================================================

Deno.test("RN-31: la proyección no contiene status, initiator_id ni el unread del otro", () => {
  const vista = projectInbox([conversacion({ status: "ignored", viewerUnreadCount: 3 })], YO);
  const json = JSON.stringify(vista);

  assertEquals(json.includes("status"), false);
  assertEquals(json.includes("initiator"), false);
  // El propio sí sale: es el badge de uno mismo.
  assertEquals(vista.contacts[0].unread_count, 3);
});

Deno.test("`from_me` marca el `Tú: ` del §8.2 y no expone el id del emisor", () => {
  const mio = projectInbox([conversacion({ status: "accepted" })], YO);
  const suyo = projectInbox([
    conversacion({
      status: "accepted",
      lastMessage: {
        senderId: OTRO,
        content: "Hola",
        createdAt: "2026-08-25T11:00:00.000Z",
        deletedFor: [],
        deletedForAll: false,
      },
    }),
  ], YO);

  assertEquals(mio.contacts[0].last_message?.from_me, true);
  assertEquals(suyo.contacts[0].last_message?.from_me, false);
  assertEquals(JSON.stringify(mio).includes("sender_id"), false);
});

// =================================================================================================
// RN-23 — EL TEST QUE SOSTIENE LA REGLA: un bloqueo no se distingue de un cupo agotado
// =================================================================================================

Deno.test("RN-23: bloqueado produce EL MISMO estado de input que el cupo agotado, campo a campo", () => {
  // El caso que delata una implementación ingenua: el bloqueado ha gastado solo 2 de sus 5, así que
  // si `messages_left` se calculara del contador en bruto saldría 3 — y un `can_send: false` con 3
  // mensajes restantes es imposible por un cupo, así que sería un oráculo de bloqueo perfecto.
  const bloqueado = resolveInputState({
    status: "pending",
    initiatorId: YO,
    viewerId: YO,
    otherUserId: OTRO,
    senderMessageCount: 2,
    blocked: true,
    now: AHORA,
  });

  const sinCupo = resolveInputState({
    status: "pending",
    initiatorId: YO,
    viewerId: YO,
    otherUserId: OTRO,
    senderMessageCount: MAX_PENDING_MESSAGES,
    blocked: false,
    now: AHORA,
  });

  assertEquals(JSON.stringify(bloqueado), JSON.stringify(sinCupo));
  assertEquals(bloqueado.can_send, false);
  assertEquals(bloqueado.messages_left, 0);
  assertEquals(bloqueado.input_notice, INPUT_NOTICE_QUOTA);
});

Deno.test("RN-23: una solicitud RECIBIDA da el MISMO estado con y sin bloqueo", () => {
  // EL ORÁCULO QUE ESTE TEST CIERRA, Y POR QUÉ ES DISTINTO DE LOS DEMÁS.
  //
  // Para una solicitud RECIBIDA, `can_send: false` **solo puede venir de un bloqueo**: el tope de
  // RN-01 se le aplica a quien pide entrar, no a quien contesta, y `evaluateSendLimits` devuelve
  // *PUEDE* en cuanto `existing.initiatorId === recipientId`. Lo único que se comprueba antes es
  // el bloqueo. Así que `can_send:false` junto a `request_actions:true` era un oráculo perfecto,
  // y `messages_left` (0 contra null) lo confirmaba por segunda vía.
  //
  // Alcanzable sin nada raro: A manda solicitud a B y después bloquea a B. B abre el hilo.
  //
  // Los tres campos no se pintan en esta fila —la UI sustituye el input por las cuatro acciones de
  // RN-04—, así que emitirlos constantes no pierde nada y cierra el canal. Un campo que nadie mira
  // pero que varía es un oráculo regalado.
  const base = {
    status: "pending" as const,
    initiatorId: OTRO, // la abrió la OTRA persona: es una solicitud recibida
    viewerId: YO,
    otherUserId: OTRO,
    senderMessageCount: 0,
    now: AHORA,
  };

  assertEquals(
    JSON.stringify(resolveInputState({ ...base, blocked: true })),
    JSON.stringify(resolveInputState({ ...base, blocked: false })),
  );
});

Deno.test("RN-23: la fila 4 se emite constante aunque el emisor haya gastado mensajes", () => {
  // El contador del espectador no puede colarse por la puerta de atrás: en una solicitud recibida
  // no hay tope que enseñar (contestar es aceptar, RN-08), así que `messages_left` es null SIEMPRE.
  for (const enviados of [0, 2, MAX_PENDING_MESSAGES, 99]) {
    for (const blocked of [true, false]) {
      const estado = resolveInputState({
        status: "pending",
        initiatorId: OTRO,
        viewerId: YO,
        otherUserId: OTRO,
        senderMessageCount: enviados,
        blocked,
        now: AHORA,
      });
      assertEquals(estado.request_actions, true);
      assertEquals(estado.can_send, true, `enviados=${enviados} blocked=${blocked}`);
      assertEquals(estado.input_notice, null, `enviados=${enviados} blocked=${blocked}`);
      assertEquals(estado.messages_left, null, `enviados=${enviados} blocked=${blocked}`);
    }
  }
});

Deno.test("el bloqueo SIGUE frenando el envío: se arregla la vista, no el enforcement", () => {
  // El arreglo de arriba toca `resolveInputState` (lo que se PINTA) y no `evaluateSendLimits` (lo
  // que se PERMITE). Si alguien lo "arreglase" en el veredicto, un bloqueado podría escribirle a
  // quien le bloqueó — RN-24 — y este test es lo que lo impide.
  const veredicto = evaluateSendLimits({
    senderId: YO,
    recipientId: OTRO,
    existing: { status: "pending", initiatorId: OTRO },
    senderMessageCount: 0,
    pendingRequests: 0,
    firstMessagesInWindow: 0,
    oldestFirstMessageAt: null,
    blocked: true,
    now: AHORA,
  });

  assertEquals(veredicto.canSend, false);
  assertEquals(veredicto.internalReason, "blocked");
  // Y lo que sale al cliente sigue sin nombrar el bloqueo.
  assertEquals(veredicto.publicReason, "quota_exhausted");
});

Deno.test("RN-23: el bloqueado conserva su conversación y su historial completo", () => {
  // No se le vacía nada: sigue viendo el hilo en su bandeja y sus mensajes en el thread.
  const vista = projectInbox([conversacion({ status: "accepted" })], YO);
  assertEquals(vista.contacts.length, 1);
  assertEquals(vista.contacts[0].last_message?.content, "Hola");

  const mensajes = projectMessages([mensaje(), mensaje({ id: "ee", content: "Dos" })], YO, null);
  assertEquals(mensajes.length, 2);
});

Deno.test("ADR 0022: el texto del input inerte sale de UNA constante, y es el de RN-02", () => {
  assertEquals(INPUT_NOTICE_QUOTA, "Podrás seguir escribiendo cuando esta persona acepte tu mensaje.");
  // El literal retirado por el ADR 0022 no puede reaparecer por ninguna vía.
  assertEquals(INPUT_NOTICE_QUOTA.includes("No puedes enviar"), false);
  assertEquals(INPUT_NOTICE_QUOTA.toLowerCase().includes("bloque"), false);
});

// =================================================================================================
// §9.2 — el resto de estados del input
// =================================================================================================

Deno.test("§9.2: conversación aceptada -> input activo y sin tope", () => {
  const estado = resolveInputState({
    status: "accepted",
    initiatorId: YO,
    viewerId: YO,
    otherUserId: OTRO,
    senderMessageCount: 40,
    blocked: false,
    now: AHORA,
  });

  assertEquals(estado.can_send, true);
  assertEquals(estado.messages_left, null);
  assertEquals(estado.input_notice, null);
  assertEquals(estado.request_actions, false);
});

Deno.test("§9.2: solicitud enviada con mensajes restantes -> activo, y el quinto AÚN pasa", () => {
  const cuarto = resolveInputState({
    status: "pending",
    initiatorId: YO,
    viewerId: YO,
    otherUserId: OTRO,
    senderMessageCount: 4,
    blocked: false,
    now: AHORA,
  });

  assertEquals(cuarto.can_send, true);
  assertEquals(cuarto.messages_left, 1);
  assertEquals(cuarto.input_notice, null);
});

Deno.test("§9.2: solicitud RECIBIDA sin aceptar -> las cuatro acciones de RN-04, no el input", () => {
  const estado = resolveInputState({
    status: "pending",
    initiatorId: OTRO,
    viewerId: YO,
    otherUserId: OTRO,
    senderMessageCount: 0,
    blocked: false,
    now: AHORA,
  });

  assertEquals(estado.request_actions, true);
  assertEquals(estado.messages_left, null);
});

Deno.test("RN-06: una ignorada da el MISMO estado de input que una pendiente, gastada o no", () => {
  for (const enviados of [2, MAX_PENDING_MESSAGES]) {
    const base = {
      initiatorId: YO,
      viewerId: YO,
      otherUserId: OTRO,
      senderMessageCount: enviados,
      blocked: false,
      now: AHORA,
    };
    assertEquals(
      JSON.stringify(resolveInputState({ ...base, status: "ignored" })),
      JSON.stringify(resolveInputState({ ...base, status: "pending" })),
      `divergen con ${enviados} mensajes enviados`,
    );
  }
});

// =================================================================================================
// RN-27, RN-28 — la página de mensajes
// =================================================================================================

Deno.test("RN-28: un mensaje borrado para mí no me llega", () => {
  const vistos = projectMessages([
    mensaje({ id: "m1", content: "Visible" }),
    mensaje({ id: "m2", content: "Borrado", deletedFor: [YO] }),
  ], YO, null);

  assertEquals(vistos.map((m) => m.id), ["m1"]);
});

Deno.test("RN-28: al otro sí le llega el que yo borré para mí", () => {
  const vistos = projectMessages([mensaje({ id: "m2", content: "Borrado", deletedFor: [YO] })], OTRO, null);

  assertEquals(vistos.length, 1);
  assertEquals(vistos[0].content, "Borrado");
});

Deno.test("RN-28: la lápida viaja sin contenido y marcada", () => {
  const vistos = projectMessages([
    mensaje({ id: "m1", content: null, deletedForAllAt: "2026-08-25T11:30:00.000Z" }),
  ], YO, null);

  assertEquals(vistos[0].content, null);
  assertEquals(vistos[0].deleted_for_all, true);
});

Deno.test("RN-28: `edited` es un booleano, no la marca de tiempo", () => {
  const vistos = projectMessages([mensaje({ editedAt: "2026-08-25T11:30:00.000Z" })], YO, null);

  assertEquals(vistos[0].edited, true);
  assertEquals(JSON.stringify(vistos).includes("11:30"), false);
});

Deno.test("RN-27: no se devuelve nada anterior a mi propio borrado de historial", () => {
  const vistos = projectMessages([
    mensaje({ id: "viejo", createdAt: "2026-08-25T10:00:00.000Z" }),
    mensaje({ id: "nuevo", createdAt: "2026-08-25T12:00:00.000Z" }),
  ], YO, "2026-08-25T11:00:00.000Z");

  assertEquals(vistos.map((m) => m.id), ["nuevo"]);
});

// =================================================================================================
// La cita — donde se puede filtrar el texto de un mensaje que no debería verse
// =================================================================================================

Deno.test("la cita se resuelve con su contenido cuando el espectador puede verla", () => {
  const citado = mensaje({ id: "orig", content: "Texto citado", senderId: OTRO });
  const vistos = projectMessages(
    [mensaje({ id: "resp", replyToId: "orig" })],
    YO,
    null,
    new Map([["orig", citado]]),
  );

  assertEquals(vistos[0].reply_to?.content, "Texto citado");
  assertEquals(vistos[0].reply_to?.from_me, false);
});

Deno.test("la cita de un mensaje que borré para mí NO me devuelve su texto", () => {
  const citado = mensaje({ id: "orig", content: "Texto citado", deletedFor: [YO] });
  const vistos = projectMessages(
    [mensaje({ id: "resp", replyToId: "orig" })],
    YO,
    null,
    new Map([["orig", citado]]),
  );

  assertEquals(vistos[0].reply_to?.content, null);
});

Deno.test("la cita de un mensaje anterior a mi borrado de historial NO me devuelve su texto", () => {
  const citado = mensaje({ id: "orig", content: "Texto citado", createdAt: "2026-08-25T10:00:00.000Z" });
  const vistos = projectMessages(
    [mensaje({ id: "resp", replyToId: "orig", createdAt: "2026-08-25T12:00:00.000Z" })],
    YO,
    "2026-08-25T11:00:00.000Z",
    new Map([["orig", citado]]),
  );

  assertEquals(vistos[0].reply_to?.content, null);
});

Deno.test("una cita a un mensaje que no se encuentra no rompe la página", () => {
  const vistos = projectMessages([mensaje({ replyToId: "no-existe" })], YO, null, new Map());

  assertEquals(vistos.length, 1);
  assertEquals(vistos[0].reply_to, null);
});

// =================================================================================================
// RN-30 — el punto de actividad no existe en Solicitudes
// =================================================================================================

Deno.test("RN-30: la proyección no inventa `is_active` en ninguna de las dos listas", () => {
  // Lo añade el handler, y SOLO a Contactos. Que la función pura no lo traiga es lo que hace
  // imposible que se cuele en Solicitudes por descuido.
  const vista = projectInbox([
    conversacion({ status: "accepted" }),
    conversacion({ id: "otra", status: "pending", initiatorId: OTRO }),
  ], YO);

  assertEquals(Object.hasOwn(vista.contacts[0], "is_active"), false);
  assertEquals(Object.hasOwn(vista.requests[0], "is_active"), false);
});

Deno.test("el otro participante se resuelve mire quien mire, con el par ordenado", () => {
  const desdeA = projectInbox([conversacion({ status: "accepted" })], YO);
  const desdeB = projectInbox([conversacion({ status: "accepted" })], OTRO);

  assertEquals(desdeA.contacts[0].other_user_id, OTRO);
  assertEquals(desdeB.contacts[0].other_user_id, YO);
  assertNotEquals(desdeA.contacts[0].other_user_id, desdeB.contacts[0].other_user_id);
});
