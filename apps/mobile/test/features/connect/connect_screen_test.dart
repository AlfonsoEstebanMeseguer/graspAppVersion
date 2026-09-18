import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/social/connect_candidate.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';
import 'package:grasp_mobile/domain/social/social_failure.dart';
import 'package:grasp_mobile/features/connect/application/connect_controller.dart';
import 'package:grasp_mobile/features/connect/presentation/connect_screen.dart';
import 'package:grasp_mobile/features/connect/presentation/widgets/connect_card.dart';
import 'package:grasp_mobile/features/connect/presentation/widgets/tag_result_card.dart';
import 'package:grasp_mobile/features/connect/presentation/widgets/tag_search_field.dart';

import '../../support/fake_connect_repository.dart';
import '../../support/fake_social_repositories.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeConnectRepository connect, {
  FakeFollowRepository? follows,
}) async {
  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        connectRepositoryProvider.overrideWithValue(connect),
        avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
        followRepositoryProvider.overrideWithValue(
          follows ?? FakeFollowRepository(),
        ),
      ],
      child: MaterialApp(theme: theme, home: const ConnectScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Los nombres de las tarjetas, en el orden en que se pintan.
List<String> _orden(WidgetTester tester) => tester
    .widgetList<ConnectCard>(find.byType(ConnectCard))
    .map((ConnectCard c) => c.candidate.displayName)
    .toList();

void main() {
  group('la lista', () {
    testWidgets('pinta una tarjeta por candidato', (WidgetTester tester) async {
      await _pump(
        tester,
        FakeConnectRepository(
          pages: <ConnectFeedPage>[
            fakePage(<ConnectCandidate>[
              fakeCandidate(userId: 'u1', displayName: 'Uno'),
              fakeCandidate(userId: 'u2', displayName: 'Dos'),
            ]),
          ],
        ),
      );
      expect(_orden(tester), <String>['Uno', 'Dos']);
    });

    testWidgets('RN-49: sin nadie, empty state EXPLÍCITO, no una lista vacía', (
      WidgetTester tester,
    ) async {
      await _pump(tester, FakeConnectRepository());
      expect(find.text(ConnectScreen.emptyState), findsOneWidget);
      expect(find.byType(ConnectCard), findsNothing);
    });

    testWidgets('RN-49: con un filtro activo, `relaxed` se le dice al usuario', (
      WidgetTester tester,
    ) async {
      // Si la tanda se puntuó sin el cuadrado del filtro, la lista no es la que el usuario pidió y
      // hay que decirlo — si no, parece que el filtro no funciona.
      await _pump(
        tester,
        FakeConnectRepository(
          pages: <ConnectFeedPage>[
            fakePage(<ConnectCandidate>[fakeCandidate(userId: 'u1')]),
            fakePage(<ConnectCandidate>[
              fakeCandidate(userId: 'u1'),
            ], relaxed: true),
          ],
        ),
      );
      expect(find.text(ConnectScreen.relaxedNotice), findsNothing);

      await tester.tap(find.text('Edad'));
      await tester.pumpAndSettle();

      expect(find.text(ConnectScreen.relaxedNotice), findsOneWidget);
    });

    testWidgets(
      'con `Todos` activo, `relaxed` NO se avisa: relajar no cambia nada',
      (WidgetTester tester) async {
        // ADR 0024: `relaxed` significa «puntuado SIN el cuadrado del filtro». Con `Todos` no hay
        // filtro que elevar al cuadrado, asi que relajar es un no-op y el aviso mentiria — ademas
        // de hablar de «ese filtro» cuando no hay ninguno.
        //
        // Salio mirando el emulador: el backend devuelve `relaxed: true` en cuanto hay menos de 20
        // elegibles, tambien sin filtros, y el aviso aparecia siempre en una base pequena.
        await _pump(
          tester,
          FakeConnectRepository(
            pages: <ConnectFeedPage>[
              fakePage(<ConnectCandidate>[
                fakeCandidate(userId: 'u1'),
              ], relaxed: true),
            ],
          ),
        );
        expect(find.text(ConnectScreen.relaxedNotice), findsNothing);
      },
    );

    testWidgets('sin `relaxed`, no se avisa de nada', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeConnectRepository(
          pages: <ConnectFeedPage>[
            fakePage(<ConnectCandidate>[fakeCandidate(userId: 'u1')]),
          ],
        ),
      );
      expect(find.text(ConnectScreen.relaxedNotice), findsNothing);
    });
  });

  group('RN-45 — la lista no se reordena al hacer scroll', () {
    testWidgets('hacer scroll no vuelve a pedir el feed ni cambia el orden', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = FakeConnectRepository(
        pages: <ConnectFeedPage>[
          fakePage(<ConnectCandidate>[
            for (int i = 0; i < 8; i++)
              fakeCandidate(userId: 'u$i', displayName: 'Persona $i'),
          ]),
        ],
      );
      await _pump(tester, connect);

      // Se compara el orden de la LISTA, no el de las tarjetas renderizadas: `ListView.builder`
      // solo construye las visibles, asi que tras el scroll las primeras ya no estan montadas y
      // `_orden` devolveria un trozo distinto aunque nada hubiera cambiado. Ese detalle hizo fallar
      // la primera version de este test por el motivo equivocado.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ConnectCard).first),
      );
      List<String> ordenReal() => container
          .read(connectControllerProvider)
          .requireValue
          .candidates
          .map((ConnectCandidate c) => c.displayName)
          .toList();

      final List<String> antes = ordenReal();
      expect(antes.length, 8);
      expect(connect.feedCalls.length, 1);

      await tester.drag(find.byType(ConnectCard).first, const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(
        ordenReal(),
        antes,
        reason: 'RN-45: la lista está cacheada durante la sesión.',
      );
      expect(
        connect.feedCalls.length,
        1,
        reason: 'Un scroll corto no puede regenerar la tanda.',
      );
    });
  });

  group('RN-46 — el pull-to-refresh SÍ la regenera', () {
    testWidgets('pide el feed con refresh:true y reemplaza la lista', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = FakeConnectRepository(
        pages: <ConnectFeedPage>[
          fakePage(<ConnectCandidate>[
            fakeCandidate(userId: 'u1', displayName: 'Vieja'),
          ]),
          fakePage(<ConnectCandidate>[
            fakeCandidate(userId: 'u2', displayName: 'Nueva'),
          ]),
        ],
      );
      await _pump(tester, connect);
      expect(_orden(tester), <String>['Vieja']);

      await tester.fling(find.byType(ConnectCard).first, const Offset(0, 320), 1000);
      await tester.pumpAndSettle();

      expect(connect.feedCalls.length, 2);
      expect(connect.feedCalls.last.refresh, isTrue);
      expect(
        _orden(tester),
        <String>['Nueva'],
        reason: 'RN-46: el pull-to-refresh REEMPLAZA, no añade.',
      );
    });

    testWidgets('al agotar el cupo diario se dice cuál y cuándo (RN-21)', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = _FailingRefresh(
        fakePage(<ConnectCandidate>[
          fakeCandidate(userId: 'u1', displayName: 'Uno'),
        ]),
      );
      await _pump(tester, connect);

      await tester.fling(find.byType(ConnectCard).first, const Offset(0, 320), 1000);
      await tester.pumpAndSettle();

      expect(find.textContaining('5'), findsWidgets);
      // Y la lista que ya estaba NO se pierde por un refresco rechazado.
      expect(_orden(tester), <String>['Uno']);
    });
  });

  group('RN-40 y decisión 8 — mensaje enviado frente a descarte', () {
    testWidgets('el ✕ quita la tarjeta al instante y llama al backend', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = FakeConnectRepository(
        pages: <ConnectFeedPage>[
          fakePage(<ConnectCandidate>[
            fakeCandidate(userId: 'u1', displayName: 'Uno'),
            fakeCandidate(userId: 'u2', displayName: 'Dos'),
          ]),
        ],
      );
      await _pump(tester, connect);

      await tester.tap(find.byKey(ConnectCard.dismissButtonKey).first);
      await tester.pumpAndSettle();

      expect(connect.dismissed, <String>['u1']);
      expect(_orden(tester), <String>['Dos']);
    });

    testWidgets(
      'RN-40: tras el primer mensaje la tarjeta SIGUE, solo cambia el botón',
      (WidgetTester tester) async {
        // La diferencia con el ✕ es el punto entero de RN-40: descartar quita la tarjeta ya;
        // escribir la deja hasta el siguiente refresco. Los dos tests van juntos porque lo que hay
        // que proteger es que NO se comporten igual.
        final FakeConnectRepository connect = FakeConnectRepository(
          pages: <ConnectFeedPage>[
            fakePage(<ConnectCandidate>[
              fakeCandidate(userId: 'u1', displayName: 'Uno'),
            ]),
          ],
        );
        await _pump(tester, connect);

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(ConnectCard)),
        );
        container.read(connectControllerProvider.notifier).markMessaged('u1');
        await tester.pumpAndSettle();

        expect(_orden(tester), <String>['Uno']);
        expect(find.text('Pendiente'), findsOneWidget);
      },
    );
  });

  group('§6.2 — búsqueda por tag', () {
    Future<void> buscar(WidgetTester tester, String tag) async {
      await tester.enterText(find.byType(TagSearchField), tag);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    testWidgets('un tag que no existe da el error inline del §6.2', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = FakeConnectRepository();
      await _pump(tester, connect);
      await buscar(tester, 'nadie#K7M2QX9F');

      expect(find.text(ConnectScreen.tagNotFound), findsOneWidget);
      expect(connect.tagsBuscados, <String>['nadie#K7M2QX9F']);
    });

    testWidgets(
      'RN-23: un tag CON BLOQUEO se pinta con el MISMO widget y el mismo texto',
      (WidgetTester tester) async {
        // El backend devuelve el mismo 404 en los dos casos, así que el repositorio devuelve `null`
        // en los dos y la pantalla **no tiene por dónde ramificar**. Este test lo fija: si alguien
        // añadiera una rama para el bloqueo, tendría que inventarse el dato — y ahí empezaría la
        // divergencia que RN-23 prohíbe.
        final FakeConnectRepository connect = FakeConnectRepository();
        await _pump(tester, connect);
        await buscar(tester, 'oculta#K7M2QX9F');

        expect(find.text(ConnectScreen.tagNotFound), findsOneWidget);
        // OJO CON EL TAG DE PRUEBA: la primera version buscaba 'bloqueada#...' y este `expect`
        // encontraba la palabra... en el propio campo de texto, porque el buscador conserva lo
        // tecleado. El test fallaba sin que nada estuviera mal.
        expect(find.textContaining('bloque'), findsNothing);
      },
    );

    testWidgets('tu propio tag SÍ se distingue', (WidgetTester tester) async {
      final FakeConnectRepository connect = FakeConnectRepository()
        ..lookupFailure = ownTagFailure;
      await _pump(tester, connect);
      await buscar(tester, 'yo#K7M2QX9F');

      expect(find.text('Ese es tu propio tag.'), findsOneWidget);
      expect(find.text(ConnectScreen.tagNotFound), findsNothing);
    });

    testWidgets('un tag que existe da su ficha con `Seguir`', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = FakeConnectRepository()
        ..tagResult = fakeTagResult(displayName: 'Ana');
      await _pump(tester, connect);
      await buscar(tester, 'ana#K7M2QX9F');

      expect(find.byType(TagResultCard), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text(TagResultCard.follow), findsOneWidget);
    });

    testWidgets('si ya le sigues, dice `Siguiendo`', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = FakeConnectRepository()
        ..tagResult = fakeTagResult(followState: FollowState.following);
      await _pump(tester, connect);
      await buscar(tester, 'ana#K7M2QX9F');

      expect(find.text(TagResultCard.following), findsOneWidget);
      expect(find.text(TagResultCard.follow), findsNothing);
    });

    testWidgets('con solicitud ya enviada, `Pendiente` deshabilitado', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = FakeConnectRepository()
        ..tagResult = fakeTagResult(followState: FollowState.pending);
      await _pump(tester, connect);
      await buscar(tester, 'ana#K7M2QX9F');

      expect(find.text(TagResultCard.pending), findsOneWidget);
    });

    testWidgets('enviar la solicitud deja el botón en `Pendiente`', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = FakeConnectRepository()
        ..tagResult = fakeTagResult();
      final FakeFollowRepository follows = FakeFollowRepository();
      await _pump(tester, connect, follows: follows);
      await buscar(tester, 'ana#K7M2QX9F');

      await tester.tap(find.text(TagResultCard.follow));
      await tester.pumpAndSettle();

      expect(follows.toggles.single.action, FollowAction.request);
      expect(find.text(TagResultCard.pending), findsOneWidget);
      expect(find.text(TagResultCard.follow), findsNothing);
    });
  });
}

/// Devuelve una tanda buena la primera vez y agota el cupo de `RN-46` en el refresco.
class _FailingRefresh extends FakeConnectRepository {
  _FailingRefresh(this.page);

  final ConnectFeedPage page;

  @override
  Future<ConnectFeedPage> feed({
    Set<ConnectFilter> filters = const <ConnectFilter>{},
    bool refresh = false,
  }) async {
    feedCalls.add((filters: Set<ConnectFilter>.of(filters), refresh: refresh));
    if (refresh) {
      throw const SocialFailure(
        SocialFailureKind.limitReached,
        'Has actualizado la lista 5 veces hoy. Podrás volver a actualizarla mañana a las 02:00.',
        limit: 5,
      );
    }
    return page;
  }
}
