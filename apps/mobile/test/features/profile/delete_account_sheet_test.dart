import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/account/account_deletion_failure.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/delete_account_sheet.dart';

import '../../support/fake_account_repository.dart';
import '../../support/fake_auth_repository.dart';

const String _kSubmitLabel = 'Eliminar cuenta definitivamente';

Future<void> _pumpSheet(
  WidgetTester tester, {
  required FakeAccountRepository account,
  required FakeAuthRepository auth,
}) async {
  auth.emitSignedIn('user-test');

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(account),
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => DeleteAccountSheet.show(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explica antes de los campos qué se borra y qué se conserva', (
    WidgetTester tester,
  ) async {
    final FakeAccountRepository account = FakeAccountRepository();
    final FakeAuthRepository auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await _pumpSheet(tester, account: account, auth: auth);

    expect(find.textContaining('no se puede deshacer'), findsOneWidget);
    expect(find.textContaining('90 días'), findsOneWidget);
    expect(find.textContaining('perfil'), findsWidgets);
  });

  testWidgets('el borrado no se dispara sin las dos confirmaciones', (
    WidgetTester tester,
  ) async {
    final FakeAccountRepository account = FakeAccountRepository();
    final FakeAuthRepository auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await _pumpSheet(tester, account: account, auth: auth);

    // Campos vacíos.
    await tester.tap(find.text(_kSubmitLabel));
    await tester.pumpAndSettle();
    expect(account.calls, isEmpty);

    // Solo contraseña.
    await tester.enterText(find.byType(TextField).at(0), 'hunter2');
    await tester.pump();
    await tester.tap(find.text(_kSubmitLabel));
    await tester.pumpAndSettle();
    expect(account.calls, isEmpty);

    // Frase incorrecta.
    await tester.enterText(find.byType(TextField).at(1), 'no es la frase');
    await tester.pump();
    await tester.tap(find.text(_kSubmitLabel));
    await tester.pumpAndSettle();
    expect(account.calls, isEmpty);

    // Las dos correctas — normalizada igual que el backend (espacios y minúsculas valen).
    await tester.enterText(find.byType(TextField).at(1), '  borrar mi cuenta  ');
    await tester.pump();
    await tester.tap(find.text(_kSubmitLabel));
    await tester.pumpAndSettle();
    expect(account.calls, hasLength(1));
  });

  testWidgets(
    'las dos confirmaciones correctas borran la cuenta, cierran sesión y cierran la hoja',
    (WidgetTester tester) async {
      final FakeAccountRepository account = FakeAccountRepository();
      final FakeAuthRepository auth = FakeAuthRepository();
      addTearDown(auth.dispose);
      await _pumpSheet(tester, account: account, auth: auth);

      await tester.enterText(find.byType(TextField).at(0), 'hunter2');
      await tester.enterText(find.byType(TextField).at(1), 'BORRAR MI CUENTA');
      await tester.pump();
      await tester.tap(find.text(_kSubmitLabel));
      await tester.pumpAndSettle();

      expect(account.calls, <DeleteAccountCall>[
        (password: 'hunter2', confirmationPhrase: 'BORRAR MI CUENTA'),
      ]);
      expect(auth.currentUserId, isNull); // signOut() se disparó
      expect(find.byType(DeleteAccountSheet), findsNothing); // la hoja se cerró
    },
  );

  testWidgets(
    'un 401 de contraseña incorrecta se enseña DENTRO de la hoja, sin cerrar sesión ni navegar',
    (WidgetTester tester) async {
      final FakeAccountRepository account = FakeAccountRepository()
        ..nextFailure = const AccountDeletionFailure(
          AccountDeletionFailureKind.wrongPassword,
        );
      final FakeAuthRepository auth = FakeAuthRepository();
      addTearDown(auth.dispose);
      await _pumpSheet(tester, account: account, auth: auth);

      await tester.enterText(find.byType(TextField).at(0), 'contraseña-mala');
      await tester.enterText(find.byType(TextField).at(1), 'BORRAR MI CUENTA');
      await tester.pump();
      await tester.tap(find.text(_kSubmitLabel));
      await tester.pumpAndSettle();

      expect(find.text('La contraseña no es correcta. Inténtalo de nuevo.'), findsOneWidget);
      expect(find.byType(DeleteAccountSheet), findsOneWidget); // sigue abierta
      expect(auth.currentUserId, 'user-test'); // NO cerró sesión
    },
  );

  testWidgets('un error nunca enseña el rawMessage crudo del backend', (
    WidgetTester tester,
  ) async {
    final FakeAccountRepository account = FakeAccountRepository()
      ..nextFailure = const AccountDeletionFailure(
        AccountDeletionFailureKind.unknown,
        rawMessage: 'internal_error: stack trace interno con detalles de servidor',
      );
    final FakeAuthRepository auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await _pumpSheet(tester, account: account, auth: auth);

    await tester.enterText(find.byType(TextField).at(0), 'hunter2');
    await tester.enterText(find.byType(TextField).at(1), 'BORRAR MI CUENTA');
    await tester.pump();
    await tester.tap(find.text(_kSubmitLabel));
    await tester.pumpAndSettle();

    expect(find.textContaining('stack trace interno'), findsNothing);
    expect(find.text('Algo no ha ido bien. Inténtalo de nuevo en unos segundos.'), findsOneWidget);
  });
}
