import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/account/account_deletion_failure.dart';
import '../../domain/account/account_repository.dart';

/// Implementación de [AccountRepository] sobre la Edge Function `account-delete`.
///
/// Es la única función que borra la cuenta: pide reautenticación por
/// contraseña y la frase de confirmación, y solo si las dos son correctas
/// dispara la cascada RGPD ya probada en el backend (perfil, foto encolada
/// para R2, respuestas del onboarding, experiencias, insignias). Hasta este
/// bloque esa cascada solo se podía disparar a mano desde el panel de
/// Supabase (hallazgo H-SV-02 de la auditoría de 2026-08-15).
///
/// `functions.invoke` de este paquete **lanza** `FunctionException` en
/// cualquier estado que no sea 2xx (no devuelve un `FunctionResponse` con
/// `status` de error) — a diferencia de lo que asume
/// `SupabaseAvatarRepository._throwIfError`, aquí el mapeo de errores vive en
/// el `catch`, no en una comprobación de `response.status` después del
/// `await`. La versión resuelta (`functions_client` 2.6.4, ver
/// `pubspec.lock`) no tiene subclases (`FunctionsHttpException` etc. son de
/// versiones más nuevas): un fallo de red ni siquiera llega a construir un
/// `FunctionException`, lanza lo que lance `http.Client.send` — de ahí el
/// `catch` genérico de más abajo con la heurística de red.
class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> deleteAccount({
    required String password,
    required String confirmationPhrase,
  }) async {
    try {
      await _client.functions.invoke(
        'account-delete',
        body: <String, dynamic>{
          'password': password,
          'confirmation': confirmationPhrase,
        },
      );
      // Sin excepción == 2xx. El contrato solo define `200 { "success": true }`.
    } on FunctionException catch (error) {
      throw AccountDeletionFailure(
        _kindOf(error),
        rawMessage: '${error.status}: ${error.details}',
      );
    } on AuthException catch (error) {
      // El propio SDK detectó que no hay JWT válido con el que llamar a la
      // función (sesión ya caducada localmente), antes de llegar al backend.
      throw AccountDeletionFailure(
        AccountDeletionFailureKind.sessionExpired,
        rawMessage: error.message,
      );
    } on Object catch (error) {
      final String message = error.toString();
      final bool looksLikeNetwork =
          message.contains('SocketException') ||
          message.contains('ClientException') ||
          message.contains('Failed host lookup');
      throw AccountDeletionFailure(
        looksLikeNetwork
            ? AccountDeletionFailureKind.network
            : AccountDeletionFailureKind.unknown,
        rawMessage: message,
      );
    }
  }

  /// Traduce el `error` (código estable del contrato) a una causa de dominio.
  ///
  /// Se mira el código, nunca el `message`: enseñar el texto interno del
  /// backend es justo el hallazgo H-A-02 de la auditoría de 2026-08-15.
  AccountDeletionFailureKind _kindOf(FunctionException error) {
    final Object? details = error.details;
    final String code = details is Map
        ? (details['error']?.toString() ?? '')
        : '';
    switch (code) {
      case 'invalid_input':
        return AccountDeletionFailureKind.invalidInput;
      case 'invalid_credentials':
        return AccountDeletionFailureKind.wrongPassword;
      case 'unauthorized':
        return AccountDeletionFailureKind.sessionExpired;
      case 'reauth_unavailable':
        return AccountDeletionFailureKind.reauthUnavailable;
    }
    // Código desconocido o cuerpo no-JSON: cae por status antes de rendirse.
    if (error.status == 401) return AccountDeletionFailureKind.sessionExpired;
    return AccountDeletionFailureKind.unknown;
  }
}
