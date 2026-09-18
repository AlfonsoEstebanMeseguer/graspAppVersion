import 'package:grasp_mobile/domain/account/account_deletion_failure.dart';
import 'package:grasp_mobile/domain/account/account_repository.dart';

/// Una llamada a `deleteAccount`, tal y como la recibió el doble.
typedef DeleteAccountCall = ({String password, String confirmationPhrase});

/// Doble de [AccountRepository] para tests.
///
/// Igual que `FakeAuthRepository`: no simula el backend, solo registra qué se
/// le pidió y devuelve lo que se le programe.
class FakeAccountRepository implements AccountRepository {
  /// Llamadas recibidas, en orden.
  final List<DeleteAccountCall> calls = <DeleteAccountCall>[];

  /// Si se asigna, la siguiente llamada lanza este fallo.
  AccountDeletionFailure? nextFailure;

  @override
  Future<void> deleteAccount({
    required String password,
    required String confirmationPhrase,
  }) async {
    calls.add((password: password, confirmationPhrase: confirmationPhrase));
    final AccountDeletionFailure? failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
  }
}
