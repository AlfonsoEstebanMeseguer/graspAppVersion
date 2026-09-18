// report-create — HTTP (app)
//
// **VERSIÓN MÍNIMA DE LA FASE 4** (decisión 6 del plan). Persiste el reporte y ejecuta el MISMO
// bloqueo que `block-create` (RN-25). Nada más.
//
// Lo que NO hace, enumerado a propósito porque la versión anterior del README prometía «crea
// incidente, aplica delta de reputación, evalúa sanción automática escalonada» —que es la Fase 10
// entera— y leerlo daba por hecha una moderación que no existe: sin categoría, sin justificación,
// sin cola de moderación, sin revisión humana, sin reputación, sin sanciones y **sin deshacer**.
//
// Los efectos y su orden viven en `_shared/moderation.ts`, los mismos que usa `block-create`. Que
// salgan del mismo sitio es lo que hace cierto RN-25 —«reportar ejecuta automáticamente un bloqueo
// (mismo comportamiento)»— sin depender de que alguien se acuerde de copiarlo igual.
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

    const body = (raw ?? {}) as { reported_id?: unknown; conversation_id?: unknown };

    if (!isUuid(body.reported_id)) {
      throw new AppError(400, "invalid_input", "reported_id debe ser un uuid", {
        field: "reported_id",
      });
    }
    const targetId = body.reported_id;

    // Opcional: se podrá reportar desde un perfil, sin conversación de por medio (§2.6).
    const conversationId = body.conversation_id ?? null;
    if (conversationId !== null && !isUuid(conversationId)) {
      throw new AppError(400, "invalid_input", "conversation_id debe ser un uuid", {
        field: "conversation_id",
      });
    }

    const service = getServiceRoleClient();

    // --- SI VIENE UNA CONVERSACIÓN, TIENE QUE SER DE QUIEN REPORTA.
    //
    // Sin esta comprobación, cualquiera podría colgar su reporte de la conversación de dos
    // desconocidos: `reports.conversation_id` es una FK y no valida quién participa, así que la fila
    // quedaría apuntando a un hilo ajeno. Cuando la Fase 10 construya la cola de moderación, ese
    // enlace es justo lo que un humano abriría para leer el contexto — y estaría leyendo la
    // conversación de otras dos personas.
    if (conversationId !== null) {
      const { data: stateRow, error } = await service
        .from("conversation_states")
        .select("user_id")
        .eq("conversation_id", conversationId)
        .eq("user_id", actorId)
        .maybeSingle();

      if (error) {
        throw new AppError(500, "internal_error", "No se pudo comprobar la conversación", {
          cause: error.message,
        });
      }
      if (stateRow === null) {
        throw new AppError(404, "not_found", "Conversación no encontrada");
      }
    }

    const state = await loadModerationState(service, actorId, targetId);

    if (!state.targetExists) {
      throw new AppError(404, "not_found", "El usuario no existe");
    }

    const ctx = {
      action: "report" as const,
      actorId,
      targetId,
      alreadyBlocked: state.alreadyBlocked,
      conversationId: state.conversationId,
      now: new Date(),
    };

    const effects = resolveModeration(ctx);
    await applyModeration(service, ctx, effects, conversationId);

    // Mismo cuerpo siempre, bloqueara o ya estuviera bloqueado: el estado previo del bloqueo no
    // viaja (RN-23).
    return jsonResponse({ success: true, reported: true, blocked: true }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
