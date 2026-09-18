import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theming/app_theme.dart';
import '../../../core/theming/grasp_palette.dart';
import '../../../domain/rooms/room_summary.dart';
import '../application/rooms_controller.dart';
import 'widgets/room_card.dart';
import 'widgets/room_category_chips.dart';

/// Pestaña **Salas de voz** — §6.1 de la spec de la Fase 5.
///
/// Boceto: `pictures/screens/09-Searching-rooms.jpeg`, **parcialmente superado** por el
/// [ADR 0032](../../../../../docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md). De él se
/// conserva el lenguaje visual —cabecera centrada, tarjetas de radio 20 sobre fondo `canvas`,
/// sombras suaves y difusas, píldoras— y se descarta la estructura: **no hay sala destacada, no hay
/// «recomendadas para ti» y no hay «Ver todas»**. Es una sola lista, igual para todo el mundo,
/// ordenada por actividad reciente, con una fila de chips para que filtre **el usuario** en vez de
/// adivinar un algoritmo.
class RoomsScreen extends ConsumerWidget {
  const RoomsScreen({super.key});

  /// Cero salas. El texto dice **exactamente** lo que pasa: no que no haya salas *para ti* —eso
  /// sería la personalización que el ADR 0032 tiró—, sino que no hay ninguna abierta.
  static const String emptyState = 'No hay ninguna sala abierta ahora mismo';

  /// Y qué va a pasar. **Sin botón**: crear una sala es la acción real disponible en el backend
  /// (`room-actions` la implementa), pero en la app todavía no existe ni el formulario que la pide
  /// ni la pantalla de sala a la que llevaría (Tarea 8), así que un «Crear una sala» aquí sería un
  /// control que no hace nada afirmando que la función existe. Vuelve —con su `FilledButton`— en
  /// cuanto haya destino.
  static const String emptyHint =
      'Cuando alguien abra una, aparecerá aquí al momento.';

  static const String loadError =
      'No se pudieron cargar las salas. Desliza hacia abajo para reintentar.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RoomsFeedView> feed = ref.watch(roomsControllerProvider);
    final RoomsFeedView? view = feed.valueOrNull;

    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(title: const Text('Salas de voz')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // La fila solo existe si hay catálogo. Sin él —`onboarding-catalogs` caído, o una
            // versión desplegada que todavía no manda el `id`— unos chips vacíos afirmarían que se
            // puede filtrar por algo.
            if (view != null && view.categories.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              RoomCategoryChips(
                categories: view.categories,
                selectedId: view.selectedCategoryId,
                onChanged: (String? id) => ref
                    .read(roomsControllerProvider.notifier)
                    .selectCategory(id),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _Body(feed: feed, view: view)),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.feed, required this.view});

  final AsyncValue<RoomsFeedView> feed;

  /// El valor anterior sobrevive a la recarga (`copyWithPrevious`), así que aquí «hay vista» y
  /// «está cargando» pueden ser ciertas a la vez: se conserva la lista y no parpadea la pantalla
  /// entera al cambiar de chip.
  final RoomsFeedView? view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RoomsFeedView? current = view;

    if (current == null) {
      if (feed.hasError) {
        return _Refreshable(
          child: const _Notice(
            title: RoomsScreen.loadError,
            icon: Icons.cloud_off_rounded,
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (current.rooms.isEmpty) {
      return _Refreshable(
        child: const _Notice(
          title: RoomsScreen.emptyState,
          hint: RoomsScreen.emptyHint,
          icon: Icons.mic_none_rounded,
        ),
      );
    }

    final Map<String, String> nombres = <String, String>{
      for (final RoomCategory c in current.categories) c.id: c.name,
    };

    return _Refreshable(
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        itemCount: current.rooms.length,
        itemBuilder: (BuildContext context, int index) {
          // Sin ordenar aquí: el orden por actividad reciente lo decide `rooms_feed` en Postgres
          // (ADR 0032 § 3) y reordenar en el cliente sería una segunda fuente de verdad.
          final RoomSummary room = current.rooms[index];
          return RoomCard(
            room: room,
            categoryName: nombres[room.categoryId],
            hostPhotoUrl: current.photoUrls[room.hostId],
            avatarUrls: current.photoUrls,
          );
        },
      ),
    );
  }
}

/// Envuelve cualquier cuerpo en el `pull-to-refresh`, avisos incluidos: reintentar tiene que
/// funcionar justo cuando la lista está vacía o ha fallado.
class _Refreshable extends ConsumerWidget {
  const _Refreshable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: context.palette.brandStrong,
      onRefresh: () => ref.read(roomsControllerProvider.notifier).refresh(),
      child: child,
    );
  }
}

/// Un aviso a pantalla completa, dentro de algo scrolleable para no romper el `RefreshIndicator`.
class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.icon, this.hint});

  final String title;
  final IconData icon;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 44, color: context.palette.iconSoft),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: context.palette.textPrimary,
                      ),
                    ),
                    if (hint != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        hint!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
