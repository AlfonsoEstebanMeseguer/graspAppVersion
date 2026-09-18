import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/profile/avatar_type.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';
import 'package:grasp_mobile/features/profile/application/follows_controller.dart';
import 'package:grasp_mobile/features/profile/presentation/follow_requests_screen.dart';
import 'package:grasp_mobile/features/profile/presentation/follows_screen.dart';

import '../../support/fake_profile_repositories.dart';
import '../../support/fake_social_repositories.dart';

/// Las listas de seguidores/seguidos y las solicitudes de seguimiento — §10, `RN-50` a `RN-54`.
///
/// Boceto: `08-profile.jpeg`, con la derivación acordada el 2026-08-23 (patrón de
/// `ProfileBadgesModal`: cabecera centrada, tarjetas blancas de radio ~20, filas con foto + nombre
/// + tag, acciones al final de la fila).
const String _ana = '00000000-0000-4000-8000-0000000000a1';
const String _luis = '00000000-0000-4000-8000-0000000000b2';

SocialProfileRef _perfil(
  String userId,
  String nombre, {
  String? tag,
  String? photoPath,
}) => SocialProfileRef(
  userId: userId,
  displayName: nombre,
  tag: tag,
  presetAvatar: AvatarType.reader,
  photoPath: photoPath,
);

FollowEdge _edge(SocialProfileRef p, {int minuto = 0}) => FollowEdge(
  profile: p,
  status: FollowState.following,
  createdAt: DateTime.utc(2026, 8, 26, 10, minuto),
);

FollowRequest _request(SocialProfileRef p, {int minuto = 0}) =>
    FollowRequest(profile: p, createdAt: DateTime.utc(2026, 8, 26, 10, minuto));

typedef _Dobles = ({
  FakeFollowRepository follows,
  FakeProfileRepository profile,
  FakeAvatarRepository avatars,
});

Future<_Dobles> _pump(
  WidgetTester tester,
  Widget pantalla, {
  List<FollowEdge> followers = const <FollowEdge>[],
  List<FollowEdge> following = const <FollowEdge>[],
  List<FollowRequest> requests = const <FollowRequest>[],
  Map<String, String> photos = const <String, String>{},
  FakeFollowRepository? repo,
}) async {
  final FakeFollowRepository follows = repo ?? FakeFollowRepository();
  follows
    ..followersList = followers
    ..followingList = following
    ..requestsList = requests;

  final FakeProfileRepository profile = FakeProfileRepository();
  final FakeAvatarRepository avatars = FakeAvatarRepository(urls: photos);

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        followRepositoryProvider.overrideWithValue(follows),
        profileRepositoryProvider.overrideWithValue(profile),
        avatarRepositoryProvider.overrideWithValue(avatars),
      ],
      child: MaterialApp(theme: theme, home: pantalla),
    ),
  );
  await tester.pumpAndSettle();
  return (follows: follows, profile: profile, avatars: avatars);
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // RN-50 — LAS DOS LISTAS
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-50 — Seguidores y Seguidos', () {
    testWidgets('cada fila trae foto, nombre y TAG (RN-52)', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.followers),
        followers: <FollowEdge>[
          _edge(_perfil(_ana, 'Ana', tag: 'ana#K7M2QX9F')),
        ],
      );

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('ana#K7M2QX9F'), findsOneWidget);
    });

    testWidgets('la lista vacía lo dice, no se queda en blanco', (
      WidgetTester tester,
    ) async {
      await _pump(tester, const FollowsScreen(tab: FollowsTab.followers));
      expect(find.text(FollowsScreen.emptyFollowers), findsOneWidget);
    });

    testWidgets('Seguidos y Seguidores piden listas DISTINTAS', (
      WidgetTester tester,
    ) async {
      // Sin esto, una pantalla que pidiera siempre `followers()` pasaría los demás tests: las dos
      // pestañas se ven igual y el doble devolvería filas en las dos.
      final _Dobles d = await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.following),
        followers: <FollowEdge>[_edge(_perfil(_ana, 'Ana'))],
        following: <FollowEdge>[_edge(_perfil(_luis, 'Luis'))],
      );

      expect(find.text('Luis'), findsOneWidget);
      expect(find.text('Ana'), findsNothing);
      expect(d.follows.followingCalls, 1);
      expect(d.follows.followersCalls, 0);
    });

    testWidgets('la foto se pide POR LOTE, y solo de quien tiene', (
      WidgetTester tester,
    ) async {
      // Mismo patrón que la bandeja: `profile-photo-view-url` acepta un array justo para esto.
      // Pedir la de quien no tiene foto gasta una firma para nada.
      final _Dobles d = await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.followers),
        followers: <FollowEdge>[
          _edge(_perfil(_ana, 'Ana', photoPath: 'avatars/a/1.webp')),
          _edge(_perfil(_luis, 'Luis'), minuto: 1),
        ],
      );

      expect(d.avatars.batchCalls, 1);
      expect(d.avatars.lastRequestedIds, <String>[_ana]);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-53 — DEJAR DE SEGUIR Y ELIMINAR SEGUIDORES
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-53 — quitar de la lista', () {
    testWidgets('en Seguidos la acción es `unfollow`', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.following),
        following: <FollowEdge>[_edge(_perfil(_luis, 'Luis'))],
      );

      await tester.tap(find.byKey(FollowsScreen.actionKeyFor(_luis)));
      await tester.pumpAndSettle();

      expect(d.follows.toggles.single.action, FollowAction.unfollow);
      expect(d.follows.toggles.single.targetId, _luis);
      expect(find.text('Luis'), findsNothing);
    });

    testWidgets('en Seguidores la acción es `remove_follower`, NO `unfollow`', (
      WidgetTester tester,
    ) async {
      // Son dos llamadas distintas y confundirlas hace lo contrario de lo que se pidió: quien
      // quería quitarse a alguien de encima acabaría dejando de seguirlo él.
      final _Dobles d = await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.followers),
        followers: <FollowEdge>[_edge(_perfil(_ana, 'Ana'))],
      );

      await tester.tap(find.byKey(FollowsScreen.actionKeyFor(_ana)));
      await tester.pumpAndSettle();

      expect(d.follows.toggles.single.action, FollowAction.removeFollower);
    });

    testWidgets('las dos etiquetas son distintas, porque las acciones lo son', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.following),
        following: <FollowEdge>[_edge(_perfil(_luis, 'Luis'))],
      );
      expect(find.text(FollowsTab.following.actionLabel), findsOneWidget);
      expect(find.text(FollowsTab.followers.actionLabel), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-51 — LA ENTRADA A LAS SOLICITUDES, CON SU CONTADOR
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-51 — solicitudes de seguimiento', () {
    testWidgets('la entrada vive DENTRO de Seguidores, y solo ahí', (
      WidgetTester tester,
    ) async {
      // `RN-51`: «dentro de Seguidores». En Seguidos no pinta nada: las solicitudes que uno recibe
      // no tienen que ver con la gente a la que uno sigue.
      await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.followers),
        requests: <FollowRequest>[_request(_perfil(_ana, 'Ana'))],
      );
      expect(find.byKey(FollowsScreen.requestsEntryKey), findsOneWidget);

      await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.following),
        requests: <FollowRequest>[_request(_perfil(_ana, 'Ana'))],
      );
      expect(find.byKey(FollowsScreen.requestsEntryKey), findsNothing);
    });

    testWidgets('el contador dice cuántas hay', (WidgetTester tester) async {
      await _pump(
        tester,
        const FollowsScreen(tab: FollowsTab.followers),
        requests: <FollowRequest>[
          _request(_perfil(_ana, 'Ana')),
          _request(_perfil(_luis, 'Luis'), minuto: 1),
        ],
      );
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('sin solicitudes NO se pinta la entrada', (
      WidgetTester tester,
    ) async {
      // Una entrada que lleva a una lista vacía es un viaje en balde, y un contador a cero es
      // ruido. Es el mismo criterio que el `(N)` de la bandeja, visible solo si N > 0.
      await _pump(tester, const FollowsScreen(tab: FollowsTab.followers));
      expect(find.byKey(FollowsScreen.requestsEntryKey), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-52, RN-13, RN-14, RN-16 — ACEPTAR Y RECHAZAR
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-52 — la pantalla de solicitudes', () {
    testWidgets('cada fila trae foto, nombre, tag y las DOS acciones', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const FollowRequestsScreen(),
        requests: <FollowRequest>[
          _request(_perfil(_ana, 'Ana', tag: 'ana#K7M2QX9F')),
        ],
      );

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('ana#K7M2QX9F'), findsOneWidget);
      expect(find.byKey(FollowRequestsScreen.acceptKeyFor(_ana)), findsOneWidget);
      expect(find.byKey(FollowRequestsScreen.rejectKeyFor(_ana)), findsOneWidget);
    });

    testWidgets('aceptar llama a `accept` y saca la fila de la lista', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(
        tester,
        const FollowRequestsScreen(),
        requests: <FollowRequest>[_request(_perfil(_ana, 'Ana'))],
      );

      await tester.tap(find.byKey(FollowRequestsScreen.acceptKeyFor(_ana)));
      await tester.pumpAndSettle();

      expect(d.follows.toggles.single.action, FollowAction.accept);
      expect(d.follows.toggles.single.targetId, _ana);
      expect(find.text('Ana'), findsNothing);
    });

    testWidgets('rechazar llama a `reject`, que BORRA la fila (RN-16)', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(
        tester,
        const FollowRequestsScreen(),
        requests: <FollowRequest>[_request(_perfil(_ana, 'Ana'))],
      );

      await tester.tap(find.byKey(FollowRequestsScreen.rejectKeyFor(_ana)));
      await tester.pumpAndSettle();

      expect(d.follows.toggles.single.action, FollowAction.reject);
      expect(find.text('Ana'), findsNothing);
    });

    testWidgets('aceptar NO abre conversación (RN-14) ni sigue de vuelta (RN-13)', (
      WidgetTester tester,
    ) async {
      // `RN-13`: el follow es UNIDIRECCIONAL — quien acepta no pasa a seguir a nadie. `RN-14`: y no
      // nace ninguna conversación. Las dos se comprueban por lo que NO se llamó: un `request` de
      // vuelta, o cualquier envío de mensaje.
      final FakeMessagingRepository messaging = FakeMessagingRepository();
      final FakeFollowRepository follows = FakeFollowRepository()
        ..requestsList = <FollowRequest>[_request(_perfil(_ana, 'Ana'))];

      final ThemeData theme = AppTheme.light().copyWith(
        extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            followRepositoryProvider.overrideWithValue(follows),
            messagingRepositoryProvider.overrideWithValue(messaging),
            profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
            avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
          ],
          child: MaterialApp(theme: theme, home: const FollowRequestsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(FollowRequestsScreen.acceptKeyFor(_ana)));
      await tester.pumpAndSettle();

      expect(follows.toggles.length, 1, reason: 'RN-13: aceptar no sigue de vuelta');
      expect(follows.toggles.single.action, FollowAction.accept);
      expect(messaging.sent, isEmpty, reason: 'RN-14: aceptar no abre conversación');
    });

    testWidgets('la lista vacía lo dice', (WidgetTester tester) async {
      await _pump(tester, const FollowRequestsScreen());
      expect(find.text(FollowRequestsScreen.empty), findsOneWidget);
    });
  });
}
