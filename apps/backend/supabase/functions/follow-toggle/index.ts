// follow-toggle — HTTP (app)
//
// Las cinco acciones sobre el grafo de seguimiento: `request`, `accept`, `reject`, `unfollow` y
// `remove_follower` (§4.3, RN-11 a RN-20).
//
// La DECISIÓN de cada acción es pura y vive en `_shared/follow.ts`, con sus 25 tests. Aquí solo se
// carga el estado, se aplica la transición y se sincronizan los contadores. Esa separación es lo
// que permite fijar RN-13, RN-15, RN-16, RN-20 y RN-24 sin levantar una base de datos.
//
// Corre con `service_role` porque `user_follows` NO tiene ninguna policy de escritura: los
// contadores de `profiles` y esta tabla tienen que moverse juntos, y RN-24 (un bloqueado no puede
// solicitar) no es expresable en un `with check`.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { isUuid } from "../_shared/validation.ts";
import {
  FOLLOW_REQUEST_WINDOW_MS,
  type FollowAction,
  type FollowRow,
  resolveFollowTransition,
} from "../_shared/follow.ts";

const ACTIONS: readonly FollowAction[] = [
  "request",
  "accept",
  "reject",
  "unfollow",
  "remove_follower",
];

/**
 * En qué dirección vive la fila que necesita cada acción.
 *
 * `request` y `unfollow` las pide el SEGUIDOR (actor → destino). `accept`, `reject` y
 * `remove_follower` las pide el SEGUIDO, así que la fila es (destino → actor). Equivocar esto no
 * daría un error: buscaría una fila que no existe y devolvería 404 en el caso legítimo.
 */
function rowDirection(
  action: FollowAction,
  actorId: string,
  targetId: string,
): { followerId: string; followeeId: string } {
  return action === "request" || action === "unfollow"
    ? { followerId: actorId, followeeId: targetId }
    : { followerId: targetId, followeeId: actorId };
}

/** El par ordenado de `conversations` (`user_a_id < user_b_id`). */
function orderedPair(x: string, y: string): [string, string] {
  return x < y ? [x, y] : [y, x];
}

interface FollowToggleResponse {
  success: boolean;
  action: FollowAction;
  /** Estado resultante de la relación: `none` cuando la fila ya no existe. */
  status: "none" | "pending" | "accepted";
  /** Solo en `accept`: si además se reanudó una conversación ignorada (RN-17). */
  conversation_resumed?: boolean;
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

    const body = (raw ?? {}) as { action?: unknown; target_id?: unknown };

    if (typeof body.action !== "string" || !ACTIONS.includes(body.action as FollowAction)) {
      throw new AppError(400, "invalid_input", `action debe ser una de: ${ACTIONS.join(", ")}`, {
        field: "action",
      });
    }
    const action = body.action as FollowAction;

    if (!isUuid(body.target_id)) {
      throw new AppError(400, "invalid_input", "target_id debe ser un uuid", { field: "target_id" });
    }
    const targetId = body.target_id;

    const service = getServiceRoleClient();
    const { followerId, followeeId } = rowDirection(action, actorId, targetId);

    // --- Estado, en paralelo: la fila, el bloqueo en AMBAS direcciones y el perfil destino.
    const [followRes, blockRes, targetRes] = await Promise.all([
      service
        .from("user_follows")
        .select("follower_id, followee_id, status")
        .eq("follower_id", followerId)
        .eq("followee_id", followeeId)
        .maybeSingle(),
      // RN-24: "en cualquier dirección". Se consulta el par en los dos sentidos con un solo `or`;
      // la mitad `blocked_id = actor` es la que necesita el índice `blocks (blocked_id)`.
      service
        .from("blocks")
        .select("blocker_id")
        .or(
          `and(blocker_id.eq.${actorId},blocked_id.eq.${targetId}),` +
            `and(blocker_id.eq.${targetId},blocked_id.eq.${actorId})`,
        )
        .limit(1),
      service.from("profiles").select("user_id").eq("user_id", targetId).maybeSingle(),
    ]);

    if (followRes.error || blockRes.error || targetRes.error) {
      throw new AppError(500, "internal_error", "No se pudo consultar el estado de seguimiento", {
        cause: followRes.error?.message ?? blockRes.error?.message ?? targetRes.error?.message,
      });
    }

    const existing = (followRes.data as FollowRow | null) ?? null;
    const blocked = (blockRes.data ?? []).length > 0;
    const targetMissing = targetRes.data === null;

    // --- RN-20, solo para `request`: se cuenta sobre el índice parcial de la Tarea 2
    // (`(follower_id, created_at) where status = 'pending'`).
    //
    // MATIZ HONESTO: cuenta las solicitudes que SIGUEN pendientes dentro de la ventana, no las
    // enviadas. Una aceptada deja de contar y libera cupo. Es lo que pide el plan («contado sobre
    // el índice parcial») y además es lo razonable: el tope existe contra el reparto masivo de
    // solicitudes a desconocidos, y una solicitud aceptada no es eso.
    const now = new Date();
    let requestsToday = 0;
    let oldestRequestAt: string | null = null;

    if (action === "request") {
      const cutoff = new Date(now.getTime() - FOLLOW_REQUEST_WINDOW_MS).toISOString();
      const { data: recent, error: recentError } = await service
        .from("user_follows")
        .select("created_at")
        .eq("follower_id", actorId)
        .eq("status", "pending")
        .gte("created_at", cutoff)
        .order("created_at", { ascending: true });

      if (recentError) {
        throw new AppError(500, "internal_error", "No se pudo contar las solicitudes recientes", {
          cause: recentError.message,
        });
      }

      requestsToday = recent?.length ?? 0;
      oldestRequestAt = recent?.[0]?.created_at ?? null;
    }

    // --- La decisión. Lanza AppError con el 422 de RN-21 o el rechazo opaco de RN-23.
    const transition = resolveFollowTransition({
      action,
      actorId,
      targetId,
      existing,
      blocked,
      targetMissing,
      requestsToday,
      oldestRequestAt,
      now,
    });

    if (transition.kind === "noop") {
      return jsonResponse({
        success: true,
        action,
        status: existing?.status ?? "none",
      } satisfies FollowToggleResponse, 200);
    }

    // --- Aplicar.
    let resultingStatus: FollowToggleResponse["status"];
    let conversationResumed = false;

    if (transition.kind === "insert") {
      const { error } = await service.from("user_follows").insert({
        follower_id: transition.followerId,
        followee_id: transition.followeeId,
        status: "pending",
      });
      if (error) {
        throw new AppError(500, "internal_error", "No se pudo crear la solicitud", {
          cause: error.message,
        });
      }
      resultingStatus = "pending";
    } else if (transition.kind === "accept") {
      // El `eq('status','pending')` hace de cerrojo: dos aceptaciones simultáneas y solo una
      // encuentra fila. Sin él, las dos "aceptarían" y RN-17 se dispararía dos veces.
      const { data: updated, error } = await service
        .from("user_follows")
        .update({ status: "accepted" })
        .eq("follower_id", transition.followerId)
        .eq("followee_id", transition.followeeId)
        .eq("status", "pending")
        .select("follower_id");

      if (error) {
        throw new AppError(500, "internal_error", "No se pudo aceptar la solicitud", {
          cause: error.message,
        });
      }
      if (!updated || updated.length === 0) {
        // Otra petición se adelantó. El estado final es el mismo, así que se responde como no-op.
        return jsonResponse({
          success: true,
          action,
          status: "accepted",
        } satisfies FollowToggleResponse, 200);
      }
      resultingStatus = "accepted";
    } else {
      const { error } = await service
        .from("user_follows")
        .delete()
        .eq("follower_id", transition.followerId)
        .eq("followee_id", transition.followeeId);
      if (error) {
        throw new AppError(500, "internal_error", "No se pudo borrar la relación", {
          cause: error.message,
        });
      }
      resultingStatus = "none";
    }

    // --- Contadores. Se RECALCULAN desde `user_follows` (ver 20260823120600): un `+1` desde aquí
    // sería una carrera, y un contador que deriva es justo lo que este repositorio ya borró una vez.
    // Solo hace falta cuando el grafo de follows ACEPTADOS ha cambiado.
    if (transition.counterDelta !== 0) {
      const { error } = await service.rpc("sync_follow_counters", {
        p_user_ids: [transition.followerId, transition.followeeId],
      });
      if (error) {
        // No se lanza: la relación ya está bien escrita, y la función es autocorrectiva — la
        // siguiente llamada arregla el número. Fallar aquí dejaría al usuario creyendo que su
        // acción no surtió efecto, cuando sí lo hizo.
        console.warn("sync_follow_counters failed:", error.message);
      }
    }

    // --- RN-17, EL CASO QUE SE OLVIDA. Al aceptar un follow, si el ahora aceptado había iniciado
    // una conversación que quedó en `ignored`, esa conversación se reanuda.
    //
    // Dos condiciones que lo acotan, y las dos importan:
    //   · `initiator_id` tiene que ser el SOLICITANTE aceptado. Si fue el otro quien escribió y
    //     este la ignoró, aceptar el follow no revive nada suyo.
    //   · Un bloqueo vigente lo impide, y ya está garantizado: `resolveFollowTransition` lanza el
    //     rechazo opaco antes de llegar aquí. RN-17 reanuda un ignorado, NO levanta un bloqueo.
    if (transition.resumesIgnoredConversation) {
      const [userA, userB] = orderedPair(transition.followerId, transition.followeeId);
      const { data: resumed, error: convError } = await service
        .from("conversations")
        .update({ status: "accepted" })
        .eq("user_a_id", userA)
        .eq("user_b_id", userB)
        .eq("status", "ignored")
        .eq("initiator_id", transition.followerId)
        .select("id");

      if (convError) {
        console.warn("RN-17 resume failed:", convError.message);
      } else if (resumed && resumed.length > 0) {
        conversationResumed = true;
        // Vuelve a la bandeja de los DOS: al que la ignoró le reaparece, y al emisor —que nunca
        // supo que estaba ignorada (RN-06)— le sigue apareciendo igual que siempre.
        const { error: stateError } = await service
          .from("conversation_states")
          .update({ hidden: false })
          .eq("conversation_id", resumed[0].id);
        if (stateError) {
          console.warn("RN-17 unhide failed:", stateError.message);
        }
      }
    }

    const response: FollowToggleResponse = { success: true, action, status: resultingStatus };
    if (transition.kind === "accept") response.conversation_resumed = conversationResumed;
    return jsonResponse(response, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
