// messaging-search — HTTP (app)
//
// La búsqueda dentro de una conversación (§9.4): insensible a mayúsculas y a acentos, con los
// offsets de cada coincidencia para resaltar en la burbuja.
//
// POR QUÉ SE BUSCA EN DENO Y NO CON UN `ilike` EN POSTGRES
// §9.4 pide además de la insensibilidad los **offsets** para resaltar. Un `ilike` no los da, así que
// el cliente tendría que volver a buscar sobre el texto — y dos normalizaciones distintas a cada
// lado **desplazan el resaltado**. Se calcula una vez, aquí, y viaja el resultado. La lógica es pura
// y vive en `_shared/text-search.ts`, con 16 tests.
//
// POR QUÉ 1000 MENSAJES, Y NO 100 000
// Es la enmienda nº 4 de la spec: cota por TAMAÑO, no por tiempo. Determinista —da el mismo
// resultado hoy y dentro de un año—, se resuelve con el índice
// `direct_messages (conversation_id, created_at desc)` que la paginación necesita igualmente, y
// **acota lo transferido a ~1 MB por búsqueda** (1000 mensajes × 1000 caracteres de RN-26), que es
// la razón real de la cota. Una cota por tiempo vaciaría la búsqueda de una conversación antigua
// sin que el usuario entienda por qué.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { isUuid } from "../_shared/validation.ts";
import { findMatches, type MatchOffset } from "../_shared/text-search.ts";
import { type MessageInput, projectMessages } from "../_shared/messaging-view.ts";

/** §9.4, enmienda nº 4. La cabecera de la búsqueda lo dice, así que también viaja en la respuesta. */
const SEARCH_LIMIT = 1000;

/** Un término más largo que esto no es una búsqueda, es un pegado accidental. */
const MAX_QUERY_LENGTH = 100;

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

interface SearchMatch {
  message_id: string;
  created_at: string;
  offsets: MatchOffset[];
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "GET") {
      throw new AppError(405, "method_not_allowed", "Usa GET");
    }

    const { userId: viewerId } = await requireAuthUser(req);
    const url = new URL(req.url);

    const conversationId = url.searchParams.get("conversation_id");
    if (!isUuid(conversationId)) {
      throw new AppError(400, "invalid_input", "conversation_id debe ser un uuid", {
        field: "conversation_id",
      });
    }

    const query = (url.searchParams.get("q") ?? "").trim();
    if (query.length < 1 || query.length > MAX_QUERY_LENGTH) {
      throw new AppError(
        400,
        "invalid_input",
        `q debe tener entre 1 y ${MAX_QUERY_LENGTH} caracteres`,
        { field: "q" },
      );
    }

    const service = getServiceRoleClient();

    // --- LA PERTENENCIA, ANTES DE NADA. `service_role` se salta la RLS, así que sin esto cualquiera
    // con un `conversation_id` podría buscar dentro de la conversación de dos desconocidos — y los
    // offsets le dirían además dónde está cada palabra.
    //
    // 404 Y NO 403, Y ESO SE APARTA DE LA LETRA DEL PASO 3 DEL PLAN. Un 403 distinguiría "existe
    // pero no es tuya" de "no existe", que es un enumerador de conversaciones ajenas. Las Tareas 11
    // y 12 ya devuelven 404 en el mismo caso; dejar aquí un 403 reabriría por una puerta lo que las
    // otras dos cierran, y la búsqueda es tan buen oráculo como el hilo.
    const { data: stateRow, error: stateError } = await service
      .from("conversation_states")
      .select("cleared_at")
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

    // --- Los últimos 1000. `cleared_at` va en la consulta además de en la proyección: la proyección
    // es la garantía, esto es no traerse de la red lo que no se va a mirar.
    let listing = service
      .from("direct_messages")
      .select(
        "id, sender_id, content, deleted_for, deleted_for_all_at, edited_at, reply_to_id, created_at",
      )
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: false })
      .limit(SEARCH_LIMIT);

    if (clearedAt !== null) listing = listing.gt("created_at", clearedAt);

    const { data: msgRows, error: msgError } = await listing;
    if (msgError) {
      throw new AppError(500, "internal_error", "No se pudo cargar los mensajes", {
        cause: msgError.message,
      });
    }

    const rows = (msgRows ?? []) as MessageRow[];

    // --- La visibilidad NO se reimplementa: se reutiliza la proyección de la Tarea 11, que ya
    // aplica `deleted_for` (RN-28) y `cleared_at` (RN-27) y deja las lápidas con `content: null`.
    // Escribirlo otra vez aquí sería una segunda copia de las mismas reglas, y §9.4 exige las tres.
    const visible: MessageInput[] = rows.map((r) => ({
      id: r.id,
      senderId: r.sender_id,
      content: r.content,
      deletedFor: r.deleted_for ?? [],
      deletedForAllAt: r.deleted_for_all_at,
      editedAt: r.edited_at,
      replyToId: r.reply_to_id,
      createdAt: r.created_at,
    }));

    const projected = projectMessages(visible, viewerId, clearedAt);

    const matches: SearchMatch[] = [];
    let total = 0;
    let searched = 0;

    for (const message of projected) {
      // `content` es null en las lápidas: §9.4 dice que tampoco se busca en ellas.
      if (message.content === null) continue;
      searched++;

      const offsets = findMatches(message.content, query);
      if (offsets.length === 0) continue;

      matches.push({
        message_id: message.id,
        created_at: message.created_at,
        offsets,
      });
      total += offsets.length;
    }

    return jsonResponse({
      // El `12` del contador `3/12` del §9.4: coincidencias TOTALES, no mensajes que coinciden. Un
      // mensaje con la palabra tres veces aporta tres saltos a las flechas arriba/abajo.
      total,
      // Los mensajes REALMENTE mirados, para que la cabecera pueda decir la verdad en vez de
      // prometer 1000 siempre. `search_limit` es la cota; `searched_messages`, lo que se miró.
      // NO cuenta las lápidas: en ellas no se busca (§9.4), así que incluirlas exageraría el
      // alcance de la búsqueda justo en la cifra que la cabecera le enseña al usuario.
      searched_messages: searched,
      search_limit: SEARCH_LIMIT,
      // De más reciente a más antiguo, igual que se leyeron: las flechas del §9.4 recorren hacia
      // atrás desde el final de la conversación, que es donde está el usuario mirando.
      matches,
    }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
