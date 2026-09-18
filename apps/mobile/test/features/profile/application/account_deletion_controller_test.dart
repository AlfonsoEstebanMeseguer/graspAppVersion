import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/account/account_deletion_failure.dart';
import 'package:grasp_mobile/features/profile/application/account_deletion_controller.dart';

import '../../../support/fake_account_repository.dart';
import '../../../support/fake_auth_repository.dart';

void main() {
  late FakeAccountRepository fakeAccount;
  late FakeAuthRepository fakeAuth;
  late ProviderContainer container;

  setUp(() {
    fakeAccount = FakeAccountRepository();
    fakeAuth = FakeAuthRepository();
    container = ProviderContainer(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(fakeAccount),
        authRepositoryProvider.overrideWithValue(fakeAuth),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(fakeAuth.dispose);
  });

  test('éxito: manda las dos credenciales tal cual y cierra la sesión local', () async {
    fakeAuth.emitSignedIn('user-test');

    final AccountDeletionController controller = container.read(
      accountDeletionControllerProvider.notifier,
    );
    final bool ok = await controller.deleteAccount(
      password: 'hunter2',
      confirmationPhrase: ' borrar mi cuenta ',
    );

    expect(ok, isTrue);
    expect(fakeAccount.calls, <DeleteAccountCall>[
      (password: 'hunter2', confirmationPhrase: ' borrar mi cuenta '),
    ]);
    // El repositorio NO normaliza — eso lo hace el backend. Aquí solo se
    // comprueba que el controller no reescribe lo que el usuario escribió.
    expect(fakeAuth.currentUserId, isNull); // signOut() se disparó
  });

  test('un 401 de contraseña incorrecta NO cierra la sesión ni se relanza', () async {
    fakeAuth.emitSignedIn('user-test');
    fakeAccount.nextFailure = const AccountDeletionFailure(
      AccountDeletionFailureKind.wrongPassword,
    );

    final AccountDeletionController controller = container.read(
      accountDeletionControllerProvider.notifier,
    );
    final bool ok = await controller.deleteAccount(
      password: 'contraseña-mala',
      confirmationPhrase: 'BORRAR MI CUENTA',
    );

    expect(ok, isFalse);
    // La sesión sigue viva: un error recuperable no debe echar al usuario.
    expect(fakeAuth.currentUserId, 'user-test');

    final AsyncValue<void> state = container.read(accountDeletionControllerProvider);
    expect(state.hasError, isTrue);
    expect(
      (state.error as AccountDeletionFailure).kind,
      AccountDeletionFailureKind.wrongPassword,
    );
  });
}
