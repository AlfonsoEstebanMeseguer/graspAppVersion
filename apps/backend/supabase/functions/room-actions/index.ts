// room-actions — toda escritura de estado de una sala (Fase 5).
//
// Las reglas (aforo, tope de hablantes, quien es el host) NO viven aqui: viven
// en las funciones de Postgres, porque tienen que contarse dentro de la misma
// transaccion que escribe. Esta funcion valida la entrada y traduce errores.
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";

const ACTIONS = new Set([
  "create", "join", "leave", "raise_hand", "grant_speak", "revoke_speak", "end",
]);

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    const { userId } = await requireAuthUser(req);
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");
    if (!ACTIONS.has(action)) {
      throw new AppError(400, "bad_action", "Acción no reconocida");
    }

    const db = getServiceRoleClient();

    if (action === "create") {
      const title = String(body.title ?? "").trim();
      if (title.length < 3 || title.length > 80) {
        throw new AppError(400, "bad_title", "El título va de 3 a 80 caracteres");
      }
      const categoryId = String(body.categoryId ?? "");
      if (!categoryId) throw new AppError(400, "bad_category", "Falta categoryId");
      const { data, error } = await db.rpc("room_create", {
        p_host: userId, p_title: title, p_category: categoryId,
      });
      if (error) throw translate(error.message);
      return jsonResponse({ roomId: data }, 201);
    }

    const roomId = String(body.roomId ?? "");
    if (!roomId) throw new AppError(400, "bad_room", "Falta roomId");

    if (action === "join") {
      const { error } = await db.rpc("room_join", { p_user: userId, p_room: roomId });
      if (error) throw translate(error.message);
      return jsonResponse({ ok: true });
    }

    if (action === "leave") {
      const { error } = await db.rpc("room_leave", { p_user: userId, p_room: roomId });
      if (error) throw translate(error.message);
      return jsonResponse({ ok: true });
    }

    if (action === "end") {
      // `end` NO es un alias de `leave`: solo el host puede terminar la sala para
      // todos. Antes las dos resolvían a `room_leave`, así que cualquier
      // participante podía "acabar" una sala ajena sin cerrarla de verdad.
      const { error } = await db.rpc("room_end", { p_host: userId, p_room: roomId });
      if (error) throw translate(error.message);
      return jsonResponse({ ok: true });
    }

    if (action === "raise_hand") {
      const note = body.note == null ? null : String(body.note).trim().slice(0, 120);
      const { error } = await db.rpc("room_raise_hand", {
        p_user: userId, p_room: roomId, p_note: note,
      });
      if (error) throw translate(error.message);
      return jsonResponse({ ok: true });
    }

    const targetUserId = String(body.targetUserId ?? "");
    if (!targetUserId) throw new AppError(400, "bad_target", "Falta targetUserId");

    if (action === "grant_speak") {
      const { error } = await db.rpc("room_grant_speak", {
        p_host: userId, p_room: roomId, p_target: targetUserId,
      });
      if (error) throw translate(error.message);
      return jsonResponse({ ok: true });
    }

    const { error } = await db.rpc("room_revoke_speak", {
      p_host: userId, p_room: roomId, p_target: targetUserId,
    });
    if (error) throw translate(error.message);
    return jsonResponse({ ok: true });
  } catch (err) {
    return errorResponse(err);
  }
});

function translate(message: string): AppError {
  const known: Record<string, [number, string]> = {
    room_full: [409, "La sala está llena"],
    stage_full: [409, "Ya hay dos personas hablando"],
    already_in_room: [409, "Ya estás en una sala"],
    room_not_live: [404, "La sala no está abierta"],
    not_the_host: [403, "Solo quien creó la sala puede hacer eso"],
    not_a_listener: [409, "No estás escuchando en esta sala"],
    not_a_speaker: [409, "Esa persona no está hablando"],
    no_request: [409, "Esa persona no ha pedido la palabra"],
  };
  for (const [code, [status, text]] of Object.entries(known)) {
    if (message.includes(code)) return new AppError(status, code, text);
  }
  return new AppError(500, "room_action_failed", "No se pudo completar la acción");
}
