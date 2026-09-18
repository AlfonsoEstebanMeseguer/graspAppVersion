import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/profile_level.dart';

/// Barra de progreso de nivel — "1.250 / 1.800 XP" bajo la cabecera de
/// `08-profile.jpeg`. `level`/`xp` son columnas reales de `profiles`; el
/// umbral del siguiente nivel es una curva de presentación (ver
/// [ProfileLevel]), no un dato de backend.
class ProfileXpBar extends StatelessWidget {
  const ProfileXpBar({super.key, required this.level, required this.xp});

  final int level;
  final int xp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int threshold = ProfileLevel.xpToNextLevel(level);
    final double progress = ProfileLevel.progress(level, xp);

    return Semantics(
      label:
          'Nivel $level, ${_withThousands(xp)} de ${_withThousands(threshold)} experiencia',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: context.palette.outline,
                valueColor: AlwaysStoppedAnimation<Color>(context.palette.brand),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_withThousands(xp)} / ${_withThousands(threshold)} XP',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(color: context.palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1250" -> "1.250". Formateador mínimo sin depender de `intl` (no está en
/// `pubspec.yaml` hoy y añadirlo solo para esto sería sobrecoste).
String _withThousands(int value) {
  final String digits = value.toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    final int fromEnd = digits.length - i;
    if (i > 0 && fromEnd % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}