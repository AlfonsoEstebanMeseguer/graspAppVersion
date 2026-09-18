import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/social/follow_edge.dart';
import '../../../domain/social/public_profile.dart';

/// El perfil ajeno listo para pintar: la ficha, más las tres cosas que **dependen de quién mira**.
///
/// Las tres van fuera de [PublicProfile] por la misma razón: no son atributos de esa persona.
/// [followState] cambia según quién pregunte, [photoUrl] caduca a los 300 s y [isActive] depende
/// de un RPC que aplica la reciprocidad de `RN-32` por dentro. Meterlas en el modelo invitaría a
/// cachearlas con él.
@immutable
class PublicProfileView {
  const PublicProfileView({
    required this.profile,
    required this.followState,
    this.photoUrl,
    this.isActive,
    this.followInFlight = false,
  });

  final PublicProfile profile;

  /// Cuál de los tres botones del §6.2 se pinta: `Seguir` / `Pendiente` / `Siguiendo`.
  final FollowState followState;

  /// URL ya firmada, o `null` si no tiene foto **o** no se pudo firmar. Los dos casos se pintan
  /// igual —la inicial—, porque una foto que no carga y una que no existe se ven igual y no hay
  /// nada que explicarle a nadie.
  final String? photoUrl;

  /// `RN-30`. `null` = no se pudo saber, que **no** es «desconectado».
  final bool? isActive;

  /// Hay un `follow-toggle` en vuelo: el botón se deshabilita para que un doble toque no mande dos
  /// solicitudes. No es idempotencia —de eso se encarga el backend— sino no prometer dos veces.
  final bool followInFlight;

  PublicProfileView copyWith({
    FollowState? followState,
    bool? followInFlight,
  }) => PublicProfileView(
    profile: profile,
    followState: followState ?? this.followState,
    photoUrl: photoUrl,
    isActive: isActive,
    followInFlight: followInFlight ?? this.followInFlight,
  );
}

/// Lanzado cuando no hay ficha que enseñar.
///
/// Un tipo propio y no un `null` en el estado: `AsyncValue.data(null)` obligaría a cada rama de la
/// pantalla a distinguir «cargando» de «no hay nadie» mirando dos cosas a la vez.
class PublicProfileNotFound implements Exception {
  const PublicProfileNotFound();
}

/// El perfil de otra persona (`RN-38`, §6.2), por `userId`.
///
/// **Family por `userId` y no un notifier suelto**: se llega a esta pantalla desde tres sitios y se
/// puede apilar una sobre otra (el perfil de alguien → sus seguidores → el perfil de otro). Con un
/// único notifier, abrir el segundo perfil borraría el primero, y al volver atrás la pantalla de
/// debajo enseñaría a quien no toca.
class PublicProfileController
    extends AutoDisposeFamilyAsyncNotifier<PublicProfileView, String> {
  @override
  Future<PublicProfileView> build(String userId) async {
    final PublicProfile? perfil = await ref
        .read(publicProfileRepositoryProvider)
        .fetch(userId);
    if (perfil == null) throw const PublicProfileNotFound();

    // En paralelo y no en serie: son tres llamadas independientes y la pantalla no puede pintarse
    // hasta tenerlas. En serie sumaría tres viajes de red donde basta el más lento.
    final (String? foto, bool? activo, FollowState follow) =
        await (
          _foto(perfil),
          _actividad(userId),
          _follow(userId),
        ).wait;

    return PublicProfileView(
      profile: perfil,
      followState: follow,
      photoUrl: foto,
      isActive: activo,
    );
  }

  /// **Por lote aunque sea una sola**, como la bandeja y las listas de follows: `photoUrls` acepta
  /// un array y es el único camino que firma URLs de R2. Y sólo si hay foto que firmar: pedir la
  /// de quien no tiene gasta una firma para nada.
  Future<String?> _foto(PublicProfile perfil) async {
    if (!perfil.hasPhoto) return null;
    try {
      final Map<String, String> urls = await ref
          .read(avatarRepositoryProvider)
          .photoUrls(<String>[perfil.userId]);
      return urls[perfil.userId];
    } on Object {
      // Que no se pueda firmar la foto no puede dejar la pantalla en un error: se pinta la
      // inicial. Mismo criterio que las listas de follows.
      return null;
    }
  }

  Future<bool?> _actividad(String userId) async {
    try {
      final Map<String, bool> estados = await ref
          .read(activityRepositoryProvider)
          .activeStatus(<String>[userId]);
      return estados[userId] ?? false;
    } on Object {
      // `null` y no `false`: `RN-30` distingue «no se pudo saber» de «está desconectado», y
      // pintar un punto gris por un fallo de red sería afirmar lo segundo.
      return null;
    }
  }

  Future<FollowState> _follow(String userId) async {
    try {
      return await ref.read(publicProfileRepositoryProvider).followState(userId);
    } on Object {
      // [FollowState.none] es el estado **menos afirmativo**, el mismo criterio que
      // `FollowState.fromWire` ante un literal desconocido: enseñar `Seguir` de más es
      // recuperable, y enseñar `Siguiendo` de más miente sobre una relación que quizá no existe.
      return FollowState.none;
    }
  }

  /// El botón de seguir (§6.2). Sólo hace algo desde [FollowState.none]: `Pendiente` va
  /// deshabilitado y `Siguiendo` no ofrece dejar de seguir **desde aquí** —eso vive en la lista de
  /// Seguidos (`RN-53`), donde se ve a quién se le está haciendo.
  Future<void> follow() async {
    final PublicProfileView? actual = state.valueOrNull;
    if (actual == null ||
        actual.followState != FollowState.none ||
        actual.followInFlight) {
      return;
    }

    state = AsyncValue<PublicProfileView>.data(
      actual.copyWith(followInFlight: true),
    );
    try {
      final FollowToggleResult resultado = await ref
          .read(followRepositoryProvider)
          .toggle(FollowAction.request, actual.profile.userId);

      // El estado sale de la RESPUESTA y no se supone `pending`: `follow-toggle` decide si la
      // solicitud queda pendiente o se acepta sola, y suponerlo aquí sería una segunda fuente de
      // verdad para algo que el backend ya dice. `fromWire` traduce los dos literales.
      state = AsyncValue<PublicProfileView>.data(
        actual.copyWith(followState: resultado.status, followInFlight: false),
      );
    } on Object {
      state = AsyncValue<PublicProfileView>.data(
        actual.copyWith(followInFlight: false),
      );
      rethrow;
    }
  }
}

final AutoDisposeAsyncNotifierProviderFamily<
  PublicProfileController,
  PublicProfileView,
  String
>
publicProfileControllerProvider =
    AsyncNotifierProvider.autoDispose
        .family<PublicProfileController, PublicProfileView, String>(
          PublicProfileController.new,
        );
