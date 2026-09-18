import 'package:flutter/foundation.dart';

import '../profile/avatar_type.dart';

/// En qué punto está la relación de seguimiento **con la persona que se está mirando**.
///
/// Los tres valores son los tres botones del §6.2: `Seguir` / `Pendiente` / `Siguiendo`. Los emite
/// `connect-tag-lookup` como `follow_state` y `follow-toggle` como `status`.
///
/// **No hay `rejected`**, y es la forma de `user_follows`: rechazar (`RN-16`) **borra la fila**,
/// porque un seguimiento rechazado se puede volver a solicitar sin dejar rastro — a diferencia de
/// una solicitud de mensaje, que es terminal.
enum FollowState {
  /// Sin relación. El botón dice `Seguir`.
  none('none'),

  /// Solicitud enviada y sin decidir. El botón dice `Pendiente` y va deshabilitado.
  pending('pending'),

  /// Aceptada. El botón dice `Siguiendo`.
  following('following');

  const FollowState(this.wireValue);

  /// El literal que viaja en el JSON. Ver [fromWire] para el segundo literal que significa lo
  /// mismo que [following].
  final String wireValue;

  /// **EL BACKEND USA DOS PALABRAS PARA ESTO, Y LAS DOS LLEGAN AL CLIENTE.**
  ///
  /// * `follow-toggle` devuelve `status: "accepted"` — el valor **de la columna**
  ///   `user_follows.status`, tal cual.
  /// * `connect-tag-lookup` devuelve `follow_state: "following"` — ya traducido a lenguaje de
  ///   botón por `_shared/connect-lookup.ts`.
  ///
  /// Los dos describen la misma relación. Reconocer solo uno hacía que el otro cayera al `default`
  /// y **acabara en [none] sin dar ningún error**: tras aceptar una solicitud, el botón volvía a
  /// decir `Seguir`. No lo detectó ningún test unitario —los dos lados parecían coherentes por
  /// separado— sino el humo de integración de `tool/integration/`, llamando a las dos funciones de
  /// verdad.
  ///
  /// Ante un valor desconocido cae a [none], que es el estado **menos afirmativo**: enseñar
  /// `Seguir` de más es recuperable —la llamada será un no-op por forma— y enseñar `Siguiendo` de
  /// más miente sobre una relación que quizá no existe.
  static FollowState fromWire(String? value) {
    // El alias, primero y explícito, para que se vea que no es un descuido.
    if (value == 'accepted') return FollowState.following;
    for (final FollowState state in FollowState.values) {
      if (state.wireValue == value) return state;
    }
    return FollowState.none;
  }
}

/// Las cinco acciones de `follow-toggle`.
///
/// Ninguna de las cinco es bloquear ni desbloquear, y tampoco `reject` significa bloquear: son
/// cosas distintas. Ver `ModerationRepository`, que desde el ADR 0027 sí tiene `unblock`, pero
/// como método aparte — no entra aquí.
enum FollowAction {
  /// Solicitar seguir a alguien. Cuenta para el tope de `RN-20` (20 en 24 h).
  request('request'),

  /// Aceptar una solicitud recibida. `pending` → `accepted` en la **misma dirección** (`RN-13`), y
  /// reanuda la conversación `ignored` que hubiera iniciado el aceptado (`RN-17`).
  accept('accept'),

  /// Rechazar una recibida: **borra la fila** (`RN-16`).
  reject('reject'),

  /// Dejar de seguir. No toca ninguna conversación (`RN-15`).
  unfollow('unfollow'),

  /// Quitarse a alguien de encima como seguidor.
  removeFollower('remove_follower');

  const FollowAction(this.wireValue);

  final String wireValue;
}

/// La ficha pública mínima de otra persona dentro de una lista social.
///
/// Solo lleva columnas que `authenticated` puede leer de `profiles` — comprobado contra
/// `information_schema.column_privileges`, no deducido de las migraciones (`rls-security`,
/// punto 11). **Ninguna de ellas es dato del Art. 9 RGPD.**
@immutable
class SocialProfileRef {
  const SocialProfileRef({
    required this.userId,
    required this.displayName,
    this.tag,
    this.presetAvatar,
    this.photoPath,
  });

  factory SocialProfileRef.fromJson(Map<String, dynamic> json) =>
      SocialProfileRef(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String? ?? '',
        tag: json['tag'] as String?,
        presetAvatar: AvatarType.fromSlug(json['preset_avatar'] as String?),
        photoPath: json['photo_path'] as String?,
      );

  final String userId;
  final String displayName;

  /// `alfon#K7M2QX9F`. Permanente salvo rotación explícita (§13).
  final String? tag;

  final AvatarType? presetAvatar;

  /// **La clave del objeto en R2, no una URL** (invariante de `media-storage`). La URL la firma
  /// `profile-photo-view-url` y caduca en 300 s, así que esto sirve para saber si hay foto y como
  /// `cacheKey`, nunca para pintar directamente.
  final String? photoPath;

  bool get hasPhoto => photoPath != null;

  @override
  bool operator ==(Object other) =>
      other is SocialProfileRef &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.tag == tag &&
      other.presetAvatar == presetAvatar &&
      other.photoPath == photoPath;

  @override
  int get hashCode =>
      Object.hash(userId, displayName, tag, presetAvatar, photoPath);
}

/// Una relación de seguimiento **ya aceptada**: una fila de «Seguidores» o de «Siguiendo».
///
/// Se lee por PostgREST directo sobre `user_follows` con el perfil incrustado — que es para lo que
/// las dos claves ajenas apuntan a `profiles`. La policy `user_follows_read_own_or_accepted` ya
/// decide qué filas se ven; el `grant select` de tabla decide que se puedan leer.
@immutable
class FollowEdge {
  const FollowEdge({
    required this.profile,
    required this.status,
    required this.createdAt,
  });

  final SocialProfileRef profile;
  final FollowState status;

  /// Ordena la lista (§8 de `08-profile.jpeg`).
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is FollowEdge &&
      other.profile == profile &&
      other.status == status &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(profile, status, createdAt);
}

/// Una solicitud de seguimiento **recibida** y sin decidir.
///
/// Va en un tipo aparte de [FollowEdge] a propósito: las acciones que admite son otras (`accept` /
/// `reject`, no `unfollow`), y mezclarlas en un solo modelo con un booleano invita a ofrecer la
/// acción equivocada. Es la misma razón por la que [FollowState] no tiene `rejected`.
@immutable
class FollowRequest {
  const FollowRequest({required this.profile, required this.createdAt});

  final SocialProfileRef profile;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is FollowRequest &&
      other.profile == profile &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(profile, createdAt);
}

/// El resultado de una llamada a `follow-toggle`.
@immutable
class FollowToggleResult {
  const FollowToggleResult({
    required this.action,
    required this.status,
    required this.conversationResumed,
  });

  factory FollowToggleResult.fromJson(Map<String, dynamic> json) =>
      FollowToggleResult(
        action: json['action'] as String? ?? '',
        status: FollowState.fromWire(json['status'] as String?),
        conversationResumed: json['conversation_resumed'] == true,
      );

  final String action;
  final FollowState status;

  /// Solo llega en `accept`: se reanudó la conversación `ignored` que había iniciado la persona
  /// aceptada (`RN-17`). La pantalla la usa para refrescar la bandeja.
  final bool conversationResumed;
}
