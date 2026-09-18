import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_motion.dart';
import '../../../../core/theming/app_theme.dart';

/// Las dos píldoras del §8.1: **`Contactos` | `Solicitudes (N)`**.
///
/// Son literalmente las del boceto `06-messaging-inbox.jpeg` —donde decían «Todos / En el
/// escenario», que son de la pantalla de sala— con la derivación acordada el 2026-08-23 y anotada
/// en `pictures/screens/README.md`.
class InboxTabs extends StatelessWidget {
  const InboxTabs({
    super.key,
    required this.selectedIndex,
    required this.requestsCount,
    required this.onSelected,
  });

  final int selectedIndex;

  /// El `N` del §8.1. Viene de `requests_count`, **no del largo de la lista**: la bandeja topa a
  /// 100 por lista y contar las filas mentiría en cuanto alguien pasara de ahí.
  final int requestsCount;

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.canvas,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Pill(
                  label: 'Contactos',
                  selected: selectedIndex == 0,
                  onTap: () => onSelected(0),
                ),
              ),
              Expanded(
                child: _Pill(
                  // El paréntesis **solo con N > 0** (§8.1). Con un 0 dentro, la píldora diría que
                  // hay algo que atender cuando no lo hay.
                  label: requestsCount > 0
                      ? 'Solicitudes ($requestsCount)'
                      : 'Solicitudes',
                  selected: selectedIndex == 1,
                  onTap: () => onSelected(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          // Vía `GraspMotion` y no con una constante: los tests montan `GraspMotion.still()` y una
          // duración fija dejaría esta animación viva, que es lo que cuelga `pumpAndSettle`.
          duration: theme.extension<GraspMotion>()?.fast ?? AppMotion.fast,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.palette.outline : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                // `purple500` no se usa como color de texto pequeño sobre fondo claro (4.23:1):
                // el seleccionado va en `purple900` sobre `purple200`, y el otro en el gris de
                // texto secundario. Los dos pasan AA.
                color: selected ? context.palette.textPrimary : context.palette.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
