// block-remove — HTTP (app)
//
// Deshacer un bloqueo (ADR 0027, `docs/pending-messaging.md` punto 2).
//
// SE LLAMA `remove` Y NO SE RENOMBRÓ `block-create` A `block-toggle`, y hay tres razones:
//
//   1. `block-create` está desplegada en producción y la app la llama. Renombrarla rompe las dos.
//   2. Un `toggle` ESCONDE en qué dirección acabaste. Sobre una operación cuyo efecto observable
//      depende del estado previo, eso es peor que dos nombres.
//   3. `create` se eligió para no prometer una operación inexistente. `create` + `remove` mantiene
//      esa honestidad: cada nombre dice lo que hace, y el par es simétrico.
//
// LO QUE ESTA FUNCIÓN REVELA, y por eso hay un ADR: desbloquear deja que el desbloqueado vuelva a
// encontrarte, a escribirte y a verte en Conectar, así que puede DEDUCIR que le habías bloqueado.
// RN-23 protege a quien bloquea de que su decisión se sepa; deshacerla es un acto suyo y puede
// renunciar a esa protección. El modal de la app está obligado a decírselo antes de confirmar.
//
// Lo que RN-23 sigue prohibiendo y esto no toca: que un bloqueo VIGENTE se distinga de un cupo
// agotado. Los dos cuerpos siguen siendo idénticos byte a byte (ADR 0022).
//
// Corre con `service_role` porque `blocks` no tiene ninguna policy de escritura y `authenticated`
// no tiene `DELETE`. `service_role` sí lo tiene desde que se creó la tabla — comprobado con
// `has_table_privilege`, no con `column_privileges`, donde `DELETE` no aparece por ser privilegio
// de tabla. Por eso esta tarea no llevó migración.
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
      action: "unblock" as const,
      actorId,
      targetId,
      alreadyBlocked: state.alreadyBlocked,
      conversationId: state.conversationId,
      now: new Date(),
    };

    const effects = resolveModeration(ctx);
    await applyModeration(service, ctx, effects, null);

    // 200 TANTO SI HABÍA FILA COMO SI NO, con el mismo cuerpo — igual que `block-create` y por lo
    // mismo: es lo que hace seguro el reintento tras un fallo de red. Quien llama quería que esa
    // persona quedara desbloqueada, y lo está.
    return jsonResponse({ success: true, blocked: false }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
