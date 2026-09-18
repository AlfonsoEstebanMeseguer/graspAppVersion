import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/social/follow_edge.dart';
import '../../../domain/social/social_failure.dart';
import '../../../domain/social/tag_lookup_result.dart';

/// Los desenlaces de la búsqueda por tag del §6.2.
///
/// ## Son CUATRO, y el §6.2 describe cinco casos. Falta uno a propósito
///
/// La spec lista: no existe · bloqueo en cualquier dirección · tu propio tag · existe. Los dos
/// primeros comparten [TagSearchNotFound] porque el backend devuelve **el mismo 404 con el mismo
/// cuerpo** (`RN-23`) y el repositorio devuelve `null` en ambos.
///
/// **No hay dato con el que construir una variante para el bloqueo**, y eso es la garantía: la
/// pantalla no tiene por dónde ramificar, así que no puede divergir en un detalle visible.
@immutable
sealed class TagSearchState {
  const TagSearchState();
}

/// Nadie ha buscado nada: se ve el feed.
final class TagSearchIdle extends TagSearchState {
  const TagSearchIdle();
}

final class TagSearchLoading extends TagSearchState {
  const TagSearchLoading();
}

/// «No existe» **o** «hay bloqueo». Indistinguibles, y no se puede saber cuál.
final class TagSearchNotFound extends TagSearchState {
  const TagSearchNotFound();
}

/// Un fallo que sí se puede contar: tu propio tag, o la red.
final class TagSearchError extends TagSearchState {
  const TagSearchError(this.message);

  final String message;
}

final class TagSearchFound extends TagSearchState {
  const TagSearchFound(this.result, this.followState);

  final TagLookupResult result;

  /// Aparte de [result] porque cambia al enviar la solicitud **sin volver a buscar**.
  final FollowState followState;
}

class TagSearchController extends AutoDisposeNotifier<TagSearchState> {
  @override
  TagSearchState build() => const TagSearchIdle();

  Future<void> search(String tag) async {
    state = const TagSearchLoading();
    try {
      final TagLookupResult? result = await ref
          .read(connectRepositoryProvider)
          .lookupTag(tag);

      // AQUÍ SE CUMPLE RN-23, Y ES UNA SOLA RAMA. `null` llega tanto por «no existe» como por
      // «hay bloqueo»; una segunda rama tendría que inventarse de dónde sale la diferencia.
      state = result == null
          ? const TagSearchNotFound()
          : TagSearchFound(result, result.followState);
    } on SocialFailure catch (failure) {
      state = TagSearchError(failure.message);
    }
  }

  void clear() => state = const TagSearchIdle();

  /// Envía la solicitud de seguimiento y deja el botón en `Pendiente` (§6.2).
  Future<void> follow() async {
    final TagSearchState actual = state;
    if (actual is! TagSearchFound) return;

    try {
      final FollowToggleResult result = await ref
          .read(followRepositoryProvider)
          .toggle(FollowAction.request, actual.result.userId);
      state = TagSearchFound(actual.result, result.status);
    } on SocialFailure catch (failure) {
      // El tope de RN-20 (20 solicitudes en 24 h) llega por aquí, ya traducido con su número y su
      // hora. La ficha se pierde y se enseña el motivo: reintentar no va a funcionar hasta esa hora.
      state = TagSearchError(failure.message);
    }
  }
}

final AutoDisposeNotifierProvider<TagSearchController, TagSearchState>
tagSearchControllerProvider =
    NotifierProvider.autoDispose<TagSearchController, TagSearchState>(
      TagSearchController.new,
    );
