import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../core/ui/grasp_buttons.dart';
import '../../../../domain/account/account_deletion_failure.dart';
import '../../../auth/presentation/widgets/grasp_field.dart';
import '../../application/account_deletion_controller.dart';
import 'account_deletion_failure_message.dart';

/// Frase exacta que exige `account-delete` para confirmar el borrado.
///
/// El backend la compara normalizada (`trim().toUpperCase()`), así que el
/// cliente valida con la misma laxitud (ver [_DeleteAccountSheetState._confirmationMatches]):
/// exigir aquí una coincidencia más estricta rechazaría entradas que el
/// servidor aceptaría igual.
const String kAccountDeletionPhrase = 'BORRAR MI CUENTA';

/// Hoja modal para borrar la cuenta — hallazgo H-SV-02 de la auditoría de
/// 2026-08-15 (no había ninguna forma de borrar la cuenta desde la app).
///
/// **Por qué es una hoja y no una pantalla nueva**: `08-profile.jpeg` no
/// tiene ninguna "zona peligrosa" ni botón de borrado, y `pictures/screens/`
/// no tiene ningún boceto de esta pantalla. En vez de improvisar un diseño
/// nuevo, se reutiliza el mismo patrón que la decisión 0014 fijó para el
/// avatar por la misma razón exacta (elegir avatar tampoco tenía boceto):
/// `showModalBottomSheet` con `isScrollControlled`, `context.palette.surface` y
/// `AppRadius.sheet`, igual que `AvatarSheet` y `ProfileEditSheet`. No se
/// inventa lenguaje visual nuevo, solo se aplica el ya aprobado.
///
/// Pide **las dos** confirmaciones (contraseña + frase escrita a mano) antes
/// de habilitar el botón — nunca se dispara con una sola.
class DeleteAccountSheet extends ConsumerStatefulWidget {
  const DeleteAccountSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (BuildContext context) => const DeleteAccountSheet(),
    );
  }

  @override
  ConsumerState<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<DeleteAccountSheet> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  bool get _confirmationMatches =>
      _confirmationController.text.trim().toUpperCase() == kAccountDeletionPhrase;

  bool get _canSubmit => _passwordController.text.isNotEmpty && _confirmationMatches;

  Future<void> _submit() async {
    if (!_canSubmit) return; // defensa en profundidad: el botón ya está deshabilitado si no.

    final bool ok = await ref
        .read(accountDeletionControllerProvider.notifier)
        .deleteAccount(
          password: _passwordController.text,
          // Se manda tal cual la escribió el usuario: el backend normaliza,
          // no hace falta (ni conviene) duplicar esa normalización aquí.
          confirmationPhrase: _confirmationController.text,
        );
    // Un éxito ya cerró la sesión dentro del controller: el router redirige
    // solo al arrancar de la app (ver `app_router.dart`). Ante un fallo la
    // hoja se queda abierta para poder reintentar sin perder lo escrito.
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<void> operation = ref.watch(accountDeletionControllerProvider);
    final bool busy = operation.isLoading;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.gutter,
          right: AppSpacing.gutter,
          top: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.delete_forever_rounded, color: context.palette.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Eliminar cuenta', style: theme.textTheme.titleLarge)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const _WarningBlock(),
              const SizedBox(height: AppSpacing.md),

              if (operation.hasError) ...<Widget>[
                _ErrorBanner(error: operation.error),
                const SizedBox(height: AppSpacing.md),
              ],

              GraspPasswordField(
                label: 'Contraseña actual',
                controller: _passwordController,
                enabled: !busy,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              GraspField(
                label: 'Escribe "$kAccountDeletionPhrase" para confirmar',
                controller: _confirmationController,
                hintText: kAccountDeletionPhrase,
                enabled: !busy,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              GraspDestructiveButton(
                label: 'Eliminar cuenta definitivamente',
                isLoading: busy,
                onPressed: (_canSubmit && !busy) ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningBlock extends StatelessWidget {
  const _WarningBlock();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.containerSubtle,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Esta acción no se puede deshacer.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Bullet(
            'Se borran tu perfil, tu foto, las respuestas del onboarding, tus experiencias e '
            'insignias.',
          ),
          const SizedBox(height: AppSpacing.xs),
          const _Bullet(
            'Se conserva 90 días el registro de auditoría de las fotos que subiste: es '
            'obligación legal (Art. 6.1.c RGPD) y no se puede borrar antes.',
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('•  ', style: style),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      // El lector de pantalla lo anuncia al aparecer: si no, alguien pulsa
      // "eliminar" y no recibe ninguna respuesta perceptible.
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 20, color: context.palette.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _messageFor(error),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _messageFor(Object? error) {
    if (error is AccountDeletionFailure) return accountDeletionFailureMessage(error);
    return 'Algo no ha ido bien. Inténtalo de nuevo en unos segundos.';
  }
}
