import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/social/conversation_summary.dart';
import '../../domain/social/message.dart';
import '../../domain/social/messaging_repository.dart';
import '../../domain/social/social_failure.dart';
import 'social_edge_call.dart';

/// [MessagingRepository] sobre Supabase.
///
/// ## Por qué casi todo pasa por Edge Function
///
/// `conversations` **no tiene ni un `grant`** para `authenticated` (migración `20260823120200`).
/// No es una omisión: es lo que hace **estructural** —y no confiada al cuidado de quien escribe el
/// endpoint— la invisibilidad de `status = 'ignored'` (`RN-06`) y de `initiator_id`. Toda lectura
/// de conversaciones pasa por una función que **proyecta por espectador**.
///
/// Lo único que el cliente lee directo es `direct_messages`, que sí concede `select` con la policy
/// `direct_messages_read_participant` — y solo para el `stream()` de tiempo real. Ver
/// [watchMessages], que documenta lo que ese camino **no** aplica.
class SupabaseMessagingRepository implements MessagingRepository {
  SupabaseMessagingRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<InboxSnapshot> inbox() async => InboxSnapshot.fromJson(
    await invokeEdge(_client, 'messaging-inbox', method: HttpMethod.get),
  );

  @override
  Future<MessageThreadPage> thread(
    String conversationId, {
    int? limit,
    String? before,
  }) async => MessageThreadPage.fromJson(
    await invokeEdge(
      _client,
      'messaging-thread',
      method: HttpMethod.get,
      query: <String, dynamic>{
        'conversation_id': conversationId,
        if (limit != null) 'limit': '$limit',
        // Se reenvía TAL CUAL, sin reinterpretarlo ni reformatearlo: el cursor sale de la fila
        // cruda más antigua y no del mensaje proyectado, porque la proyección descarta filas
        // (RN-27, RN-28) y un cursor sacado de la lista ya filtrada saltaría por encima de ellas.
        'before': ?before,
      },
    ),
  );

  @override
  Future<({Message message, int? messagesLeft, bool idempotentReplay})> send({
    required String recipientId,
    required String content,
    required String idempotencyKey,
    String? replyToId,
  }) async {
    final Map<String, dynamic> data = await invokeEdge(
      _client,
      'messaging-send',
      body: <String, dynamic>{
        'recipient_id': recipientId,
        'content': content,
        // Obligatoria (invariante de CLAUDE.md). Quien llama la genera UNA vez y la conserva
        // durante los reintentos: generarla de nuevo en cada intento es no tenerla.
        'idempotency_key': idempotencyKey,
        'reply_to_id': ?replyToId,
      },
    );

    final Object? message = data['message'];
    if (message is! Map) {
      throw const SocialFailure(
        SocialFailureKind.unknown,
        'El mensaje se pudo haber enviado, pero no se recibió confirmación.',
        rawCode: 'messaging_send_sin_message',
      );
    }

    return (
      message: Message.fromJson(<String, dynamic>{
        ...Map<String, dynamic>.from(message),
        // `messaging-send` devuelve la fila recién creada, no la proyección: no trae `from_me`
        // (siempre es propio), ni `edited`, ni `deleted_for_all`. Se completan aquí para que la
        // burbuja optimista sea del mismo tipo que las de `thread`.
        'from_me': true,
        'edited': false,
        'deleted_for_all': false,
      }),
      messagesLeft: (data['messages_left'] as num?)?.toInt(),
      idempotentReplay: data['idempotent_replay'] == true,
    );
  }

  @override
  Future<void> conversationAction(
    String conversationId,
    ConversationAction action, {
    bool? notificationsEnabled,
  }) async {
    await invokeEdge(
      _client,
      'messaging-actions',
      body: <String, dynamic>{
        'conversation_id': conversationId,
        'action': action.wireValue,
        // Se manda solo cuando toca. El backend devuelve 400 si `set_notifications` llega sin
        // booleano, **en vez de asumir un valor por defecto**, así que mandarlo siempre haría que
        // un `null` accidental apagara las notificaciones de alguien.
        if (action == ConversationAction.setNotifications)
          'notifications_enabled': notificationsEnabled,
      },
    );
  }

  @override
  Future<void> messageAction(
    String messageId,
    MessageAction action, {
    String? content,
  }) async {
    await invokeEdge(
      _client,
      'messaging-message-actions',
      body: <String, dynamic>{
        'message_id': messageId,
        'action': action.wireValue,
        if (action == MessageAction.edit) 'content': content,
      },
    );
  }

  @override
  Future<MessageSearchResult> search(
    String conversationId,
    String query,
  ) async {
    final Map<String, dynamic> data = await invokeEdge(
      _client,
      'messaging-search',
      method: HttpMethod.get,
      query: <String, dynamic>{'conversation_id': conversationId, 'q': query},
    );

    return MessageSearchResult(
      total: (data['total'] as num?)?.toInt() ?? 0,
      searchedMessages: (data['searched_messages'] as num?)?.toInt() ?? 0,
      searchLimit: (data['search_limit'] as num?)?.toInt() ?? 0,
      hits: ((data['matches'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> raw) {
            final Map<String, dynamic> row = Map<String, dynamic>.from(raw);
            return MessageSearchHit(
              messageId: row['message_id'] as String,
              createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
              // Los offsets se usan TAL CUAL. Recalcularlos aquí con otra normalización los
              // desplaza, que es el fallo que `_shared/text-search.ts` documenta arriba del todo.
              offsets:
                  ((row['offsets'] as List<dynamic>?) ?? const <dynamic>[])
                      .whereType<Map<dynamic, dynamic>>()
                      .map(
                        (Map<dynamic, dynamic> o) => (
                          start: (o['start'] as num).toInt(),
                          end: (o['end'] as num).toInt(),
                        ),
                      )
                      .toList(growable: false),
            );
          })
          .toList(growable: false),
    );
  }

  /// El valor guardado de la campana (§9.3 punto 1), leído **directo** de `conversation_states`.
  ///
  /// Directo y no por Edge Function porque ninguna lo devuelve, y el camino es legal: la columna
  /// tiene `grant select` para `authenticated` y la policy `conversation_states_read_own` acota la
  /// fila a la propia (`auth.uid() = user_id`). El `eq('user_id', …)` de abajo **no** es lo que
  /// protege nada —eso lo hace RLS—; está para que la consulta pida una sola fila en vez de
  /// apoyarse en que la policy filtre la del otro participante.
  ///
  /// `maybeSingle` y no `single`: una conversación recién nacida puede no tener fila todavía, y eso
  /// no es un error sino el `default` de la columna.
  @override
  Future<bool> notificationsEnabled(String conversationId) async {
    final String? viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return true;

    final Map<String, dynamic>? row = await _client
        .from('conversation_states')
        .select('notifications_enabled')
        .eq('conversation_id', conversationId)
        .eq('user_id', viewerId)
        .maybeSingle();

    return row?['notifications_enabled'] as bool? ?? true;
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    final String? viewerId = _client.auth.currentUser?.id;

    return _client
        .from('direct_messages')
        .stream(primaryKey: <String>['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map(
          (List<Map<String, dynamic>> rows) => rows
              // ATENCIÓN: estas filas llegan CRUDAS. No pasan por `projectMessages`, así que aquí
              // no las filtra nadie — hay que reaplicar RN-28 (borrado "para mí") a mano. El
              // `cleared_at` de RN-27 NO se puede aplicar aquí porque vive en `conversation_states`
              // y no viaja con la fila: por eso este stream sirve para **saber que hay algo
              // nuevo**, y la verdad proyectada la sigue dando `thread()`.
              .where(
                (Map<String, dynamic> row) => !_deletedForViewer(row, viewerId),
              )
              .map(_messageFromRow)
              .toList(growable: false),
        );
  }

  bool _deletedForViewer(Map<String, dynamic> row, String? viewerId) {
    if (viewerId == null) return false;
    final Object? deletedFor = row['deleted_for'];
    return deletedFor is List && deletedFor.contains(viewerId);
  }

  /// Convierte una fila cruda de `direct_messages` en un [Message].
  ///
  /// La lápida se fuerza a `content: null` aunque la fila trajera texto: `delete_for_all` pone
  /// `content = null` en la misma sentencia, pero un cliente que se fiara de la fila y no de la
  /// bandera pintaría el texto de un mensaje borrado si esa constraint fallara alguna vez.
  Message _messageFromRow(Map<String, dynamic> row) {
    final bool deletedForAll = row['deleted_for_all_at'] != null;
    return Message(
      id: row['id'] as String,
      fromMe: row['sender_id'] == _client.auth.currentUser?.id,
      content: deletedForAll ? null : row['content'] as String?,
      deletedForAll: deletedForAll,
      edited: row['edited_at'] != null,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      // La cita no se resuelve aquí: haría falta el mensaje citado Y su prueba de visibilidad, que
      // es justo lo que `resolveQuote` hace en el backend. Un stream que la resolviera a medias
      // podría enseñar el texto de un mensaje que quien mira no debería ver.
      replyTo: null,
    );
  }
}
