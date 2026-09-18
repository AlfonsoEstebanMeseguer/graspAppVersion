// Límites antispam de la mensajería (RN-01, RN-07, RN-18, RN-19, RN-21) y la ocultación de RN-23.
// PURA: sin red, sin Postgres y sin reloj propio (`now` entra por parámetro).
//
// NO lanza excepciones: devuelve un VEREDICTO. Es deliberado, porque el mismo veredicto sirve para
// dos sitios que tienen que coincidir exactamente:
//   · `messaging-send` (Tarea 10), que convierte un `canSend: false` en un 422;
//   · `messaging-thread` (Tarea 11), que lo convierte en el estado del input (§9.2).
// Si fueran dos cálculos, el input podría decir «puedes escribir» y el envío rechazar — o peor,
// divergir justo en el caso del bloqueo, que es donde RN-23 exige que no se distinga nada.
//
// Sin Redis: los contadores los cuenta Postgres con índices parciales (Global Constraints del plan).
import type { ExistingConversation } from "./messaging-routing.ts";

/** RN-01: «exactamente 5 mensajes… ni uno más, bajo ninguna circunstancia». */
export const MAX_PENDING_MESSAGES = 5;
/** RN-18: solicitudes de mensaje pendientes simultáneas. */
export const MAX_PENDING_REQUESTS = 5;
/** RN-19: primeros mensajes en la ventana móvil. */
export const MAX_FIRST_MESSAGES_PER_DAY = 5;
/** Ventana MÓVIL de 24 h: el cupo no vuelve a medianoche, vuelve cuando el más antiguo caduca. */
export const FIRST_MESSAGE_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * Motivo que SÍ puede viajar al cliente.
 *
 * No hay ninguna variante para el bloqueo, y es la garantía de RN-23 escrita en el tipo: no existe
 * valor que el handler pueda enviar y que delate un bloqueo, ni por descuido.
 *
 * **PARA LA TAREA 11 (`messaging-view.ts`), que es quien traduce esto a texto:** `quota_exhausted`
 * se pinta SIEMPRE como *«Podrás seguir escribiendo cuando esta persona acepte tu mensaje.»*, tanto
 * si viene de un cupo agotado como de un bloqueo. Lo decide el ADR 0022, que resolvió el choque
 * entre RN-21 (di cuál es el límite y cuándo se recupera) y RN-23 (que el bloqueo no se distinga):
 * el literal *«No puedes enviar mensajes a esta cuenta.»* que RN-23 citaba **está retirado**.
 *
 * Y ese texto va en UNA SOLA CONSTANTE, no en dos literales iguales: dos literales pueden divergir
 * al editarlos, y ése es exactamente el fallo que el ADR existe para prevenir.
 */
export type PublicSendBlockedReason =
  | "quota_exhausted"
  | "too_many_pending_requests"
  | "too_many_first_messages";

/** Motivo real. `blocked` y `conversation_ignored` son SOLO para logs: nunca salen al cliente. */
export type InternalSendBlockedReason =
  | PublicSendBlockedReason
  | "blocked"
  | "conversation_ignored";

export interface LimitsContext {
  senderId: string;
  recipientId: string;
  existing: ExistingConversation | null;
  /** Mensajes que YA ha enviado el emisor en esa conversación (RN-01). */
  senderMessageCount: number;
  /** Conversaciones `pending` que el emisor tiene abiertas ahora mismo (RN-18). */
  pendingRequests: number;
  /** Primeros mensajes del emisor dentro de la ventana móvil (RN-19). */
  firstMessagesInWindow: number;
  /** El más antiguo de esos, para dar el `retry_at` exacto de RN-21. */
  oldestFirstMessageAt: string | Date | null;
  /** Bloqueo en CUALQUIERA de las dos direcciones. Sin dirección, a propósito. */
  blocked: boolean;
  now: Date;
}

export interface SendVerdict {
  canSend: boolean;
  /** Lo único que puede llegar al cliente. `null` si se puede enviar. */
  publicReason: PublicSendBlockedReason | null;
  /** Para logs y métricas. NUNCA se serializa en una respuesta. */
  internalReason: InternalSendBlockedReason | null;
  /** El número del límite alcanzado (RN-21). */
  limit: number | null;
  /** Cuándo se recupera el cupo, si el reloj lo devuelve. `null` cuando no depende del reloj. */
  retryAt: Date | null;
}

const PUEDE: SendVerdict = {
  canSend: true,
  publicReason: null,
  internalReason: null,
  limit: null,
  retryAt: null,
};

/**
 * EL VEREDICTO CUANDO NO SE PUEDE ESCRIBIR EN UNA CONVERSACIÓN QUE YA EXISTE.
 *
 * Una sola función para los TRES motivos —cupo agotado, bloqueo e ignorada— y ahí está RN-23: el
 * cuerpo es idéntico porque sale del mismo sitio, no porque alguien se acuerde de copiarlo igual.
 * Lo único que cambia es `internalReason`, que no se serializa.
 *
 * Por qué la ignorada también entra aquí: RN-06 exige que en el lado del emisor la conversación
 * siga «exactamente igual, en estado pendiente, para siempre». Si al agotarse el cupo de una
 * ignorada el mensaje fuera distinto del de una pendiente agotada, el emisor sabría que le
 * ignoraron.
 */
function noPuede(internalReason: InternalSendBlockedReason): SendVerdict {
  return {
    canSend: false,
    publicReason: "quota_exhausted",
    internalReason,
    limit: MAX_PENDING_MESSAGES,
    retryAt: null,
  };
}

export function evaluateSendLimits(ctx: LimitsContext): SendVerdict {
  // --- RN-07, camino 2 y 3: el bloqueo manda sobre todo lo demás y se comprueba EL PRIMERO. Si se
  // comprobara después, un bloqueado con el cupo agotado recibiría el motivo del cupo y uno con
  // cupo recibiría el del bloqueo: dos respuestas distintas para dos bloqueados, que es una fuga.
  if (ctx.blocked) return noPuede("blocked");

  // --- Primer mensaje: aquí es donde se ABRE conversación, y por tanto donde aplican RN-18 y RN-19.
  if (ctx.existing === null) {
    if (ctx.pendingRequests >= MAX_PENDING_REQUESTS) {
      return {
        canSend: false,
        publicReason: "too_many_pending_requests",
        internalReason: "too_many_pending_requests",
        limit: MAX_PENDING_REQUESTS,
        // Sin `retryAt` A PROPÓSITO: este cupo no lo libera el reloj, lo libera que alguien acepte.
        // Inventar un instante sería mentir, y RN-21 pide decir la verdad sobre cuándo se recupera.
        retryAt: null,
      };
    }

    if (ctx.firstMessagesInWindow >= MAX_FIRST_MESSAGES_PER_DAY) {
      const oldest = ctx.oldestFirstMessageAt === null ? null : new Date(ctx.oldestFirstMessageAt);
      const retryAt = oldest && !Number.isNaN(oldest.getTime())
        ? new Date(oldest.getTime() + FIRST_MESSAGE_WINDOW_MS)
        : new Date(ctx.now.getTime() + FIRST_MESSAGE_WINDOW_MS);

      return {
        canSend: false,
        publicReason: "too_many_first_messages",
        internalReason: "too_many_first_messages",
        limit: MAX_FIRST_MESSAGES_PER_DAY,
        retryAt,
      };
    }

    return PUEDE;
  }

  // --- Ya hay conversación. RN-18 y RN-19 no aplican: son topes de solicitudes ABIERTAS y de
  // primeros mensajes, no de mensajes. Seguir una conversación viva no consume ninguno de los dos.

  // Aceptada: sin límite (§4.2 caso 1, RN-05).
  if (ctx.existing.status === "accepted") return PUEDE;

  // RN-08: si el hilo lo abrió EL OTRO y sigue pendiente, contestarle es aceptar de hecho. No se
  // le aplica el tope de 5 a quien está aceptando, solo a quien pide entrar.
  if (ctx.existing.initiatorId === ctx.recipientId) return PUEDE;

  // Pendiente o ignorada iniciada por el emisor: RN-01, exactamente 5 y ni uno más.
  if (ctx.senderMessageCount >= MAX_PENDING_MESSAGES) {
    return noPuede(
      ctx.existing.status === "ignored" ? "conversation_ignored" : "quota_exhausted",
    );
  }

  return PUEDE;
}
