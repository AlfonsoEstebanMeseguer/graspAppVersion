import 'package:flutter/foundation.dart';

import '../profile/avatar_type.dart';

/// Los chips del §6.3 con los que se acota el feed de Conectar.
///
/// `Todos` (`RN-35`) **no es un valor de este enum**: es la lista vacía. Modelarlo como un chip más
/// obligaría a decidir qué significa `[all, age]`, y `RN-36` («pulsar Todos apaga el resto») se
/// convertiría en disciplina de la pantalla en vez de una propiedad del tipo.
enum ConnectFilter {
  age('age'),
  interests('interests'),
  suffered('suffered'),
  current('current');

  const ConnectFilter(this.wireValue);

  final String wireValue;
}

/// Una tarjeta del feed de Conectar (§6.4).
///
/// ## LA FRONTERA DEL ART. 9 RGPD PASA POR ESTA CLASE
///
/// `connect-feed` puntúa leyendo `onboarding_responses`, `user_experiences` y
/// `profiles_private.primary_category_id`/`secondary_categories` — el mismo catálogo de salud
/// mental— **con `service_role` y dentro de la función**. Todo eso se convierte en **un número**
/// que solo sirve para muestrear, y el número tampoco sale.
///
/// **Ni un slug, ni un id de categoría, ni el desglose por eje.** El desglose diría *qué* eje
/// coincidió, que es la categoría dicha de otra forma
/// ([ADR 0020](../../../../docs/decisions/0020-conectar-no-muestra-datos-del-articulo-9.md)).
///
/// [listenerProfile] **sí** puede estar aquí y no es una excepción a lo anterior: es una
/// preferencia de **estilo de escucha** («empático y cercano»), no una condición de salud. Lo
/// declara así `docs/api-contracts.md` en la propia respuesta de `connect-feed`.
///
/// Si alguien añade aquí un campo de categoría, el test
/// `test/domain/social/no_articulo_9_test.dart` se pone rojo.
@immutable
class ConnectCandidate {
  const ConnectCandidate({
    required this.userId,
    required this.displayName,
    required this.tag,
    required this.hasPhoto,
    required this.isActive,
    required this.timeHelpingSeconds,
    required this.streakDays,
    this.age,
    this.bio,
    this.presetAvatar,
    this.listenerProfile,
  });

  factory ConnectCandidate.fromJson(Map<String, dynamic> json) =>
      ConnectCandidate(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        age: (json['age'] as num?)?.toInt(),
        bio: json['bio'] as String?,
        presetAvatar: AvatarType.fromSlug(json['preset_avatar'] as String?),
        hasPhoto: json['has_photo'] == true,
        isActive: json['is_active'] == true,
        listenerProfile: json['listener_profile'] as String?,
        timeHelpingSeconds:
            (json['time_helping_seconds'] as num?)?.toInt() ?? 0,
        streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String displayName;
  final String tag;
  final int? age;

  /// La bio, que la tarjeta pinta a **2 líneas con elipsis** (§6.4).
  final String? bio;

  final AvatarType? presetAvatar;

  /// Si tiene foto subida. **No viene la clave de R2 ni la URL**: la firma
  /// `profile-photo-view-url` aparte, y caduca en 300 s.
  final bool hasPhoto;

  /// El punto de actividad (`RN-30`). Sale del RPC `activity_status`, que devuelve un booleano y
  /// **nunca** una marca de tiempo — ni siquiera redondeada.
  final bool isActive;

  /// Preferencia de **estilo de escucha**, no una condición. Ver el bloque de arriba.
  final String? listenerProfile;

  final int timeHelpingSeconds;
  final int streakDays;

  @override
  bool operator ==(Object other) =>
      other is ConnectCandidate &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.tag == tag &&
      other.age == age &&
      other.bio == bio &&
      other.presetAvatar == presetAvatar &&
      other.hasPhoto == hasPhoto &&
      other.isActive == isActive &&
      other.listenerProfile == listenerProfile &&
      other.timeHelpingSeconds == timeHelpingSeconds &&
      other.streakDays == streakDays;

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    tag,
    age,
    bio,
    presetAvatar,
    hasPhoto,
    isActive,
    listenerProfile,
    timeHelpingSeconds,
    streakDays,
  );
}

/// Una tanda del feed de Conectar.
@immutable
class ConnectFeedPage {
  const ConnectFeedPage({
    required this.candidates,
    required this.emptyState,
    required this.relaxed,
  });

  factory ConnectFeedPage.fromJson(Map<String, dynamic> json) =>
      ConnectFeedPage(
        candidates: ((json['candidates'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (Map<dynamic, dynamic> row) =>
                  ConnectCandidate.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(growable: false),
        emptyState: json['empty_state'] == true,
        relaxed: json['relaxed'] == true,
      );

  final List<ConnectCandidate> candidates;

  /// `RN-49`: no queda nadie a quien enseñar. **Nunca una lista vacía sin explicación** — la
  /// pantalla tiene que decir algo, y por eso esto viaja aparte de `candidates.isEmpty`.
  final bool emptyState;

  /// `RN-49`: había menos de 20 elegibles, así que se puntuó **sin el cuadrado del filtro**.
  ///
  /// Relajar el filtro cambia los **pesos**, nunca las exclusiones
  /// ([ADR 0024](../../../../docs/decisions/0024-relajar-el-filtro-de-conectar-solo-cambia-los-pesos.md)):
  /// quien está bloqueado o excluido sigue fuera.
  final bool relaxed;
}
