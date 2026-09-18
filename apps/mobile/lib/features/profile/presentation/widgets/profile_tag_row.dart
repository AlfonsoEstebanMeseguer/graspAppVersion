import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/profile_repository.dart';
import '../../../../domain/social/social_failure.dart';
import '../../application/profile_controller.dart';

/// El tag del §6.2 en el perfil propio: se ve, se copia y **se puede cambiar**.
///
/// ## El botón de copiar no es un adorno
///
/// El §6.2 dice que teclear el tag a mano es **la única forma de encontrar a alguien**. Un
/// identificador que hay que transcribir carácter a carácter desde la pantalla de un móvil y que no
/// se puede copiar es un identificador roto: por eso el alfabeto es Crockford base32 (sin I/L/O/U,
/// para que nadie confunda 0 con O) *y* por eso hay botón de copiar.
///
/// ## Y el de cambiarlo tampoco, aunque el plan no lo pidiera
///
/// `profile-tag-rotate` llevaba desde la Tarea 7 construido, contratado y probado — **y sin que
/// ninguna pantalla lo llamara**. El §6.2 promete que el usuario «puede solicitar un nuevo tag» y la
/// decisión 5 dice «se implementa la rotación con tope de 1 cada 24 h». Un mecanismo sin puerta de
/// entrada no existe (principio general de `CLAUDE.md`), así que la puerta va aquí.
///
/// **Lo que el modal está obligado a decir** es que el tag actual dejará de funcionar: quien lo
/// tuviera apuntado deja de poder encontrar a esta persona. Sin esa frase, «cambiar tag» parece
/// gratis y no lo es.
class ProfileTagRow extends ConsumerWidget {
  const ProfileTagRow({super.key, required this.tag});

  static const Key copyKey = Key('profile-tag-copy');
  static const Key rotateKey = Key('profile-tag-rotate');
  static const Key rotateConfirmKey = Key('profile-tag-rotate-confirm');
  static const Key cancelKey = Key('profile-tag-rotate-cancel');

  static const String rotateTitle = 'Cambiar tu tag';

  /// El aviso completo. **La frase de que el tag actual dejará de funcionar es el requisito**, no
  /// el adorno: es lo único que le da a la persona la información para decidir.
  static const String rotateWarning =
      'Tu tag actual dejará de funcionar: quien lo tenga apuntado ya no podrá '
      'encontrarte con él. El nuevo lo elige Grasp, no tú, y solo puedes '
      'cambiarlo una vez cada 24 horas.';

  static const String copied = 'Tag copiado';

  /// `null` mientras el trigger de alta no lo haya acuñado.
  final String? tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String? actual = tag;

    if (actual == null || actual.isEmpty) {
      // Sin tag no hay nada que copiar ni que rotar: dos botones que no pueden funcionar.
      return Text(
        'Tu tag se está preparando.',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(color: context.palette.textMuted),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            actual,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: context.palette.brandStrong,
              fontWeight: FontWeight.w700,
              // Cifras y letras de ancho fijo: un identificador que se transcribe a mano se lee
              // mejor monoespaciado, y evita confundir caracteres parecidos al copiarlo a ojo.
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          key: copyKey,
          icon: const Icon(Icons.copy_rounded, size: 18),
          tooltip: 'Copiar tu tag',
          visualDensity: VisualDensity.compact,
          onPressed: () => _copiar(context, actual),
        ),
        TextButton(
          key: rotateKey,
          onPressed: () => _confirmarRotacion(context, ref),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: context.palette.textMuted,
          ),
          child: const Text('Cambiar'),
        ),
      ],
    );
  }

  Future<void> _copiar(BuildContext context, String valor) async {
    await Clipboard.setData(ClipboardData(text: valor));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(copied)));
  }

  Future<void> _confirmarRotacion(BuildContext context, WidgetRef ref) async {
    final bool? si = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        backgroundColor: context.palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        ),
        title: const Text(rotateTitle),
        content: const Text(rotateWarning),
        actions: <Widget>[
          TextButton(
            key: cancelKey,
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: rotateConfirmKey,
            onPressed: () => Navigator.of(dialog).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.brandStrong,
              foregroundColor: context.palette.onBrand,
            ),
            child: const Text('Cambiar tag'),
          ),
        ],
      ),
    );

    if (si != true || !context.mounted) return;

    try {
      final TagRotation rotation = await ref
          .read(profileControllerProvider.notifier)
          .rotateTag();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Tu tag ahora es ${rotation.tag}')));
    } on Object catch (error) {
      if (!context.mounted) return;
      // `SocialFailure` ya trae el texto en castellano — y el del tope de 24 h viene **retraducido**
      // por `SupabaseProfileRepository`, porque el código `rate_limited` lo comparte con
      // `follow-toggle` y el mapeador compartido lo cuenta como solicitudes de seguimiento.
      final String texto = error is SocialFailure
          ? error.message
          : 'No se pudo cambiar tu tag. Inténtalo de nuevo.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(texto)));
    }
  }
}
