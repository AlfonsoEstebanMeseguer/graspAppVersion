import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/social/follow_edge.dart';
import '../../messages/application/inbox_controller.dart';
import 'profile_controller.dart';

/// Cuál de las dos listas del §10 se está mirando (`RN-50`).
///
/// Son dos listas y no una con un filtro porque **admiten acciones distintas**: sobre un seguidor
/// se puede «Eliminar seguidor» y sobre un seguido «Dejar de seguir», y son dos llamadas distintas
/// a `follow-toggle`. Mezclarlas en un modelo con un booleano invita a ofrecer la acción
/// equivocada, que es el mismo motivo por el que [FollowRequest] es un tipo aparte de [FollowEdge].
enum FollowsTab {
  followers('Seguidores'),
  following('Seguidos');

  const FollowsTab(this.title);

  final String title;

  /// La acción que se ofrece sobre una fila de esta lista.
  FollowAction get action => switch (this) {
    FollowsTab.followers => FollowAction.removeFollower,
    FollowsTab.following => FollowAction.unfollow,
  };

  /// La etiqueta del botón de esa acción.
  String get actionLabel => switch (this) {
    FollowsTab.followers => 'Eliminar',
    FollowsTab.following => 'Dejar de seguir',
  };
}

/// Una lista de follows lista para pintar: las filas más las URLs firmadas de sus fotos.
///
/// Las fotos van aparte por lo mismo que en la bandeja: `SocialProfileRef` trae la **clave del
/// objeto en R2**, no una URL, y la URL la firma `profile-photo-view-url` con 300 s de caducidad —
/// así que no puede viajar cacheada dentro de la fila.
@immutable
class FollowsView {
  const FollowsView({required this.edges, required this.photoUrls});

  final List<FollowEdge> edges;

  /// `userId` → URL firmada. Quien no tenga foto **no está en el mapa**.
  final Map<String, String> photoUrls;
}

/// Las dos listas de `RN-50`, una por pestaña.
class FollowsController
    extends AutoDisposeFamilyAsyncNotifier<FollowsView, FollowsTab> {
  /// De quién son las listas: **del perfil propio**.
  ///
  /// El `userId` sale de `profileControllerProvider` y no de `supabaseClient.auth.currentUser`
  /// aposta. Dos motivos, y el segundo es el que manda: (a) el perfil ya está cargado en esta
  /// pantalla, así que no cuesta nada; y (b) leer la sesión directamente ataría este controlador al
  /// cliente de Supabase, y entonces probarlo exigiría un doble del cliente en vez de uno del
  /// dominio — exactamente lo que prohíbe el punto 6 de la skill `flutter-ui`.
  @override
  Future<FollowsView> build(FollowsTab tab) async {
    // `read` y no `watch`, y la diferencia se ve al quitar una fila: [remove] invalida el perfil
    // para que sus contadores se refresquen, y con `watch` esa invalidación **reconstruiría esta
    // lista entera**, deshaciendo el borrado optimista y pidiendo de nuevo al backend algo que no
    // ha cambiado. La identidad de quien mira no cambia mientras la pantalla vive.
    final String userId = (await ref.read(profileControllerProvider.future))
        .userId;

    final List<FollowEdge> edges = switch (tab) {
      FollowsTab.followers => await ref
          .read(followRepositoryProvider)
          .followers(userId),
      FollowsTab.following => await ref
          .read(followRepositoryProvider)
          .following(userId),
    };

    return FollowsView(edges: edges, photoUrls: await _fotos(edges));
  }

  Future<Map<String, String>> _fotos(List<FollowEdge> edges) async {
    final List<String> ids = <String>[
      for (final FollowEdge e in edges)
        if (e.profile.hasPhoto) e.profile.userId,
    ];
    if (ids.isEmpty) return const <String, String>{};
    try {
      return await ref.read(avatarRepositoryProvider).photoUrls(ids);
    } on Object {
      // Que no se pueda firmar una foto no puede vaciar la lista: se pintan las iniciales y la
      // lista sigue siendo utilizable. Mismo criterio que la bandeja.
      return const <String, String>{};
    }
  }

  /// `RN-53`: dejar de seguir, o quitarse a alguien de encima como seguidor.
  ///
  /// **Quita la fila del estado antes de recargar** para que la lista responda al toque, pero
  /// **recarga igualmente**: los contadores de `profiles` los escribe el backend y la única forma de
  /// que el perfil los enseñe bien es volver a pedirlos.
  Future<void> remove(FollowsTab tab, String targetUserId) async {
    await ref.read(followRepositoryProvider).toggle(tab.action, targetUserId);

    final FollowsView? actual = state.valueOrNull;
    if (actual != null) {
      state = AsyncValue<FollowsView>.data(
        FollowsView(
          edges: actual.edges
              .where((FollowEdge e) => e.profile.userId != targetUserId)
              .toList(growable: false),
          photoUrls: actual.photoUrls,
        ),
      );
    }
    // El perfil enseña `followers_count`/`following_count`, que acaban de cambiar en el backend.
    ref.invalidate(profileControllerProvider);
  }
}

final AutoDisposeAsyncNotifierProviderFamily<
  FollowsController,
  FollowsView,
  FollowsTab
>
followsControllerProvider =
    AsyncNotifierProvider.autoDispose
        .family<FollowsController, FollowsView, FollowsTab>(
          FollowsController.new,
        );

/// Las solicitudes de seguimiento **recibidas** y sin decidir (`RN-51`).
///
/// Lista aparte de las dos de arriba, y es lo que pide `RN-51`: *«una lista distinta e
/// independiente de las solicitudes de mensaje»*. No comparte tipo con [FollowEdge] porque las
/// acciones son otras — `accept`/`reject`, no `unfollow`.
@immutable
class FollowRequestsView {
  const FollowRequestsView({required this.requests, required this.photoUrls});

  final List<FollowRequest> requests;
  final Map<String, String> photoUrls;

  int get count => requests.length;
}

class FollowRequestsController
    extends AutoDisposeAsyncNotifier<FollowRequestsView> {
  @override
  Future<FollowRequestsView> build() async {
    final List<FollowRequest> requests = await ref
        .read(followRepositoryProvider)
        .pendingRequests();

    final List<String> ids = <String>[
      for (final FollowRequest r in requests)
        if (r.profile.hasPhoto) r.profile.userId,
    ];

    Map<String, String> fotos = const <String, String>{};
    if (ids.isNotEmpty) {
      try {
        fotos = await ref.read(avatarRepositoryProvider).photoUrls(ids);
      } on Object {
        fotos = const <String, String>{};
      }
    }

    return FollowRequestsView(requests: requests, photoUrls: fotos);
  }

  /// `RN-13`: aceptar crea un follow **unidireccional** — quien acepta NO pasa a seguir a nadie.
  ///
  /// Y `RN-14`: **no abre conversación**. Lo único que puede reanudarse es una conversación que el
  /// aceptado hubiera iniciado y que se ignoró (`RN-17`), y eso lo decide el backend y lo anuncia
  /// con `conversation_resumed`; por eso se invalida la bandeja **solo cuando llega ese campo**, en
  /// vez de refrescarla siempre por si acaso.
  Future<void> accept(String userId) => _decidir(FollowAction.accept, userId);

  /// `RN-16`: rechazar **borra la fila**, no la marca. Un seguimiento rechazado se puede volver a
  /// solicitar sin dejar rastro, a diferencia de una solicitud de mensaje, que sí es terminal.
  Future<void> reject(String userId) => _decidir(FollowAction.reject, userId);

  Future<void> _decidir(FollowAction action, String userId) async {
    final FollowToggleResult result = await ref
        .read(followRepositoryProvider)
        .toggle(action, userId);

    final FollowRequestsView? actual = state.valueOrNull;
    if (actual != null) {
      state = AsyncValue<FollowRequestsView>.data(
        FollowRequestsView(
          requests: actual.requests
              .where((FollowRequest r) => r.profile.userId != userId)
              .toList(growable: false),
          photoUrls: actual.photoUrls,
        ),
      );
    }

    if (action == FollowAction.accept) {
      // `followers_count` acaba de subir.
      ref.invalidate(profileControllerProvider);
      ref.invalidate(followsControllerProvider(FollowsTab.followers));
    }
    if (result.conversationResumed) ref.invalidate(inboxControllerProvider);
  }
}

final AutoDisposeAsyncNotifierProvider<
  FollowRequestsController,
  FollowRequestsView
>
followRequestsControllerProvider =
    AsyncNotifierProvider.autoDispose<
      FollowRequestsController,
      FollowRequestsView
    >(FollowRequestsController.new);

/// Cuántas solicitudes de seguimiento hay sin decidir, para el contador de `RN-51`.
///
/// `null` mientras carga o si falla: **un contador equivocado es peor que ninguno**, igual que en
/// el badge de la barra.
final AutoDisposeProvider<int?> followRequestsCountProvider =
    Provider.autoDispose<int?>(
      (Ref ref) => ref.watch(followRequestsControllerProvider).valueOrNull?.count,
    );
