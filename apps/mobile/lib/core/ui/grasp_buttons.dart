import 'package:flutter/material.dart';

import '../theming/grasp_palette.dart';
import '../theming/app_motion.dart';
import '../theming/app_theme.dart';

/// CTA primario: píldora con degradado `purple500 → purple700`.
///
/// El degradado no es decorativo. Un relleno plano de `purple500` con texto
/// blanco da 4.23:1 y no cumple AA para texto de 16px; el degradado conserva el
/// púrpura de marca del boceto y deja el texto sobre la mitad oscura
/// (ver la nota de contraste en `app_colors.dart`).
class GraspPrimaryButton extends StatefulWidget {
  const GraspPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.semanticsLabel,
  });

  final String label;

  /// `null` deshabilita el botón.
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final String? semanticsLabel;

  @override
  State<GraspPrimaryButton> createState() => _GraspPrimaryButtonState();
}

class _GraspPrimaryButtonState extends State<GraspPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = widget.onPressed != null && !widget.isLoading;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? widget.label,
      child: ExcludeSemantics(
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: AppMotion.fast,
          curve: AppMotion.enter,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.5,
            duration: AppMotion.fast,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                gradient: LinearGradient(
                  colors: context.palette.primaryCta,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: enabled
                    ? <BoxShadow>[
                        BoxShadow(
                          // El halo del CTA sigue siendo el morado de marca en
                          // los dos temas: en oscuro es lo que separa el botón
                          // del fondo, porque ahí una sombra negra no se ve.
                          color: context.palette.brand.withValues(alpha: 0.20),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: enabled ? widget.onPressed : null,
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapUp: (_) => setState(() => _pressed = false),
                  onTapCancel: () => setState(() => _pressed = false),
                  child: SizedBox(
                    height: 56,
                    child: Center(
                      child: widget.isLoading
                          ? SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: context.palette.onBrand,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (widget.icon != null) ...<Widget>[
                                  Icon(
                                    widget.icon,
                                    size: 20,
                                    color: context.palette.onBrand,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                ],
                                Text(
                                  widget.label,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: context.palette.onBrand,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// CTA destructivo: misma silueta y alto que [GraspPrimaryButton], pero en
/// rojo y con icono — el botón tiene que distinguirse por algo más que el
/// color (accesibilidad, `08-profile.jpeg` no define este componente porque
/// no hay "zona peligrosa" en el boceto; ver `DeleteAccountSheet`).
class GraspDestructiveButton extends StatelessWidget {
  const GraspDestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon = Icons.delete_forever_rounded,
    this.semanticsLabel,
  });

  final String label;

  /// `null` deshabilita el botón.
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData icon;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = onPressed != null && !isLoading;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: enabled ? onPressed : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.palette.error,
              disabledForegroundColor: context.palette.error.withValues(alpha: 0.4),
              side: BorderSide(
                color: enabled ? context.palette.error : context.palette.error.withValues(alpha: 0.4),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: isLoading
                ? SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: context.palette.error,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Text(label, style: theme.textTheme.labelLarge?.copyWith(color: context.palette.error)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// CTA secundario: misma silueta de píldora, superficie blanca y borde suave.
class GraspSecondaryButton extends StatelessWidget {
  const GraspSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 20, color: context.palette.brandStrong),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(label),
        ],
      ),
    );
  }
}
