import 'profile.dart';

/// Contrato de lectura/edición del perfil propio.
abstract interface class ProfileRepository {
  /// Perfil del usuario autenticado: `profiles` + `profiles_private` +
  /// `onboarding_responses` (propias) + `badges`/`user_badges`.
  Future<Profile> fetchOwn();

  /// Actualiza los campos editables vía la Edge Function `profile-update`.
  /// Todos son opcionales, pero al menos uno debe venir informado — lo valida
  /// el backend, no esta capa.
  ///
  /// El avatar no está aquí: lo escribe `profile-avatar-set` (subir foto o
  /// elegir predeterminado), que es la única dueña del invariante
  /// "una cosa o la otra". `password` tampoco: requiere un flujo de
  /// verificación propio, deferido a Fase 4+.
  Future<void> updateProfile({
    String? displayName,
    DateTime? birthDate,
    String? gender,
    String? country,
  });

  /// Guarda la biografía del §6.4. `null` la borra.
  ///
  /// ## Por qué esto NO pasa por `profile-update`
  ///
  /// Porque esa función **no acepta `bio`**: mandársela es un 400 por campo desconocido, no un campo
  /// ignorado en silencio. Y no hace falta que la acepte: `authenticated` tiene `grant update (bio)`
  /// sobre `profiles` —comprobado contra `information_schema.column_privileges`, no deducido de la
  /// migración— y el tope de 160 lo impone `profiles_bio_length_chk` **en la base**, así que la regla
  /// no depende de por dónde entre la escritura (`db-schema`, punto 4d). El contador de la UI es
  /// cortesía; la constraint es la regla.
  ///
  /// `tag` no tiene un método equivalente **y no puede tenerlo**: `authenticated` no tiene `update`
  /// sobre esa columna. Ver [rotateTag].
  Future<void> updateBio(String? bio);

  /// `RN-32`/`RN-54`: ocultar el punto de actividad a los demás.
  ///
  /// Directo sobre `profiles_private` por lo mismo que [updateBio]: el `grant update
  /// (hide_activity_status)` está concedido y no hay nada que validar en un booleano. Quien lo
  /// **aplica** son los RPC de actividad, no el cliente.
  Future<void> setHideActivityStatus(bool hidden);

  /// Acuña un tag nuevo (`profile-tag-rotate`, §6.2 y decisión 5).
  ///
  /// **Sin parámetros, y ése es el punto**: «inmutable» significa que el usuario no lo *elige*, no
  /// que no se pueda cambiar (`RN-11`). Es el único camino por el que `profiles.tag` se puede
  /// escribir, porque `authenticated` no tiene `update` sobre esa columna.
  ///
  /// **No es idempotente, y es lo contrario de lo deseable**: cada llamada con éxito produce un tag
  /// distinto. Lo que impide encadenar rotaciones por un reintento accidental es el tope de una cada
  /// 24 h, que va dentro del propio `UPDATE`.
  ///
  /// Al superar el tope lanza `SocialFailure` con [SocialFailureKind.rateLimited] y **el instante de
  /// recuperación**, porque `RN-21` prohíbe el fallo mudo.
  Future<TagRotation> rotateTag();
}

/// Lo que devuelve una rotación de tag con éxito.
class TagRotation {
  const TagRotation({required this.tag, this.nextRotationAt});

  final String tag;

  /// Cuándo se podrá volver a rotar. `null` si el backend no lo mandó.
  final DateTime? nextRotationAt;
}