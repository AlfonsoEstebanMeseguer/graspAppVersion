import 'package:flutter/foundation.dart';

import 'message_input_state.dart';

/// Un mensaje directo, tal y como lo ve quien abre la conversación (§9.1).
///
/// **No tiene `readAt` ni nada equivalente**, y no es un olvido: `RN-31` y el
/// [ADR 0021](../../../../docs/decisions/0021-mensajeria-sin-confirmacion-de-lectura.md) prohíben
/// la confirmación de lectura en Grasp. No hay columna en `direct_messages`, el backend no la
/// emite y este modelo no la tiene. Lo único que existe es el `unread_count` **propio**, que vive
/// en [ConversationSummary] y nunca se comparte.
///
/// Tampoco tiene `senderId`: quién escribió qué llega como [fromMe], que es lo único que la
/// burbuja necesita para elegir lado y color.
@immutable
class Message {
  const Message({
    required this.id,
    required this.fromMe,
    required this.content,
    required this.deletedForAll,
    required this.edited,
    required this.createdAt,
    this.replyTo,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final Object? quote = json['reply_to'];
    return Message(
      id: json['id'] as String,
      fromMe: json['from_me'] == true,
      content: json['content'] as String?,
      deletedForAll: json['deleted_for_all'] == true,
      edited: json['edited'] == true,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      replyTo: quote is Map
          ? MessageQuote.fromJson(Map<String, dynamic>.from(quote))
          : null,
    );
  }

  final String id;
  final bool fromMe;

  /// `null` cuando [deletedForAll] es `true`. La lápida "Este mensaje ha sido eliminado" la pinta
  /// la burbuja; el texto original **no viaja** (`RN-28`).
  final String? content;

  final bool deletedForAll;

  /// El tag «editado» del §9. Es un booleano y no una marca de tiempo a propósito: el §9 pide
  /// decir *que* se editó, no *cuándo* (punto 8 de la skill `db-schema`).
  final bool edited;

  final DateTime createdAt;

  /// La cita, si este mensaje responde a otro.
  final MessageQuote? replyTo;

  @override
  bool operator ==(Object other) =>
      other is Message &&
      other.id == id &&
      other.fromMe == fromMe &&
      other.content == content &&
      other.deletedForAll == deletedForAll &&
      other.edited == edited &&
      other.createdAt == createdAt &&
      other.replyTo == replyTo;

  @override
  int get hashCode => Object.hash(
    id,
    fromMe,
    content,
    deletedForAll,
    edited,
    createdAt,
    replyTo,
  );
}

/// El mensaje citado dentro de una respuesta.
///
/// Llega con [content] a `null` —y no ausente— cuando quien mira no puede verlo: borrado «para mí»
/// (`RN-28`), anterior a su `cleared_at` (`RN-27`) o lápida. La burbuja pinta «mensaje no
/// disponible» y conserva el hilo, en vez de omitir la cita y romperlo.
@immutable
class MessageQuote {
  const MessageQuote({
    required this.id,
    required this.fromMe,
    required this.content,
  });

  factory MessageQuote.fromJson(Map<String, dynamic> json) => MessageQuote(
    id: json['id'] as String,
    fromMe: json['from_me'] == true,
    content: json['content'] as String?,
  );

  final String id;
  final bool fromMe;
  final String? content;

  @override
  bool operator ==(Object other) =>
      other is MessageQuote &&
      other.id == id &&
      other.fromMe == fromMe &&
      other.content == content;

  @override
  int get hashCode => Object.hash(id, fromMe, content);
}

/// Una página de `messaging-thread`: los mensajes, el cursor y **el estado del input**.
///
/// El input viaja con la página y no se calcula en el cliente porque sale del **mismo veredicto**
/// que usa `messaging-send` (`evaluateSendLimits`). Recalcularlo aquí es justo lo que haría que el
/// input dijera «puedes escribir» y el envío rechazara — o, peor, que divergieran en el caso del
/// bloqueo, que es donde `RN-23` exige que no se distinga nada.
@immutable
class MessageThreadPage {
  const MessageThreadPage({
    required this.otherUserId,
    required this.displayName,
    required this.messages,
    required this.input,
    required this.hasMore,
    required this.unreadCount,
    this.presetAvatarSlug,
    this.isActive,
    this.nextBefore,
  });

  factory MessageThreadPage.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> conversation = Map<String, dynamic>.from(
      (json['conversation'] as Map<dynamic, dynamic>?) ??
          const <dynamic, dynamic>{},
    );
    final Object? input = json['input'];

    return MessageThreadPage(
      otherUserId: conversation['other_user_id'] as String? ?? '',
      displayName: conversation['display_name'] as String? ?? '',
      presetAvatarSlug: conversation['preset_avatar'] as String?,
      isActive: conversation.containsKey('is_active')
          ? conversation['is_active'] == true
          : null,
      unreadCount: (conversation['unread_count'] as num?)?.toInt() ?? 0,
      messages: ((json['messages'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> row) =>
                Message.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
      // Sin objeto `input` se falla cerrado, como en `MessageInputState.fromJson`.
      input: MessageInputState.fromJson(
        input is Map
            ? Map<String, dynamic>.from(input)
            : const <String, dynamic>{},
      ),
      hasMore: json['has_more'] == true,
      nextBefore: json['next_before'] as String?,
    );
  }

  final String otherUserId;
  final String displayName;
  final String? presetAvatarSlug;
  final bool? isActive;
  final int unreadCount;

  /// Orden **cronológico ascendente**, como los devuelve el backend.
  final List<Message> messages;

  final MessageInputState input;
  final bool hasMore;

  /// Cursor de la siguiente página. Sale de la **fila cruda** más antigua y no del mensaje
  /// proyectado más antiguo: la proyección descarta filas (`RN-27`, `RN-28`) y un cursor sacado de
  /// la lista ya filtrada saltaría por encima de ellas. Se reenvía tal cual, sin reinterpretarlo.
  final String? nextBefore;
}
