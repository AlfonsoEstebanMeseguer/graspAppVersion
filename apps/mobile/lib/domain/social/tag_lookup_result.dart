import 'package:flutter/foundation.dart';

import '../profile/avatar_type.dart';
import 'follow_edge.dart';

/// La ficha que devuelve `connect-tag-lookup` al buscar un tag exacto (§6.2).
///
/// ## Los cuatro desenlaces, y por qué dos son el mismo
///
/// | Caso | Respuesta |
/// |---|---|
/// | No existe | `404` |
/// | **Bloqueo en cualquier dirección** | `404` — **mismo cuerpo y mismo código** |
/// | Tu propio tag | `422 own_tag` |
/// | Existe | `200` con esta ficha |
///
/// El cliente **no puede distinguir** los dos primeros, y es deliberado (`RN-23`): la pantalla
/// pinta «No existe ningún usuario con ese tag» con **el mismo widget** en los dos casos, sin rama
/// propia — una rama distinta acaba divergiendo en un detalle visible.
///
/// **Lo que no se promete:** las dos respuestas son idénticas en cuerpo y código, **no en tiempo**.
/// Un bloqueo hace una consulta más, así que son distinguibles por latencia. **No es deuda
/// pendiente**: el ADR 0028 (2026-08-30) decide no cerrarlo, porque el tiempo constante artificial
/// no compra nada mientras siga abierto el oráculo activo —intentar escribir y ver que falla—.
@immutable
class TagLookupResult {
  const TagLookupResult({
    required this.userId,
    required this.displayName,
    required this.tag,
    required this.hasPhoto,
    required this.followState,
    required this.timeHelpingSeconds,
    required this.streakDays,
    this.bio,
    this.presetAvatar,
  });

  factory TagLookupResult.fromJson(Map<String, dynamic> json) =>
      TagLookupResult(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        bio: json['bio'] as String?,
        presetAvatar: AvatarType.fromSlug(json['preset_avatar'] as String?),
        hasPhoto: json['has_photo'] == true,
        followState: FollowState.fromWire(json['follow_state'] as String?),
        timeHelpingSeconds:
            (json['time_helping_seconds'] as num?)?.toInt() ?? 0,
        streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String displayName;
  final String tag;
  final String? bio;
  final AvatarType? presetAvatar;
  final bool hasPhoto;

  /// Cuál de los tres botones del §6.2 se pinta: `Seguir`, `Pendiente` o `Siguiendo`.
  final FollowState followState;

  final int timeHelpingSeconds;
  final int streakDays;

  @override
  bool operator ==(Object other) =>
      other is TagLookupResult &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.tag == tag &&
      other.bio == bio &&
      other.presetAvatar == presetAvatar &&
      other.hasPhoto == hasPhoto &&
      other.followState == followState &&
      other.timeHelpingSeconds == timeHelpingSeconds &&
      other.streakDays == streakDays;

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    tag,
    bio,
    presetAvatar,
    hasPhoto,
    followState,
    timeHelpingSeconds,
    streakDays,
  );
}
