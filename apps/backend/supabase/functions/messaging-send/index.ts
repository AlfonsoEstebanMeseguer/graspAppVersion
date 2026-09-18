// messaging-send — HTTP (app)
//
// Enviar un mensaje directo: abre la conversación si no existía, la enruta (§4.2) y entrega.
//
// Las DOS DECISIONES del envío son puras y viven en `_shared/`, con sus 35 tests:
//   · `messaging-limits.ts` → `evaluateSendLimits()`: ¿se puede? Devuelve un VEREDICTO, no lanza.
//   · `messaging-routing.ts` → `routeConversation()`: ¿a qué estado nace o se reutiliza el hilo?
// Aquí solo se carga el estado desde Postgres, se aplica el veredicto y se escribe.
//
// Corre con `service_role` porque `conversations` NO TIENE NI UN GRANT para `authenticated` — es lo
// que hace estructural la invisibilidad de `ignored` y de `initiator_id` (RN-06). Ningún cliente
// puede leer ni escribir esa tabla; toda la mensajería pasa por aquí y por la Tarea 11.
//
// LO QUE ESTE FICHERO NO HACE, Y ES DELIBERADO: no incrementa `unread_count`, no sube
// `last_message_at` y no toca `hidden`. Eso lo hace el trigger `direct_messages_delivery`
// (migración `20260825120000`), en la MISMA TRANSACCIÓN que el `insert`. El motivo está entero en
// esa migración y se resume en una línea: lo no leído no se deriva de ninguna tabla (RN-31 prohíbe
// `read_at`), así que un incremento perdido es permanente e indetectable — un `+1` desde aquí, o
// incluso un RPC posterior al insert, podría perderse.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { isUuid, normalizeMessageContent } from "../_shared/validation.ts";
import {
  evaluateSendLimits,
  FIRST_MESSAGE_WINDOW_MS,
  MAX_PENDING_MESSAGES,
  type SendVerdict,
} from "../_shared/messaging-limits.ts";
import {
  type ConversationStatus,
  type ExistingConversation,
  routeConversation,
} from "../_shared/messaging-routing.ts";

/** Violación de constraint única de Postgres, tal y como la reporta PostgREST. */
const UNIQUE_VIOLATION = "23505";

/** El par ordenado de `conversations` (`user_a_id < user_b_id`). */
function orderedPair(x: string, y: string): [string, string] {
  return x < y ? [x, y] : [y, x];
}

interface ConversationRow {
  id: string;
  status: ConversationStatus;
  initiator_id: string;
}

interface MessageRow {
  id: string;
  conversation_id: string;
  content: string | null;
  reply_to_id: string | null;
  created_at: string;
}

interface MessagingSendResponse {
  success: true;
  /** `true` si esta petición era un reintento y no se creó nada nuevo. */
  idempotent_replay: boolean;
  message: MessageRow;
  /**
   * Cuántos de los 5 de RN-01 le quedan al emisor, o `null` si no hay tope.
   *
   * En una conversación `ignored` sale EXACTAMENTE el mismo número que en una `pending` — se
   * calcula solo con los mensajes enviados, sin mirar el estado. Es RN-06: el emisor no puede
   * enterarse de nada, y un contador que se comportara distinto se lo diría.
   */
  messages_left: number | null;
}

/**
 * El cuerpo del 422, derivado ÚNICAMENTE de los campos públicos del veredicto.
 *
 * RN-23 vive en esta firma: recibe `SendVerdict` pero **no lee `internalReason`**, así que un
 * bloqueo y un cupo agotado producen el mismo cuerpo byte a byte porque salen del mismo cálculo,
 * no porque alguien se acuerde de copiarlos iguales. Ramificar aquí por el motivo interno sería
 * la fuga que `PublicSendBlockedReason` existe para hacer imposible.
 */
function blockedResponse(verdict: SendVerdict): never {
  throw new AppError(
    422,
    "send_blocked",
    "No se puede enviar el mensaje ahora mismo",
    {
      reason: verdict.publicReason,
      limit: verdict.limit,
      retry_at: verdict.retryAt?.toISOString() ?? null,
    },
  );
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    const { userId: senderId } = await requireAuthUser(req);

    let raw: unknown;
    try {
      raw = await req.json();
    } catch {
      throw new AppError(400, "invalid_input", "Body no es JSON válido");
    }

    const body = (raw ?? {}) as {
      recipient_id?: unknown;
      content?: unknown;
      idempotency_key?: unknown;
      reply_to_id?: unknown;
    };

    // --- Validación ANTES de tocar la base (checklist 1 de `edge-functions`).
    if (!isUuid(body.recipient_id)) {
      throw new AppError(400, "invalid_input", "recipient_id debe ser un uuid", {
        field: "recipient_id",
      });
    }
    const recipientId = body.recipient_id;

    if (recipientId === senderId) {
      throw new AppError(400, "invalid_input", "No puedes escribirte a ti mismo", {
        field: "recipient_id",
      });
    }

    // RN-26 vive en UN solo sitio (`normalizeMessageContent`), porque `content` nace por DOS
    // caminos: este y la edición de `messaging-message-actions`. Tener el 1000 en dos literales es
    // exactamente cómo divergen (`db-schema` punto 4d). Devuelve el texto ya recortado y medido en
    // puntos de código, como `char_length` en Postgres.
    const content = normalizeMessageContent(body.content);

    // Idempotencia OBLIGATORIA (invariante de CLAUDE.md), no opcional: si el cliente pudiera
    // omitirla, el reintento tras un timeout duplicaría el mensaje y gastaría dos de los 5 de
    // RN-01. Es `uuid` porque así es la columna.
    if (!isUuid(body.idempotency_key)) {
      throw new AppError(400, "invalid_input", "idempotency_key debe ser un uuid", {
        field: "idempotency_key",
      });
    }
    const idempotencyKey = body.idempotency_key;

    const replyToId = body.reply_to_id ?? null;
    if (replyToId !== null && !isUuid(replyToId)) {
      throw new AppError(400, "invalid_input", "reply_to_id debe ser un uuid", {
        field: "reply_to_id",
      });
    }

    const service = getServiceRoleClient();

    // =============================================================================================
    // 1) IDEMPOTENCIA — LO PRIMERO DE TODO, Y EL ORDEN IMPORTA
    // =============================================================================================
    // Se resuelve ANTES de los límites a propósito. Si se comprobaran antes, el reintento del
    // QUINTO mensaje se evaluaría como si fuera el sexto —porque el quinto ya está escrito— y
    // devolvería un 422 por un mensaje que en realidad se entregó. El cliente que reintenta tras un
    // timeout vería un rechazo por una entrega correcta.
    //
    // Y devuelve EL MISMO MENSAJE, con un 200, no un 409: un 409 el cliente no puede distinguirlo
    // de un fallo real, así que reintentaría en bucle o daría el envío por perdido.
    const { data: replay, error: replayError } = await service
      .from("direct_messages")
      .select("id, conversation_id, content, reply_to_id, created_at")
      .eq("sender_id", senderId)
      .eq("idempotency_key", idempotencyKey)
      .maybeSingle();

    if (replayError) {
      throw new AppError(500, "internal_error", "No se pudo comprobar la idempotencia", {
        cause: replayError.message,
      });
    }

    if (replay) {
      const message = replay as MessageRow;
      return jsonResponse(
        {
          success: true,
          idempotent_replay: true,
          message,
          messages_left: await messagesLeftFor(service, message.conversation_id, senderId),
        } satisfies MessagingSendResponse,
        200,
      );
    }

    // =============================================================================================
    // 2) ESTADO, EN PARALELO
    // =============================================================================================
    const [ua, ub] = orderedPair(senderId, recipientId);

    const [convRes, blockRes, followRes, recipientRes] = await Promise.all([
      service
        .from("conversations")
        .select("id, status, initiator_id")
        .eq("user_a_id", ua)
        .eq("user_b_id", ub)
        .maybeSingle(),
      // RN-07 caminos 2 y 3: el bloqueo cuenta EN CUALQUIERA DE LAS DOS DIRECCIONES. Quien bloqueó
      // no quiere recibir; quien fue bloqueado no puede escribir. La mitad `blocked_id = sender`
      // es la que usa el índice `blocks (blocked_id)`.
      service
        .from("blocks")
        .select("blocker_id")
        .or(
          `and(blocker_id.eq.${senderId},blocked_id.eq.${recipientId}),` +
            `and(blocker_id.eq.${recipientId},blocked_id.eq.${senderId})`,
        )
        .limit(1),
      // RN-09: lo ÚNICO que decide el enrutado es si el RECEPTOR sigue al emisor. Que el emisor
      // siga al receptor es irrelevante (§4.2 caso 3), así que ni se consulta.
      service
        .from("user_follows")
        .select("follower_id")
        .eq("follower_id", recipientId)
        .eq("followee_id", senderId)
        .eq("status", "accepted")
        .maybeSingle(),
      service.from("profiles").select("user_id").eq("user_id", recipientId).maybeSingle(),
    ]);

    const firstError = convRes.error ?? blockRes.error ?? followRes.error ?? recipientRes.error;
    if (firstError) {
      throw new AppError(500, "internal_error", "No se pudo cargar el estado de la conversación", {
        cause: firstError.message,
      });
    }

    if (recipientRes.data === null) {
      throw new AppError(404, "not_found", "El destinatario no existe");
    }

    const conversationRow = (convRes.data as ConversationRow | null) ?? null;
    const existing: ExistingConversation | null = conversationRow === null ? null : {
      status: conversationRow.status,
      initiatorId: conversationRow.initiator_id,
    };
    const blocked = (blockRes.data ?? []).length > 0;
    const recipientFollowsSender = followRes.data !== null;

    // =============================================================================================
    // 3) LOS CONTADORES DE LOS LÍMITES (RN-01, RN-18, RN-19) — sin Redis, en Postgres
    // =============================================================================================
    const now = new Date();
    let senderMessageCount = 0;
    let pendingRequests = 0;
    let firstMessagesInWindow = 0;
    let oldestFirstMessageAt: string | null = null;

    if (conversationRow !== null) {
      // RN-01. Cuenta TODAS las filas del emisor en el hilo, lápidas incluidas: RN-01 dice
      // «ni uno más, bajo ninguna circunstancia», y si borrar un mensaje devolviera el hueco,
      // borrar-y-reenviar sería un bucle infinito que se salta el tope entero.
      const { count, error } = await service
        .from("direct_messages")
        .select("id", { count: "exact", head: true })
        .eq("conversation_id", conversationRow.id)
        .eq("sender_id", senderId);

      if (error) {
        throw new AppError(500, "internal_error", "No se pudo contar los mensajes enviados", {
          cause: error.message,
        });
      }
      senderMessageCount = count ?? 0;
    } else {
      // Solo al ABRIR conversación: RN-18 y RN-19 son topes de solicitudes y de primeros mensajes,
      // no de mensajes.
      const windowStart = new Date(now.getTime() - FIRST_MESSAGE_WINDOW_MS).toISOString();

      const [pendingRes, windowRes] = await Promise.all([
        // RN-18: solicitudes abiertas ahora mismo.
        //
        // `ignored` CUENTA COMO PENDIENTE, y no es un descuido: es RN-06. Si una conversación
        // ignorada dejara de ocupar cupo, al emisor le volvería a caber una solicitud más de las
        // que debería, y comparando cuántas le caben sabría cuáles le han ignorado. La invisibilidad
        // del ignorar tiene que sostenerse también en los números, no solo en las pantallas.
        service
          .from("conversations")
          .select("id", { count: "exact", head: true })
          .eq("initiator_id", senderId)
          .in("status", ["pending", "ignored"]),
        // RN-19: ventana MÓVIL de 24 h. Se piden ordenadas para sacar la más antigua, que es la que
        // da el `retry_at` exacto de RN-21 — no "24 h desde ahora", que sería mentir.
        service
          .from("conversations")
          .select("created_at")
          .eq("initiator_id", senderId)
          .gte("created_at", windowStart)
          .order("created_at", { ascending: true }),
      ]);

      if (pendingRes.error || windowRes.error) {
        throw new AppError(500, "internal_error", "No se pudo contar los límites de apertura", {
          cause: pendingRes.error?.message ?? windowRes.error?.message,
        });
      }

      pendingRequests = pendingRes.count ?? 0;
      firstMessagesInWindow = windowRes.data?.length ?? 0;
      oldestFirstMessageAt = windowRes.data?.[0]?.created_at ?? null;
    }

    // =============================================================================================
    // 4) EL VEREDICTO
    // =============================================================================================
    const verdict = evaluateSendLimits({
      senderId,
      recipientId,
      existing,
      senderMessageCount,
      pendingRequests,
      firstMessagesInWindow,
      oldestFirstMessageAt,
      blocked,
      now,
    });

    if (!verdict.canSend) {
      // El motivo REAL solo aquí, en el log del servidor. Nunca en la respuesta.
      //
      // Y con esto queda cumplida la EXCEPCIÓN DE RN-23 del paso 3: cuando el motivo es un bloqueo
      // se sale por aquí, antes de escribir absolutamente nada. No hay mensaje, así que el trigger
      // de entrega no llega a dispararse y el `hidden` del bloqueador no se toca. Reaparecer en su
      // bandeja le revelaría al bloqueado que el mensaje llegó a algún sitio, y al bloqueador un
      // mensaje que pidió no recibir.
      console.info("messaging-send blocked:", verdict.internalReason);
      blockedResponse(verdict);
    }

    // =============================================================================================
    // 5) LA CONVERSACIÓN
    // =============================================================================================
    const decision = routeConversation({
      senderId,
      recipientId,
      existing,
      recipientFollowsSender,
      // Se pasa a propósito aunque RN-09 lo ignore: que se vea que se descarta.
      senderFollowsRecipient: false,
    });

    let conversationId: string;
    let finalStatus: ConversationStatus;
    let finalInitiatorId: string;

    if (decision.kind === "create") {
      const { data: created, error } = await service
        .from("conversations")
        .insert({
          user_a_id: ua,
          user_b_id: ub,
          status: decision.status,
          initiator_id: decision.initiatorId,
        })
        .select("id, status, initiator_id")
        .single();

      if (error && error.code === UNIQUE_VIOLATION) {
        // Dos primeros mensajes del par cruzados en el tiempo. El índice único
        // `conversations_pair_key` es lo que impide el hilo duplicado de RN-08; aquí solo hay que
        // recoger el hilo que ganó la carrera y seguir con él.
        const { data: raced, error: raceError } = await service
          .from("conversations")
          .select("id, status, initiator_id")
          .eq("user_a_id", ua)
          .eq("user_b_id", ub)
          .single();

        if (raceError || !raced) {
          throw new AppError(500, "internal_error", "No se pudo resolver la conversación", {
            cause: raceError?.message,
          });
        }
        conversationId = raced.id;
        finalStatus = raced.status;
        finalInitiatorId = raced.initiator_id;

        // Si el que ganó fue el OTRO y quedó pendiente, contestarle es aceptar (RN-08).
        if (finalStatus === "pending" && finalInitiatorId === recipientId) {
          await service.from("conversations").update({ status: "accepted" }).eq("id", conversationId)
            .eq("status", "pending");
          finalStatus = "accepted";
        }
      } else if (error || !created) {
        throw new AppError(500, "internal_error", "No se pudo crear la conversación", {
          cause: error?.message,
        });
      } else {
        conversationId = created.id;
        finalStatus = created.status;
        finalInitiatorId = created.initiator_id;
      }
    } else {
      conversationId = conversationRow!.id;
      finalStatus = decision.status;
      finalInitiatorId = conversationRow!.initiator_id;

      if (decision.upgradedToAccepted) {
        // El `eq('status','pending')` hace de cerrojo, igual que en `follow-toggle`: si dos
        // respuestas cruzan, solo una encuentra fila que actualizar.
        const { error } = await service
          .from("conversations")
          .update({ status: "accepted" })
          .eq("id", conversationId)
          .eq("status", "pending");

        if (error) {
          throw new AppError(500, "internal_error", "No se pudo aceptar la conversación", {
            cause: error.message,
          });
        }
      }
    }

    // --- Las dos filas de estado. `ignoreDuplicates` es OBLIGATORIO, no una optimización: sin él
    // el upsert pisaría el `hidden`, el `cleared_at` y el `unread_count` que ya tuviera el otro, y
    // con ellos el ignorar (RN-06) y el borrado de historial (RN-27). Aquí solo se crean si faltan;
    // moverlas es trabajo del trigger de entrega.
    const { error: statesError } = await service
      .from("conversation_states")
      .upsert(
        [
          { conversation_id: conversationId, user_id: senderId },
          { conversation_id: conversationId, user_id: recipientId },
        ],
        { onConflict: "conversation_id,user_id", ignoreDuplicates: true },
      );

    if (statesError) {
      throw new AppError(500, "internal_error", "No se pudo preparar la conversación", {
        cause: statesError.message,
      });
    }

    // =============================================================================================
    // 6) `reply_to_id` TIENE QUE SER DE ESTA CONVERSACIÓN
    // =============================================================================================
    // Sin esta comprobación se puede citar un mensaje de OTRA conversación: al pintar la cita, el
    // cliente resuelve el id y enseña su texto, así que sería una lectura de mensajes ajenos por la
    // puerta de atrás. Va ANTES del insert: un mensaje con una cita inválida no debe llegar a
    // existir.
    if (replyToId !== null) {
      const { data: quoted, error } = await service
        .from("direct_messages")
        .select("id")
        .eq("id", replyToId)
        .eq("conversation_id", conversationId)
        .maybeSingle();

      if (error) {
        throw new AppError(500, "internal_error", "No se pudo validar la cita", {
          cause: error.message,
        });
      }
      if (!quoted) {
        throw new AppError(
          422,
          "invalid_reply_target",
          "El mensaje citado no pertenece a esta conversación",
          { field: "reply_to_id" },
        );
      }
    }

    // =============================================================================================
    // 7) EL MENSAJE
    // =============================================================================================
    // El trigger `direct_messages_delivery` hace el resto —`last_message_at`, el `unread_count` del
    // receptor y el `hidden`— dentro de esta misma transacción.
    const { data: inserted, error: insertError } = await service
      .from("direct_messages")
      .insert({
        conversation_id: conversationId,
        sender_id: senderId,
        content,
        reply_to_id: replyToId,
        idempotency_key: idempotencyKey,
      })
      .select("id, conversation_id, content, reply_to_id, created_at")
      .single();

    let message: MessageRow;
    let idempotentReplay = false;

    if (insertError?.code === UNIQUE_VIOLATION) {
      // Dos peticiones con la misma clave a la vez: la comprobación del paso 1 no las vio porque
      // ninguna había commiteado todavía. El índice único parcial
      // `direct_messages (sender_id, idempotency_key)` es quien decide, y la que pierde devuelve el
      // mensaje de la que ganó — el mismo resultado que un reintento normal.
      const { data: winner, error: winnerError } = await service
        .from("direct_messages")
        .select("id, conversation_id, content, reply_to_id, created_at")
        .eq("sender_id", senderId)
        .eq("idempotency_key", idempotencyKey)
        .single();

      if (winnerError || !winner) {
        throw new AppError(500, "internal_error", "No se pudo resolver el envío duplicado", {
          cause: winnerError?.message,
        });
      }
      message = winner as MessageRow;
      idempotentReplay = true;
    } else if (insertError || !inserted) {
      throw new AppError(500, "internal_error", "No se pudo enviar el mensaje", {
        cause: insertError?.message,
      });
    } else {
      message = inserted as MessageRow;
    }

    // --- Los que le quedan de RN-01. Solo hay tope mientras el hilo lo sostenga el emisor: una
    // conversación aceptada no tiene límite (§4.2 caso 1), y una que abrió el otro tampoco, porque
    // contestarle ya la aceptó (RN-08).
    const messagesLeft = finalStatus === "accepted" || finalInitiatorId !== senderId
      ? null
      : Math.max(0, MAX_PENDING_MESSAGES - (senderMessageCount + (idempotentReplay ? 0 : 1)));

    return jsonResponse(
      {
        success: true,
        idempotent_replay: idempotentReplay,
        message,
        messages_left: messagesLeft,
      } satisfies MessagingSendResponse,
      200,
    );
  } catch (err) {
    return errorResponse(err);
  }
});

/**
 * `messages_left` para el camino de REINTENTO, donde no se ha recalculado nada.
 *
 * Se recuenta en vez de devolver `null`: un reintento tiene que dar la MISMA respuesta que el envío
 * original (es lo que significa idempotente), y un `null` donde antes había un número le diría al
 * cliente que el tope desapareció.
 */
async function messagesLeftFor(
  // deno-lint-ignore no-explicit-any
  service: any,
  conversationId: string,
  senderId: string,
): Promise<number | null> {
  const [convRes, countRes] = await Promise.all([
    service.from("conversations").select("status, initiator_id").eq("id", conversationId)
      .maybeSingle(),
    service.from("direct_messages").select("id", { count: "exact", head: true })
      .eq("conversation_id", conversationId).eq("sender_id", senderId),
  ]);

  const conv = convRes.data as { status: ConversationStatus; initiator_id: string } | null;
  if (!conv || conv.status === "accepted" || conv.initiator_id !== senderId) return null;

  return Math.max(0, MAX_PENDING_MESSAGES - (countRes.count ?? 0));
}
