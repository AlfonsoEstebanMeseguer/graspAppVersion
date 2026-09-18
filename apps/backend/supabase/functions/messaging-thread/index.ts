// messaging-thread — HTTP (app)
//
// Una página de mensajes de una conversación, más el estado del input del §9.2.
//
// Como `messaging-inbox`, corre con `service_role` —`conversations` no tiene ningún grant para
// `authenticated`— y por tanto SE SALTA LA RLS. Las dos protecciones que la policy
// `direct_messages_read_participant` aplica al cliente las reimplementa `_shared/messaging-view.ts`:
// el `deleted_for` de RN-28 y el `cleared_at` de RN-27. Aquí no se pinta ni una fila sin pasarla por
// esa proyección.
//
// LA COMPROBACIÓN QUE NO PUEDE FALTAR: al saltarse la RLS, la pertenencia a la conversación deja de
// comprobarla Postgres. Si este handler no la comprobara, cualquiera con un `conversation_id` leería
// la conversación entera de dos desconocidos.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { isUuid } from "../_shared/validation.ts";
import {
  type InputState,
  type MessageInput,
  type MessageView,
  projectMessages,
  resolveInputState,
} from "../_shared/messaging-view.ts";
import type { ConversationStatus } from "../_shared/messaging-routing.ts";

const DEFAULT_LIMIT = 30;
const MAX_LIMIT = 100;

interface MessageRow {
  id: string;
  sender_id: string;
  content: string | null;
  deleted_for: string[];
  deleted_for_all_at: string | null;
  edited_at: string | null;
  reply_to_id: string | null;
  created_at: string;
}

function toMessageInput(r: MessageRow): MessageInput {
  return {
    id: r.id,
    senderId: r.sender_id,
    content: r.content,
    deletedFor: r.deleted_for ?? [],
    deletedForAllAt: r.deleted_for_all_at,
    editedAt: r.edited_at,
    replyToId: r.reply_to_id,
    createdAt: r.created_at,
  };
}

interface ThreadResponse {
  conversation: {
    conversation_id: string;
    other_user_id: string;
    display_name: string | null;
    preset_avatar: string | null;
    is_active: boolean;
    unread_count: number;
  };
  messages: MessageView[];
  has_more: boolean;
  /** Cursor para la página siguiente (más antigua). `null` si no hay más. */
  next_before: string | null;
  input: InputState;
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "GET") {
      throw new AppError(405, "method_not_allowed", "Usa GET");
    }

    const { userId: viewerId, client: userClient } = await requireAuthUser(req);
    const url = new URL(req.url);

    const conversationId = url.searchParams.get("conversation_id");
    if (!isUuid(conversationId)) {
      throw new AppError(400, "invalid_input", "conversation_id debe ser un uuid", {
        field: "conversation_id",
      });
    }

    const rawLimit = url.searchParams.get("limit");
    let limit = DEFAULT_LIMIT;
    if (rawLimit !== null) {
      const parsed = Number(rawLimit);
      if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_LIMIT) {
        throw new AppError(400, "invalid_input", `limit debe ser un entero de 1 a ${MAX_LIMIT}`, {
          field: "limit",
        });
      }
      limit = parsed;
    }

    // Cursor de paginación: se piden los mensajes ANTERIORES a este instante.
    const before = url.searchParams.get("before");
    if (before !== null && Number.isNaN(Date.parse(before))) {
      throw new AppError(400, "invalid_input", "before debe ser una fecha ISO-8601", {
        field: "before",
      });
    }

    const service = getServiceRoleClient();

    // --- 1) LA PERTENENCIA, ANTES DE NADA.
    //
    // Se comprueba contra `conversation_states`, que es la tabla que tiene una fila por
    // participante — la misma fuente que usa la policy de `direct_messages`, y de paso trae el
    // `cleared_at` que hace falta justo después.
    //
    // Un 404 y no un 403: un 403 confirmaría que esa conversación existe. Quien no participa no
    // tiene por qué distinguir "no es tuya" de "no existe".
    const { data: stateRow, error: stateError } = await service
      .from("conversation_states")
      .select("unread_count, cleared_at")
      .eq("conversation_id", conversationId)
      .eq("user_id", viewerId)
      .maybeSingle();

    if (stateError) {
      throw new AppError(500, "internal_error", "No se pudo cargar la conversación", {
        cause: stateError.message,
      });
    }
    if (stateRow === null) {
      throw new AppError(404, "not_found", "Conversación no encontrada");
    }

    const clearedAt = stateRow.cleared_at as string | null;

    const { data: convRow, error: convError } = await service
      .from("conversations")
      .select("id, user_a_id, user_b_id, status, initiator_id")
      .eq("id", conversationId)
      .maybeSingle();

    if (convError || convRow === null) {
      throw new AppError(500, "internal_error", "No se pudo cargar la conversación", {
        cause: convError?.message,
      });
    }

    const conv = convRow as {
      id: string;
      user_a_id: string;
      user_b_id: string;
      status: ConversationStatus;
      initiator_id: string;
    };
    // El par es ORDENADO, así que el otro hay que compararlo, no suponerlo por la posición.
    const otherUserId = conv.user_a_id === viewerId ? conv.user_b_id : conv.user_a_id;

    // --- 2) La página. Se pide UNA fila de más para saber si hay siguiente sin contar la tabla
    // entera, que es el truco de siempre y evita un `count` en cada scroll.
    let query = service
      .from("direct_messages")
      .select(
        "id, sender_id, content, deleted_for, deleted_for_all_at, edited_at, reply_to_id, created_at",
      )
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: false })
      .limit(limit + 1);

    // RN-27: nada anterior a mi propio borrado de historial. Va en la CONSULTA además de en la
    // proyección: la proyección es la garantía, esto es no traerse de la red lo que no se va a
    // enseñar.
    if (clearedAt !== null) query = query.gt("created_at", clearedAt);
    if (before !== null) query = query.lt("created_at", before);

    const { data: msgRows, error: msgError } = await query;
    if (msgError) {
      throw new AppError(500, "internal_error", "No se pudo cargar los mensajes", {
        cause: msgError.message,
      });
    }

    const rows = (msgRows ?? []) as MessageRow[];
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;

    // --- 3) Las citas. Los mensajes citados pueden caer FUERA de la página (se cita algo de hace
    // semanas), así que se piden aparte por id. Se acotan a esta conversación: sin ese filtro, un
    // `reply_to_id` manipulado traería aquí una fila de otra conversación para resolverla — el
    // mismo agujero que `messaging-send` cierra al escribir, cerrado también al leer.
    const quotedIds = [...new Set(page.map((m) => m.reply_to_id).filter((id): id is string => id !== null))];
    const quoted = new Map<string, MessageInput>();

    if (quotedIds.length > 0) {
      const { data: quotedRows, error: quotedError } = await service
        .from("direct_messages")
        .select(
          "id, sender_id, content, deleted_for, deleted_for_all_at, edited_at, reply_to_id, created_at",
        )
        .eq("conversation_id", conversationId)
        .in("id", quotedIds);

      if (quotedError) {
        throw new AppError(500, "internal_error", "No se pudo resolver las citas", {
          cause: quotedError.message,
        });
      }
      for (const q of (quotedRows ?? []) as MessageRow[]) quoted.set(q.id, toMessageInput(q));
    }

    // Se proyecta en el orden en que vino (más nuevo primero) y se le da la vuelta al final: el
    // cliente pinta de arriba abajo en orden cronológico.
    const messages = projectMessages(page.map(toMessageInput), viewerId, clearedAt, quoted)
      .reverse();

    // --- 4) El estado del input (§9.2). Necesita dos datos más: cuántos mensajes llevo enviados en
    // esta conversación (RN-01) y si hay bloqueo en cualquiera de las dos direcciones.
    const [countRes, blockRes, profileRes] = await Promise.all([
      service
        .from("direct_messages")
        .select("id", { count: "exact", head: true })
        .eq("conversation_id", conversationId)
        .eq("sender_id", viewerId),
      service
        .from("blocks")
        .select("blocker_id")
        .or(
          `and(blocker_id.eq.${viewerId},blocked_id.eq.${otherUserId}),` +
            `and(blocker_id.eq.${otherUserId},blocked_id.eq.${viewerId})`,
        )
        .limit(1),
      service.from("profiles").select("display_name, preset_avatar").eq("user_id", otherUserId)
        .maybeSingle(),
    ]);

    if (countRes.error || blockRes.error || profileRes.error) {
      throw new AppError(500, "internal_error", "No se pudo resolver el estado del input", {
        cause: countRes.error?.message ?? blockRes.error?.message ?? profileRes.error?.message,
      });
    }

    const input = resolveInputState({
      status: conv.status,
      initiatorId: conv.initiator_id,
      viewerId,
      otherUserId,
      senderMessageCount: countRes.count ?? 0,
      blocked: (blockRes.data ?? []).length > 0,
      now: new Date(),
    });

    // El punto de la cabecera (§9.1). Con el cliente del USUARIO: `activity_status` deriva quién
    // pregunta de `auth.uid()`, que con la clave de servicio es NULL y devolvería `false` siempre,
    // sin error. Y RN-32 es recíproco, así que sin identidad no se puede aplicar.
    let isActive = false;
    const { data: activity, error: activityError } = await userClient.rpc("activity_status", {
      p_user_ids: [otherUserId],
    });
    if (activityError) {
      console.warn("activity_status failed:", activityError.message);
    } else {
      isActive = (activity ?? [])[0]?.is_active ?? false;
    }

    const profile = profileRes.data as
      | { display_name: string | null; preset_avatar: string | null }
      | null;

    return jsonResponse(
      {
        conversation: {
          conversation_id: conv.id,
          other_user_id: otherUserId,
          display_name: profile?.display_name ?? null,
          preset_avatar: profile?.preset_avatar ?? null,
          is_active: isActive,
          unread_count: stateRow.unread_count as number,
        },
        messages,
        has_more: hasMore,
        // EL CURSOR SALE DE LA FILA CRUDA MÁS ANTIGUA, NO DEL MENSAJE PROYECTADO MÁS ANTIGUO.
        // `projectMessages` DESCARTA filas (RN-27, RN-28), así que si la más antigua de la página
        // resultara invisible para este espectador, un cursor sacado de la lista proyectada saltaría
        // por encima de ella y la página siguiente devolvería mensajes ya vistos — o se dejaría un
        // hueco. `page` viene ordenada de más nueva a más vieja: la última es la más antigua.
        next_before: hasMore ? page[page.length - 1].created_at : null,
        input,
      } satisfies ThreadResponse,
      200,
    );
  } catch (err) {
    return errorResponse(err);
  }
});
