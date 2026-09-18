// Las acciones sobre una conversación y sobre un mensaje (§9.3, RN-05, RN-06, RN-27, RN-28, RN-31).
//
// PURA: sin red, sin Postgres y sin reloj propio (`now` entra por parámetro). Decide QUÉ hay que
// escribir; los dos handlers solo lo aplican.
//
// Lanza `AppError` para los rechazos, igual que `resolveFollowTransition` en `follow.ts`: aquí no
// hay nada que ocultar —los dos participantes se conocen y ninguna de estas respuestas revela un
// bloqueo—, así que un 403 explícito es mejor que un veredicto. Eso lo necesita
// `messaging-limits.ts`, que sí decide sobre algo que RN-23 obliga a disimular.
//
// LA FORMA DEL TIPO DE SALIDA ES EL INVARIANTE. `stateWrites` lleva el `userId` dentro de cada
// escritura en vez de dar por hecho que es el actor, precisamente para que un test pueda recorrer
// TODAS las acciones y comprobar que ninguna escribe en la fila del otro. De eso dependen dos reglas
// a la vez: RN-31 (el `unread_count` es estrictamente local) y RN-06 (el emisor no se entera de
// nada). Un tipo que sólo pudiera expresar "el actor" haría el invariante cierto por construcción,
// pero también invisible — y el día que alguien necesite escribir en la otra fila, lo añadiría sin
// que ningún test dijera nada.
import { AppError } from "./http.ts";
import type { ConversationStatus } from "./messaging-routing.ts";

export type ConversationAction =
  | "accept"
  | "ignore"
  | "delete_history"
  | "mark_read"
  | "set_notifications";

export type MessageAction = "delete_for_me" | "delete_for_all" | "edit";

export interface ConversationSnapshot {
  id: string;
  status: ConversationStatus;
  initiatorId: string;
}

export interface ConversationActionContext {
  action: ConversationAction;
  actorId: string;
  conversation: ConversationSnapshot;
  /** Solo para `set_notifications`. Sin valor por defecto: ver el 400 de abajo. */
  notificationsEnabled?: boolean;
  now: Date;
}

/** Una escritura sobre `conversation_states`. El `userId` viaja explícito — ver la cabecera. */
export interface StateWrite {
  userId: string;
  patch: {
    hidden?: boolean;
    unread_count?: number;
    cleared_at?: string;
    notifications_enabled?: boolean;
  };
}

export interface ConversationEffects {
  /** Nuevo `status` de la conversación, o `null` si no se toca. */
  conversationStatus: "accepted" | "ignored" | null;
  stateWrites: StateWrite[];
  /** Ya estaba así: se responde 200 sin escribir. */
  noop: boolean;
}

const NADA: ConversationEffects = { conversationStatus: null, stateWrites: [], noop: true };

export function resolveConversationAction(ctx: ConversationActionContext): ConversationEffects {
  const { action, actorId, conversation, now } = ctx;
  const soyElIniciador = conversation.initiatorId === actorId;

  switch (action) {
    // --- RN-05: la conversación pasa a Contactos de los dos y ambos escriben sin límite.
    case "accept": {
      if (conversation.status === "accepted") return NADA;
      // RN-07: `ignored` es TERMINAL. Lo único que reanuda una ignorada es RN-17, y vive en
      // `follow-toggle` (al aceptar el follow del que escribió). Desde aquí no, entre otras cosas
      // porque al receptor la conversación ya no le aparece en ninguna pestaña.
      if (conversation.status === "ignored") return NADA;

      // Aceptar la solicitud que uno mismo envió sería colarse en los Contactos del otro sin que el
      // otro haga nada. Un 403 y no un no-op: un no-op silencioso taparía el intento.
      if (soyElIniciador) {
        throw new AppError(403, "forbidden", "Solo puede aceptar quien recibió la solicitud");
      }

      return { conversationStatus: "accepted", stateWrites: [], noop: false };
    }

    // --- RN-06: desaparece de Solicitudes del receptor y el emisor NO se entera de nada.
    case "ignore": {
      if (conversation.status === "ignored") return NADA;
      // Las cuatro acciones de RN-04 solo se ofrecen sobre una solicitud sin aceptar (§9.2, fila 4).
      // Sobre una conversación ya aceptada no hay "ignorar": lo que hay es bloquear o vaciar.
      if (conversation.status === "accepted") {
        throw new AppError(
          422,
          "invalid_action",
          "Solo se puede ignorar una solicitud que no se ha aceptado",
        );
      }
      if (soyElIniciador) {
        throw new AppError(403, "forbidden", "Solo puede ignorar quien recibió la solicitud");
      }

      // El `hidden` va SOLO en la fila de quien ignora. Es el mecanismo de RN-06, y es justo el que
      // el trigger de entrega (`20260825120000`) respeta al no tocar nada del receptor en una
      // conversación `ignored` — si aquí se pusiera también en la del emisor, o allí se limpiara,
      // los mensajes 2..5 desharían el rechazo. Ver ADR 0023.
      //
      // Y `unread_count: 0` EN LA MISMA ESCRITURA, no como paso aparte. El trigger de entrega ya no
      // sube ese contador en una conversación ignorada, pero el PRIMER mensaje —el que provocó la
      // solicitud— llegó cuando todavía era `pending` y dejó su 1. Sin esta línea ese 1 se quedaba
      // ahí para siempre: la conversación desaparece de las dos pestañas del receptor, así que **no
      // hay pantalla donde marcarlo como leído**. Es el mismo estado absorbente que el ADR 0023
      // nombra como motivo para no dejar subir el contador, y el argumento no distingue de dónde
      // vino el número. Detectado auditando la casilla 6 del §12 el 2026-08-28 (hallazgo H-1).
      return {
        conversationStatus: "ignored",
        stateWrites: [{ userId: actorId, patch: { hidden: true, unread_count: 0 } }],
        noop: false,
      };
    }

    // --- RN-27: borra la conversación SOLO para quien lo hace. El otro conserva su historial
    // íntegro, y por eso no se borra ni una fila de `direct_messages`: se marca desde cuándo ve
    // ESTE usuario. Si el otro vuelve a escribir, el trigger de entrega le quita el `hidden` y la
    // conversación reaparece vacía, mostrando solo lo posterior.
    case "delete_history":
      return {
        conversationStatus: null,
        stateWrites: [{
          userId: actorId,
          patch: { cleared_at: now.toISOString(), hidden: true },
        }],
        noop: false,
      };

    // --- RN-31: el contador es estrictamente local. Ponerlo a cero no toca ninguna fila del otro,
    // que es lo que hace que no exista confirmación de lectura que filtrar (ADR 0021).
    case "mark_read":
      return {
        conversationStatus: null,
        stateWrites: [{ userId: actorId, patch: { unread_count: 0 } }],
        noop: false,
      };

    // --- §9.3 punto 1: persiste el valor y no hace nada más (no hay notificaciones todavía).
    case "set_notifications": {
      if (typeof ctx.notificationsEnabled !== "boolean") {
        throw new AppError(400, "invalid_input", "notifications_enabled debe ser booleano", {
          field: "notifications_enabled",
        });
      }
      return {
        conversationStatus: null,
        stateWrites: [{
          userId: actorId,
          patch: { notifications_enabled: ctx.notificationsEnabled },
        }],
        noop: false,
      };
    }
  }
}

// =================================================================================================
// EL MENSAJE (RN-28)
// =================================================================================================

export interface MessageSnapshot {
  id: string;
  senderId: string;
  content: string | null;
  deletedFor: string[];
  deletedForAllAt: string | null;
}

export interface MessageActionContext {
  action: MessageAction;
  actorId: string;
  message: MessageSnapshot;
  /** Solo para `edit`, y **ya normalizado** por `normalizeMessageContent`. */
  newContent?: string;
  now: Date;
}

export interface MessageEffects {
  patch: {
    deleted_for?: string[];
    content?: string | null;
    deleted_for_all_at?: string;
    edited_at?: string;
  };
  noop: boolean;
}

const SIN_CAMBIOS: MessageEffects = { patch: {}, noop: true };

function requireAuthor(ctx: MessageActionContext, queHace: string): void {
  if (ctx.message.senderId !== ctx.actorId) {
    throw new AppError(403, "forbidden", `Solo el autor puede ${queHace} este mensaje`);
  }
}

export function resolveMessageAction(ctx: MessageActionContext): MessageEffects {
  const { action, actorId, message, now } = ctx;
  const esLapida = message.deletedForAllAt !== null;

  switch (action) {
    // --- Borrado "para mí": lo puede hacer CUALQUIER participante, autor o no. Es su copia, y la
    // policy de lectura lo aplica con `not (auth.uid() = any(deleted_for))`.
    case "delete_for_me": {
      if (message.deletedFor.includes(actorId)) return SIN_CAMBIOS;
      return {
        patch: { deleted_for: [...message.deletedFor, actorId] },
        noop: false,
      };
    }

    // --- Borrado "para todos": la fila sobrevive como lápida.
    case "delete_for_all": {
      requireAuthor(ctx, "borrar para todos");
      if (esLapida) return SIN_CAMBIOS;

      // LOS DOS CAMPOS EN EL MISMO PATCH, y no es una preferencia de estilo: la constraint
      // `direct_messages_content_or_tombstone` exige `content is null` en cuanto hay lápida, así
      // que un patch a medias no es "incompleto" — es un 500. Y `content` a null es lo que impide
      // que un cliente que ignore la bandera siga pintando el texto.
      return {
        patch: { content: null, deleted_for_all_at: now.toISOString() },
        noop: false,
      };
    }

    // --- Edición, con el tag "editado" visible para los dos.
    case "edit": {
      requireAuthor(ctx, "editar");

      if (typeof ctx.newContent !== "string") {
        throw new AppError(400, "invalid_input", "content es obligatorio para editar", {
          field: "content",
        });
      }

      // Una lápida no se edita. Sin este guardia el UPDATE dejaría `content` no nulo con
      // `deleted_for_all_at` puesto: la constraint lo rechaza (500 en vez de 422) y, si algún día
      // se relajara, un mensaje borrado para todos resucitaría con texto nuevo.
      if (esLapida) {
        throw new AppError(422, "invalid_action", "No se puede editar un mensaje eliminado");
      }

      // Guardar sin cambios no marca nada. El tag lo ven los dos (RN-28), así que ponerlo por un
      // guardado idéntico le diría al otro que estuve editando cuando no cambié una coma.
      if (ctx.newContent === message.content) return SIN_CAMBIOS;

      return {
        patch: { content: ctx.newContent, edited_at: now.toISOString() },
        noop: false,
      };
    }
  }
}
