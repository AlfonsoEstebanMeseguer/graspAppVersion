// block-create — HTTP (app)
//
// Bloquear a alguien (§2.5, RN-22, RN-23, RN-24, RN-07).
//
// SE LLAMA `create` Y NO `toggle`, Y ES DELIBERADO. Cuando se escribió era porque **no había
// desbloqueo**; desde el ADR 0027 sí lo hay, y vive en `block-remove` — una función aparte, no un
// `toggle`, porque un toggle esconde en qué dirección acabaste. El par `create` + `remove` mantiene
// la propiedad que buscaba el nombre original: cada uno dice exactamente lo que hace.
//
// La decisión de los efectos es pura y vive en `_shared/moderation.ts`, con sus 10 tests y cinco
// mutaciones comprobadas. El orden de las escrituras también vive allí, porque es lo que hace seguro
// el reintento.
//
// Corre con `service_role` porque `blocks` no tiene ninguna policy de escritura: bloquear NO es
// insertar una fila, tiene efectos en otra tabla (archivar la conversación del bloqueador, RN-22).
// Si el cliente pudiera insertar directo, existiría un bloqueo a medias por diseño.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { isUuid } from "../_shared/validation.ts";
import {
  applyModeration,
  loadModerationState,
  resolveModeration,
} from "../_shared/moderation.ts";

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

    const body = (raw ?? {}) as { target_id?: unknown };

    if (!isUuid(body.target_id)) {
      throw new AppError(400, "invalid_input", "target_id debe ser un uuid", { field: "target_id" });
    }
    const targetId = body.target_id;

    const service = getServiceRoleClient();
    const state = await loadModerationState(service, actorId, targetId);

    if (!state.targetExists) {
      throw new AppError(404, "not_found", "El usuario no existe");
    }

    const ctx = {
      action: "block" as const,
      actorId,
      targetId,
      alreadyBlocked: state.alreadyBlocked,
      conversationId: state.conversationId,
      now: new Date(),
    };

    const effects = resolveModeration(ctx);
    await applyModeration(service, ctx, effects, null);

    // 200 TANTO SI BLOQUEÓ COMO SI YA ESTABA BLOQUEADO, con el mismo cuerpo. Distinguir los dos
    // casos le diría a quien llama algo sobre el estado previo, y el estado previo del bloqueo no es
    // información que deba viajar (RN-23). El cliente no necesita saberlo: quería que esa persona
    // quedara bloqueada, y lo está.
    return jsonResponse({ success: true, blocked: true }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
