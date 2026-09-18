import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';

/// Bloque de sección con título, acción opcional a la derecha ("Ver todas",
/// "Ajustes avanzados"...) y contenido — patrón repetido en
/// `08-profile.jpeg` para Insignias y Estadísticas.
class ProfileSectionCard extends StatelessWidget {
  const ProfileSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailingLabel,
    this.onTrailingTap,
  });

  final String title;
  final Widget child;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: context.palette.shadowSoft,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              if (trailingLabel != null)
                Semantics(
                  button: onTrailingTap != null,
                  label: trailingLabel,
                  child: InkWell(
                    onTap: onTrailingTap,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        trailingLabel!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: context.palette.brandStrong,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
