import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/auth/auth_failure.dart';

/// Copia en castellano de cada causa de fallo.
///
/// Vive en presentación (no en el dominio) para que traducir la app no obligue
/// a tocar la capa de negocio. Los mensajes son accionables: dicen qué hacer,
/// no solo qué ha fallado.
String authFailureMessage(AuthFailure failure) => switch (failure.kind) {
  AuthFailureKind.invalidEmail =>
    'Revisa el correo: parece que falta algo (por ejemplo, «@» o el dominio).',
  AuthFailureKind.invalidPassword =>
    'La contraseña debe tener al menos 8 caracteres.',
  AuthFailureKind.passwordMismatch =>
    'Las contraseñas no coinciden. Asegúrate de escribir la misma en ambos campos.',
  AuthFailureKind.accountNotFound =>
    'No encontramos ninguna cuenta con esos datos. ¿Quieres crear una?',
  AuthFailureKind.accountAlreadyExists =>
    'Ya existe una cuenta con esos datos. Inicia sesión en su lugar.',
  AuthFailureKind.invalidCredentials =>
    'El correo o la contraseña no son correctos. Inténtalo de nuevo.',
  AuthFailureKind.rateLimited =>
    'Demasiados intentos seguidos. Espera un momento antes de reintentarlo.',
  AuthFailureKind.signUpUnavailable =>
    'El registro no está disponible ahora mismo. No es cosa tuya: '
        'inténtalo más tarde.',
  AuthFailureKind.network =>
    'No hemos podido conectar. Comprueba tu conexión e inténtalo otra vez.',
  AuthFailureKind.unknown =>
    'Algo no ha ido bien. Inténtalo de nuevo en unos segundos.',
};

/// Banda de error dentro del formulario.
///
/// Se anuncia como `liveRegion` para que el lector de pantalla lo lea al
/// aparecer: si no, un usuario ciego pulsa "continuar" y no recibe respuesta.
class AuthFailureBanner extends StatelessWidget {
  const AuthFailureBanner({super.key, required this.failure});

  final AuthFailure? failure;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AnimatedSize(
      duration: GraspMotion.of(context).medium,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: failure == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              container: true,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md - AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: context.palette.error,
                    ),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: Text(
                        authFailureMessage(failure!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
