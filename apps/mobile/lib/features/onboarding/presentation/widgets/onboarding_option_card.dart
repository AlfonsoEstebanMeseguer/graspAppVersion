import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_motion.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/onboarding/onboarding_question.dart';

/// Tarjeta de opción del onboarding: icono en círculo + etiqueta, tal y como
/// aparece en la rejilla 3×3 de `02-onboarding-questions.jpeg`.
class OnboardingOptionCard extends StatelessWidget {
  const OnboardingOptionCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final OnboardingOption option;
  final bool selected;
  final VoidCallback onTap;

  /// La proporción de la celda que esta tarjeta necesita en la rejilla, y **la usan la pantalla y
  /// su test**, que es el punto: era un `0.92` suelto en `onboarding_feed_screen.dart`, calculado
  /// para etiquetas de UNA línea. Tres de las nueve opciones de la primera pregunta ocupan más
  /// —«Ansiedad y estrés cotidiano», «Cambios de ciudad», «Crecimiento personal»— y desbordaban por
  /// 0,9 px, cortando el texto (hallazgo H-2, 2026-08-28).
  ///
  /// La celda mide unos **110 px de ancho** con tres columnas y el `gutter` de 24, y ahí dentro
  /// «Ansiedad y estrés cotidiano» no cabe en dos líneas por mucho alto que se le dé: por eso el
  /// arreglo es alto para **tres** y [maxLines] es 3, no solo un número mayor.
  ///
  /// Vive aquí y no en la pantalla porque **quien sabe cuánto alto necesita es la tarjeta**. Con el
  /// número suelto allí, cualquier cambio en el padding o en la tipografía de aquí lo dejaba
  /// desfasado sin que nada lo dijera.
  /// Alto para **tres** líneas de etiqueta: 16+16 de padding, 44 de icono, 8 de hueco y 3×20 de
  /// texto ≈ 144, sobre una celda de ~110 de ancho.
  static const double gridAspectRatio = 0.76;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      identifier: option.slug,
      label: option.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected ? context.palette.containerSubtle : context.palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: selected ? context.palette.brand : context.palette.outline,
                width: selected ? 1.6 : 1,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: context.palette.shadowSoft,
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: Curves.easeOut,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? context.palette.brand
                        : context.palette.containerSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    option.icon,
                    size: 22,
                    color: selected ? context.palette.onBrand : context.palette.brandStrong,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // `Flexible` y no el `Text` a pelo: [gridAspectRatio] da alto de sobra para dos
                // líneas, pero eso depende de la tipografía y del **escalado de fuente del
                // sistema**, que el usuario controla y nosotros no. Sin esto, alguien con el texto
                // ampliado en los ajustes de Android vuelve a ver la barra amarilla. Con esto, en
                // el peor caso el `ellipsis` recorta —que es feo pero legible— en vez de desbordar.
                Flexible(
                  child: Text(
                  option.label,
                  textAlign: TextAlign.center,
                  // TRES líneas, no dos. Dos era el número del boceto, pensado para etiquetas
                  // cortas como «Autoestima» o «Duelo»; la más larga del catálogo tiene 27
                  // caracteres y en 110 px no entra en dos por mucho alto que se le dé.
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? context.palette.textPrimary
                        : context.palette.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
