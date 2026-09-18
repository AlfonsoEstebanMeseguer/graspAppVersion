import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../core/theming/app_typography.dart';
import '../../../core/ui/brand_mark.dart';
import '../../../core/ui/grasp_backdrop.dart';
import '../../../core/ui/grasp_buttons.dart';
import '../../../core/ui/staggered_reveal.dart';

/// Pantalla de bienvenida — réplica de `pictures/screens/01-Start_Menu.jpeg`.
///
/// Estructura del boceto, de arriba abajo: marca (cerebro), logotipo, claim a
/// dos líneas, corazón, y la escena del grupo ocupando el tercio inferior. Los
/// dos CTAs son el único añadido: el boceto es una pantalla de presentación y
/// no muestra la entrada al flujo.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: GraspBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SingleChildScrollView(
                // El scroll solo entra en juego en pantallas muy bajas o con
                // el texto muy ampliado; en un móvil normal no aparece.
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  // `IntrinsicHeight` es lo que le da una altura determinada a
                  // la Column: sin ella los `Spacer` no tienen constraint
                  // vertical del que repartir y el layout revienta en cuanto el
                  // contenido no cabe.
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.gutter,
                      ),
                      child: Column(
                        children: <Widget>[
                          const Spacer(flex: 2),
                          StaggeredReveal(
                            children: <Widget>[
                              const Center(child: BrandMark(size: 92)),
                              const SizedBox(height: AppSpacing.lg),
                              Center(
                                child: Text(
                                  'Grasp',
                                  style: AppTypography.wordmark(
                                    fontSize: 40,
                                    palette: context.palette,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                'Charlas que te entienden.\n'
                                'Personas que te acompañan.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: context.palette.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              const Center(child: _BreathingHeart()),
                            ],
                          ),
                          const Spacer(flex: 3),
                          StaggeredReveal(
                            children: <Widget>[
                              GraspPrimaryButton(
                                label: 'Crear cuenta',
                                onPressed: () =>
                                    context.push(AppRoute.register),
                              ),
                              const SizedBox(
                                height: AppSpacing.md - AppSpacing.xs,
                              ),
                              GraspSecondaryButton(
                                label: 'Ya tengo cuenta',
                                onPressed: () => context.push(AppRoute.login),
                              ),
                            ],
                          ),
                          // Aquí no va nada más: en el boceto el pie es solo
                          // ilustración. Cualquier texto sobre esa zona cae
                          // encima de la parte saturada de la escena y no
                          // llega al contraste AA.
                          const SizedBox(height: AppSpacing.xxl),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// El corazón bajo el claim, latiendo muy despacio.
class _BreathingHeart extends StatefulWidget {
  const _BreathingHeart();

  @override
  State<_BreathingHeart> createState() => _BreathingHeartState();
}

class _BreathingHeartState extends State<_BreathingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool shouldAnimate =
        !GraspMotion.of(context).isStill &&
        !MediaQuery.disableAnimationsOf(context);

    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!shouldAnimate) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.06).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: Icon(
          Icons.favorite_rounded,
          size: 26,
          color: context.palette.chip,
        ),
      ),
    );
  }
}
