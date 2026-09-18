import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/profile.dart';
import '../../application/profile_controller.dart';
import '../blocked_users_screen.dart';
import 'profile_section_card.dart';

/// Privacidad — hoy, el ajuste de `RN-32`/`RN-54`.
///
/// ## Por qué está a la vista y no dentro de la hoja de edición
///
/// La hoja de edición trata de **quién eres** (nombre, fecha, país); esto trata de **qué ven los
/// demás**. Un ajuste de privacidad enterrado a dos toques dentro de un formulario de identidad no
/// lo encuentra nadie, y un ajuste que no se encuentra es igual de inútil que uno que no existe —
/// el mismo principio que obliga a que cada mecanismo tenga su puerta de entrada.
///
/// ## Lo que este interruptor NO hace
///
/// No esconde nada por su cuenta: quien decide si el punto verde se emite es el RPC
/// `activity_status`, que lee `profiles_private.hide_activity_status` en el servidor. Esto solo
/// escribe la columna. Si la escritura falla, **el interruptor vuelve atrás**: en un ajuste de
/// privacidad, dejarlo encendido tras un error haría creerse oculta a una persona que no lo está,
/// que es la peor forma de mentir que puede tener esta pantalla.
class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});

  static const Key hideActivityKey = Key('privacy-hide-activity');
  static const Key blockedEntryKey = Key('privacy-blocked-users');

  static const String title = 'Privacidad';
  static const String hideActivityLabel = 'Ocultar mi estado de actividad';
  static const String hideActivityHelp =
      'Nadie verá si estás en línea. Tú tampoco verás el de los demás.';

  static const String blockedLabel = 'Usuarios bloqueados';
  static const String blockedHelp =
      'Quién no puede escribirte ni encontrarte. Puedes deshacerlo.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Profile? profile = ref.watch(profileControllerProvider).valueOrNull;
    final ThemeData theme = Theme.of(context);

    return ProfileSectionCard(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(hideActivityLabel, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      hideActivityHelp,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: context.palette.textMuted,
                        // `labelSmall` de Material 3 viene en `w500`, y la etiqueta de arriba es
                        // `bodyMedium` en `w400`: sin esto, la **explicación** se pinta más gruesa
                        // que aquello que explica y la jerarquía queda del revés. Se vio en el
                        // emulador.
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Switch(
                key: hideActivityKey,
                value: profile?.hideActivityStatus ?? false,
                activeThumbColor: context.palette.onBrand,
                activeTrackColor: context.palette.brand,
                inactiveThumbColor: context.palette.surface,
                inactiveTrackColor: context.palette.outline,
                onChanged: profile == null
                    ? null
                    : (bool valor) => _guardar(context, ref, valor),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          // `ProfileSectionCard` pinta su fondo en un `Container`/`DecoratedBox`, no en un
          // `Material`: sin este envoltorio el `ListTile` no tiene dónde pintar su splash y
          // Flutter lo señala como excepción en tests (invisible en release, pero rompe la suite).
          Material(
            color: Colors.transparent,
            child: ListTile(
              key: blockedEntryKey,
              contentPadding: EdgeInsets.zero,
              title: Text(blockedLabel, style: theme.textTheme.bodyMedium),
              subtitle: Text(
                blockedHelp,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.palette.textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: context.palette.textMuted,
              ),
              // `rootNavigator: true` para que la lista se apile POR ENCIMA de la barra inferior,
              // igual que `FollowsScreen`: es un sitio del que se vuelve, no una quinta pestaña.
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const BlockedUsersScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar(BuildContext context, WidgetRef ref, bool valor) async {
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .setHideActivityStatus(valor);
    } on Object {
      if (!context.mounted) return;
      // El controlador ya restauró el estado anterior; aquí solo se cuenta lo que pasó.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar el ajuste. Inténtalo de nuevo.'),
          ),
        );
    }
  }
}
