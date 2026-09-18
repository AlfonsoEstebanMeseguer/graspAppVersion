import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/social/blocked_user.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';
import 'package:grasp_mobile/domain/social/moderation_repository.dart';
import 'package:grasp_mobile/features/profile/application/blocked_users_controller.dart';

BlockedUser _bloqueado(String id, String nombre) => BlockedUser(
  profile: SocialProfileRef(userId: id, displayName: nombre),
  blockedAt: DateTime(2026, 8, 20),
);

class _FakeModeration implements ModerationRepository {
  _FakeModeration(this._users);

  List<BlockedUser> _users;
  final List<String> desbloqueados = <String>[];
  bool falla = false;

  @override
  Future<List<BlockedUser>> blockedUsers() async => _users;

  @override
  Future<void> unblock(String userId) async {
    if (falla) throw Exception('boom');
    desbloqueados.add(userId);
    _users = _users
        .where((BlockedUser u) => u.profile.userId != userId)
        .toList(growable: false);
  }

  @override
  Future<void> block(String userId) async {}

  @override
  Future<void> report(String userId, {String? conversationId}) async {}
}

void main() {
  test('carga la lista de bloqueados', () async {
    final _FakeModeration fake = _FakeModeration(<BlockedUser>[
      _bloqueado('u1', 'Ana'),
      _bloqueado('u2', 'Bruno'),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        moderationRepositoryProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    final BlockedUsersView vista = await container.read(
      blockedUsersControllerProvider.future,
    );

    expect(vista.users.map((BlockedUser u) => u.profile.userId), <String>[
      'u1',
      'u2',
    ]);
  });

  test('unblock quita la fila de la lista', () async {
    final _FakeModeration fake = _FakeModeration(<BlockedUser>[
      _bloqueado('u1', 'Ana'),
      _bloqueado('u2', 'Bruno'),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        moderationRepositoryProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await container.read(blockedUsersControllerProvider.future);
    await container
        .read(blockedUsersControllerProvider.notifier)
        .unblock('u1');

    expect(fake.desbloqueados, <String>['u1']);
    expect(
      container
          .read(blockedUsersControllerProvider)
          .requireValue
          .users
          .map((BlockedUser u) => u.profile.userId),
      <String>['u2'],
    );
  });

  test('si unblock falla, la fila NO desaparece de la lista', () async {
    // En una pantalla de privacidad, dejar la UI mostrando el estado deseado en vez del real es la
    // peor forma de mentir que puede tener: haria creer desbloqueada a una persona que no lo esta.
    // Mismo criterio que el interruptor de PrivacySection, que revierte al fallar.
    final _FakeModeration fake = _FakeModeration(<BlockedUser>[
      _bloqueado('u1', 'Ana'),
    ])..falla = true;
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        moderationRepositoryProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await container.read(blockedUsersControllerProvider.future);

    await expectLater(
      container.read(blockedUsersControllerProvider.notifier).unblock('u1'),
      throwsA(isA<Object>()),
    );
    expect(
      container
          .read(blockedUsersControllerProvider)
          .requireValue
          .users
          .length,
      1,
    );
  });
}
