import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theming/app_motion.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../core/theming/grasp_palette.dart';
import '../../../../domain/settings/appearance_mode.dart';
import '../../application/appearance_controller.dart';

/// Sección «Apariencia»: las tres opciones de [AppearanceMode], una por fila.
///
/// ## Por qué tres filas y no un `Switch`
///
/// Un interruptor solo sabe decir sí o no, y aquí hay **tres** estados
/// —automático incluido— porque «que lo decida el teléfono» es lo que quiere
/// casi todo el mundo que programa el modo oscuro por horas. Con un interruptor
/// esa persona tendría que elegir bando y perder el cambio nocturno.
///
/// El grupo es un `radio` semántico de verdad (`Semantics(inMutuallyExclusiveGroup:
/// true, selected: ...)`), no tres botones sueltos: un lector de pantalla tiene
/// que anunciar «2 de 3, seleccionado», o el ajuste es inusable a ciegas.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  /// Clave por modo, para que los tests pulsen la fila y no un texto que
  /// mañana se reescriba.
  static Key optionKey(AppearanceMode mode) =>
      Key('appearance-option-${mode.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppearanceMode current = ref.watch(appearanceControllerProvider);
    final GraspPalette palette = context.palette;
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadowSoft,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Apariencia', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Elige cómo se ve Grasp. El cambio se aplica al momento y se '
            'recuerda en este dispositivo.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final AppearanceMode mode in AppearanceMode.values) ...<Widget>[
            _AppearanceOption(
              key: optionKey(mode),
              mode: mode,
              selected: mode == current,
              onTap: () =>
                  ref.read(appearanceControllerProvider.notifier).set(mode),
            ),
            if (mode != AppearanceMode.values.last)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _AppearanceOption extends StatelessWidget {
  const _AppearanceOption({
    super.key,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final AppearanceMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GraspPalette palette = context.palette;
    final ThemeData theme = Theme.of(context);
    final GraspMotion motion = GraspMotion.of(context);

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '${mode.label}. ${mode.description}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: AnimatedContainer(
              duration: motion.fast,
              curve: AppMotion.enter,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: selected ? palette.containerSubtle : palette.canvas,
                borderRadius: BorderRadius.circular(AppRadius.field),
                border: Border.all(
                  color: selected ? palette.brand : palette.outline,
                  width: selected ? 1.6 : 1.2,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    mode.icon,
                    size: 22,
                    color: selected ? palette.brandStrong : palette.iconSoft,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          mode.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: selected
                                ? palette.brandStrong
                                : palette.textPrimary,
                          ),
                        ),
                        Text(
                          mode.description,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // La marca de selección va **además** del borde y del color:
                  // el borde solo se distingue por tono, y quien no distingue
                  // ese tono se queda sin saber cuál está activo (WCAG 1.4.1,
                  // "el color no es el único medio").
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 22,
                      color: palette.brandStrong,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
