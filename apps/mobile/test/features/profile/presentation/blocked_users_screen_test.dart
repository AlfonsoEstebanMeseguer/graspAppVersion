import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/domain/social/blocked_user.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';
import 'package:grasp_mobile/features/profile/application/blocked_users_controller.dart';
import 'package:grasp_mobile/features/profile/presentation/blocked_users_screen.dart';

BlockedUser _u(String id, String nombre) => BlockedUser(
  profile: SocialProfileRef(userId: id, displayName: nombre, tag: '$nombre#AAAA1111'),
  blockedAt: DateTime(2026, 8, 20),
);

/// Sustituye al controlador real: la pantalla se prueba contra el dominio, nunca contra Supabase.
class _FakeController extends BlockedUsersController {
  _FakeController(this._view, {this.falla = false});

  final BlockedUsersView _view;
  final bool falla;
  final List<String> desbloqueados = <String>[];

  @override
  Future<BlockedUsersView> build() async => _view;

  @override
  Future<void> unblock(String userId) async {
    if (falla) throw Exception('boom');
    desbloqueados.add(userId);
  }
}

Future<void> _montar(WidgetTester tester, BlockedUsersController fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        blockedUsersControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: BlockedUsersScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pinta una fila por persona bloqueada', (WidgetTester tester) async {
    await _montar(
      tester,
      _FakeController(
        BlockedUsersView(
          users: <BlockedUser>[_u('u1', 'Ana'), _u('u2', 'Bruno')],
          photoUrls: const <String, String>{},
        ),
      ),
    );

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.byKey(BlockedUsersScreen.actionKeyFor('u1')), findsOneWidget);
  });

  testWidgets('sin nadie bloqueado sale el empty state, no una lista vacia', (
    WidgetTester tester,
  ) async {
    await _montar(
      tester,
      _FakeController(
        const BlockedUsersView(
          users: <BlockedUser>[],
          photoUrls: <String, String>{},
        ),
      ),
    );

    expect(find.text(BlockedUsersScreen.empty), findsOneWidget);
    expect(find.text(BlockedUsersScreen.loadError), findsNothing);
  });

  testWidgets('el modal dice lo que el desbloqueo revela (ADR 0027)', (
    WidgetTester tester,
  ) async {
    await _montar(
      tester,
      _FakeController(
        BlockedUsersView(
          users: <BlockedUser>[_u('u1', 'Ana')],
          photoUrls: const <String, String>{},
        ),
      ),
    );

    await tester.tap(find.byKey(BlockedUsersScreen.actionKeyFor('u1')));
    await tester.pumpAndSettle();

    // La frase entera es el requisito, no un detalle de copy: es lo unico que le da a quien
    // desbloquea la informacion para decidir.
    expect(find.textContaining('Puede deducir que la habías bloqueado'), findsOneWidget);
    expect(find.byKey(BlockedUsersScreen.confirmKey), findsOneWidget);
    expect(find.byKey(BlockedUsersScreen.cancelKey), findsOneWidget);
  });

  testWidgets('cancelar el modal NO desbloquea', (WidgetTester tester) async {
    final _FakeController fake = _FakeController(
      BlockedUsersView(
        users: <BlockedUser>[_u('u1', 'Ana')],
        photoUrls: const <String, String>{},
      ),
    );
    await _montar(tester, fake);

    await tester.tap(find.byKey(BlockedUsersScreen.actionKeyFor('u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BlockedUsersScreen.cancelKey));
    await tester.pumpAndSettle();

    expect(fake.desbloqueados, isEmpty);
  });

  testWidgets('confirmar el modal desbloquea', (WidgetTester tester) async {
    final _FakeController fake = _FakeController(
      BlockedUsersView(
        users: <BlockedUser>[_u('u1', 'Ana')],
        photoUrls: const <String, String>{},
      ),
    );
    await _montar(tester, fake);

    await tester.tap(find.byKey(BlockedUsersScreen.actionKeyFor('u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BlockedUsersScreen.confirmKey));
    await tester.pumpAndSettle();

    expect(fake.desbloqueados, <String>['u1']);
  });

  testWidgets('si el desbloqueo falla, se dice; no se finge que funciono', (
    WidgetTester tester,
  ) async {
    final _FakeController fake = _FakeController(
      BlockedUsersView(
        users: <BlockedUser>[_u('u1', 'Ana')],
        photoUrls: const <String, String>{},
      ),
      falla: true,
    );
    await _montar(tester, fake);

    await tester.tap(find.byKey(BlockedUsersScreen.actionKeyFor('u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BlockedUsersScreen.confirmKey));
    await tester.pumpAndSettle();

    expect(find.text(BlockedUsersScreen.unblockFailed), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('cota conservadora de overflow a 800x600', (WidgetTester tester) async {
    // Un test de widget NO ve un overflow de movil: corre a 800x600 —mas ancho que cualquier
    // telefono— y con fuente de fallback, porque google_fonts no descarga nada en tests. Ademas un
    // overflow no tumba el test salvo que se recoja con takeException(). Sirve como cota
    // conservadora: si SALTA aqui, en un movil es peor. Lo contrario no se puede concluir.
    await _montar(
      tester,
      _FakeController(
        BlockedUsersView(
          users: <BlockedUser>[
            _u('u1', 'Una persona con un nombre francamente largo de verdad'),
          ],
          photoUrls: const <String, String>{},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
