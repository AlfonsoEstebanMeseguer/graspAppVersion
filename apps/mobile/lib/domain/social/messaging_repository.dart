import 'conversation_summary.dart';
import 'message.dart';

/// Qué hacer con una conversación entera (`messaging-actions`).
enum ConversationAction {
  /// `status = 'accepted'` (`RN-05`). **Solo quien recibió** la solicitud.
  accept('accept'),

  /// `status = 'ignored'` + archivada **solo del lado de quien ignora** (`RN-06`). Solo quien
  /// recibió. Es terminal: lo único que la reanuda es aceptar el seguimiento (`RN-17`).
  ignore('ignore'),

  /// `cleared_at = now()` + archivada, solo de quien lo pide (`RN-27`).
  deleteHistory('delete_history'),

  /// Pone a cero **el contador propio** (`RN-31`). Ninguna acción escribe en la fila del otro.
  markRead('mark_read'),

  /// Persiste el toggle de notificaciones y nada más (§9.3 punto 1).
  setNotifications('set_notifications');

  const ConversationAction(this.wireValue);

  final String wireValue;
}

/// Qué hacer con un mensaje suelto (`messaging-message-actions`).
enum MessageAction {
  /// Añade al actor a `deleted_for`. **Cualquier participante**, autor o no: es su copia.
  deleteForMe('delete_for_me'),

  /// Lápida: `content = null` + marca. **Solo el autor**.
  deleteForAll('delete_for_all'),

  /// Texto nuevo + tag «editado», que ven los dos. **Solo el autor**.
  edit('edit');

  const MessageAction(this.wireValue);

  final String wireValue;
}

/// Una coincidencia de la búsqueda dentro de la conversación (§9.4).
class MessageSearchHit {
  const MessageSearchHit({
    required this.messageId,
    required this.createdAt,
    required this.offsets,
  });

  final String messageId;
  final DateTime createdAt;

  /// Rangos `[start, end)` **del texto original y en unidades UTF-16**, calculados por el backend.
  ///
  /// Se usan tal cual y **no se recalculan aquí**: normalizar a los dos lados con reglas distintas
  /// desplaza el resaltado, que es el fallo que `_shared/text-search.ts` documenta. El espejo de
  /// `data/social/message_search.dart` existe para lo que no pasa por esta llamada.
  final List<({int start, int end})> offsets;
}

/// El resultado completo de una búsqueda en la conversación.
class MessageSearchResult {
  const MessageSearchResult({
    required this.total,
    required this.searchedMessages,
    required this.searchLimit,
    required this.hits,
  });

  /// **Coincidencias**, no mensajes: uno con la palabra tres veces aporta tres saltos a las flechas.
  /// Es el `12` del contador `3/12` del §9.4.
  final int total;

  /// Los realmente mirados, sin lápidas.
  final int searchedMessages;

  /// La cota (1000). La cabecera de la búsqueda **tiene que decirlo** (§9.4), y con `total` solo no
  /// se puede.
  final int searchLimit;

  final List<MessageSearchHit> hits;
}

/// Contrato de la mensajería directa (§8 y §9).
///
/// Sin ninguna dependencia de Supabase, como `AvatarRepository`: la implementación vive en
/// `data/social/`. Todo lo transaccional pasa por Edge Functions porque `conversations` **no tiene
/// ni un `grant`** para `authenticated` — la invisibilidad de `status = 'ignored'` y de
/// `initiator_id` es estructural, no confiada al cuidado de quien escribe la pantalla.
///
/// Todos los métodos lanzan `SocialFailure` con el texto ya en castellano.
abstract interface class MessagingRepository {
  /// Las dos bandejas del §8 (`messaging-inbox`).
  Future<InboxSnapshot> inbox();

  /// Una página de mensajes + **el estado del input** (`messaging-thread`).
  ///
  /// [before] es el cursor que devolvió la página anterior; se reenvía **tal cual**, sin
  /// reinterpretarlo, porque sale de la fila cruda y no del mensaje proyectado.
  Future<MessageThreadPage> thread(
    String conversationId, {
    int? limit,
    String? before,
  });

  /// Envía un mensaje (`messaging-send`).
  ///
  /// [idempotencyKey] es **obligatoria** (invariante de `CLAUDE.md`): un reintento devuelve el
  /// mismo mensaje con un 200, nunca un 409 que el cliente no sabría distinguir de un fallo real.
  /// La genera quien llama y la **conserva durante los reintentos** — generarla de nuevo en cada
  /// intento es exactamente lo mismo que no tenerla.
  ///
  /// Devuelve los mensajes que quedan (`RN-01`), o `null` si no hay tope.
  Future<({Message message, int? messagesLeft, bool idempotentReplay})> send({
    required String recipientId,
    required String content,
    required String idempotencyKey,
    String? replyToId,
  });

  /// Una acción sobre la conversación entera (`messaging-actions`).
  ///
  /// [notificationsEnabled] es obligatorio con [ConversationAction.setNotifications] y se ignora en
  /// el resto: el backend devuelve 400 si falta, en vez de asumir un valor por defecto.
  Future<void> conversationAction(
    String conversationId,
    ConversationAction action, {
    bool? notificationsEnabled,
  });

  /// Una acción sobre un mensaje suelto (`messaging-message-actions`).
  ///
  /// [content] solo con [MessageAction.edit]. Editar con el **mismo texto** es un no-op: el tag
  /// «editado» lo ven los dos, y ponerlo por un guardado idéntico diría que hubo una edición que no
  /// hubo.
  Future<void> messageAction(
    String messageId,
    MessageAction action, {
    String? content,
  });

  /// Busca dentro de una conversación (`messaging-search`, §9.4).
  Future<MessageSearchResult> search(String conversationId, String query);

  /// El valor guardado del toggle de la campana (§9.3 punto 1).
  ///
  /// ## Por qué esto no pasa por Edge Function, si todo lo demás sí
  ///
  /// Porque **ningún endpoint lo devuelve**: `messaging-actions` lo escribe con
  /// `set_notifications` y ni `messaging-thread` ni `messaging-inbox` lo traen de vuelta. Sin una
  /// lectura, la campana se abriría siempre en «activadas» aunque se apagara ayer — un toggle que se
  /// rearma solo es exactamente el botón que miente que el §9.3 quiere evitar, y un test de «persiste
  /// su valor» que solo comprobara la llamada de escritura pasaría con cualquier implementación.
  ///
  /// La lectura es legal para el cliente y no hace falta tocar el backend:
  /// `conversation_states` concede `select` a `authenticated` sobre esta columna y la policy
  /// `conversation_states_read_own` (`auth.uid() = user_id`) acota la fila a la propia. Comprobado
  /// contra `information_schema.column_privileges`, no contra la migración. Es el mismo camino
  /// directo que ya usa [watchMessages] sobre `direct_messages`, y por el mismo motivo: es de lo
  /// poquísimo de la mensajería que el cliente sí puede leer.
  ///
  /// **No confundir con `conversations`**, que no tiene ni un `grant` y nunca lo tendrá.
  ///
  /// Sin fila todavía —una conversación recién nacida— devuelve el `default` de la columna, `true`.
  Future<bool> notificationsEnabled(String conversationId);

  /// Mensajes nuevos en tiempo real, por `stream()` sobre `direct_messages`.
  ///
  /// Va por PostgREST/Realtime y no por Edge Function porque es lo único de la mensajería que sí
  /// puede leer el cliente: `direct_messages` **sí** concede `select` a `authenticated`, con la
  /// policy `direct_messages_read_participant` filtrando por participación.
  ///
  /// **Ojo con lo que este camino NO aplica.** Las filas llegan crudas, sin pasar por
  /// `projectMessages`: hay que respetar `deleted_for` (`RN-28`) y el `cleared_at` propio
  /// (`RN-27`) al pintarlas. El `stream` sirve para **saber que hay algo nuevo**; la verdad
  /// proyectada la da [thread].
  Stream<List<Message>> watchMessages(String conversationId);
}
