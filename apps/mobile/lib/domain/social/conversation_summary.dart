import 'package:flutter/foundation.dart';

import '../profile/avatar_type.dart';

/// Una fila de la bandeja de mensajes (§8), **ya proyectada por el backend para quien mira**.
///
/// ## Lo que este modelo NO tiene, y por qué
///
/// `conversations` no concede **ni un `grant`** a `authenticated`: las dos bandejas las sirve
/// `messaging-inbox` con `service_role` y `_shared/messaging-view.ts` decide qué ve cada uno. De
/// ahí salen tres ausencias que no son olvidos:
///
///   * **`status`** — una conversación `ignored` tiene que verse *exactamente igual* que una
///     `pending` para quien la inició (`RN-06`). El backend no lo emite; este modelo tampoco lo
///     tiene, así que no hay campo donde pudiera colarse.
///   * **`initiatorId`** — lo que la pantalla necesita es [pendingAcceptance], ya derivado.
///   * **cualquier cosa parecida a `readAt`** — `RN-31` y el
///     [ADR 0021](../../../../docs/decisions/0021-mensajeria-sin-confirmacion-de-lectura.md)
///     prohíben la confirmación de lectura. No hay columna, no hay campo, y un test recorre el
///     fichero para que no vuelva.
///
/// El `sender_id` del último mensaje tampoco viaja: el «Tú: » del §8.2 llega como
/// [LastMessagePreview.fromMe].
@immutable
class ConversationSummary {
  const ConversationSummary({
    required this.conversationId,
    required this.otherUserId,
    required this.displayName,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.pendingAcceptance,
    this.presetAvatar,
    this.lastMessage,
    this.isActive,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final Object? last = json['last_message'];
    return ConversationSummary(
      conversationId: json['conversation_id'] as String,
      otherUserId: json['other_user_id'] as String,
      displayName: json['display_name'] as String? ?? '',
      presetAvatar: AvatarType.fromSlug(json['preset_avatar'] as String?),
      lastMessageAt: DateTime.parse(json['last_message_at'] as String).toLocal(),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      pendingAcceptance: json['pending_acceptance'] == true,
      lastMessage: last is Map
          ? LastMessagePreview.fromJson(Map<String, dynamic>.from(last))
          : null,
      // `containsKey` y no `?? false`: la diferencia entre «offline» y «esta lista no lo trae» es
      // justo lo que sostiene RN-30. Ver el doc de [isActive].
      isActive: json.containsKey('is_active') ? json['is_active'] == true : null,
    );
  }

  final String conversationId;
  final String otherUserId;
  final String displayName;
  final AvatarType? presetAvatar;
  final DateTime lastMessageAt;

  /// **El propio, y solo el propio** (`RN-31`). Vive en `conversation_states`, una fila por
  /// usuario: el del otro no se consulta ni se deriva porque no hay forma de pedirlo.
  final int unreadCount;

  /// El «Pendiente de aceptación» del §8.2. Deriva del estado **sin revelarlo**: vale `true` tanto
  /// para una `pending` como para una `ignored` iniciada por uno mismo, que es la mitad de `RN-06`
  /// que sostiene la ilusión.
  final bool pendingAcceptance;

  /// `null` si no hay ninguno visible: puede no haber mensajes, o el último puede estar borrado
  /// «para mí» (`RN-28`) o ser anterior a mi `cleared_at` (`RN-27`). El backend ya lo filtró.
  final LastMessagePreview? lastMessage;

  /// El punto de actividad — **`null` significa «esta lista no lo trae»**, no «está desconectado».
  ///
  /// `RN-30`: el punto aparece en **Contactos** y no en **Solicitudes**, y por eso el JSON de
  /// `requests` **omite la clave** en vez de mandarla a `false`. Si esto fuera un `bool` con
  /// defecto `false`, una fila de Solicitudes sería indistinguible de un contacto desconectado y
  /// nada impediría pintarle un punto gris.
  ///
  /// La pantalla pinta punto **solo** con `isActive == true`.
  final bool? isActive;

  @override
  bool operator ==(Object other) =>
      other is ConversationSummary &&
      other.conversationId == conversationId &&
      other.otherUserId == otherUserId &&
      other.displayName == displayName &&
      other.presetAvatar == presetAvatar &&
      other.lastMessageAt == lastMessageAt &&
      other.unreadCount == unreadCount &&
      other.pendingAcceptance == pendingAcceptance &&
      other.lastMessage == lastMessage &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(
    conversationId,
    otherUserId,
    displayName,
    presetAvatar,
    lastMessageAt,
    unreadCount,
    pendingAcceptance,
    lastMessage,
    isActive,
  );
}

/// El último mensaje de una conversación, tal y como lo ve quien mira la bandeja.
@immutable
class LastMessagePreview {
  const LastMessagePreview({
    required this.content,
    required this.fromMe,
    required this.createdAt,
    required this.deletedForAll,
  });

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) =>
      LastMessagePreview(
        content: json['content'] as String?,
        fromMe: json['from_me'] == true,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        deletedForAll: json['deleted_for_all'] == true,
      );

  /// `null` cuando [deletedForAll] es `true`: la lápida viaja **sin texto** aunque la fila lo
  /// tuviera, para que un cliente que ignorase la bandera no pudiera pintarlo igual (`RN-28`).
  final String? content;

  /// El «Tú: » del §8.2, sin exponer el `sender_id`.
  final bool fromMe;

  final DateTime createdAt;
  final bool deletedForAll;

  @override
  bool operator ==(Object other) =>
      other is LastMessagePreview &&
      other.content == content &&
      other.fromMe == fromMe &&
      other.createdAt == createdAt &&
      other.deletedForAll == deletedForAll;

  @override
  int get hashCode => Object.hash(content, fromMe, createdAt, deletedForAll);
}

/// Las dos bandejas del §8 en una sola respuesta de `messaging-inbox`.
@immutable
class InboxSnapshot {
  const InboxSnapshot({
    required this.contacts,
    required this.requests,
    required this.requestsCount,
  });

  factory InboxSnapshot.fromJson(Map<String, dynamic> json) {
    List<ConversationSummary> parse(String key) =>
        ((json[key] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (Map<dynamic, dynamic> row) =>
                  ConversationSummary.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(growable: false);

    return InboxSnapshot(
      contacts: parse('contacts'),
      requests: parse('requests'),
      requestsCount: (json['requests_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// `accepted` + las `pending` **iniciadas por uno mismo** (`RN-02`), de más reciente a más
  /// antigua (`RN-29`).
  final List<ConversationSummary> contacts;

  /// Las `pending` **recibidas** (`RN-03`). Sus filas no traen [ConversationSummary.isActive].
  final List<ConversationSummary> requests;

  /// El `N` de la píldora «Solicitudes (N)», que el §8.1 **solo enseña con N > 0**.
  final int requestsCount;
}
