import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  evaluateSendLimits,
  FIRST_MESSAGE_WINDOW_MS,
  type LimitsContext,
  MAX_FIRST_MESSAGES_PER_DAY,
  MAX_PENDING_MESSAGES,
  MAX_PENDING_REQUESTS,
} from "./messaging-limits.ts";

const EMISOR = "aaaaaaaa-0009-4000-8000-00000000000a";
const RECEPTOR = "bbbbbbbb-0009-4000-8000-00000000000b";
const AHORA = new Date("2026-08-25T12:00:00.000Z");

function ctx(over: Partial<LimitsContext> = {}): LimitsContext {
  return {
    senderId: EMISOR,
    recipientId: RECEPTOR,
    existing: null,
    senderMessageCount: 0,
    pendingRequests: 0,
    firstMessagesInWindow: 0,
    oldestFirstMessageAt: null,
    blocked: false,
    now: AHORA,
    ...over,
  };
}

const pendientePropia = { status: "pending" as const, initiatorId: EMISOR };

// =================================================================================================
// RN-01 — exactamente 5, "ni uno mas". El off-by-one que la spec subraya.
// =================================================================================================

Deno.test("RN-01: con 0 enviados se puede escribir", () => {
  assertEquals(evaluateSendLimits(ctx({ existing: pendientePropia })).canSend, true);
});

Deno.test("RN-01: el QUINTO mensaje SI pasa (4 enviados)", () => {
  // El borde exacto: "exactamente 5 mensajes". Con 4 gastados queda uno.
  const v = evaluateSendLimits(ctx({
    existing: pendientePropia,
    senderMessageCount: MAX_PENDING_MESSAGES - 1,
  }));
  assertEquals(v.canSend, true);
});

Deno.test("RN-01: el SEXTO se rechaza (5 enviados)", () => {
  const v = evaluateSendLimits(ctx({
    existing: pendientePropia,
    senderMessageCount: MAX_PENDING_MESSAGES,
  }));
  assertEquals(v.canSend, false);
  assertEquals(v.publicReason, "quota_exhausted");
});

Deno.test("RN-01: el tope NO aplica en una conversacion aceptada", () => {
  const v = evaluateSendLimits(ctx({
    existing: { status: "accepted", initiatorId: EMISOR },
    senderMessageCount: 500,
  }));
  assertEquals(v.canSend, true);
});

Deno.test("RN-08: contestar a la pendiente del OTRO no consume mi cupo", () => {
  // Si B me escribio y yo contesto, eso acepta de hecho (RN-08). Aplicarme el tope de 5 aqui
  // seria tratarme como si yo fuera quien pide entrar.
  const v = evaluateSendLimits(ctx({
    existing: { status: "pending", initiatorId: RECEPTOR },
    senderMessageCount: MAX_PENDING_MESSAGES,
  }));
  assertEquals(v.canSend, true);
});

// =================================================================================================
// RN-18 y RN-19 — solo al ABRIR conversacion (primer mensaje).
// =================================================================================================

Deno.test("RN-18: la QUINTA solicitud pendiente simultanea pasa", () => {
  const v = evaluateSendLimits(ctx({ pendingRequests: MAX_PENDING_REQUESTS - 1 }));
  assertEquals(v.canSend, true);
});

Deno.test("RN-18: la SEXTA solicitud pendiente simultanea se rechaza", () => {
  const v = evaluateSendLimits(ctx({ pendingRequests: MAX_PENDING_REQUESTS }));
  assertEquals(v.canSend, false);
  assertEquals(v.publicReason, "too_many_pending_requests");
});

Deno.test("RN-18: no aplica a una conversacion que YA existe", () => {
  // El tope es de solicitudes ABIERTAS, no de mensajes: seguir una conversacion viva no cuenta.
  const v = evaluateSendLimits(ctx({
    existing: pendientePropia,
    pendingRequests: MAX_PENDING_REQUESTS,
  }));
  assertEquals(v.canSend, true);
});

Deno.test("RN-19: el QUINTO primer mensaje del dia pasa", () => {
  const v = evaluateSendLimits(ctx({ firstMessagesInWindow: MAX_FIRST_MESSAGES_PER_DAY - 1 }));
  assertEquals(v.canSend, true);
});

Deno.test("RN-19: el SEXTO primer mensaje dentro de la ventana se rechaza", () => {
  const v = evaluateSendLimits(ctx({ firstMessagesInWindow: MAX_FIRST_MESSAGES_PER_DAY }));
  assertEquals(v.canSend, false);
  assertEquals(v.publicReason, "too_many_first_messages");
});

Deno.test("RN-19: a las 24 h y un segundo vuelve a haber cupo", () => {
  // La ventana es MOVIL: el cupo no vuelve a medianoche, vuelve cuando el mas antiguo caduca.
  // Se modela como lo hara el handler: al salir de la ventana, deja de contarse.
  const justoFuera = new Date(AHORA.getTime() - FIRST_MESSAGE_WINDOW_MS - 1000);
  const v = evaluateSendLimits(ctx({
    firstMessagesInWindow: MAX_FIRST_MESSAGES_PER_DAY - 1,
    oldestFirstMessageAt: justoFuera.toISOString(),
  }));
  assertEquals(v.canSend, true);
});

Deno.test("RN-21: el rechazo por RN-19 dice CUANDO se recupera", () => {
  const masAntiguo = new Date(AHORA.getTime() - 5 * 60 * 60 * 1000); // hace 5 h
  const v = evaluateSendLimits(ctx({
    firstMessagesInWindow: MAX_FIRST_MESSAGES_PER_DAY,
    oldestFirstMessageAt: masAntiguo.toISOString(),
  }));
  assertEquals(v.canSend, false);
  assertEquals(
    v.retryAt?.toISOString(),
    new Date(masAntiguo.getTime() + FIRST_MESSAGE_WINDOW_MS).toISOString(),
  );
});

Deno.test("RN-21: RN-18 no promete instante de recuperacion, y es correcto", () => {
  // El cupo de RN-18 no se libera con el reloj: se libera cuando alguien ACEPTA o el emisor deja
  // de tener solicitudes abiertas. Inventar un `retry_at` seria mentir.
  const v = evaluateSendLimits(ctx({ pendingRequests: MAX_PENDING_REQUESTS }));
  assertEquals(v.retryAt, null);
});

Deno.test("RN-21: todo rechazo trae limite y motivo, nunca un fallo mudo", () => {
  const rechazos = [
    evaluateSendLimits(ctx({ existing: pendientePropia, senderMessageCount: MAX_PENDING_MESSAGES })),
    evaluateSendLimits(ctx({ pendingRequests: MAX_PENDING_REQUESTS })),
    evaluateSendLimits(ctx({ firstMessagesInWindow: MAX_FIRST_MESSAGES_PER_DAY })),
  ];
  for (const v of rechazos) {
    assertEquals(v.canSend, false);
    assertEquals(typeof v.limit, "number");
    assertEquals(v.publicReason !== null, true);
  }
});

// =================================================================================================
// RN-07 — TRES caminos terminales, y los tres impiden abrir conversacion.
// =================================================================================================

Deno.test("RN-07 camino 1: una conversacion IGNORADA impide abrir otra", () => {
  // No hay segundo hilo posible: el par ya tiene el suyo, y quedo ignorado.
  const v = evaluateSendLimits(ctx({
    existing: { status: "ignored", initiatorId: EMISOR },
    senderMessageCount: MAX_PENDING_MESSAGES,
  }));
  assertEquals(v.canSend, false);
});

Deno.test("RN-07 camino 2: el RECEPTOR bloqueo al emisor -> no se puede enviar", () => {
  assertEquals(evaluateSendLimits(ctx({ blocked: true })).canSend, false);
});

Deno.test("RN-07 camino 3: el EMISOR bloqueo al receptor -> tampoco se puede enviar", () => {
  // El bloqueo llega en `blocked` sin direccion a proposito: los dos sentidos cierran el par, y
  // distinguirlos aqui invitaria a exponer cual es cual.
  assertEquals(evaluateSendLimits(ctx({ blocked: true })).canSend, false);
});

Deno.test("RN-07: el bloqueo manda sobre TODO lo demas, incluso con cupo de sobra", () => {
  const v = evaluateSendLimits(ctx({
    blocked: true,
    existing: { status: "accepted", initiatorId: EMISOR },
    senderMessageCount: 0,
    pendingRequests: 0,
    firstMessagesInWindow: 0,
  }));
  assertEquals(v.canSend, false);
});

// =================================================================================================
// RN-23 — lo que sale al cliente no distingue un bloqueo de un limite agotado.
// =================================================================================================

Deno.test("RN-23: bloqueo y cupo agotado devuelven el MISMO motivo publico", () => {
  // Es el corazon de RN-23 en esta capa. Si estos dos divergieran, el bloqueado sabria que lo
  // esta con solo comparar dos respuestas. El motivo INTERNO si se distingue, para logs.
  const porBloqueo = evaluateSendLimits(ctx({
    blocked: true,
    existing: pendientePropia,
  }));
  const porCupo = evaluateSendLimits(ctx({
    existing: pendientePropia,
    senderMessageCount: MAX_PENDING_MESSAGES,
  }));

  assertEquals(porBloqueo.publicReason, porCupo.publicReason);
  assertEquals(porBloqueo.retryAt, porCupo.retryAt);
  assertEquals(porBloqueo.limit, porCupo.limit);
});

Deno.test("RN-23: el motivo INTERNO si distingue el bloqueo (para logs, nunca para el cliente)", () => {
  assertEquals(evaluateSendLimits(ctx({ blocked: true })).internalReason, "blocked");
});

Deno.test("RN-06: una ignorada tampoco se distingue de una pendiente agotada", () => {
  const porIgnorada = evaluateSendLimits(ctx({
    existing: { status: "ignored", initiatorId: EMISOR },
    senderMessageCount: MAX_PENDING_MESSAGES,
  }));
  const porCupo = evaluateSendLimits(ctx({
    existing: pendientePropia,
    senderMessageCount: MAX_PENDING_MESSAGES,
  }));
  assertEquals(porIgnorada.publicReason, porCupo.publicReason);
  assertEquals(porIgnorada.limit, porCupo.limit);
});

Deno.test("RN-06: en una ignorada con cupo, el emisor SIGUE pudiendo escribir", () => {
  // La ilusion de RN-06 exige que su lado se comporte "exactamente igual, para siempre". Si al
  // ignorar se le cortara el input, lo notaria en el acto.
  const v = evaluateSendLimits(ctx({
    existing: { status: "ignored", initiatorId: EMISOR },
    senderMessageCount: 2,
  }));
  assertEquals(v.canSend, true);
});

// =================================================================================================
// Constantes
// =================================================================================================

Deno.test("las constantes son las de la spec", () => {
  assertEquals(MAX_PENDING_MESSAGES, 5); // RN-01
  assertEquals(MAX_PENDING_REQUESTS, 5); // RN-18
  assertEquals(MAX_FIRST_MESSAGES_PER_DAY, 5); // RN-19
  assertEquals(FIRST_MESSAGE_WINDOW_MS, 86_400_000);
});
