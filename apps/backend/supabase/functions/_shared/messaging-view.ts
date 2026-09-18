// La PROYECCIÓN POR ESPECTADOR de la mensajería (§8, §9.1, §9.2).
//
// PURA: sin red, sin Postgres y sin reloj propio. Recibe filas y el id de quien mira, y devuelve lo
// que ESA persona puede ver. Es el fichero donde RN-06, RN-23 y RN-31 se cumplen o se pierden.
//
// POR QUÉ ESTO EXISTE COMO MÓDULO APARTE, Y NO DENTRO DE CADA HANDLER
// `conversations` no tiene NI UN GRANT para `authenticated` (migración `20260823120200`), así que
// las dos bandejas y el hilo se sirven con `service_role` — que se salta la RLS. Es decir: todas las
// protecciones que la policy `direct_messages_read_participant` aplica al cliente (el `deleted_for`
// de RN-28 y el `cleared_at` de RN-27) **aquí no las aplica nadie**. Las reimplementa este fichero,
// una sola vez, con tests, en vez de dos veces a mano en dos handlers.
//
// LA REGLA QUE GOBIERNA EL DISEÑO: lo que no se emite no se puede filtrar. `status` e `initiator_id`
// no aparecen en NINGÚN tipo de salida de este módulo, así que no hay descuido posible que enseñe
// que una conversación quedó en `ignored` (RN-06). Lo que el espectador necesita saber viaja
// derivado y despersonalizado: `pending_acceptance` en vez del estado, `from_me` en vez del
// `sender_id`.
import { evaluateSendLimits, MAX_PENDING_MESSAGES } from "./messaging-limits.ts";
import type { ConversationStatus } from "./messaging-routing.ts";

/**
 * EL TEXTO DEL INPUT INERTE. Una sola constante, y es deliberado.
 *
 * Lo fija el ADR 0022, que resolvió el choque entre RN-21 (di qué límite y cuándo se recupera) y
 * RN-23 (que el bloqueo no se distinga): el mismo texto para el cupo agotado y para el bloqueo. El
 * literal «No puedes enviar mensajes a esta cuenta.» que RN-23 citaba **está retirado**.
 *
 * Va en UNA constante y no en dos literales iguales porque dos literales divergen al editarlos, y
 * ése es exactamente el fallo que el ADR existe para prevenir.
 */
export const INPUT_NOTICE_QUOTA =
  "Podrás seguir escribiendo cuando esta persona acepte tu mensaje.";

// =================================================================================================
// LA BANDEJA (§8)
// =================================================================================================

export type InboxBucket = "contacts" | "requests";

export interface LastMessageInput {
  senderId: string;
  /** `null` si es una lápida (RN-28, borrado para todos). */
  content: string | null;
  createdAt: string;
  /** RN-28, borrado "para mí". */
  deletedFor: string[];
  deletedForAll: boolean;
}

export interface ConversationViewInput {
  id: string;
  /** El par es ORDENADO (`user_a_id < user_b_id`): quién es el otro hay que compararlo, no suponerlo. */
  userAId: string;
  userBId: string;
  status: ConversationStatus;
  initiatorId: string;
  lastMessageAt: string;
  /** Del espectador. RN-22 (bloqueo) y RN-27 (borrado de historial) archivan por aquí. */
  viewerHidden: boolean;
  /** Del espectador y SOLO del espectador (RN-31). */
  viewerUnreadCount: number;
  viewerClearedAt: string | null;
  lastMessage: LastMessageInput | null;
}

export interface ConversationView {
  conversation_id: string;
  other_user_id: string;
  last_message_at: string;
  /** El propio. El del otro no se consulta ni se deriva (RN-31). */
  unread_count: number;
  /** El «Pendiente de aceptación» del §8.2. Sustituye a `status`, que no sale nunca. */
  pending_acceptance: boolean;
  last_message: {
    content: string | null;
    /** El «Tú: » del §8.2, sin exponer el `sender_id`. */
    from_me: boolean;
    created_at: string;
    deleted_for_all: boolean;
  } | null;
}

function otherParticipant(c: ConversationViewInput, viewerId: string): string {
  return c.userAId === viewerId ? c.userBId : c.userAId;
}

/**
 * A qué pestaña va una conversación para quien la mira, o `null` si no debe verla.
 *
 * AQUÍ VIVE RN-06, y es una sola línea: una `ignored` va a Contactos si la inició el espectador y
 * **desaparece** si no. En el lado del emisor se comporta exactamente igual que una `pending`
 * —misma pestaña, y más abajo el mismo JSON—; en el del receptor no existe en ninguna de las dos.
 */
export function bucketFor(c: ConversationViewInput, viewerId: string): InboxBucket | null {
  // RN-22 y RN-27: lo archivado no se lista. Es lo que esconde la conversación del bloqueador.
  if (c.viewerHidden) return null;

  const soyElIniciador = c.initiatorId === viewerId;

  if (c.status === "accepted") return "contacts";
  // RN-02: mi solicitud enviada aparece en MIS Contactos desde el primer mensaje.
  // RN-03: la recibida aparece en Solicitudes, nunca en Contactos.
  if (c.status === "pending") return soyElIniciador ? "contacts" : "requests";
  return soyElIniciador ? "contacts" : null;
}

/**
 * El último mensaje TAL Y COMO LO VE el espectador.
 *
 * Devuelve `null` —no el texto— cuando el espectador no debe verlo. La bandeja es justo donde se
 * escapan estas dos: al borrar un mensaje o vaciar el historial, la lista sigue enseñando el
 * "último mensaje" cacheado si nadie lo filtra aquí.
 */
function visibleLastMessage(
  c: ConversationViewInput,
  viewerId: string,
): ConversationView["last_message"] {
  const m = c.lastMessage;
  if (m === null) return null;
  if (m.deletedFor.includes(viewerId)) return null; // RN-28
  if (c.viewerClearedAt !== null && m.createdAt <= c.viewerClearedAt) return null; // RN-27

  return {
    content: m.deletedForAll ? null : m.content,
    from_me: m.senderId === viewerId,
    created_at: m.createdAt,
    deleted_for_all: m.deletedForAll,
  };
}

export function projectConversation(
  c: ConversationViewInput,
  viewerId: string,
): ConversationView | null {
  if (bucketFor(c, viewerId) === null) return null;

  return {
    conversation_id: c.id,
    other_user_id: otherParticipant(c, viewerId),
    last_message_at: c.lastMessageAt,
    unread_count: c.viewerUnreadCount,
    // Deriva del estado sin revelarlo: para una `ignored` iniciada por el espectador vale `true`,
    // igual que para una `pending`. Es la mitad de RN-06 que sostiene la ilusión.
    pending_acceptance: c.status !== "accepted" && c.initiatorId === viewerId,
    last_message: visibleLastMessage(c, viewerId),
  };
}

/**
 * Las dos listas del §8, ya ordenadas.
 *
 * NO añade `is_active`: lo pone el handler y **solo en Contactos** (RN-30, el punto no aparece en
 * Solicitudes). Que la función pura no lo traiga es lo que hace imposible que se cuele en la lista
 * equivocada por descuido.
 */
export function projectInbox(
  rows: ConversationViewInput[],
  viewerId: string,
): { contacts: ConversationView[]; requests: ConversationView[] } {
  const contacts: ConversationView[] = [];
  const requests: ConversationView[] = [];

  for (const row of rows) {
    const bucket = bucketFor(row, viewerId);
    if (bucket === null) continue;
    const view = projectConversation(row, viewerId);
    if (view === null) continue;
    (bucket === "contacts" ? contacts : requests).push(view);
  }

  // RN-29. Las marcas son ISO-8601 en UTC, así que el orden lexicográfico ES el cronológico.
  const masRecientePrimero = (a: ConversationView, b: ConversationView) =>
    a.last_message_at < b.last_message_at ? 1 : a.last_message_at > b.last_message_at ? -1 : 0;

  contacts.sort(masRecientePrimero);
  requests.sort(masRecientePrimero);
  return { contacts, requests };
}

// =================================================================================================
// EL ESTADO DEL INPUT (§9.2)
// =================================================================================================

export interface InputStateInput {
  status: ConversationStatus;
  initiatorId: string;
  viewerId: string;
  otherUserId: string;
  /** Mensajes que YA envió el espectador en esta conversación (RN-01). */
  senderMessageCount: number;
  /** Bloqueo en CUALQUIERA de las dos direcciones. Sin dirección, a propósito. */
  blocked: boolean;
  now: Date;
}

export interface InputState {
  can_send: boolean;
  input_notice: string | null;
  messages_left: number | null;
  /** Las cuatro acciones de RN-04 en lugar del input (§9.2, fila 4). */
  request_actions: boolean;
}

/**
 * LA FILA 4 DEL §9.2, EMITIDA CONSTANTE. Es una corrección de RN-23 del 2026-08-26.
 *
 * ## El oráculo que esto cierra
 *
 * Para una solicitud **recibida**, `can_send: false` **solo puede venir de un bloqueo**: el tope de
 * `RN-01` se le aplica a quien pide entrar, no a quien contesta, y `evaluateSendLimits` devuelve
 * *PUEDE* en cuanto `existing.initiatorId === recipientId`. Lo único que comprueba antes es el
 * bloqueo. Así que `can_send:false` junto a `request_actions:true` era un oráculo perfecto, y
 * `messages_left` —0 contra `null`— lo confirmaba por segunda vía.
 *
 * Alcanzable sin nada raro: A manda solicitud a B y después bloquea a B; B abre el hilo.
 *
 * ## Por qué emitir constante NO es «falsear un campo para que encaje con otro»
 *
 * Estos tres campos **no se pintan en esta fila**: el §9.2 sustituye el input por las cuatro
 * acciones de `RN-04`. Un campo que nadie mira pero que varía con el bloqueo es un canal lateral
 * regalado, y el principio que gobierna toda esta fase es que *lo que no se emite no se puede
 * filtrar*.
 *
 * ## La frontera: se arregla lo pasivo, no lo activo
 *
 * Esto tapa el oráculo **pasivo** —un `GET` que devuelve bytes distintos sin que nadie haga nada—.
 * El **activo** no se puede tapar: si el bloqueado intenta enviar, `messaging-send` tiene que
 * rechazarlo (`RN-24`), y en una solicitud recibida un envío solo falla si hay bloqueo. Cerrarlo
 * exigiría aceptar el mensaje y descartarlo en silencio, que es el diseño que el ADR 0022 ya
 * descartó por su coste ético. Mismo límite conocido que el input inerte de una conversación
 * aceptada (`pending-messaging.md` § 15).
 */
const SOLICITUD_RECIBIDA: InputState = Object.freeze({
  can_send: true,
  input_notice: null,
  messages_left: null,
  request_actions: true,
});

/**
 * El estado del input, DERIVADO DEL MISMO VEREDICTO QUE USA `messaging-send`.
 *
 * No recalcula nada: llama a `evaluateSendLimits`. Es el motivo por el que la Tarea 9 lo hizo
 * devolver un veredicto en vez de lanzar — si fueran dos cálculos, el input podría decir «puedes
 * escribir» y el envío rechazar, o peor, divergir justo en el caso del bloqueo, que es donde RN-23
 * exige que no se distinga nada.
 *
 * **La única excepción es la fila 4**, que se emite constante por [SOLICITUD_RECIBIDA]. Y se
 * corrige aquí —en lo que se PINTA— y no en `evaluateSendLimits` —lo que se PERMITE—: tocar el
 * veredicto dejaría a un bloqueado escribiéndole a quien le bloqueó, que es `RN-24`.
 */
export function resolveInputState(i: InputStateInput): InputState {
  // §9.2 fila 4: una solicitud RECIBIDA y sin aceptar no enseña input, enseña las cuatro acciones.
  // Se resuelve ANTES del veredicto y sale sin mirarlo: es lo que cierra el oráculo.
  if (i.status === "pending" && i.initiatorId === i.otherUserId) return SOLICITUD_RECIBIDA;

  const verdict = evaluateSendLimits({
    senderId: i.viewerId,
    recipientId: i.otherUserId,
    existing: { status: i.status, initiatorId: i.initiatorId },
    senderMessageCount: i.senderMessageCount,
    // RN-18 y RN-19 son topes de APERTURA: no aplican cuando ya hay conversación, y
    // `evaluateSendLimits` los ignora en esa rama. Van a cero para que se vea que no se consultan.
    pendingRequests: 0,
    firstMessagesInWindow: 0,
    oldestFirstMessageAt: null,
    blocked: i.blocked,
    now: i.now,
  });

  // Aquí abajo `request_actions` es SIEMPRE `false`: la fila 4 ya salió arriba. Se escribe el
  // literal en vez de recalcular la condición para que se vea que no hay dos caminos que puedan
  // divergir.
  return {
    can_send: verdict.canSend,
    input_notice: verdict.canSend ? null : INPUT_NOTICE_QUOTA,
    messages_left: remainingMessages(i, verdict.canSend),
    request_actions: false,
  };
}

/**
 * LOS MENSAJES QUE QUEDAN — y el `0` de la primera línea es RN-23, no una simplificación.
 *
 * Si esto devolviera siempre `MAX - enviados`, un bloqueado que solo hubiera gastado 2 de sus 5
 * recibiría `can_send: false` junto a `messages_left: 3`. Esa combinación **es imposible por un
 * cupo agotado** —sin cupo implica cero restantes—, así que sería un oráculo de bloqueo perfecto,
 * y encima construido a partir de dos campos que por separado parecen inocentes.
 *
 * Por eso el número se deriva del VEREDICTO y no del contador en bruto: no se puede enviar, luego
 * no quedan mensajes, sea cual sea el motivo.
 */
function remainingMessages(i: InputStateInput, canSend: boolean): number | null {
  if (!canSend) return 0;
  // Sin tope: aceptada (§4.2 caso 1) o abierta por el otro, que al contestar ya la acepta (RN-08).
  if (i.status === "accepted" || i.initiatorId !== i.viewerId) return null;
  return Math.max(0, MAX_PENDING_MESSAGES - i.senderMessageCount);
}

// =================================================================================================
// LA PÁGINA DE MENSAJES (§9.1)
// =================================================================================================

export interface MessageInput {
  id: string;
  senderId: string;
  content: string | null;
  deletedFor: string[];
  deletedForAllAt: string | null;
  editedAt: string | null;
  replyToId: string | null;
  createdAt: string;
}

export interface MessageView {
  id: string;
  from_me: boolean;
  content: string | null;
  deleted_for_all: boolean;
  /** Booleano, no la marca de tiempo: el §9 pide el tag "editado", no cuándo (punto 8 de db-schema). */
  edited: boolean;
  created_at: string;
  reply_to: { id: string; from_me: boolean; content: string | null } | null;
}

/** Si ESTE espectador puede ver este mensaje: RN-28 (borrado para mí) y RN-27 (historial vaciado). */
function visibleFor(m: MessageInput, viewerId: string, clearedAt: string | null): boolean {
  if (m.deletedFor.includes(viewerId)) return false;
  if (clearedAt !== null && m.createdAt <= clearedAt) return false;
  return true;
}

/**
 * LA CITA, que es por donde se filtra el texto de un mensaje que no debería verse.
 *
 * Se resuelve contra la MISMA prueba de visibilidad que el mensaje que la contiene. Sin esto,
 * borrar un mensaje "para mí" o vaciar el historial dejaría su texto accesible a través de
 * cualquier respuesta que lo citara — el mensaje desaparece de la lista y reaparece dentro de la
 * burbuja de otro.
 *
 * Se devuelve la cita con `content: null` en vez de omitirla: el cliente tiene que poder pintar
 * "mensaje no disponible" y conservar el hilo de la conversación.
 */
function resolveQuote(
  replyToId: string | null,
  viewerId: string,
  clearedAt: string | null,
  quoted: Map<string, MessageInput>,
): MessageView["reply_to"] {
  if (replyToId === null) return null;

  const q = quoted.get(replyToId);
  // Puede no estar: `reply_to_id` es `on delete set null`, y el borrado de cuenta se lleva mensajes
  // por delante. Una página que reventara por una cita rota dejaría la conversación ilegible.
  if (q === undefined) return null;

  const puedeVerlo = visibleFor(q, viewerId, clearedAt) && q.deletedForAllAt === null;
  return {
    id: q.id,
    from_me: q.senderId === viewerId,
    content: puedeVerlo ? q.content : null,
  };
}

export function projectMessages(
  rows: MessageInput[],
  viewerId: string,
  clearedAt: string | null,
  quoted: Map<string, MessageInput> = new Map(),
): MessageView[] {
  return rows
    .filter((m) => visibleFor(m, viewerId, clearedAt))
    .map((m) => ({
      id: m.id,
      from_me: m.senderId === viewerId,
      // La lápida viaja sin contenido aunque la fila lo tuviera: si el texto siguiera ahí,
      // cualquier cliente que ignorase la bandera lo pintaría igual (RN-28).
      content: m.deletedForAllAt !== null ? null : m.content,
      deleted_for_all: m.deletedForAllAt !== null,
      edited: m.editedAt !== null,
      created_at: m.createdAt,
      reply_to: resolveQuote(m.replyToId, viewerId, clearedAt, quoted),
    }));
}
