import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../domain/social/blocked_user.dart';
import '../application/blocked_users_controller.dart';
import 'widgets/social_person_row.dart';

/// Perfil → Privacidad → **Usuarios bloqueados** (ADR 0027, punto 3 de `pending-messaging`).
///
/// ## Por qué existe esta pantalla y no solo el endpoint
///
/// La lista vive en la base desde el 2026-08-23 y su dueño siempre pudo leerla. Durante cinco días
/// **nada la pintó**, que es el mismo fallo que ya costó `account-delete`: un mecanismo sin puerta
/// de entrada no existe, por bien construido que esté.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  static const String title = 'Usuarios bloqueados';

  static const String empty = 'No has bloqueado a nadie.';
  static const String emptyHelp =
      'Cuando bloquees a alguien aparecerá aquí, y podrás deshacerlo.';
  static const String loadError =
      'No se pudo cargar la lista. Desliza hacia abajo para reintentar.';
  static const String unblockFailed =
      'No se pudo desbloquear. Inténtalo de nuevo.';

  static const String unblockLabel = 'Desbloquear';

  /// El texto **es el requisito**: el ADR 0027 obliga a decir lo que el desbloqueo revela, porque
  /// es la única información con la que quien desbloquea decide.
  static String confirmBody(String nombre) =>
      'Volveréis a poder escribiros y $nombre podrá encontrarte otra vez en Grasp. '
      'Puede deducir que la habías bloqueado.';

  static String confirmTitle(String nombre) => '¿Desbloquear a $nombre?';

  static const Key confirmKey = Key('blocked-users-confirm');
  static const Key cancelKey = Key('blocked-users-cancel');

  /// La acción de la fila de [userId]. Se indexa por id y **no por posición**: la lista se acorta
  /// al desbloquear, así que una clave por índice apuntaría a otra persona.
  static Key actionKeyFor(String userId) => Key('blocked-users-action-$userId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BlockedUsersView> vista = ref.watch(
      blockedUsersControllerProvider,
    );

    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(title: const Text(title), centerTitle: true),
      body: SafeArea(
        top: false,
        child: vista.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // El error va SEPARADO del vacío a propósito: confundirlos le diría a alguien que no
          // bloqueó a nadie cuando lo que pasó es que falló la consulta.
          error: (Object error, StackTrace _) => const _Centrado(text: loadError),
          data: (BlockedUsersView view) => view.users.isEmpty
              ? const _Centrado(text: empty, help: emptyHelp)
              : RefreshIndicator(
                  color: context.palette.brandStrong,
                  onRefresh: () =>
                      ref.refresh(blockedUsersControllerProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.gutter),
                    itemCount: view.users.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (BuildContext context, int i) {
                      final BlockedUser u = view.users[i];
                      return SocialPersonRow(
                        profile: u.profile,
                        photoUrl: view.photoUrls[u.profile.userId],
                        trailing: TextButton(
                          key: actionKeyFor(u.profile.userId),
                          onPressed: () => _confirmar(context, ref, u),
                          child: const Text(unblockLabel),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _confirmar(
    BuildContext context,
    WidgetRef ref,
    BlockedUser u,
  ) async {
    final String nombre = u.profile.displayName;
    final bool? sigue = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(confirmTitle(nombre)),
        content: Text(confirmBody(nombre)),
        actions: <Widget>[
          TextButton(
            key: cancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(unblockLabel),
          ),
        ],
      ),
    );

    if (sigue != true) return;

    try {
      await ref
          .read(blockedUsersControllerProvider.notifier)
          .unblock(u.profile.userId);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(unblockFailed)));
    }
  }
}

class _Centrado extends StatelessWidget {
  const _Centrado({required this.text, this.help});

  final String text;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (help != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                help!,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.palette.textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
