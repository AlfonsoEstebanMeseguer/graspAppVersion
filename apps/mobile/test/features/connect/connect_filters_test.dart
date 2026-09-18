import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/router/app_router.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/features/connect/presentation/connect_screen.dart';
import 'package:grasp_mobile/domain/social/connect_candidate.dart';
import 'package:grasp_mobile/domain/social/conversation_summary.dart';
import 'package:grasp_mobile/features/connect/presentation/widgets/connect_filter_chips.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_connect_repository.dart';
import '../../support/fake_social_repositories.dart';

/// Tests de los chips de filtro del §6.3 — `RN-34` a `RN-37`.
FakeAvatarRepository _noAvatars() => FakeAvatarRepository();

FakeMessagingRepository _emptyInbox() => FakeMessagingRepository(
  const InboxSnapshot(
    contacts: <ConversationSummary>[],
    requests: <ConversationSummary>[],
    requestsCount: 0,
  ),
);

FakeConnectRepository _unCandidato() => FakeConnectRepository(
  pages: <ConnectFeedPage>[
    fakePage(<ConnectCandidate>[
      fakeCandidate(userId: 'u1', displayName: 'Uno'),
    ]),
  ],
);

Future<FakeConnectRepository> _pump(WidgetTester tester) async {
  final FakeConnectRepository connect = _unCandidato();

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        connectRepositoryProvider.overrideWithValue(connect),
        avatarRepositoryProvider.overrideWithValue(_noAvatars()),
      ],
      child: MaterialApp(theme: theme, home: const ConnectScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return connect;
}

/// Qué chips están activos ahora mismo, en el orden en que se pintan.
Set<String> _activos(WidgetTester tester) => tester
    .widgetList<ConnectFilterChip>(find.byType(ConnectFilterChip))
    .where((ConnectFilterChip c) => c.selected)
    .map((ConnectFilterChip c) => c.label)
    .toSet();

void main() {
  group('§6.3 — los cinco chips', () {
    testWidgets('están los cinco, y `Todos` el primero', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      expect(
        tester
            .widgetList<ConnectFilterChip>(find.byType(ConnectFilterChip))
            .map((ConnectFilterChip c) => c.label)
            .toList(),
        <String>[
          'Todos',
          'Edad',
          'Intereses',
          'Situación sufrida',
          'Situación correspondida',
        ],
      );
    });

    testWidgets('RN-35: `Todos` es visible y es el estado por defecto', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      expect(find.text('Todos'), findsOneWidget);
      expect(_activos(tester), <String>{'Todos'});
    });
  });

  group('RN-34 — selección múltiple', () {
    testWidgets('se pueden activar dos a la vez', (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Edad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intereses'));
      await tester.pumpAndSettle();

      expect(_activos(tester), <String>{'Edad', 'Intereses'});
    });

    testWidgets('activar uno apaga `Todos`', (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Edad'));
      await tester.pumpAndSettle();

      expect(_activos(tester).contains('Todos'), isFalse);
    });

    testWidgets('apagar el último vuelve a `Todos`', (
      WidgetTester tester,
    ) async {
      // Sin esto, quedarse con cero chips sería un estado distinto de `Todos` que la spec no define
      // y que el backend interpreta igual — pero la pantalla mentiría sobre lo que está filtrando.
      await _pump(tester);
      await tester.tap(find.text('Edad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edad'));
      await tester.pumpAndSettle();

      expect(_activos(tester), <String>{'Todos'});
    });

    testWidgets('`Todos` es lo que se manda como lista VACÍA, no como "all"', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = await _pump(tester);
      expect(connect.feedCalls.first.filters, isEmpty);
    });
  });

  group('RN-36 — pulsar `Todos` apaga el resto', () {
    testWidgets('con dos activos, `Todos` los apaga los dos', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Edad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Situación sufrida'));
      await tester.pumpAndSettle();
      expect(_activos(tester).length, 2);

      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      expect(_activos(tester), <String>{'Todos'});
    });
  });

  group('el filtro llega al backend', () {
    testWidgets('cambiar un chip vuelve a pedir el feed con ese filtro', (
      WidgetTester tester,
    ) async {
      final FakeConnectRepository connect = await _pump(tester);
      await tester.tap(find.text('Edad'));
      await tester.pumpAndSettle();

      expect(connect.feedCalls.length, 2);
      expect(
        connect.feedCalls.last.filters.map((dynamic f) => f.wireValue).toSet(),
        <String>{'age'},
      );
      expect(
        connect.feedCalls.last.refresh,
        isFalse,
        reason:
            'Cambiar de filtro NO es un pull-to-refresh: no puede gastar el cupo de 5 al día '
            'de RN-46.',
      );
    });
  });

  group('RN-37 — el filtro NO persiste', () {
    testWidgets('remontar la pantalla lo devuelve a `Todos`', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Edad'));
      await tester.pumpAndSettle();
      expect(_activos(tester), <String>{'Edad'});

      // Desmontar y volver a montar.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pump(tester);

      expect(_activos(tester), <String>{'Todos'});
    });

    testWidgets(
      'volver a la pestaña desde otra TAMBIÉN lo devuelve a `Todos`',
      (WidgetTester tester) async {
        // ESTE ES EL TEST QUE DE VERDAD PROTEGE RN-37, Y EL QUE EL PLAN NO PEDÍA.
        //
        // El plan decía «se prueba desmontando y remontando, que es donde se rompe». Pero el shell
        // es `StatefulShellRoute.indexedStack`: **las cuatro ramas siguen montadas** al cambiar de
        // pestaña, así que ConnectScreen NO se desmonta y el test de arriba pasaría con una
        // implementación que guarda el filtro en el `State` y no lo reinicia nunca.
        //
        // Cambiar de pestaña y volver es lo que hace un usuario de verdad, y es donde la regla se
        // rompe. Por eso este test monta el router completo en vez de la pantalla suelta.
        final FakeAuthRepository auth = FakeAuthRepository();
        addTearDown(auth.dispose);
        final FakeConnectRepository connect = _unCandidato();

        final ThemeData theme = AppTheme.light().copyWith(
          extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              authRepositoryProvider.overrideWith((Ref ref) => auth),
              hasCompletedOnboardingProvider.overrideWith(
                (Ref ref) async => true,
              ),
              connectRepositoryProvider.overrideWithValue(connect),
              avatarRepositoryProvider.overrideWithValue(_noAvatars()),
              messagingRepositoryProvider.overrideWithValue(_emptyInbox()),
            ],
            child: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                  MaterialApp.router(
                    theme: theme,
                    routerConfig: ref.watch(routerProvider),
                  ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        auth.emitSignedIn('cf3969f3-6180-4606-9896-f91aaad58fc4');
        await tester.pumpAndSettle();

        // A Conectar, activar un filtro.
        await tester.tap(find.text('Conectar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edad'));
        await tester.pumpAndSettle();
        expect(_activos(tester), <String>{'Edad'});

        // A Mensajes y de vuelta.
        await tester.tap(find.text('Mensajes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Conectar'));
        await tester.pumpAndSettle();

        expect(
          _activos(tester),
          <String>{'Todos'},
          reason:
              'RN-37: cada vez que se ENTRA en Conectar el filtro vuelve a Todos. Con '
              'indexedStack la pantalla no se desmonta, así que hay que reiniciarlo al volver '
              'a ser visible.',
        );

        // Y NO BASTA CON QUE LOS CHIPS LO DIGAN: el filtro que de verdad manda es el que va al
        // backend. Sin esta comprobación, un `resetFilters()` que no hiciera nada seguiría pasando
        // el test —la pantalla repinta los chips por su cuenta— y quedaría una regla a medias:
        // «Todos» seleccionado sobre una lista todavía filtrada por edad. Se descubrió mutando el
        // controlador para vaciar ese método.
        expect(
          connect.feedCalls.last.filters,
          isEmpty,
          reason: 'El reinicio tiene que llegar al backend, no solo a los chips.',
        );
      },
    );
  });
}
