import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/avatar_type.dart';
import '../../../../domain/profile/profile.dart';
import '../../application/avatar_url_provider.dart';

/// Cómo se recorta el avatar.
///
/// El círculo es la forma del perfil. El cuadrado es para el visor: la foto se sube recortada a un
/// cuadrado, así que el círculo **esconde las esquinas** — al ampliarla se quiere ver todo lo que
/// se subió, no otra vez el mismo recorte.
enum AvatarShape { circle, rounded }

/// Pinta el avatar de alguien, con las tres ramas que puede tener.
///
/// La precedencia no es arbitraria, la impone la base de datos: `profiles_avatar_exclusive`
/// garantiza que `photo_path` y `preset_avatar` **nunca** están los dos informados, así que el
/// orden solo desempata contra el tercer caso, que es no tener ninguno:
///
///   1. `photoPath` → URL firmada (300 s), pedida a `profile-photo-view-url`.
///   2. `presetAvatar` → asset local. Los 8 predeterminados **no existen en R2**.
///   3. nada → la inicial del nombre, que es como nace todo perfil.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.size = 96,
    this.shape = AvatarShape.circle,
  });

  final Profile profile;
  final double size;
  final AvatarShape shape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String name = profile.displayName?.trim() ?? '';
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final String? photoPath = profile.photoPath;
    if (photoPath != null) {
      final AsyncValue<String?> url = ref.watch(
        avatarUrlProvider((userId: profile.userId, photoPath: photoPath)),
      );
      return url.when(
        data: (String? signed) => signed == null
            ? _Initial(initial: initial, size: size)
            : _Frame(
                size: size,
                shape: shape,
                child: Image.network(
                  signed,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  // Una URL caducada o un R2 caído no pueden dejar un hueco roto en el perfil.
                  errorBuilder: (_, _, _) =>
                      _Initial(initial: initial, size: size, shape: shape),
                ),
              ),
        loading: () => _Initial(initial: initial, size: size, shape: shape),
        // Si no se pudo firmar, se cae a la inicial en vez de enseñar un error: el avatar es
        // decoración, y romper el perfil entero por no poder pintarlo sería desproporcionado.
        error: (_, _) => _Initial(initial: initial, size: size, shape: shape),
      );
    }

    final AvatarType? preset = profile.presetAvatar;
    if (preset != null) {
      return _Frame(
        size: size,
        shape: shape,
        child: Image.asset(
          preset.assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              _Initial(initial: initial, size: size, shape: shape),
        ),
      );
    }

    return _Initial(initial: initial, size: size, shape: shape);
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.size, required this.shape, required this.child});

  final double size;
  final AvatarShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget box = SizedBox(width: size, height: size, child: child);
    return shape == AvatarShape.circle
        ? ClipOval(child: box)
        : ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: box,
          );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({
    required this.initial,
    required this.size,
    this.shape = AvatarShape.circle,
  });

  final String initial;
  final double size;
  final AvatarShape shape;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.palette.outline,
        shape: shape == AvatarShape.circle
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius: shape == AvatarShape.circle
            ? null
            : BorderRadius.circular(AppRadius.card),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: (size > 70 ? theme.textTheme.headlineLarge : theme.textTheme.titleLarge)
            ?.copyWith(color: context.palette.textPrimary),
      ),
    );
  }
}
