import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../domain/profile/avatar_type.dart';

/// La cara de **otra persona** en una lista social.
///
/// ## Por qué no se reutiliza `ProfileAvatar`
///
/// `ProfileAvatar` recibe un [Profile] entero y pide la URL firmada él mismo, cacheada por
/// `photo_path`. En la bandeja no sirve ninguna de las dos cosas:
///
///   * `messaging-inbox` **no devuelve `photo_path`** —ni la foto— así que no hay clave de caché;
///   * y aunque la hubiera, una fila por conversación pediría una firma por fila. La bandeja las
///     pide **todas de una vez** (`AvatarRepository.photoUrls`) y le pasa la URL ya resuelta a cada
///     fila.
///
/// Las tres ramas son las mismas que las de `ProfileAvatar`, y en el mismo orden:
///   1. [photoUrl] → la foto;
///   2. [presetAvatar] → asset local (los 8 predeterminados **no existen en R2**);
///   3. nada → la inicial del nombre, que es como nace todo perfil.
class SocialAvatar extends StatelessWidget {
  const SocialAvatar({
    super.key,
    required this.displayName,
    this.presetAvatar,
    this.photoUrl,
    this.size = 52,
  });

  final String displayName;
  final AvatarType? presetAvatar;

  /// URL firmada ya resuelta. **Caduca en 300 s**, así que quien la pase la tiene cacheada por su
  /// cuenta — este widget no pide nada.
  final String? photoUrl;

  final double size;

  @override
  Widget build(BuildContext context) {
    final String name = displayName.trim();
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: _content(context, initial),
      ),
    );
  }

  Widget _content(BuildContext context, String initial) {
    final String? url = photoUrl;
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        // Una firma caducada o una red caída no pueden dejar un hueco roto en la lista: se cae a
        // la inicial, que siempre se puede pintar.
        errorBuilder: (BuildContext context, Object _, StackTrace? _) =>
            _Initial(initial: initial, size: size),
      );
    }

    final AvatarType? preset = presetAvatar;
    if (preset != null) {
      return Image.asset(
        preset.assetPath,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object _, StackTrace? _) =>
            _Initial(initial: initial, size: size),
      );
    }

    return _Initial(initial: initial, size: size);
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.initial, required this.size});

  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.containerSubtle,
      child: Center(
        child: Text(
          initial,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: context.palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }
}
