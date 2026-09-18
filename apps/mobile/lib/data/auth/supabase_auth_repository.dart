import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/auth/auth_failure.dart';
import '../../domain/auth/auth_repository.dart';

/// Implementación de [AuthRepository] sobre Supabase Auth.
///
/// Toda la superficie de error de Supabase se normaliza aquí a [AuthFailure]:
/// es el único sitio del proyecto que conoce los códigos concretos del
/// proveedor.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  /*
    Identico a:
    SupabaseAuthRepository(SupabaseClient client) {
      _client = client;
}
 */
  final SupabaseClient _client;

  @override
  Stream<String?> authStateChanges() => _client.auth.onAuthStateChange.map(
    (AuthState state) => state
        .session
        ?.user
        .id, //para cada state de client.auth.onAuthStateChang
    // devuelve el id de usuario.
  );

  @override
  String? get currentUserId => _client.auth.currentUser?.id;
  // Equivalente a currentUser == null ? null : currentUser.id
  @override
  Future<void> signInWithPassword({
    required String identifier,
    required String password,
  }) async {
    /*
      async = la función devuelve una Future. Permite usar await dentro.
      await = pausa el código hasta que esa Future se resuelva.
    */
    await _guard(() async {
      await _client.auth.signInWithPassword(
        email: identifier,
        password: password,
      );
    });
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
    required DateTime birthDate,
    required String gender,
  }) async {
    await _guard(() async {
      // Los datos de perfil viajan como metadata del alta y los escribe el
      // trigger `on_auth_user_created` (migración
      // 20260808000000_schema_baseline_bloque1.sql).
      //
      // El cliente NO inserta en `profiles`: el trigger ya ha creado la fila
      // cuando este `await` vuelve, así que un insert aquí choca contra la PK y
      // tira el alta entera pese a que la cuenta ya existe. Además, hacerlo
      // desde el cliente dejaría un usuario sin perfil en cuanto fallara la red
      // entre las dos llamadas.
      await _client.auth.signUp(
        email: email,
        password: password,
        data: <String, dynamic>{
          'display_name': displayName,
          'birth_date': birthDate.toIso8601String().split('T')[0],
          'gender': gender,
        },
      );
    });
  }

  @override
  Future<void> signOut() => _guard(() => _client.auth.signOut());

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (error) {
      throw AuthFailure(_kindOf(error), rawMessage: error.message);
    } on TimeoutException catch (error) {
      throw AuthFailure(AuthFailureKind.network, rawMessage: error.message);
    } on Object catch (error) {
      final String message = error.toString();
      final bool looksLikeNetwork =
          message.contains('SocketException') ||
          message.contains('ClientException') ||
          message.contains('Failed host lookup');
      throw AuthFailure(
        looksLikeNetwork ? AuthFailureKind.network : AuthFailureKind.unknown,
        rawMessage: message,
      );
    }
  }

  /// Traduce el error de Supabase a una causa de dominio.
  ///
  /// Se mira primero `code` (estable) y solo después el texto del mensaje, que
  /// cambia entre versiones de GoTrue.
  AuthFailureKind _kindOf(AuthException error) {
    switch (error.code) {
      // Configuración del proyecto, no del usuario: el proveedor de email está
      // apagado en Supabase Auth, o los registros están cerrados.
      case 'email_provider_disabled':
      case 'signup_disabled':
        return AuthFailureKind.signUpUnavailable;
      // No hay 'phone_exists': Grasp nunca manda `phone:` a `signUp` (solo
      // `email:`), así que GoTrue no puede devolver ese código para esta app.
      // Mantenerlo sería código muerto sugiriendo un alta por SMS que no existe.
      case 'user_already_exists':
      case 'email_exists':
        return AuthFailureKind.accountAlreadyExists;
      case 'invalid_credentials':
        return AuthFailureKind.invalidCredentials;
      case 'over_request_rate_limit':
      case 'too_many_requests':
        return AuthFailureKind.rateLimited;
      case 'weak_password':
        return AuthFailureKind.invalidPassword;
    }

    final String message = error.message.toLowerCase();
    if (error.statusCode == '429' || message.contains('rate limit')) {
      return AuthFailureKind.rateLimited;
    }
    if (message.contains('invalid password') ||
        message.contains('password is too short')) {
      return AuthFailureKind.invalidPassword;
    }
    if (message.contains('invalid credentials') ||
        message.contains('incorrect password')) {
      return AuthFailureKind.invalidCredentials;
    }
    if (message.contains('signups are disabled') ||
        message.contains('signups not allowed') ||
        message.contains('provider is not enabled') ||
        message.contains('provider is disabled')) {
      return AuthFailureKind.signUpUnavailable;
    }
    if (message.contains('user not found')) {
      return AuthFailureKind.accountNotFound;
    }
    if (message.contains('already registered')) {
      return AuthFailureKind.accountAlreadyExists;
    }
    return AuthFailureKind.unknown;
  }
}
