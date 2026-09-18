import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/social/blocked_user.dart';

/// La lista de bloqueados lista para pintar: las filas más las URLs firmadas de sus fotos.
///
/// Las fotos van aparte por lo mismo que en la bandeja y en las listas de follows:
/// `SocialProfileRef` trae la **clave del objeto en R2**, no una URL, y la URL la firma
/// `profile-photo-view-url` con 300 s de caducidad — así que no puede viajar cacheada dentro de la
/// fila.
@immutable
class BlockedUsersView {
  const BlockedUsersView({required this.users, required this.photoUrls});

  final List<BlockedUser> users;

  /// `userId` → URL firmada. Quien no tenga foto **no está en el mapa**.
  final Map<String, String> photoUrls;
}

/// Perfil → Privacidad → Usuarios bloqueados (ADR 0027).
class BlockedUsersController
    extends AutoDisposeAsyncNotifier<BlockedUsersView> {
  @override
  Future<BlockedUsersView> build() async {
    final List<BlockedUser> users = await ref
        .read(moderationRepositoryProvider)
        .blockedUsers();

    return BlockedUsersView(users: users, photoUrls: await _fotos(users));
  }

  Future<Map<String, String>> _fotos(List<BlockedUser> users) async {
    final List<String> ids = <String>[
      for (final BlockedUser u in users)
        if (u.profile.hasPhoto) u.profile.userId,
    ];
    if (ids.isEmpty) return const <String, String>{};
    try {
      return await ref.read(avatarRepositoryProvider).photoUrls(ids);
    } on Object {
      // Que no se pueda firmar una foto no puede vaciar la lista: se pintan las iniciales y la
      // lista sigue siendo utilizable. Mismo criterio que la bandeja y que las listas de follows.
      return const <String, String>{};
    }
  }

  /// Deshace el bloqueo y quita la fila.
  ///
  /// **El backend primero y la UI después**, al revés que en [FollowsController.remove]. Allí la
  /// retirada optimista es inocua: si falla, se ha quitado de una lista y basta con recargar. Aquí
  /// no lo es — una fila que desaparece dice «ya no está bloqueado», y si la llamada falló esa
  /// persona **sigue bloqueada**. Mismo criterio que el interruptor de `PrivacySection`, que vuelve
  /// atrás al fallar: en un ajuste de privacidad, mostrar el estado deseado en vez del real es la
  /// peor forma de mentir que puede tener una pantalla.
  Future<void> unblock(String userId) async {
    await ref.read(moderationRepositoryProvider).unblock(userId);

    final BlockedUsersView? actual = state.valueOrNull;
    if (actual != null) {
      state = AsyncValue<BlockedUsersView>.data(
        BlockedUsersView(
          users: actual.users
              .where((BlockedUser u) => u.profile.userId != userId)
              .toList(growable: false),
          photoUrls: actual.photoUrls,
        ),
      );
    }
  }
}

final AutoDisposeAsyncNotifierProvider<BlockedUsersController, BlockedUsersView>
blockedUsersControllerProvider =
    AsyncNotifierProvider.autoDispose<BlockedUsersController, BlockedUsersView>(
      BlockedUsersController.new,
    );
