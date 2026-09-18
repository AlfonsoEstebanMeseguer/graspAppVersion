import 'package:flutter/foundation.dart';

/// Una insignia del catálogo (`badges`), con si el usuario la ha ganado o no
/// (`user_badges`).
///
/// `earned` decide cómo se pinta en el grid de "Ver todas" de
/// `08-profile.jpeg`: en color si es `true`, en gris si es `false`. La fila de
/// insignias resumida solo muestra las ganadas.
@immutable
class ProfileBadge {
  const ProfileBadge({
    required this.slug,
    required this.name,
    required this.description,
    required this.icon,
    required this.earned,
  });

  final String slug;
  final String name;
  final String? description;

  /// Nombre de icono tal y como lo guarda `badges.icon` (p. ej.
  /// `"local_fire_department"`). Se resuelve a `IconData` en presentación —
  /// ver `features/profile/presentation/widgets/profile_badge_icons.dart`.
  final String? icon;
  final bool earned;
}