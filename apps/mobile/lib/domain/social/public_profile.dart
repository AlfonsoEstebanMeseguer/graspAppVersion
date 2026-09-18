import 'package:flutter/foundation.dart';

import '../profile/avatar_type.dart';
import '../profile/profile_badge.dart';
import 'follow_edge.dart';

/// El perfil de **otra persona** — `RN-38` y §6.2.
///
/// ## LA FRONTERA DEL ART. 9 RGPD TAMBIÉN PASA POR AQUÍ
///
/// Igual que [ConnectCandidate], esta clase es una de las que el test
/// `test/domain/social/no_articulo_9_test.dart` escanea: **ni una categoría, ni un id de
/// categoría, ni una experiencia**. Lo que el scoring del §7 lee para puntuar se queda dentro de
/// `connect-feed`, y lo que esta ficha enseña sale de `public.public_profiles`, que **enumera sus
/// columnas una a una** justo para que nada de eso se pueda colar
/// ([ADR 0020](../../../../docs/decisions/0020-conectar-no-muestra-datos-del-articulo-9.md)).
///
/// ## Lo que NO está en esta clase, y por qué
///
/// * **`birthDate`.** Sale [age], que es el derivado; la fecha exacta identifica mucho más y se
///   queda en `profiles_private`. La vista devuelve el número, no la fecha
///   ([ADR 0026](../../../../docs/decisions/0026-la-edad-es-publica.md)).
/// * **La marca de actividad.** `RN-30` se responde con un **booleano** que viaja aparte, desde el
///   RPC `activity_status` — nunca un `DateTime`, ni redondeado. Ver `ActivityRepository`.
/// * **El estado de seguimiento.** No es un atributo de esta persona sino de **mi relación con
///   ella**: dos personas distintas miran el mismo perfil y ven botones distintos. Vive en
///   `PublicProfileView`, junto a la foto firmada y al punto de actividad, que son igual de
///   dependientes de quién mira y de cuándo.
/// * **`xp`, `vipStatus`, `reputationScore`.** El §6.2 pide el **nivel**. El resto es progreso
///   propio y estado de backend.
@immutable
class PublicProfile {
  const PublicProfile({
    required this.userId,
    required this.displayName,
    this.tag,
    this.bio,
    this.age,
    this.presetAvatar,
    this.photoPath,
    this.level = 1,
    this.streakDays = 0,
    this.timeHelpingSeconds = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.featuredBadge,
  });

  /// Desde `public.public_profiles`, que es una **vista** y no la tabla: la lista de columnas de
  /// esa vista es la autorización, así que lo que no esté ahí no puede llegar aquí.
  factory PublicProfile.fromJson(
    Map<String, dynamic> json, {
    ProfileBadge? featuredBadge,
  }) => PublicProfile(
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String? ?? '',
    tag: json['tag'] as String?,
    bio: json['bio'] as String?,
    age: (json['age'] as num?)?.toInt(),
    presetAvatar: AvatarType.fromSlug(json['preset_avatar'] as String?),
    photoPath: json['photo_path'] as String?,
    level: (json['level'] as num?)?.toInt() ?? 1,
    streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
    timeHelpingSeconds: (json['time_helping_seconds'] as num?)?.toInt() ?? 0,
    followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
    followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
    featuredBadge: featuredBadge,
  );

  final String userId;
  final String displayName;

  /// `alfon#K7M2QX9F` — el identificador tecleable del §6.2, que es **la única forma de encontrar
  /// a alguien** (`RN-11`). Por eso se pinta también en el perfil ajeno y no solo en el propio.
  final String? tag;

  final String? bio;

  /// Años cumplidos. **Pública desde el 2026-08-27** (ADR 0026): la calcula al vuelo la vista
  /// `public_profiles` desde `birth_date`, así que es correcta el día del cumpleaños y nunca se
  /// desfasa.
  ///
  /// `null` cuando esa persona no tiene fecha de nacimiento registrada. **No se pinta un cero ni
  /// un guion**: se omite la edad entera, porque «edad desconocida» y «cero años» no son lo mismo.
  final int? age;

  final AvatarType? presetAvatar;

  /// **La clave del objeto en R2, no una URL** (invariante de `media-storage`): la firma
  /// `profile-photo-view-url` y caduca en 300 s. Sirve para saber si hay foto, nunca para pintar.
  final String? photoPath;

  bool get hasPhoto => photoPath != null;

  /// El nivel del §6.2. **Va solo en esta pantalla y no en la tarjeta de Conectar** (decisión 1
  /// del plan): la tarjeta es para decidir si abrir el perfil, no para comparar a nadie.
  final int level;

  final int streakDays;
  final int timeHelpingSeconds;
  final int followersCount;
  final int followingCount;

  /// La insignia destacada: **la última ganada**, o `null` si no tiene ninguna.
  ///
  /// «Destacada» no es una columna que nadie elija —no existe tal cosa en `user_badges`— sino la
  /// más reciente por `earned_at`. Se resuelve en el repositorio y no aquí para que la pantalla no
  /// tenga que traerse el catálogo entero de insignias sólo para enseñar una.
  final ProfileBadge? featuredBadge;

  @override
  bool operator ==(Object other) =>
      other is PublicProfile &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.tag == tag &&
      other.bio == bio &&
      other.age == age &&
      other.presetAvatar == presetAvatar &&
      other.photoPath == photoPath &&
      other.level == level &&
      other.streakDays == streakDays &&
      other.timeHelpingSeconds == timeHelpingSeconds &&
      other.followersCount == followersCount &&
      other.followingCount == followingCount &&
      other.featuredBadge == featuredBadge;

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    tag,
    bio,
    age,
    presetAvatar,
    photoPath,
    level,
    streakDays,
    timeHelpingSeconds,
    followersCount,
    followingCount,
    featuredBadge,
  );
}

/// Contrato de lectura del perfil ajeno (`RN-38`, §6.2).
///
/// ## Por qué NO hay Edge Function detrás de esto
///
/// Porque no hace falta ninguna: todo lo que el §6.2 pide es legible por `authenticated` con
/// PostgREST directo —comprobado contra `information_schema.column_privileges` y `pg_policies`, no
/// deducido de las migraciones (`rls-security`, punto 11)—. `profiles` tiene
/// `profiles_read_public` con `qual = true`, `user_badges` y `badges` igual, y la edad la publica
/// la vista `public_profiles`. Inventar un endpoint habría añadido una superficie que desplegar y
/// versionar para no decidir nada que la base no decida ya.
///
/// Es el mismo criterio que `updateBio` y `setHideActivityStatus`: primero se mira qué `grant`
/// hay, y sólo se sube a una Edge Function lo que necesite `service_role` para existir.
abstract interface class PublicProfileRepository {
  /// La ficha de [userId], o `null` si no hay ninguna.
  ///
  /// **`null` no significa «no existe la cuenta»** y la pantalla no debe decir eso: significa que
  /// no hay fila que enseñar. Es deliberadamente el mismo desenlace para varias causas, como el
  /// 404 de `connect-tag-lookup` (`RN-23`).
  Future<PublicProfile?> fetch(String userId);

  /// En qué punto está **mi** relación de seguimiento con [userId] — los tres botones del §6.2.
  ///
  /// Va aparte de [fetch] porque no es un atributo de esa persona: dos personas distintas miran el
  /// mismo perfil y ven botones distintos. Se lee de `user_follows`, cuya policy
  /// `user_follows_read_own_or_accepted` ya acota qué filas se ven.
  Future<FollowState> followState(String userId);
}
