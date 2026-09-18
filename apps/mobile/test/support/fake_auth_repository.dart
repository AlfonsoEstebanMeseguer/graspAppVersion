import 'dart:async';

import 'package:grasp_mobile/domain/auth/auth_failure.dart';
import 'package:grasp_mobile/domain/auth/auth_repository.dart';

/// Una llamada de alta o login con contraseña, tal y como la recibió el doble.
///
/// Los campos de perfil son nullable porque el login no los manda: solo el
/// registro los lleva.
typedef PasswordCall = ({
  String method,
  String identifier,
  String password,
  String? displayName,
  DateTime? birthDate,
  String? gender,
});

/// Doble de [AuthRepository] para tests.
///
/// Deliberadamente **no** simula Supabase ni RLS: solo registra qué se le pidió
/// y devuelve lo que se le programe. Un doble que fingiera responder como el
/// backend real escondería justo los fallos que importan (skill `flutter-ui`,
/// punto 6) — esos se prueban contra Supabase de verdad, no aquí.
class FakeAuthRepository implements AuthRepository {
  final StreamController<String?> _authState =
      StreamController<String?>.broadcast();

  /// Altas y logins recibidos, en orden, para poder afirmar sobre ellos.
  final List<PasswordCall> passwordCalls = <PasswordCall>[];

  /// Si se asigna, la siguiente llamada lanza este fallo.
  AuthFailure? nextFailure;

  String? _currentUserId;

  @override
  Stream<String?> authStateChanges() => _authState.stream;

  @override
  String? get currentUserId => _currentUserId;

  /// Simula que el backend ha abierto sesión para este usuario.
  void emitSignedIn(String userId) {
    _currentUserId = userId;
    _authState.add(userId);
  }

  void dispose() => _authState.close();

  void _maybeThrow() {
    final AuthFailure? failure = nextFailure;
    if (failure == null) return;
    nextFailure = null;
    throw failure;
  }

  @override
  Future<void> signInWithPassword({
    required String identifier,
    required String password,
  }) async {
    passwordCalls.add((
      method: 'signInWithPassword',
      identifier: identifier,
      password: password,
      displayName: null,
      birthDate: null,
      gender: null,
    ));
    // El registro va antes que `emitSignedIn`: así un test que espere un fallo
    // sigue viendo la llamada que lo provocó.
    _maybeThrow();
    emitSignedIn('user-test');
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
    required DateTime birthDate,
    required String gender,
  }) async {
    passwordCalls.add((
      method: 'signUpWithPassword',
      identifier: email,
      password: password,
      displayName: displayName,
      birthDate: birthDate,
      gender: gender,
    ));
    _maybeThrow();
    emitSignedIn('user-test');
  }

  @override
  Future<void> signOut() async {
    _currentUserId = null;
    _authState.add(null);
  }
}
