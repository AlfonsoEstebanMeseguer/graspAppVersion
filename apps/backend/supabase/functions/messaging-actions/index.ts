// messaging-actions — HTTP (app)
//
// Las acciones sobre una CONVERSACIÓN: `accept`, `ignore` (RN-04), `delete_history` (§9.3 punto 4),
// `mark_read` y `set_notifications` (§9.3 punto 1).
//
// La decisión es pura y vive en `_shared/messaging-actions.ts`, con sus 30 tests. Aquí solo se
// comprueba la pertenencia, se cargan dos filas y se aplican los efectos.
//
// Corre con `service_role` porque `conversations` no tiene ningún `grant` para `authenticated`: el
// cliente no puede cambiar un `status` ni leerlo. Y `hidden` y `cleared_at` tampoco se le conceden
// —solo `unread_count` y `notifications_enabled`—, porque archivar y vaciar el historial son
// acciones con consecuencias y pasan por aquí.
//
// COROLARIO DE SALTARSE LA RLS: la pertenencia deja de comprobarla Postgres. Sin la comprobación de
// abajo, cualquiera con un `conversation_id` podría ignorar o vaciar la conversación de otros dos.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { isUuid } from "../_shared/validation.ts";
import {
  type ConversationAction,
  resolveConversationAction,
} from "../_shared/messaging-actions.ts";
import type { ConversationStatus } from "../_shared/messaging-routing.ts";

const ACTIONS: readonly ConversationAction[] = [
  "accept",
  "ignore",
  "delete_history",
  "mark_read",
  "set_notifications",
];

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    const { userId: actorId } = await requireAuthUser(req);

    let raw: unknown;
    try {
      raw = await req.json();
    } catch {
      throw new AppError(400, "invalid_input", "Body no es JSON válido");
    }

    const body = (raw ?? {}) as {
      conversation_id?: unknown;
      action?: unknown;
      notifications_enabled?: unknown;
    };

    if (!isUuid(body.conversation_id)) {
      throw new AppError(400, "invalid_input", "conversation_id debe ser un uuid", {
        field: "conversation_id",
      });
    }
    const conversationId = body.conversation_id;

    if (
      typeof body.action !== "string" || !ACTIONS.includes(body.action as ConversationAction)
    ) {
      throw new AppError(400, "invalid_input", `action debe ser una de: ${ACTIONS.join(", ")}`, {
        field: "action",
      });
    }
    const action = body.action as ConversationAction;

    const service = getServiceRoleClient();

    // --- LA PERTENENCIA, ANTES DE NADA. Contra `conversation_states`, que tiene una fila por
    // participante. 404 y no 403: un 403 confirmaría que esa conversación existe.
    const { data: stateRow, error: stateError } = await service
      .from("conversation_states")
      .select("user_id")
      .eq("conversation_id", conversationId)
      .eq("user_id", actorId)
      .maybeSingle();

    if (stateError) {
      throw new AppError(500, "internal_error", "No se pudo cargar la conversación", {
        cause: stateError.message,
      });
    }
    if (stateRow === null) {
      throw new AppError(404, "not_found", "Conversación no encontrada");
    }

    const { data: convRow, error: convError } = await service
      .from("conversations")
      .select("id, status, initiator_id")
      .eq("id", conversationId)
      .maybeSingle();

    if (convError || convRow === null) {
      throw new AppError(500, "internal_error", "No se pudo cargar la conversación", {
        cause: convError?.message,
      });
    }

    const conversation = convRow as {
      id: string;
      status: ConversationStatus;
      initiator_id: string;
    };

    // --- La decisión. Lanza 403 si el actor no puede, 422 si la acción no cabe en ese estado.
    const effects = resolveConversationAction({
      action,
      actorId,
      conversation: {
        id: conversation.id,
        status: conversation.status,
        initiatorId: conversation.initiator_id,
      },
      notificationsEnabled: typeof body.notifications_enabled === "boolean"
        ? body.notifications_enabled
        : undefined,
      now: new Date(),
    });

    if (effects.noop) {
      return jsonResponse({ success: true, action, applied: false }, 200);
    }

    // --- El estado de la conversación. El `eq('status', ...)` hace de cerrojo, igual que en
    // `follow-toggle`: si dos peticiones cruzan, solo una encuentra fila que actualizar y la otra
    // no vuelve a disparar el efecto.
    if (effects.conversationStatus !== null) {
      const { error } = await service
        .from("conversations")
        .update({ status: effects.conversationStatus })
        .eq("id", conversationId)
        .eq("status", conversation.status);

      if (error) {
        throw new AppError(500, "internal_error", "No se pudo actualizar la conversación", {
          cause: error.message,
        });
      }
    }

    // --- Las escrituras de estado. Todas son sobre la fila del actor (lo fija un test que recorre
    // el enum entero), pero el `eq('user_id', ...)` va explícito de todas formas: es la última
    // barrera si algún día alguien devolviera aquí una escritura ajena.
    for (const write of effects.stateWrites) {
      const { error } = await service
        .from("conversation_states")
        .update(write.patch)
        .eq("conversation_id", conversationId)
        .eq("user_id", write.userId);

      if (error) {
        throw new AppError(500, "internal_error", "No se pudo actualizar el estado", {
          cause: error.message,
        });
      }
    }

    // La respuesta NO lleva el `status` de la conversación. El actor sabe lo que acaba de hacer, y
    // no emitirlo mantiene la regla de que `status` no sale de la base por ningún endpoint (RN-06).
    return jsonResponse({ success: true, action, applied: true }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
