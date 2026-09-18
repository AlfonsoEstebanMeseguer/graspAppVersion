import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/profile_badge.dart';
import 'profile_badge_icons.dart';

/// Fila resumida de hasta 5 insignias ganadas, con acceso al grid completo —
/// sección "Insignias" de `08-profile.jpeg`.
class ProfileBadgesSummary extends StatelessWidget {
  const ProfileBadgesSummary({super.key, required this.badges});

  final List<ProfileBadge> badges;

  @override
  Widget build(BuildContext context) {
    final List<ProfileBadge> earned = badges.where((ProfileBadge b) => b.earned).toList();

    if (earned.isEmpty) {
      return Text(
        'Sin insignias todavía.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted),
      );
    }

    return Row(
      children: <Widget>[
        for (final ProfileBadge badge in earned.take(5)) ...<Widget>[
          _BadgeCircle(badge: badge),
          const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}

/// Modal "Ver todas": catálogo completo, ganadas en color y el resto en gris.
class ProfileBadgesModal extends StatelessWidget {
  const ProfileBadgesModal({super.key, required this.badges});

  final List<ProfileBadge> badges;

  static Future<void> show(BuildContext context, List<ProfileBadge> badges) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (BuildContext context) => ProfileBadgesModal(badges: badges),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Todas las insignias', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final ProfileBadge badge in badges) _BadgeCircle(badge: badge, showLabel: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeCircle extends StatelessWidget {
  const _BadgeCircle({required this.badge, this.showLabel = false});

  final ProfileBadge badge;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = badge.earned ? context.palette.containerSubtle : context.palette.canvas;
    final Color foreground = badge.earned ? context.palette.brandStrong : context.palette.outline;

    final Widget circle = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(badgeIconFor(badge.icon), size: 22, color: foreground),
    );

    return Semantics(
      label: badge.earned ? '${badge.name}, ganada' : '${badge.name}, sin ganar',
      child: ExcludeSemantics(
        child: Tooltip(
          message: badge.description ?? badge.name,
          child: showLabel
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    circle,
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      badge.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: badge.earned ? context.palette.textPrimary : context.palette.textMuted,
                      ),
                    ),
                  ],
                )
              : circle,
        ),
      ),
    );
  }
}