import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/auth/auth_failure.dart';
import '../../../domain/auth/auth_repository.dart';

/// Qué está intentando hacer el usuario. Login y registro **no** son lo mismo:
/// en login no se crea la cuenta, en signup sí.
enum AuthIntent { login, signUp }

/// Paso dentro del flujo. Se resuelven en la misma pantalla, con transiciones.
enum AuthStep {
  /// Solo registro: pidiendo nombre, email, fecha de nacimiento, género.
  registerDetails,

  /// Ambos: pidiendo email.
  identifier,

  /// Ambos: pidiendo contraseña.
  password,
}

@immutable
class AuthFormState {
  const AuthFormState({
    this.step = AuthStep.identifier,
    this.identifier = '',
    this.password = '',
    this.passwordConfirm = '',
    this.displayName = '',
    this.birthDate,
    this.gender,
    this.isSubmitting = false,
    this.acceptedTerms = false,
    this.failure,
  });

  final AuthStep step;

  /// Email con el que se inicia sesión.
  final String identifier;

  /// Contraseña en el flujo de password.
  final String password;

  /// Confirmación de contraseña en registro.
  final String passwordConfirm;

  /// Nombre completo (solo registro).
  final String displayName;

  /// Fecha de nacimiento (solo registro).
  final DateTime? birthDate;

  /// Género: 'hombre', 'mujer', 'otro' (solo registro).
  final String? gender;

  final bool isSubmitting;

  /// Solo relevante en registro.
  final bool acceptedTerms;
  final AuthFailure? failure;

  bool get isBusy => isSubmitting;

  AuthFormState copyWith({
    AuthStep? step,
    String? identifier,
    String? password,
    String? passwordConfirm,
    String? displayName,
    DateTime? birthDate,
    String? gender,
    bool? isSubmitting,
    bool? acceptedTerms,
    AuthFailure? failure,
    bool clearFailure = false,
  }) => AuthFormState(
    step: step ?? this.step,
    identifier: identifier ?? this.identifier,
    password: password ?? this.password,
    passwordConfirm: passwordConfirm ?? this.passwordConfirm,
    displayName: displayName ?? this.displayName,
    birthDate: birthDate ?? this.birthDate,
    gender: gender ?? this.gender,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    acceptedTerms: acceptedTerms ?? this.acceptedTerms,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

/// Orquesta el flujo de autenticación de una pantalla (login o registro).
///
/// No conoce Supabase: habla con [AuthRepository]. Toda la validación que hace
/// es de *forma* (¿esto parece un email?) — la de verdad la hace el backend.
class AuthController
    extends AutoDisposeFamilyNotifier<AuthFormState, AuthIntent> {
  @override
  AuthFormState build(AuthIntent arg) => AuthFormState(
    step: arg == AuthIntent.signUp
        ? AuthStep.registerDetails
        : AuthStep.identifier,
  );

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  void setAcceptedTerms({required bool accepted}) {
    state = state.copyWith(acceptedTerms: accepted, clearFailure: true);
  }

  void clearFailure() {
    if (state.failure == null) return;
    state = state.copyWith(clearFailure: true);
  }

  /// Navega al paso anterior.
  void backToPreviousStep() {
    if (state.step == AuthStep.password) {
      state = state.copyWith(step: AuthStep.identifier, clearFailure: true);
    } else if (state.step == AuthStep.identifier && arg == AuthIntent.signUp) {
      state = state.copyWith(
        step: AuthStep.registerDetails,
        clearFailure: true,
      );
    }
  }

  /// Actualiza campos de registro (nombre, edad, género).
  void updateRegisterDetails({
    String? displayName,
    DateTime? birthDate,
    String? gender,
  }) {
    state = state.copyWith(
      displayName: displayName ?? state.displayName,
      birthDate: birthDate ?? state.birthDate,
      gender: gender ?? state.gender,
      clearFailure: true,
    );
  }

  /// Valida la forma del identificador. `null` = válido.
  AuthFailureKind? validateIdentifier(String raw) =>
      _looksLikeEmail(raw.trim()) ? null : AuthFailureKind.invalidEmail;

  /// Valida contraseña. `null` = válido.
  AuthFailureKind? validatePassword(String password) {
    if (password.isEmpty) {
      return AuthFailureKind.invalidPassword;
    }
    if (password.length < 8) {
      return AuthFailureKind.invalidPassword;
    }
    return null;
  }

  /// Valida que las contraseñas coincidan.
  AuthFailureKind? validatePasswordMatch(String pwd1, String pwd2) {
    if (pwd1 != pwd2) {
      return AuthFailureKind.passwordMismatch;
    }
    return null;
  }

  /// Avanza al siguiente paso: registerDetails → identifier → password.
  Future<bool> submitIdentifier(String raw) async {
    if (state.isBusy) return false;

    final String identifier = _normalize(raw);
    final AuthFailureKind? invalid = validateIdentifier(identifier);
    if (invalid != null) {
      state = state.copyWith(failure: AuthFailure(invalid));
      return false;
    }

    state = state.copyWith(identifier: identifier, clearFailure: true);

    state = state.copyWith(step: AuthStep.password);
    return true;
  }

  /// Verifica contraseña y hace login/signup.
  ///
  /// Devuelve `true` si la operación salió bien.
  Future<bool> submitPassword(String password, String passwordConfirm) async {
    if (state.isBusy) return false;

    final AuthFailureKind? invalid = validatePassword(password);
    if (invalid != null) {
      state = state.copyWith(failure: AuthFailure(invalid));
      return false;
    }

    if (arg == AuthIntent.signUp) {
      final AuthFailureKind? mismatch = validatePasswordMatch(
        password,
        passwordConfirm,
      );
      if (mismatch != null) {
        state = state.copyWith(failure: AuthFailure(mismatch));
        return false;
      }
    }

    state = state.copyWith(
      password: password,
      passwordConfirm: passwordConfirm,
      isSubmitting: true,
      clearFailure: true,
    );

    try {
      if (arg == AuthIntent.login) {
        await _repository.signInWithPassword(
          identifier: state.identifier,
          password: password,
        );
      } else {
        await _repository.signUpWithPassword(
          email: state.identifier,
          password: password,
          displayName: state.displayName,
          birthDate: state.birthDate!,
          gender: state.gender!,
        );
      }
      state = state.copyWith(isSubmitting: false);
      return true;
    } on AuthFailure catch (failure) {
      state = state.copyWith(isSubmitting: false, failure: failure);
      return false;
    }
  }

  /// El identificador siempre es un email, así que basta con normalizar
  /// mayúsculas: dos personas no pueden tener cuentas distintas que solo
  /// difieran en eso.
  String _normalize(String raw) => raw.trim().toLowerCase();

  // Deliberadamente permisivo: rechazar emails raros pero válidos es peor que
  // dejar que el backend confirme. Solo filtra erratas evidentes.
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]{2,}$');

  static bool _looksLikeEmail(String value) => _emailPattern.hasMatch(value);
}

final AutoDisposeNotifierProviderFamily<
  AuthController,
  AuthFormState,
  AuthIntent
>
authControllerProvider = NotifierProvider.autoDispose
    .family<AuthController, AuthFormState, AuthIntent>(AuthController.new);
