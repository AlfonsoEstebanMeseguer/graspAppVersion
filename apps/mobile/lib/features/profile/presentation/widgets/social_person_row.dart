import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/social/follow_edge.dart';
import '../../../messages/presentation/widgets/social_avatar.dart';

/// Una fila de persona dentro de una lista social — `RN-52`.
///
/// Boceto: `08-profile.jpeg`, derivación acordada el 2026-08-23 — «tarjetas blancas de radio ~20 y
/// filas con foto + nombre + tag. Las acciones van **al final de la fila**».
///
/// ## El tag va debajo del nombre, y no es decoración
///
/// `RN-52` lo pide explícitamente en cada fila, y tiene una razón práctica: dos personas pueden
/// llamarse igual, y el tag es lo único que las distingue de verdad (§6.2). Una lista de
/// «Seguidores» con dos «Ana» y sin tag no se puede usar para decidir a cuál quitar.
class SocialPersonRow extends StatelessWidget {
  const SocialPersonRow({
    super.key,
    required this.profile,
    this.photoUrl,
    this.isActive,
    this.trailing,
    this.onTap,
  });

  final SocialProfileRef profile;

  /// URL ya firmada. `null` = no tiene foto **o** no se pudo firmar; en los dos casos se pinta la
  /// inicial, porque una foto que no carga y una que no existe se ven igual y no hay nada que
  /// explicarle a nadie.
  final String? photoUrl;

  /// `null` = esta lista no trae el dato, que **no** es «desconectado» (`RN-30`).
  final bool? isActive;

  /// Las acciones de la fila. Van al final, como pide la derivación del boceto.
  final Widget? trailing;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? tag = profile.tag;

    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: <Widget>[
              SocialAvatar(
                displayName: profile.displayName,
                presetAvatar: profile.presetAvatar,
                photoUrl: photoUrl,
                size: 44,
              ),
              const SizedBox(width: AppSpacing.md - 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: context.palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (tag != null && tag.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 1),
                      Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
