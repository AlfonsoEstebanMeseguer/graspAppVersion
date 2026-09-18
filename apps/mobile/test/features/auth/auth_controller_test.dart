import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/auth/auth_failure.dart';
import 'package:grasp_mobile/features/auth/application/auth_controller.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeAuthRepository();
    container = ProviderContainer(
      overrides: <Override>[
        authRepositoryProvider.overrideWith((Ref ref) => repository),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    repository.dispose();
  });

  AuthController controllerFor(AuthIntent intent) =>
      container.read(authControllerProvider(intent).notifier);

  AuthFormState stateFor(AuthIntent intent) =>
      container.read(authControllerProvider(intent));

  group('validación de correo', () {
    test('rechaza un correo sin dominio', () async {
      final AuthController controller = controllerFor(AuthIntent.login);

      final bool ok = await controller.submitIdentifier('alguien@correo');

      expect(ok, isFalse);
      expect(
        stateFor(AuthIntent.login).failure?.kind,
        AuthFailureKind.invalidEmail,
      );
    });

    test('normaliza el correo a minúsculas', () async {
      final AuthController controller = controllerFor(AuthIntent.login);

      await controller.submitIdentifier('  Alguien@Correo.COM  ');

      expect(stateFor(AuthIntent.login).identifier, 'alguien@correo.com');
    });
  });

  group('validación de contraseña', () {
    test('rechaza contraseña vacía', () {
      final AuthController controller = controllerFor(AuthIntent.login);

      final AuthFailureKind? invalid = controller.validatePassword('');

      expect(invalid, AuthFailureKind.invalidPassword);
    });

    test('rechaza contraseña menor de 8 caracteres', () {
      final AuthController controller = controllerFor(AuthIntent.login);

      final AuthFailureKind? invalid = controller.validatePassword('1234567');

      expect(invalid, AuthFailureKind.invalidPassword);
    });

    test('acepta contraseña de 8+ caracteres', () {
      final AuthController controller = controllerFor(AuthIntent.login);

      final AuthFailureKind? invalid = controller.validatePassword('12345678');

      expect(invalid, isNull);
    });
  });

  group('validación de coincidencia de contraseñas', () {
    test('rechaza si no coinciden', () {
      final AuthController controller = controllerFor(AuthIntent.signUp);

      final AuthFailureKind? invalid =
          controller.validatePasswordMatch('password1', 'password2');

      expect(invalid, AuthFailureKind.passwordMismatch);
    });

    test('acepta si coinciden', () {
      final AuthController controller = controllerFor(AuthIntent.signUp);

      final AuthFailureKind? invalid =
          controller.validatePasswordMatch('password1', 'password1');

      expect(invalid, isNull);
    });
  });

  group('flujo de identificador', () {
    test('un correo válido avanza al paso de contraseña', () async {
      await controllerFor(AuthIntent.login).submitIdentifier('a@b.com');

      expect(stateFor(AuthIntent.login).step, AuthStep.password);
      expect(stateFor(AuthIntent.login).identifier, 'a@b.com');
    });

    test('un correo inválido no avanza', () async {
      final bool ok = await controllerFor(AuthIntent.login)
          .submitIdentifier('no-es-correo');

      expect(ok, isFalse);
      expect(stateFor(AuthIntent.login).step, AuthStep.identifier);
    });
  });

  group('flujo de registro', () {
    test('registro comienza en registerDetails', () {
      final AuthFormState state = stateFor(AuthIntent.signUp);

      expect(state.step, AuthStep.registerDetails);
    });

    test('actualizar detalles guarda los datos', () {
      final AuthController controller = controllerFor(AuthIntent.signUp);
      final DateTime birthDate = DateTime(2000, 1, 1);

      controller.updateRegisterDetails(
        displayName: 'Juan',
        birthDate: birthDate,
        gender: 'hombre',
      );

      expect(stateFor(AuthIntent.signUp).displayName, 'Juan');
      expect(stateFor(AuthIntent.signUp).birthDate, birthDate);
      expect(stateFor(AuthIntent.signUp).gender, 'hombre');
    });
  });

  group('flujo de contraseña', () {
    test('contraseña válida en login autentica', () async {
      final AuthController controller = controllerFor(AuthIntent.login);
      await controller.submitIdentifier('a@b.com');

      final bool ok = await controller.submitPassword('password1', '');

      expect(ok, isTrue);
      expect(repository.currentUserId, isNotNull);
    });

    test('contraseñas no coincidentes en signup fallan', () async {
      final AuthController controller = controllerFor(AuthIntent.signUp);

      final bool ok = await controller.submitPassword('password1', 'password2');

      expect(ok, isFalse);
      expect(
        stateFor(AuthIntent.signUp).failure?.kind,
        AuthFailureKind.passwordMismatch,
      );
    });

    test('contraseña válida en signup autentica', () async {
      final AuthController controller = controllerFor(AuthIntent.signUp);
      controller.updateRegisterDetails(
        displayName: 'Juan',
        birthDate: DateTime(2000, 1, 1),
        gender: 'hombre',
      );
      await controller.submitIdentifier('a@b.com');

      final bool ok = await controller.submitPassword('password1', 'password1');

      expect(ok, isTrue);
      expect(repository.currentUserId, isNotNull);
      expect(stateFor(AuthIntent.signUp).step, AuthStep.password);
    });

  });

  group('navegación', () {
    test('volver desde password va a identifier', () async {
      final AuthController controller = controllerFor(AuthIntent.login);
      await controller.submitIdentifier('a@b.com');

      controller.backToPreviousStep();

      expect(stateFor(AuthIntent.login).step, AuthStep.identifier);
    });

    test('volver desde identifier en registro va a registerDetails', () async {
      final AuthController controller = controllerFor(AuthIntent.signUp);
      await controller.submitIdentifier('a@b.com');

      controller.backToPreviousStep();

      expect(stateFor(AuthIntent.signUp).step, AuthStep.identifier);
    });
  });

  group('concurrencia', () {
    test('no se lanzan dos envíos a la vez', () async {
      final AuthController controller = controllerFor(AuthIntent.login);

      await Future.wait<bool>(<Future<bool>>[
        controller.submitIdentifier('a@b.com'),
        controller.submitIdentifier('a@b.com'),
      ]);

      expect(stateFor(AuthIntent.login).isBusy, isFalse);
    });
  });
}
