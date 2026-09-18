import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../domain/social/follow_edge.dart';
import '../../../domain/social/social_failure.dart';
import '../application/follows_controller.dart';
import 'widgets/social_person_row.dart';
import 'public_profile_screen.dart';

/// Solicitudes de seguimiento recibidas — `RN-51`, `RN-52`.
///
/// ## Lista distinta e independiente de las solicitudes de mensaje
///
/// Lo dice `RN-51` con esas palabras, y no es un detalle de organización: son dos cosas que se
/// deciden por motivos distintos y que el backend guarda en tablas distintas (`user_follows` frente
/// a `conversations`). Aceptar aquí **no** abre ninguna conversación (`RN-14`) y **no** hace que
/// quien acepta pase a seguir a nadie (`RN-13`): el follow es unidireccional.
///
/// ## Rechazar borra, no marca
///
/// `RN-16`: la fila **desaparece** de `user_follows`. Un seguimiento rechazado se puede volver a
/// solicitar sin dejar rastro, a diferencia de una solicitud de mensaje ignorada, que es terminal
/// (`RN-07`). Por eso [FollowState] no tiene `rejected`: no hay estado que guardar.
class FollowRequestsScreen extends ConsumerWidget {
  const FollowRequestsScreen({super.key});

  /// Indexadas por id y no por posición: la lista se acorta al decidir cada solicitud, así que una
  /// clave por índice apuntaría a otra persona en cuanto se acepta la primera.
  static Key acceptKeyFor(String userId) => Key('follow-request-accept-$userId');
  static Key rejectKeyFor(String userId) => Key('follow-request-reject-$userId');

  static const String title = 'Solicitudes de seguimiento';
  static const String empty = 'No tienes solicitudes pendientes.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FollowRequestsView> vista = ref.watch(
      followRequestsControllerProvider,
    );

    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(title: const Text(title), centerTitle: true),
      body: SafeArea(
        top: false,
        child: vista.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => const _Centrado(
            text: 'No se pudieron cargar las solicitudes. Vuelve a intentarlo.',
          ),
          data: (FollowRequestsView view) {
            if (view.requests.isEmpty) return const _Centrado(text: empty);

            return RefreshIndicator(
              color: context.palette.brandStrong,
              onRefresh: () =>
                  ref.refresh(followRequestsControllerProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.gutter,
                  AppSpacing.xl,
                ),
                itemCount: view.requests.length,
                separatorBuilder: (BuildContext _, int _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final FollowRequest request = view.requests[index];
                  final String userId = request.profile.userId;

                  return SocialPersonRow(
                    profile: request.profile,
                    photoUrl: view.photoUrls[userId],
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // `Rechazar` va primero y en discreto; `Aceptar` a la derecha y coloreado.
                        // El orden importa: la acción que crea una relación es la afirmativa, y
                        // ponerla donde cae el pulgar por inercia haría que se aceptara sin mirar.
                        IconButton(
                          key: rejectKeyFor(userId),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Rechazar',
                          color: context.palette.textMuted,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _decidir(
                            context,
                            ref,
                            userId,
                            aceptar: false,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        FilledButton(
                          key: acceptKeyFor(userId),
                          onPressed: () => _decidir(
                            context,
                            ref,
                            userId,
                            aceptar: true,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.palette.brandStrong,
                            foregroundColor: context.palette.onBrand,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md - 2,
                            ),
                            // Finito: el tema pone `Size.fromHeight(56)`, que deja el ancho en
                            // infinito y revienta dentro de un `Row`.
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text('Aceptar'),
                        ),
                      ],
                    ),
                    // Aquí importa más que en ninguna otra lista: antes de aceptar o rechazar a
                    // alguien que no conoces, lo natural es querer ver quién es.
                    onTap: () => PublicProfileScreen.open(
                      context,
                      request.profile.userId,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _decidir(
    BuildContext context,
    WidgetRef ref,
    String userId, {
    required bool aceptar,
  }) async {
    final FollowRequestsController controller = ref.read(
      followRequestsControllerProvider.notifier,
    );
    try {
      await (aceptar ? controller.accept(userId) : controller.reject(userId));
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

class _Centrado extends StatelessWidget {
  const _Centrado({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted),
      ),
    ),
  );
}
