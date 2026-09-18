import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/social/connect_candidate.dart';
import '../../../domain/social/social_failure.dart';

/// El feed de Conectar tal y como se pinta.
@immutable
class ConnectFeedView {
  const ConnectFeedView({
    required this.candidates,
    required this.emptyState,
    required this.relaxed,
    this.messaged = const <String>{},
    this.photoUrls = const <String, String>{},
    this.notice,
  });

  /// **La caché de sesión de `RN-45`**: la lista no se reordena mientras se hace scroll porque
  /// nadie la vuelve a pedir al hacer scroll. Solo la reemplazan un cambio de filtro y el
  /// `pull-to-refresh`.
  final List<ConnectCandidate> candidates;

  /// `RN-49`: no queda nadie. **Nunca una lista vacía sin explicación**, y por eso viaja aparte de
  /// `candidates.isEmpty`: son cosas distintas mientras carga.
  final bool emptyState;

  /// `RN-49`: la tanda se puntuó **sin el cuadrado del filtro** (ADR 0024). Hay que decirlo, o
  /// parecerá que el filtro no funciona.
  final bool relaxed;

  /// `RN-40`: a quién se le ha escrito ya en esta sesión. Su tarjeta **sigue en la lista** y solo
  /// cambia el botón — al contrario que un descarte, que la quita al instante.
  final Set<String> messaged;

  final Map<String, String> photoUrls;

  /// Un aviso que la pantalla enseña **en línea**: hoy, el cupo de refrescos agotado (`RN-46`) con
  /// su número y su hora (`RN-21`).
  ///
  /// Va en el estado y no en un `SnackBar` por una razón práctica: un `SnackBar` se va solo a los
  /// cuatro segundos, y el mensaje que dice **cuándo** se recupera el cupo es justo el que la
  /// persona necesita releer.
  final String? notice;

  ConnectFeedView copyWith({
    List<ConnectCandidate>? candidates,
    Set<String>? messaged,
    Map<String, String>? photoUrls,
    Object? notice = _sinTocar,
  }) => ConnectFeedView(
    candidates: candidates ?? this.candidates,
    emptyState: emptyState,
    relaxed: relaxed,
    messaged: messaged ?? this.messaged,
    photoUrls: photoUrls ?? this.photoUrls,
    notice: identical(notice, _sinTocar) ? this.notice : notice as String?,
  );

  static const Object _sinTocar = Object();
}

/// Carga y mantiene el feed de Conectar (§6).
class ConnectController extends AutoDisposeAsyncNotifier<ConnectFeedView> {
  Set<ConnectFilter> _filters = const <ConnectFilter>{};
  final Set<String> _messaged = <String>{};

  /// Los chips activos. Vacío = `Todos` (`RN-35`).
  Set<ConnectFilter> get filters => Set<ConnectFilter>.unmodifiable(_filters);

  @override
  Future<ConnectFeedView> build() => _fetch(refresh: false);

  /// Cambia los chips y vuelve a pedir la tanda.
  ///
  /// Va con `refresh: false` **a propósito**: cambiar de filtro no es un `pull-to-refresh` y no
  /// puede gastar el cupo de 5 al día de `RN-46`.
  Future<void> applyFilters(Set<ConnectFilter> filters) async {
    if (setEquals(_filters, filters)) return;
    _filters = Set<ConnectFilter>.of(filters);
    state = const AsyncValue<ConnectFeedView>.loading();
    state = await AsyncValue.guard(() => _fetch(refresh: false));
  }

  /// `RN-37`: se vuelve a `Todos`. Lo llama la pantalla al **volver a ser visible**, no solo al
  /// montarse — con `StatefulShellRoute.indexedStack` la rama no se desmonta al cambiar de pestaña.
  Future<void> resetFilters() => applyFilters(const <ConnectFilter>{});

  /// `Pull-to-refresh` (`RN-46`): regenera la tanda entera. **Reemplaza**, no añade.
  ///
  /// Un refresco rechazado por cupo **no puede vaciar la lista que ya estaba**: sería castigar dos
  /// veces por lo mismo. Se conserva el estado y el motivo se enseña en línea.
  Future<void> refresh() async {
    try {
      state = AsyncValue<ConnectFeedView>.data(await _fetch(refresh: true));
    } on SocialFailure catch (failure) {
      final ConnectFeedView? actual = state.valueOrNull;
      if (actual == null) rethrow;
      state = AsyncValue<ConnectFeedView>.data(
        actual.copyWith(notice: failure.message),
      );
    }
  }

  /// El `✕` de la tarjeta (decisión 8). Quita la tarjeta **al instante** y lo persiste.
  ///
  /// Se quita antes de esperar a la red porque `RN-48` la hace irreversible: si el backend falla, lo
  /// peor que pasa es que reaparezca en el siguiente refresco, y eso es mejor que dejar la tarjeta
  /// puesta mientras el usuario ya ha decidido que no quiere verla.
  Future<void> dismiss(String userId) async {
    final ConnectFeedView? actual = state.valueOrNull;
    if (actual != null) {
      state = AsyncValue<ConnectFeedView>.data(
        actual.copyWith(
          candidates: actual.candidates
              .where((ConnectCandidate c) => c.userId != userId)
              .toList(growable: false),
        ),
      );
    }
    await ref.read(connectRepositoryProvider).dismiss(userId);
  }

  /// `RN-40`: se le acaba de escribir el primer mensaje.
  ///
  /// **La tarjeta NO se quita**: el botón pasa a `Pendiente` y desaparece «en el siguiente
  /// refresco», que es cuando `connect-feed` la excluirá por `RN-47`(3). Quitarla ya sería un
  /// comportamiento distinto del que la spec describe, y además dejaría al usuario sin la
  /// confirmación de que su mensaje salió.
  void markMessaged(String userId) {
    _messaged.add(userId);
    final ConnectFeedView? actual = state.valueOrNull;
    if (actual == null) return;
    state = AsyncValue<ConnectFeedView>.data(
      actual.copyWith(messaged: Set<String>.of(_messaged)),
    );
  }

  Future<ConnectFeedView> _fetch({required bool refresh}) async {
    final ConnectFeedPage page = await ref
        .read(connectRepositoryProvider)
        .feed(filters: _filters, refresh: refresh);

    // Una sola llamada para todas las caras de la tanda, igual que en la bandeja.
    Map<String, String> photos = const <String, String>{};
    final List<String> conFoto = page.candidates
        .where((ConnectCandidate c) => c.hasPhoto)
        .map((ConnectCandidate c) => c.userId)
        .toList(growable: false);

    if (conFoto.isNotEmpty) {
      try {
        photos = await ref.read(avatarRepositoryProvider).photoUrls(conFoto);
      } on Object {
        // Que no se pueda firmar una foto no puede vaciar el feed: se pintan las iniciales.
        photos = const <String, String>{};
      }
    }

    return ConnectFeedView(
      candidates: page.candidates,
      emptyState: page.emptyState,
      relaxed: page.relaxed,
      messaged: Set<String>.of(_messaged),
      photoUrls: photos,
    );
  }
}

final AutoDisposeAsyncNotifierProvider<ConnectController, ConnectFeedView>
connectControllerProvider =
    AsyncNotifierProvider.autoDispose<ConnectController, ConnectFeedView>(
      ConnectController.new,
    );
