import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/account/account_repository.dart';

/// Estado de la operación de borrar la cuenta.
///
/// Igual que [AvatarController]: no es el estado de la cuenta (que, si esto
/// sale bien, deja de existir), es el estado de **la operación en curso**,
/// para que la hoja pueda deshabilitar los campos y enseñar el error sin
/// cerrarse.
class AccountDeletionController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AccountRepository get _repository => ref.read(accountRepositoryProvider);

  /// Pide el borrado y, si el backend responde `200`, cierra la sesión local.
  ///
  /// No navega a ningún sitio: en cuanto `authStateProvider` emite `null` el
  /// `redirect` de `routerProvider` manda solo a `/` (ver `app_router.dart`),
  /// exactamente igual que el botón "Cerrar sesión" de `ProfileScreen`.
  /// `signOut()` es seguro de llamar aunque el usuario ya no exista en el
  /// backend: GoTrue ignora los 401/403/404 de esa llamada porque asume que
  /// el usuario podría no existir ya (ver `gotrue_client.dart`), que es
  /// exactamente este caso.
  ///
  /// Devuelve `true` si funcionó, para que la hoja sepa si cerrarse. Un
  /// fallo se queda en el estado (no se relanza): la hoja tiene que poder
  /// enseñarlo **sin cerrarse**, sobre todo si fue una contraseña incorrecta
  /// — cerrar la hoja obligaría a reintroducir la frase de confirmación
  /// entera para reintentar.
  Future<bool> deleteAccount({
    required String password,
    required String confirmationPhrase,
  }) async {
    state = const AsyncLoading<void>();
    try {
      await _repository.deleteAccount(
        password: password,
        confirmationPhrase: confirmationPhrase,
      );
      await ref.read(authRepositoryProvider).signOut();
      state = const AsyncData<void>(null);
      return true;
    } on Object catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return false;
    }
  }
}

final AutoDisposeAsyncNotifierProvider<AccountDeletionController, void>
accountDeletionControllerProvider =
    AsyncNotifierProvider.autoDispose<AccountDeletionController, void>(
      AccountDeletionController.new,
    );
