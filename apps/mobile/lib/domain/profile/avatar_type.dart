/// Tipos de avatar estáticos disponibles en Grasp.
///
/// Cada tipo tiene un label (en español), la ruta del asset y el **slug** con el
/// que viaja al backend. El slug NO se deriva del nombre de la constante: aquí es
/// `normalOne` (camelCase de Dart) y allí es `normal_1` (snake_case de SQL), así
/// que la correspondencia es explícita y no se puede improvisar en la pantalla.
///
/// **La autoridad de los slugs es el `check` `profiles_preset_avatar_valid`**
/// (`20260813090000_add_preset_avatar_to_profiles.sql`), no este enum. Si divergen,
/// el backend rechaza el `UPDATE` y el usuario no puede cambiar de avatar.
/// `avatar_assets_test.dart` fija el conjunto exacto para que la divergencia salte
/// aquí y no en producción.
///
/// Vive en `domain/` y no en el widget que lo pintaba porque `Profile.presetAvatar`
/// lo expone: el dominio no puede importar de presentación.
enum AvatarType {
  gym('Gym', 'assets/avatars/gym-user.png', 'gym'),
  reader('Lector', 'assets/avatars/reader-user.png', 'reader'),
  music('Música', 'assets/avatars/music-user.png', 'music'),
  coding('Coding', 'assets/avatars/coding-user.png', 'coding'),
  animal('Animal', 'assets/avatars/animal-user.png', 'animal'),
  normalOne('Normal 1', 'assets/avatars/normal-user-1.png', 'normal_1'),
  normalTwo('Normal 2', 'assets/avatars/normal-user-2.png', 'normal_2'),
  normalThree('Normal 3', 'assets/avatars/normal-user-3.png', 'normal_3');

  const AvatarType(this.label, this.assetPath, this.slug);

  /// Etiqueta descriptiva del avatar en español.
  final String label;

  /// Ruta del asset de la imagen del avatar.
  final String assetPath;

  /// Valor que se manda en `profile-avatar-set` y que guarda `profiles.preset_avatar`.
  final String slug;

  /// Resuelve el avatar que devuelve el backend en `profiles.preset_avatar`.
  ///
  /// Devuelve `null` si el slug no se reconoce, que es lo que pasaría si el backend
  /// añadiese un avatar antes que la app. Quien llame debe caer al placeholder en vez
  /// de reventar: una app vieja tiene que seguir funcionando contra un backend nuevo.
  static AvatarType? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final AvatarType avatar in AvatarType.values) {
      if (avatar.slug == slug) return avatar;
    }
    return null;
  }
}
