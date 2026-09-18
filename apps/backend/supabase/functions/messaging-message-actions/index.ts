// messaging-message-actions — HTTP (app)
//
// Las acciones sobre UN MENSAJE (RN-28): `delete_for_me`, `delete_for_all` y `edit`.
//
// La decisión es pura y vive en `_shared/messaging-actions.ts`. Aquí se comprueba la pertenencia a
// la conversación, se carga el mensaje y se aplica el patch.
//
// Corre con `service_role`: `direct_messages` solo concede `select` a `authenticated` (migración
// `20260823120200`), y con razón — si el cliente pudiera hacer `update`, RLS filtraría la FILA pero
// no las COLUMNAS, así que cualquiera podría marcar `deleted_for_all_at` en el mensaje del otro.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { isUuid, normalizeMessageContent } from "../_shared/validation.ts";
import { type MessageAction, resolveMessageAction } from "../_shared/messaging-actions.ts";

const ACTIONS: readonly MessageAction[] = ["delete_for_me", "delete_for_all", "edit"];

interface MessageRow {
  id: string;
  conversation_id: string;
  sender_id: string;
  content: string | null;
  deleted_for: string[];
  deleted_for_all_at: string | null;
}

/** Literal de array de Postgres: `{uuid,uuid}`. Vacío es `{}`, no `{ }` ni `{""}`. */
function toPgArray(ids: string[]): string {
  return `{${ids.join(",")}}`;
}

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

    const body = (raw ?? {}) as { message_id?: unknown; action?: unknown; content?: unknown };

    if (!isUuid(body.message_id)) {
      throw new AppError(400, "invalid_input", "message_id debe ser un uuid", {
        field: "message_id",
      });
    }
    const messageId = body.message_id;

    if (typeof body.action !== "string" || !ACTIONS.includes(body.action as MessageAction)) {
      throw new AppError(400, "invalid_input", `action debe ser una de: ${ACTIONS.join(", ")}`, {
        field: "action",
      });
    }
    const action = body.action as MessageAction;

    const service = getServiceRoleClient();

    const { data: msgRow, error: msgError } = await service
      .from("direct_messages")
      .select("id, conversation_id, sender_id, content, deleted_for, deleted_for_all_at")
      .eq("id", messageId)
      .maybeSingle();

    if (msgError) {
      throw new AppError(500, "internal_error", "No se pudo cargar el mensaje", {
        cause: msgError.message,
      });
    }
    if (msgRow === null) {
      throw new AppError(404, "not_found", "Mensaje no encontrado");
    }

    const message = msgRow as MessageRow;

    // --- LA PERTENENCIA. Se comprueba sobre la CONVERSACIÓN del mensaje, no sobre el mensaje: ser
    // autor no es lo que autoriza (borrar "para mí" lo hace quien no escribió), lo que autoriza es
    // participar. La autoría la comprueba la función pura donde toca.
    //
    // 404 y no 403, y aquí importa el doble: un 403 confirmaría que ese id de mensaje existe, y
    // permitiría enumerar mensajes ajenos probando uuids.
    const { data: stateRow, error: stateError } = await service
      .from("conversation_states")
      .select("user_id")
      .eq("conversation_id", message.conversation_id)
      .eq("user_id", actorId)
      .maybeSingle();

    if (stateError) {
      throw new AppError(500, "internal_error", "No se pudo comprobar la conversación", {
        cause: stateError.message,
      });
    }
    if (stateRow === null) {
      throw new AppError(404, "not_found", "Mensaje no encontrado");
    }

    // La longitud sale de `normalizeMessageContent`, la MISMA que usa `messaging-send`: editar es el
    // segundo camino por el que nace un `content`, y RN-26 tiene que valer igual en los dos
    // (`db-schema` punto 4d).
    const newContent = action === "edit" ? normalizeMessageContent(body.content) : undefined;

    const effects = resolveMessageAction({
      action,
      actorId,
      message: {
        id: message.id,
        senderId: message.sender_id,
        content: message.content,
        deletedFor: message.deleted_for ?? [],
        deletedForAllAt: message.deleted_for_all_at,
      },
      newContent,
      now: new Date(),
    });

    if (effects.noop) {
      return jsonResponse({ success: true, action, applied: false }, 200);
    }

    let update = service.from("direct_messages").update(effects.patch).eq("id", messageId);

    if (action === "delete_for_me") {
      // CERROJO OPTIMISTA, y hace falta: `deleted_for` se calcula leyendo el array y reescribiéndolo
      // entero, así que si los dos participantes borran el mismo mensaje a la vez, el segundo
      // `UPDATE` pisaría al primero y una de las dos personas volvería a ver el mensaje.
      //
      // Exigiendo que el array siga siendo el que se leyó, la que pierde la carrera no escribe nada
      // y se responde 409 en vez de descartar en silencio el borrado de la otra. El cliente
      // reintenta y la segunda pasada ya ve el array actualizado.
      update = update.eq("deleted_for", toPgArray(message.deleted_for ?? []));
    } else {
      // Para lápida y edición basta con exigir que no se haya convertido en lápida entre la lectura
      // y la escritura: es lo que impide editar un mensaje que el propio autor acaba de borrar para
      // todos desde otro dispositivo.
      update = update.is("deleted_for_all_at", null);
    }

    const { data: updated, error: updateError } = await update.select("id");

    if (updateError) {
      throw new AppError(500, "internal_error", "No se pudo aplicar la acción", {
        cause: updateError.message,
      });
    }

    if (!updated || updated.length === 0) {
      throw new AppError(
        409,
        "conflict",
        "El mensaje cambió mientras se aplicaba la acción; vuelve a intentarlo",
      );
    }

    return jsonResponse({ success: true, action, applied: true }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
