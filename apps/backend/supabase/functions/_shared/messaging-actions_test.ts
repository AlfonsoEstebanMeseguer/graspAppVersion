import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type ConversationAction,
  type ConversationActionContext,
  type MessageActionContext,
  resolveConversationAction,
  resolveMessageAction,
} from "./messaging-actions.ts";
import { AppError } from "./http.ts";
import { MAX_MESSAGE_LENGTH, normalizeMessageContent } from "./validation.ts";

const EMISOR = "aaaaaaaa-0012-4000-8000-00000000000a"; // inició la conversación
const RECEPTOR = "bbbbbbbb-0012-4000-8000-00000000000b";
const CONV = "cccccccc-0012-4000-8000-0000000000c1";
const MSG = "dddddddd-0012-4000-8000-00000000000d";
const AHORA = new Date("2026-08-25T12:00:00.000Z");

function conversacion(over: Partial<ConversationActionContext> = {}): ConversationActionContext {
  return {
    action: "accept",
    actorId: RECEPTOR,
    conversation: { id: CONV, status: "pending", initiatorId: EMISOR },
    now: AHORA,
    ...over,
  };
}

function mensaje(over: Partial<MessageActionContext> = {}): MessageActionContext {
  return {
    action: "delete_for_me",
    actorId: EMISOR,
    message: {
      id: MSG,
      senderId: EMISOR,
      content: "Hola",
      deletedFor: [],
      deletedForAllAt: null,
    },
    now: AHORA,
    ...over,
  };
}

/** El status del `AppError` que lanza, o 0 si no lanza. */
function statusOf(fn: () => unknown): number {
  try {
    fn();
    return 0;
  } catch (err) {
    return err instanceof AppError ? err.status : -1;
  }
}

// =================================================================================================
// RN-05 — aceptar
// =================================================================================================

Deno.test("RN-05: aceptar deja la conversación en `accepted` y no escribe ningún estado", () => {
  const efectos = resolveConversationAction(conversacion({ action: "accept" }));

  assertEquals(efectos.conversationStatus, "accepted");
  assertEquals(efectos.stateWrites, []);
  assertEquals(efectos.noop, false);
});

Deno.test("aceptar la solicitud que YO envié es un 403, no un no-op silencioso", () => {
  // Si esto fuera un no-op, cualquiera podría auto-aceptarse en los Contactos de otro sin que la
  // otra persona hiciera nada — y encima sin error que lo delatara.
  assertEquals(statusOf(() => resolveConversationAction(conversacion({ actorId: EMISOR }))), 403);
});

Deno.test("aceptar una conversación ya aceptada es un no-op con 200", () => {
  const efectos = resolveConversationAction(
    conversacion({ conversation: { id: CONV, status: "accepted", initiatorId: EMISOR } }),
  );

  assertEquals(efectos.noop, true);
  assertEquals(efectos.conversationStatus, null);
});

Deno.test("RN-07: aceptar una IGNORADA no la resucita — solo RN-17 lo hace, desde follow-toggle", () => {
  const efectos = resolveConversationAction(
    conversacion({ conversation: { id: CONV, status: "ignored", initiatorId: EMISOR } }),
  );

  assertEquals(efectos.noop, true);
  assertEquals(efectos.conversationStatus, null);
});

// =================================================================================================
// RN-06 — ignorar
// =================================================================================================

Deno.test("RN-06: ignorar pone `ignored` y oculta SOLO la fila de quien ignora", () => {
  const efectos = resolveConversationAction(conversacion({ action: "ignore" }));

  assertEquals(efectos.conversationStatus, "ignored");
  assertEquals(efectos.stateWrites, [{
    userId: RECEPTOR,
    patch: { hidden: true, unread_count: 0 },
  }]);
});

Deno.test("ignorar deja el `unread_count` de quien ignora a CERO, no solo oculto (H-1)", () => {
  // Detectado el 2026-08-28 auditando la casilla 6 del §12. `ignore` ponía `hidden: true` y nada
  // más, así que el contador que había dejado el PRIMER mensaje —el que provocó la solicitud— se
  // quedaba en 1 para siempre.
  //
  // No es un detalle cosmético: es el mismo argumento con el que el ADR 0023 justifica que la
  // entrega POSTERIOR no toque ese contador —«un badge que sube por una conversación que no aparece
  // en ninguna pestaña es un número que no puede bajar nunca, porque no hay pantalla donde marcarlo
  // como leído»—, o sea un ESTADO ABSORBENTE. El argumento no distingue de dónde vino el número.
  //
  // Hoy no era observable porque `messaging-inbox` no lista las `ignored` del receptor, pero eso
  // deja la invisibilidad colgando de UN SOLO mecanismo, que es justo lo que el ADR quería evitar.
  const efectos = resolveConversationAction(conversacion({ action: "ignore" }));

  assertEquals(efectos.stateWrites, [{
    userId: RECEPTOR,
    patch: { hidden: true, unread_count: 0 },
  }]);
});

Deno.test("RN-06: ignorar no produce NI UNA escritura sobre la fila del emisor", () => {
  const efectos = resolveConversationAction(conversacion({ action: "ignore" }));

  assertEquals(efectos.stateWrites.filter((w) => w.userId === EMISOR), []);
});

Deno.test("ignorar una conversación ya aceptada es 422: las cuatro acciones de RN-04 solo salen en una solicitud", () => {
  assertEquals(
    statusOf(() =>
      resolveConversationAction(
        conversacion({
          action: "ignore",
          conversation: { id: CONV, status: "accepted", initiatorId: EMISOR },
        }),
      )
    ),
    422,
  );
});

Deno.test("ignorar mi propia solicitud enviada es un 403", () => {
  assertEquals(
    statusOf(() => resolveConversationAction(conversacion({ action: "ignore", actorId: EMISOR }))),
    403,
  );
});

// =================================================================================================
// EL INVARIANTE QUE SOSTIENE RN-06 Y RN-31 A LA VEZ
// =================================================================================================

Deno.test("NINGUNA acción sobre la conversación escribe en la fila del otro participante", () => {
  // RN-31 (el `unread_count` es estrictamente local) y RN-06 (el emisor no se entera de nada)
  // dependen los dos de esto. Un test por acción se olvidaría de la acción que se añada mañana;
  // este recorre el enum entero.
  const acciones: ConversationAction[] = [
    "accept",
    "ignore",
    "delete_history",
    "mark_read",
    "set_notifications",
  ];

  for (const action of acciones) {
    const efectos = resolveConversationAction(conversacion({
      action,
      notificationsEnabled: true,
    }));
    const ajenas = efectos.stateWrites.filter((w) => w.userId !== RECEPTOR);
    assertEquals(ajenas, [], `\`${action}\` escribió en una fila que no es la del actor`);
  }
});

// =================================================================================================
// RN-27 — borrar el historial
// =================================================================================================

Deno.test("RN-27: borrar el historial marca `cleared_at` y oculta, solo para quien lo pide", () => {
  const efectos = resolveConversationAction(conversacion({ action: "delete_history" }));

  assertEquals(efectos.stateWrites, [{
    userId: RECEPTOR,
    patch: { cleared_at: AHORA.toISOString(), hidden: true },
  }]);
});

Deno.test("RN-27: borrar el historial NO cambia el estado de la conversación", () => {
  // Si lo cambiara, vaciar mi historial le movería la conversación de pestaña al otro.
  const efectos = resolveConversationAction(conversacion({ action: "delete_history" }));

  assertEquals(efectos.conversationStatus, null);
});

Deno.test("RN-27: el emisor también puede vaciar su historial, y sigue sin tocar al otro", () => {
  const efectos = resolveConversationAction(
    conversacion({ action: "delete_history", actorId: EMISOR }),
  );

  assertEquals(efectos.stateWrites.map((w) => w.userId), [EMISOR]);
});

// =================================================================================================
// RN-31 — marcar como leído
// =================================================================================================

Deno.test("RN-31: marcar como leído pone a cero el contador PROPIO y nada más", () => {
  const efectos = resolveConversationAction(conversacion({ action: "mark_read" }));

  assertEquals(efectos.stateWrites, [{ userId: RECEPTOR, patch: { unread_count: 0 } }]);
  assertEquals(efectos.conversationStatus, null);
});

// =================================================================================================
// §9.3 punto 1 — el interruptor de notificaciones
// =================================================================================================

Deno.test("§9.3: el interruptor de notificaciones persiste y no hace nada más", () => {
  const off = resolveConversationAction(
    conversacion({ action: "set_notifications", notificationsEnabled: false }),
  );

  assertEquals(off.stateWrites, [{ userId: RECEPTOR, patch: { notifications_enabled: false } }]);
  assertEquals(off.conversationStatus, null);
});

Deno.test("§9.3: sin el booleano, el interruptor es un 400 — no se asume un valor por defecto", () => {
  assertEquals(
    statusOf(() => resolveConversationAction(conversacion({ action: "set_notifications" }))),
    400,
  );
});

// =================================================================================================
// RN-28 — borrar "para mí"
// =================================================================================================

Deno.test("RN-28: borrar para mí me añade al array y no toca el contenido", () => {
  const efectos = resolveMessageAction(mensaje({ action: "delete_for_me", actorId: RECEPTOR }));

  assertEquals(efectos.patch, { deleted_for: [RECEPTOR] });
});

Deno.test("RN-28: borrar para mí lo puede hacer QUIEN NO ES EL AUTOR — es su copia", () => {
  const efectos = resolveMessageAction(mensaje({ action: "delete_for_me", actorId: RECEPTOR }));

  assertEquals(efectos.noop, false);
  assertEquals(efectos.patch.deleted_for, [RECEPTOR]);
});

Deno.test("RN-28: borrar para mí conserva a quien ya estuviera en el array", () => {
  const efectos = resolveMessageAction(mensaje({
    action: "delete_for_me",
    actorId: RECEPTOR,
    message: {
      id: MSG,
      senderId: EMISOR,
      content: "Hola",
      deletedFor: [EMISOR],
      deletedForAllAt: null,
    },
  }));

  assertEquals(efectos.patch.deleted_for, [EMISOR, RECEPTOR]);
});

Deno.test("RN-28: borrar dos veces para mí es idempotente, no me duplica en el array", () => {
  const efectos = resolveMessageAction(mensaje({
    action: "delete_for_me",
    actorId: RECEPTOR,
    message: {
      id: MSG,
      senderId: EMISOR,
      content: "Hola",
      deletedFor: [RECEPTOR],
      deletedForAllAt: null,
    },
  }));

  assertEquals(efectos.noop, true);
});

// =================================================================================================
// RN-28 — borrar "para todos"
// =================================================================================================

Deno.test("RN-28: borrar para todos SOLO lo puede el autor", () => {
  assertEquals(
    statusOf(() => resolveMessageAction(mensaje({ action: "delete_for_all", actorId: RECEPTOR }))),
    403,
  );
});

Deno.test("RN-28: borrar para todos pone `content` a null Y la marca, en el mismo patch", () => {
  // Los dos juntos o ninguno: el `check` de la tabla exige `content is null` cuando hay lápida, así
  // que un patch a medias no es "incompleto", es un 500.
  const efectos = resolveMessageAction(mensaje({ action: "delete_for_all" }));

  assertEquals(efectos.patch, {
    content: null,
    deleted_for_all_at: AHORA.toISOString(),
  });
});

Deno.test("RN-28: borrar para todos dos veces es idempotente", () => {
  const efectos = resolveMessageAction(mensaje({
    action: "delete_for_all",
    message: {
      id: MSG,
      senderId: EMISOR,
      content: null,
      deletedFor: [],
      deletedForAllAt: "2026-08-25T11:00:00.000Z",
    },
  }));

  assertEquals(efectos.noop, true);
});

// =================================================================================================
// RN-28 — editar
// =================================================================================================

Deno.test("RN-28: editar SOLO lo puede el autor", () => {
  assertEquals(
    statusOf(() =>
      resolveMessageAction(mensaje({ action: "edit", actorId: RECEPTOR, newContent: "Otro" }))
    ),
    403,
  );
});

Deno.test("RN-28: editar cambia el contenido y marca `edited_at`", () => {
  const efectos = resolveMessageAction(mensaje({ action: "edit", newContent: "Corregido" }));

  assertEquals(efectos.patch, {
    content: "Corregido",
    edited_at: AHORA.toISOString(),
  });
});

Deno.test("RN-28: NO se puede editar una lápida", () => {
  // Sin este guardia el UPDATE dejaría `content` no nulo con `deleted_for_all_at` puesto, que la
  // constraint rechaza: un 500 en vez de un 422, y un mensaje borrado para todos resucitando.
  assertEquals(
    statusOf(() =>
      resolveMessageAction(mensaje({
        action: "edit",
        newContent: "Resucitado",
        message: {
          id: MSG,
          senderId: EMISOR,
          content: null,
          deletedFor: [],
          deletedForAllAt: "2026-08-25T11:00:00.000Z",
        },
      }))
    ),
    422,
  );
});

Deno.test("RN-28: editar con el mismo texto es un no-op y NO pone el tag «editado»", () => {
  // El tag lo ven los dos (RN-28). Ponerlo por un guardado sin cambios le diría al otro que estuve
  // toqueteando el mensaje cuando no cambié nada.
  const efectos = resolveMessageAction(mensaje({ action: "edit", newContent: "Hola" }));

  assertEquals(efectos.noop, true);
});

Deno.test("editar sin texto es un 400", () => {
  assertEquals(statusOf(() => resolveMessageAction(mensaje({ action: "edit" }))), 400);
});

// =================================================================================================
// RN-26 — la longitud, ahora en un solo sitio para los DOS caminos de escritura
// =================================================================================================

Deno.test("RN-26: el texto se recorta y se acepta entre 1 y 1000", () => {
  assertEquals(normalizeMessageContent("  Hola  "), "Hola");
  assertEquals(normalizeMessageContent("a".repeat(MAX_MESSAGE_LENGTH)).length, MAX_MESSAGE_LENGTH);
});

Deno.test("RN-26: 1001 se rechaza y solo espacios se rechaza", () => {
  assertEquals(statusOf(() => normalizeMessageContent("a".repeat(MAX_MESSAGE_LENGTH + 1))), 400);
  assertEquals(statusOf(() => normalizeMessageContent("     ")), 400);
  assertEquals(statusOf(() => normalizeMessageContent(42)), 400);
});

Deno.test("RN-26: se mide en PUNTOS DE CÓDIGO, como `char_length` en Postgres", () => {
  // 1000 emojis son 2000 unidades UTF-16 y 1000 puntos de código. La base los acepta; medirlos con
  // `.length` los rechazaría con un 400 que quien escribe no puede entender.
  const milEmojis = "🌈".repeat(MAX_MESSAGE_LENGTH);
  assertEquals(milEmojis.length, MAX_MESSAGE_LENGTH * 2);
  assertEquals(normalizeMessageContent(milEmojis), milEmojis);
});
