import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../domain/social/follow_edge.dart';
import '../../../domain/social/social_failure.dart';
import '../application/follows_controller.dart';
import 'follow_requests_screen.dart';
import 'public_profile_screen.dart';
import 'widgets/social_person_row.dart';

/// Las listas de **Seguidores** y **Seguidos** — `RN-50`, `RN-53`.
///
/// Boceto: `08-profile.jpeg` (derivación del 2026-08-23: cabecera centrada, tarjetas blancas de
/// radio ~20, filas con foto + nombre + tag, acciones al final de la fila).
///
/// ## Una pantalla, dos listas, y NO un filtro
///
/// [FollowsTab] decide de cuál se trata, y lo que cambia no es solo el título: **la acción de cada
/// fila es una llamada distinta** a `follow-toggle` (`unfollow` frente a `remove_follower`).
/// Confundirlas hace lo contrario de lo que se pidió — quien quería quitarse a alguien de encima
/// acabaría dejando de seguirlo él—, así que la pestaña es un tipo y no un booleano.
class FollowsScreen extends ConsumerWidget {
  const FollowsScreen({super.key, required this.tab});

  final FollowsTab tab;

  static const Key requestsEntryKey = Key('follows-requests-entry');

  /// La acción de la fila de [userId]. Se indexa por id y **no por posición**: la lista se reordena
  /// y se acorta al quitar filas, así que una clave por índice apuntaría a otra persona.
  static Key actionKeyFor(String userId) => Key('follows-action-$userId');

  static const String emptyFollowers = 'Todavía no te sigue nadie.';
  static const String emptyFollowing = 'Todavía no sigues a nadie.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FollowsView> vista = ref.watch(
      followsControllerProvider(tab),
    );

    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(title: Text(tab.title), centerTitle: true),
      body: SafeArea(
        top: false,
        child: vista.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => _Centrado(
            text: 'No se pudo cargar la lista. Desliza hacia abajo para reintentar.',
          ),
          data: (FollowsView view) => RefreshIndicator(
            color: context.palette.brandStrong,
            onRefresh: () => ref.refresh(followsControllerProvider(tab).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.md,
                AppSpacing.gutter,
                AppSpacing.xl,
              ),
              children: <Widget>[
                // `RN-51`: la entrada a las solicitudes vive **dentro de Seguidores**, y solo ahí.
                // Las solicitudes que uno recibe no tienen nada que ver con la gente a la que uno
                // sigue.
                if (tab == FollowsTab.followers) const _RequestsEntry(),
                if (view.edges.isEmpty)
                  _Centrado(
                    text: tab == FollowsTab.followers
                        ? emptyFollowers
                        : emptyFollowing,
                  )
                else
                  for (final FollowEdge edge in view.edges) ...<Widget>[
                    SocialPersonRow(
                      profile: edge.profile,
                      photoUrl: view.photoUrls[edge.profile.userId],
                      trailing: _AccionDeFila(
                        itemKey: actionKeyFor(edge.profile.userId),
                        label: tab.actionLabel,
                        onPressed: () => _quitar(context, ref, edge),
                      ),
                      // Tocar la fila abre el perfil de esa persona. No lo pedía ninguna RN
                      // —`RN-53` sólo exige las acciones del final—, pero una fila con foto,
                      // nombre y tag que no lleva a ninguna parte es la mitad de un `InkWell`: ya
                      // se ilumina al tocarla, así que o lleva a algún sitio o no debería
                      // iluminarse.
                      onTap: () => PublicProfileScreen.open(
                        context,
                        edge.profile.userId,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _quitar(
    BuildContext context,
    WidgetRef ref,
    FollowEdge edge,
  ) async {
    try {
      await ref
          .read(followsControllerProvider(tab).notifier)
          .remove(tab, edge.profile.userId);
    } on Object catch (error) {
      if (!context.mounted) return;
      final String texto = error is SocialFailure
          ? error.message
          : 'No se pudo completar la acción. Inténtalo de nuevo.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(texto)));
    }
  }
}

/// La entrada a «Solicitudes de seguimiento» con su contador — `RN-51`.
///
/// **No se pinta con cero.** Una entrada que lleva a una lista vacía es un viaje en balde y un
/// contador a cero es ruido; es el mismo criterio que el `(N)` de la bandeja del §8.1.
class _RequestsEntry extends ConsumerWidget {
  const _RequestsEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? count = ref.watch(followRequestsCountProvider);
    if (count == null || count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ListTile(
          key: FollowsScreen.requestsEntryKey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          leading: Icon(
            Icons.person_add_alt_1_outlined,
            color: context.palette.brandStrong,
          ),
          title: Text(
            'Solicitudes de seguimiento',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: context.palette.containerSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.palette.brandStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.textMuted,
              ),
            ],
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => const FollowRequestsScreen(),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccionDeFila extends StatelessWidget {
  const _AccionDeFila({
    required this.itemKey,
    required this.label,
    required this.onPressed,
  });

  final Key itemKey;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: itemKey,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: context.palette.brandStrong,
      side: BorderSide(color: context.palette.chip),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
      // FINITO, y no es cosmético: el tema pone `Size.fromHeight(56)`, que deja el **ancho en
      // `double.infinity`**. Dentro del `Row` de la fila eso es un `BoxConstraints forces an
      // infinite width` y la pantalla entera no llega a pintarse. Taparlo con un `SizedBox` de
      // ancho fijo cambiaría el fallo por otro más callado —el texto cortado—, así que se arregla
      // donde nace.
      minimumSize: const Size(0, 36),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}

class _Centrado extends StatelessWidget {
  const _Centrado({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted),
    ),
  );
}
