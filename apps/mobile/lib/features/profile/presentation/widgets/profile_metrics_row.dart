import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';

/// Rejilla 2×2 de estadísticas — mismo patrón visual que los 3 números en
/// fila de `08-profile.jpeg` ("Salas participadas", "Tiempo escuchando",
/// "Personas ayudadas"), pero con 4 tarjetas: el boceto muestra 3, la
/// cuarta ("Personas ayudadas") no tiene columna de backend todavía
/// (`room-actions`, que la escribiría, es Fase 5) y se sustituye por
/// "Seguidos", que sí es una columna real de `profiles` — igual que
/// "Seguidores", que ya estaba implícito en el boceto de otras pantallas de
/// perfil ajeno. Se documenta aquí porque diverge del boceto a propósito
/// (Sección "antes de cualquier cosa" de CLAUDE.md: cuestionar antes de
/// implementar en silencio, no inventar un contador falso).
class ProfileStatsGrid extends StatelessWidget {
  const ProfileStatsGrid({
    super.key,
    required this.roomsJoinedCount,
    required this.timeHelpingSeconds,
    required this.followersCount,
    required this.followingCount,
    this.onTapFollowers,
    this.onTapFollowing,
  });

  static const Key followersKey = Key('profile-stat-followers');
  static const Key followingKey = Key('profile-stat-following');

  final int roomsJoinedCount;
  final int timeHelpingSeconds;
  final int followersCount;
  final int followingCount;

  /// `RN-50`: los dos contadores de follows **navegan**.
  ///
  /// El §0 de la spec afirmaba que «la UI ya existe». Era falso: eran dos números sin `onTap`, y
  /// eso es lo que este parámetro corrige. Las otras dos tarjetas —salas y tiempo— siguen sin
  /// destino, y por eso **no llevan `onTap` ni pueden llevarlo**: un `InkWell` que enseña la
  /// pulsación y no lleva a ninguna parte es un botón muerto disfrazado de vivo.
  final VoidCallback? onTapFollowers;
  final VoidCallback? onTapFollowing;

  @override
  Widget build(BuildContext context) {
    final int hours = timeHelpingSeconds ~/ 3600;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.7,
      children: <Widget>[
        _MetricCard(value: '$roomsJoinedCount', label: 'Salas participadas'),
        _MetricCard(value: '$hours h', label: 'Tiempo escuchando'),
        _MetricCard(
          itemKey: followersKey,
          value: '$followersCount',
          label: 'Seguidores',
          onTap: onTapFollowers,
        ),
        _MetricCard(
          itemKey: followingKey,
          value: '$followingCount',
          label: 'Seguidos',
          onTap: onTapFollowing,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    this.itemKey,
    this.onTap,
  });

  final Key? itemKey;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool navegable = onTap != null;

    return Semantics(
      label: '$label: $value',
      button: navegable,
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: <BoxShadow>[
              BoxShadow(color: context.palette.shadowSoft, blurRadius: 14, offset: Offset(0, 4)),
            ],
          ),
          // `Material` transparente encima del `Container`: sin él la onda del `InkWell` se pinta
          // por debajo del fondo blanco de la tarjeta y no se ve nada al tocar.
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: InkWell(
              key: itemKey,
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(value, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        // La flecha solo donde se puede ir a algún sitio: es lo que distingue a
                        // simple vista las dos tarjetas que navegan de las dos que no.
                        if (navegable)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: context.palette.textMuted,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}