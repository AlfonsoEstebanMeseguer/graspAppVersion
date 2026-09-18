import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_motion.dart';
import '../../../../core/theming/app_theme.dart';

/// Pista segmentada de progreso — un segmento por pregunta, coherente con la
/// franja fina bajo "Bienvenido/a" en `02-onboarding-questions.jpeg`.
class OnboardingProgressTrack extends StatelessWidget {
  const OnboardingProgressTrack({
    super.key,
    required this.total,
    required this.currentIndex,
  });

  final int total;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < total; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Semantics(
              label: 'Pregunta ${i + 1} de $total',
              child: AnimatedContainer(
                duration: AppMotion.medium,
                curve: Curves.easeOut,
                height: 6,
                decoration: BoxDecoration(
                  color: i <= currentIndex
                      ? context.palette.brand
                      : context.palette.outline,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
