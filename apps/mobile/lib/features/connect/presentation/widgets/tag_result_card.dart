import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/social/follow_edge.dart';
import '../../../../domain/social/tag_lookup_result.dart';
import '../../../messages/presentation/widgets/social_avatar.dart';

/// La ficha que sale al encontrar un tag (§6.2).
///
/// Los tres estados del botón son los tres de [FollowState], y no hay un cuarto: `rejected` no
/// existe porque rechazar (`RN-16`) **borra la fila**, así que una solicitud rechazada vuelve a ser
/// `Seguir` sin dejar rastro.
class TagResultCard extends StatelessWidget {
  const TagResultCard({
    super.key,
    required this.result,
    required this.followState,
    this.photoUrl,
    this.onFollow,
    this.onOpenProfile,
  });

  static const String follow = 'Enviar solicitud de seguimiento';
  static const String pending = 'Pendiente';
  static const String following = 'Siguiendo';

  final TagLookupResult result;

  /// Se pasa aparte de [result] porque cambia al pulsar el botón **sin volver a buscar**: tras
  /// enviar la solicitud pasa a `pending` y la ficha no se recarga.
  final FollowState followState;

  final String? photoUrl;
  final VoidCallback? onFollow;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? bio = result.bio?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.sm,
      ),
      child: Material(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onOpenProfile,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.palette.containerSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SocialAvatar(
                      displayName: result.displayName,
                      presetAvatar: result.presetAvatar,
                      photoUrl: photoUrl,
                      size: 56,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            result.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // El tag SÍ se pinta aquí, al contrario que en la tarjeta del feed: es lo
                          // que la persona acaba de teclear y necesita poder comprobar que coincide.
                          Text(
                            result.tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: context.palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (bio != null && bio.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: _FollowButton(state: followState, onFollow: onFollow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.state, required this.onFollow});

  final FollowState state;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      // `onPressed: null` en los dos estados finales, no un callback vacío: un botón que parece
      // pulsable y no hace nada es peor que uno que se ve apagado.
      FollowState.pending => const FilledButton(
        onPressed: null,
        child: Text(TagResultCard.pending),
      ),
      FollowState.following => const OutlinedButton(
        onPressed: null,
        child: Text(TagResultCard.following),
      ),
      FollowState.none => FilledButton(
        onPressed: onFollow,
        child: const Text(TagResultCard.follow),
      ),
    };
  }
}
