import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../core/ui/brand_mark.dart';
import '../../../../core/ui/grasp_backdrop.dart';

/// Marco común de Login y Registro.
///
/// Mantiene el fondo de `01-Start_Menu.jpeg` —con la escena bajada de tamaño y
/// de opacidad, para que el formulario mande— más la marca pequeña, el título y
/// el botón de volver.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: GraspBackdrop(
        // La escena pasa a segundo plano: sigue estando, pero no compite con
        // el formulario.
        sceneHeightFactor: 0.30,
        sceneOpacity: 0.45,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: IconButton(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoute.start),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: context.palette.textPrimary,
                  tooltip: 'Volver',
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: AppSpacing.gutter,
                    right: AppSpacing.gutter,
                    bottom:
                        AppSpacing.xxl +
                        MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const BrandMark(size: 56),
                      const SizedBox(height: AppSpacing.lg),
                      Text(title, style: theme.textTheme.headlineLarge),
                      const SizedBox(height: AppSpacing.sm),
                      Text(subtitle, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: AppSpacing.xl),
                      child,
                    ],
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

/// Enlace de pie entre Login y Registro.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  final String question;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: Text(
            question,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
        TextButton(
          onPressed: onPressed,
          child: Text(
            action,
            style: theme.textTheme.labelMedium?.copyWith(
              color: context.palette.brandStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
