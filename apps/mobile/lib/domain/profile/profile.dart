import 'package:flutter/foundation.dart';

import 'avatar_type.dart';
import 'profile_badge.dart';

/// Perfil de un usuario, tal y como lo pinta `08-profile.jpeg`.
///
/// **Todos los campos numéricos tienen columna real** desde el baseline de
/// Bloque 1 (`profiles.level`/`xp`/`time_helping_seconds`/`streak_days`/
/// `followers_count`/`following_count`) o la migración de Bloque 2
/// (`profiles.rooms_joined_count`) — a diferencia de la nota que llevaba esta
/// clase antes ("badges_count/experiences_count no tienen columna"): esas dos
/// columnas se crearon y se **revirtieron** en la misma auditoría de Bloque 2
/// (eran estado duplicado y falsificable por el cliente, ver la migración
/// `20260809120000_...`), así que no vuelven aquí. Insignias reales viven en
/// [badges], leídas de `user_badges`/`badges` (RLS de lectura pública).
///
/// [interests] y [privateAnswers] sí tienen backend real hoy:
/// `onboarding_responses.responses` (jsonb, solo legible por el propio
/// usuario) — no hace falta ninguna tabla adicional, la política
/// `onboarding_responses_select_own` ya lo permite.
///
/// [photoPath] y [presetAvatar] son excluyentes por el `check`
/// `profiles_avatar_exclusive` (`20260813090000`): quien elige un dibujo deja de
/// tener foto y al revés. La columna legacy `profiles.photo_url` sigue existiendo
/// en Postgres pero **no la escribe nadie**, así que esta clase no la lee.
@immutable
class Profile {
  const Profile({
    required this.userId,
    this.displayName,
    this.photoPath,
    this.presetAvatar,
    this.age,
    this.birthDate,
    this.gender,
    this.country,
    this.level = 1,
    this.xp = 0,
    this.streakDays = 0,
    this.roomsJoinedCount = 0,
    this.timeHelpingSeconds = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.badges = const <ProfileBadge>[],
    this.interests = const <String>[],
    this.privateAnswers = const <String, String>{},
    this.tag,
    this.bio,
    this.hideActivityStatus = false,
  });

  final String userId;
  final String? displayName;

  /// El identificador tecleable del §6.2 — `alfon#K7M2QX9F`.
  ///
  /// **Lo acuña siempre el servidor y el usuario no lo elige** (`RN-11`, decisión 5). Por eso
  /// `authenticated` tiene `select` sobre esta columna pero **no `update`** —comprobado contra
  /// `information_schema.column_privileges`—, y el único camino para cambiarlo es
  /// `profile-tag-rotate`, con su tope de una rotación cada 24 h.
  ///
  /// `null` mientras el trigger de alta no lo haya acuñado.
  final String? tag;

  /// La biografía del §6.4, máximo 160 caracteres.
  ///
  /// El tope **no lo guarda el contador de la UI**: lo guarda `profiles_bio_length_chk` en la base
  /// (1-160 sobre el texto recortado). El contador es cortesía; la constraint es la regla, y por eso
  /// da igual por qué camino nazca la fila (invariante de `db-schema`, punto 4d).
  final String? bio;

  /// `RN-32`/`RN-54`: ocultar el punto de actividad a los demás.
  ///
  /// Vive en `profiles_private`, no en `profiles`: es un ajuste de privacidad y nadie más que su
  /// dueño tiene por qué saber que está puesto. Los RPC de actividad ya lo respetan, así que esto
  /// es solo el reflejo local de lo que la base ya aplica.
  final bool hideActivityStatus;

  /// Clave del objeto en R2 (`avatars/<user_id>/<uuid>.webp`), **no una URL**:
  /// la URL la firma `profile-photo-view-url` y caduca en 5 minutos. Se guarda
  /// para saber si hay foto subida y como `cacheKey` de la imagen.
  final String? photoPath;

  /// Avatar predeterminado elegido, resuelto desde `profiles.preset_avatar`.
  /// `null` si no eligió ninguno **o** si el backend mandó un slug que esta
  /// versión de la app no conoce.
  final AvatarType? presetAvatar;

  final int? age;

  /// `profiles_private.birth_date` sin transformar — hace falta para
  /// pintar "25 de agosto" (sin año) y como valor inicial del selector de
  /// fecha en la hoja de edición. [age] sigue siendo el derivado que ya
  /// consumía el resto de la UI.
  final DateTime? birthDate;
  final String? gender;
  final String? country;

  final int level;
  final int xp;
  final int streakDays;
  final int roomsJoinedCount;
  final int timeHelpingSeconds;
  final int followersCount;
  final int followingCount;

  /// Catálogo completo de `badges`, con [ProfileBadge.earned] marcado desde
  /// `user_badges`. Vacío mientras carga, nunca `null`.
  final List<ProfileBadge> badges;

  /// Slugs de `categories` elegidos como temas de interés en el onboarding
  /// (pregunta 4). Vienen de `onboarding_responses.responses['interests']`.
  final List<String> interests;

  /// Resto de respuestas del onboarding que son de solo lectura aquí
  /// (`situation`, `profile`, `discovery`): un slug cada una. Nunca se
  /// muestran a terceros — esta clase solo representa el perfil *propio*.
  final Map<String, String> privateAnswers;

  int get earnedBadgesCount => badges.where((ProfileBadge b) => b.earned).length;

  Profile copyWith({
    String? displayName,
    int? age,
    DateTime? birthDate,
    String? gender,
    String? country,
    String? tag,
    String? bio,
    bool? hideActivityStatus,
    // Sin esto, `bio: null` significa «no lo toques» y **borrar la biografía sería
    // irrepresentable**: el `??` de abajo conservaría siempre la anterior. Es la misma forma que
    // `limpiarTarget` en `ConversationView`.
    bool limpiarBio = false,
  }) => Profile(
    userId: userId,
    displayName: displayName ?? this.displayName,
    photoPath: photoPath,
    presetAvatar: presetAvatar,
    age: age ?? this.age,
    birthDate: birthDate ?? this.birthDate,
    gender: gender ?? this.gender,
    country: country ?? this.country,
    level: level,
    xp: xp,
    streakDays: streakDays,
    roomsJoinedCount: roomsJoinedCount,
    timeHelpingSeconds: timeHelpingSeconds,
    followersCount: followersCount,
    followingCount: followingCount,
    badges: badges,
    interests: interests,
    privateAnswers: privateAnswers,
    tag: tag ?? this.tag,
    bio: limpiarBio ? null : (bio ?? this.bio),
    hideActivityStatus: hideActivityStatus ?? this.hideActivityStatus,
  );
}