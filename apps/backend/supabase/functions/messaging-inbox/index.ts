// messaging-inbox — HTTP (app)
//
// Las dos bandejas del §8: `Contactos` y `Solicitudes`, proyectadas POR ESPECTADOR.
//
// La decisión de qué ve cada uno es pura y vive en `_shared/messaging-view.ts`, con sus 30 tests.
// Aquí solo se cargan filas, se le pasan a la proyección y se decoran con lo que exige red: el
// nombre del otro y el punto de actividad.
//
// Corre con `service_role` porque `conversations` NO TIENE NI UN GRANT para `authenticated`
// (migración `20260823120200`): no existe consulta de cliente que pueda leer `status` ni
// `initiator_id`, y por eso RN-06 no depende del cuidado de quien escriba este fichero.
//
// EL COROLARIO QUE HAY QUE TENER DELANTE: `service_role` SE SALTA LA RLS. Todo lo que la policy
// `direct_messages_read_participant` protege para el cliente —el `deleted_for` de RN-28 y el
// `cleared_at` de RN-27— aquí no lo aplica nadie. Lo aplica `messaging-view.ts`, y por eso el
// último mensaje se pasa por la proyección en vez de pintarse tal cual viene de la tabla.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import {
  type ConversationView,
  type ConversationViewInput,
  type LastMessageInput,
  projectInbox,
} from "../_shared/messaging-view.ts";
import type { ConversationStatus } from "../_shared/messaging-routing.ts";

/**
 * Tope de conversaciones por bandeja.
 *
 * No es un número al azar: `activity_status` **lanza excepción** por encima de 500 ids (migración
 * `20260823120300`), y la bandeja le pasa un id por cada contacto. 100 dejan margen de sobra y
 * mantienen acotado el `in (...)` de las tres consultas de abajo.
 */
const MAX_CONVERSATIONS = 100;

interface ConversationRow {
  id: string;
  user_a_id: string;
  user_b_id: string;
  status: ConversationStatus;
  initiator_id: string;
  last_message_at: string;
}

interface StateRow {
  conversation_id: string;
  hidden: boolean;
  unread_count: number;
  cleared_at: string | null;
}

interface MessageRow {
  conversation_id: string;
  sender_id: string;
  content: string | null;
  created_at: string;
  deleted_for: string[];
  deleted_for_all_at: string | null;
}

interface InboxEntry extends ConversationView {
  display_name: string | null;
  preset_avatar: string | null;
  /** SOLO en Contactos. RN-30: el punto no aparece en Solicitudes. */
  is_active?: boolean;
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "GET") {
      throw new AppError(405, "method_not_allowed", "Usa GET");
    }

    // `client` es el del USUARIO (lleva su JWT). Hace falta más abajo, y no es intercambiable con
    // el de servicio — ver el comentario de `activity_status`.
    const { userId: viewerId, client: userClient } = await requireAuthUser(req);
    const service = getServiceRoleClient();

    // --- 1) Mis filas de estado. Son el índice de "mis conversaciones": la participación se deriva
    // de aquí, igual que en la policy de `direct_messages`.
    const { data: stateRows, error: statesError } = await service
      .from("conversation_states")
      .select("conversation_id, hidden, unread_count, cleared_at")
      .eq("user_id", viewerId)
      // RN-22/RN-27: lo archivado no se lista. Se filtra en la consulta y no después, para no
      // traerse a memoria conversaciones que de todas formas no se van a enseñar.
      .eq("hidden", false)
      .limit(MAX_CONVERSATIONS);

    if (statesError) {
      throw new AppError(500, "internal_error", "No se pudo cargar la bandeja", {
        cause: statesError.message,
      });
    }

    const states = (stateRows ?? []) as StateRow[];
    if (states.length === 0) {
      return jsonResponse({ contacts: [], requests: [], requests_count: 0 }, 200);
    }

    const stateById = new Map(states.map((s) => [s.conversation_id, s]));
    const conversationIds = states.map((s) => s.conversation_id);

    // --- 2) Las conversaciones.
    const { data: convRows, error: convError } = await service
      .from("conversations")
      .select("id, user_a_id, user_b_id, status, initiator_id, last_message_at")
      .in("id", conversationIds);

    if (convError) {
      throw new AppError(500, "internal_error", "No se pudo cargar las conversaciones", {
        cause: convError.message,
      });
    }

    const conversations = (convRows ?? []) as ConversationRow[];

    // --- 3) El último mensaje de cada una, EN UNA SOLA CONSULTA.
    //
    // El truco es `conversations.last_message_at`: ya sabemos el instante exacto del último mensaje
    // de cada hilo, así que se piden por ese par (conversación, instante) en vez de paginar cada
    // conversación por separado. PostgREST no sabe hacer "el más reciente por grupo", y la
    // alternativa sería una consulta por conversación — N+1 en la pantalla más visitada de la app.
    const lastMessageAts = [...new Set(conversations.map((c) => c.last_message_at))];
    const { data: msgRows, error: msgError } = await service
      .from("direct_messages")
      .select("conversation_id, sender_id, content, created_at, deleted_for, deleted_for_all_at")
      .in("conversation_id", conversationIds)
      .in("created_at", lastMessageAts);

    if (msgError) {
      throw new AppError(500, "internal_error", "No se pudo cargar los últimos mensajes", {
        cause: msgError.message,
      });
    }

    const conversationById = new Map(conversations.map((c) => [c.id, c]));
    const lastMessageByConversation = new Map<string, MessageRow>();
    for (const m of (msgRows ?? []) as MessageRow[]) {
      // Dos conversaciones pueden compartir instante —el `in (...)` los pide todos a la vez—, así
      // que se queda solo el mensaje que de verdad es el último de SU hilo.
      if (conversationById.get(m.conversation_id)?.last_message_at === m.created_at) {
        lastMessageByConversation.set(m.conversation_id, m);
      }
    }

    // --- 4) La proyección. Aquí es donde se aplica RN-06, RN-22, RN-27, RN-28 y RN-29.
    const viewInputs: ConversationViewInput[] = conversations.map((c) => {
      const state = stateById.get(c.id)!;
      const raw = lastMessageByConversation.get(c.id);
      const lastMessage: LastMessageInput | null = raw === undefined ? null : {
        senderId: raw.sender_id,
        content: raw.content,
        createdAt: raw.created_at,
        deletedFor: raw.deleted_for ?? [],
        deletedForAll: raw.deleted_for_all_at !== null,
      };

      return {
        id: c.id,
        userAId: c.user_a_id,
        userBId: c.user_b_id,
        status: c.status,
        initiatorId: c.initiator_id,
        lastMessageAt: c.last_message_at,
        viewerHidden: state.hidden,
        viewerUnreadCount: state.unread_count,
        viewerClearedAt: state.cleared_at,
        lastMessage,
      };
    });

    const { contacts, requests } = projectInbox(viewInputs, viewerId);

    // --- 5) Los nombres. `display_name` y `preset_avatar` ya son legibles por `authenticated` vía
    // PostgREST, así que devolverlos aquí no expone nada nuevo: ahorra una tanda de peticiones.
    // La FOTO no viaja: se pide aparte a `profile-photo-view-url`, que es quien firma su URL contra
    // R2 (skill `media-storage` — la clave del objeto no se sirve suelta).
    const otherIds = [...new Set([...contacts, ...requests].map((c) => c.other_user_id))];
    const { data: profileRows, error: profileError } = await service
      .from("profiles")
      .select("user_id, display_name, preset_avatar")
      .in("user_id", otherIds);

    if (profileError) {
      throw new AppError(500, "internal_error", "No se pudo cargar los perfiles", {
        cause: profileError.message,
      });
    }

    const profileById = new Map(
      (profileRows ?? []).map((p) => [p.user_id as string, p as {
        display_name: string | null;
        preset_avatar: string | null;
      }]),
    );

    // --- 6) EL PUNTO DE ACTIVIDAD, Y LA TRAMPA QUE TIENE.
    //
    // `activity_status` SE LLAMA CON EL CLIENTE DEL USUARIO, no con el de servicio, y no es
    // indiferente: la función deriva quién pregunta de `auth.uid()`, que con la clave de servicio
    // es NULL. Comprobado contra la base, no deducido: con un token sin `sub` devuelve `false` para
    // un usuario que está activo ahora mismo. Es decir, llamarla con `service` no da error — pinta
    // TODOS los puntos en gris, en silencio, para siempre.
    //
    // Y hay una segunda razón, de regla y no de fontanería: RN-32 es recíproco —quien oculta su
    // actividad no ve la de nadie— y se resuelve mirando al llamante. Sin identidad no hay forma de
    // aplicarlo.
    //
    // SOLO para Contactos: RN-30 dice que el punto no aparece en Solicitudes, y la lista de ids que
    // se manda es exactamente esa. Lo que no se pregunta no se puede pintar por descuido.
    const activeById = new Map<string, boolean>();
    if (contacts.length > 0) {
      const { data: activity, error: activityError } = await userClient.rpc("activity_status", {
        p_user_ids: contacts.map((c) => c.other_user_id),
      });

      if (activityError) {
        // No se lanza: el punto de actividad es decoración, y una bandeja sin puntos es mucho mejor
        // que una bandeja que no carga. Se registra para que no pase inadvertido.
        console.warn("activity_status failed:", activityError.message);
      } else {
        for (const row of activity ?? []) {
          activeById.set(row.user_id as string, row.is_active as boolean);
        }
      }
    }

    const decorate = (c: ConversationView, withActivity: boolean): InboxEntry => {
      const profile = profileById.get(c.other_user_id);
      const entry: InboxEntry = {
        ...c,
        display_name: profile?.display_name ?? null,
        preset_avatar: profile?.preset_avatar ?? null,
      };
      if (withActivity) entry.is_active = activeById.get(c.other_user_id) ?? false;
      return entry;
    };

    return jsonResponse({
      contacts: contacts.map((c) => decorate(c, true)),
      requests: requests.map((c) => decorate(c, false)),
      // §8.1: la pestaña enseña «Solicitudes (N)» solo si N > 0. El cliente decide; aquí va el número.
      requests_count: requests.length,
    }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
