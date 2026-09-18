import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/ui/brand_mark.dart';
import 'package:grasp_mobile/features/auth/presentation/login_screen.dart';
import 'package:grasp_mobile/features/auth/presentation/register_screen.dart';
import 'package:grasp_mobile/features/auth/presentation/start_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/pump_app.dart';

/// Rellena el primer paso del registro (nombre, correo, fecha, género) y
/// opcionalmente acepta los términos, **sin** pulsar "Continuar".
///
/// La fecha se escribe en vez de abrir el `showDatePicker`: `GraspDateField`
/// parsea `DD/MM/YYYY` del propio campo, así que conducir el diálogo nativo
/// añadiría fragilidad sin probar nada más.
Future<void> _fillRegisterDetails(
  WidgetTester tester, {
  required bool acceptTerms,
  String email = 'alguien@correo.com',
  String name = 'Alguien de Prueba',
}) async {
  final Finder fields = find.byType(TextField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), email);
  await tester.enterText(fields.at(2), '19/04/1998');
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byType(DropdownButton<String>));
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Hombre').last);
  await tester.pumpAndSettle();

  if (acceptTerms) {
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
  }
}

/// Pulsa un botón que puede haber quedado por debajo del pliegue.
Future<void> _tapButton(WidgetTester tester, String label) async {
  final Finder button = find.text(label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('StartScreen', () {
    testWidgets('muestra la marca, el claim y las dos vías de entrada', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, const StartScreen());

      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('Grasp'), findsOneWidget);
      expect(find.textContaining('Charlas que te entienden.'), findsOneWidget);
      expect(find.text('Crear cuenta'), findsOneWidget);
      expect(find.text('Ya tengo cuenta'), findsOneWidget);
    });
  });

  group('LoginScreen', () {
    testWidgets('empieza pidiendo el correo, no la contraseña', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, const LoginScreen());

      expect(find.text('Tu correo'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Contraseña'), findsNothing);
    });

    testWidgets('un correo válido pasa al paso de contraseña', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const LoginScreen(),
      );

      // En mayúsculas a propósito: el controlador normaliza a minúsculas.
      await tester.enterText(find.byType(TextField), 'Alguien@Correo.com');
      await _tapButton(tester, 'Iniciar sesión');

      expect(find.text('Contraseña'), findsOneWidget);
      expect(find.textContaining('alguien@correo.com'), findsOneWidget);
      // Avanzar de paso es cosa del cliente: todavía no se ha tocado el backend.
      expect(repository.passwordCalls, isEmpty);
    });

    testWidgets('al entrar NO se pide CREAR una contraseña: ya se tiene', (
      WidgetTester tester,
    ) async {
      // Detectado mirando la app corriendo en el emulador el 2026-08-25: el paso
      // de contraseña decia "Crea una contrasena para <correo>" tambien al
      // INICIAR SESION, que es decirle a quien vuelve que se invente la
      // contraseña que ya tiene. El literal estaba fijo aunque el widget ya
      // recibia `isSignUp` y lo usaba dos lineas mas abajo para otra cosa.
      await pumpApp(tester, const LoginScreen());

      await tester.enterText(find.byType(TextField), 'alguien@correo.com');
      await _tapButton(tester, 'Iniciar sesión');

      expect(find.textContaining('Crea una contraseña'), findsNothing);
      expect(find.textContaining('Introduce tu contraseña'), findsOneWidget);
    });

    testWidgets('un correo mal escrito muestra el error y no avanza', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const LoginScreen(),
      );

      await tester.enterText(find.byType(TextField), 'alguien-arroba-nada');
      await _tapButton(tester, 'Iniciar sesión');

      expect(find.textContaining('Revisa el correo'), findsOneWidget);
      expect(find.text('Contraseña'), findsNothing);
      expect(repository.passwordCalls, isEmpty);
    });

    testWidgets('una contraseña corta no llega al backend', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const LoginScreen(),
      );

      await tester.enterText(find.byType(TextField), 'alguien@correo.com');
      await _tapButton(tester, 'Iniciar sesión');

      await tester.enterText(find.byType(TextField).first, 'corta');
      await _tapButton(tester, 'Continuar');

      expect(find.textContaining('al menos 8 caracteres'), findsOneWidget);
      expect(repository.passwordCalls, isEmpty);
    });

    testWidgets('con correo y contraseña válidos llama a signInWithPassword', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const LoginScreen(),
      );

      await tester.enterText(find.byType(TextField), 'Alguien@Correo.com');
      await _tapButton(tester, 'Iniciar sesión');

      await tester.enterText(find.byType(TextField).first, 'contraseña-larga');
      await _tapButton(tester, 'Continuar');

      final PasswordCall call = repository.passwordCalls.single;
      expect(call.method, 'signInWithPassword');
      expect(call.identifier, 'alguien@correo.com');
      expect(call.password, 'contraseña-larga');
    });
  });

  group('RegisterScreen', () {
    testWidgets('no deja avanzar sin aceptar los términos', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const RegisterScreen(),
      );

      await _fillRegisterDetails(tester, acceptTerms: false);
      await _tapButton(tester, 'Continuar');

      expect(
        find.textContaining('Acepta los Términos de Uso'),
        findsOneWidget,
      );
      // Sigue en el primer paso: no ha llegado a pedir contraseña.
      expect(find.text('Tu nombre'), findsOneWidget);
      expect(repository.passwordCalls, isEmpty);
    });

    testWidgets('con los términos aceptados avanza a la contraseña', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, const RegisterScreen());

      await _fillRegisterDetails(tester, acceptTerms: true);
      await _tapButton(tester, 'Continuar');

      expect(find.text('Contraseña'), findsOneWidget);
      expect(find.text('Confirmar contraseña'), findsOneWidget);
    });

    testWidgets('al registrarse SÍ se pide crear una contraseña', (
      WidgetTester tester,
    ) async {
      // La otra mitad, y no es decorativa: sin ella, cambiar el texto de login a
      // secas dejaria el registro diciendo "Introduce tu contraseña" a quien
      // todavia no tiene ninguna, que es el mismo fallo al reves.
      await pumpApp(tester, const RegisterScreen());

      await _fillRegisterDetails(tester, acceptTerms: true);
      await _tapButton(tester, 'Continuar');

      expect(find.textContaining('Crea una contraseña'), findsOneWidget);
      expect(find.textContaining('Introduce tu contraseña'), findsNothing);
    });

    testWidgets('dos contraseñas distintas no llegan al backend', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const RegisterScreen(),
      );

      await _fillRegisterDetails(tester, acceptTerms: true);
      await _tapButton(tester, 'Continuar');

      await tester.enterText(find.byType(TextField).at(0), 'contraseña-larga');
      await tester.enterText(find.byType(TextField).at(1), 'otra-distinta-8');
      await _tapButton(tester, 'Continuar');

      expect(find.textContaining('no coinciden'), findsOneWidget);
      expect(repository.passwordCalls, isEmpty);
    });

    testWidgets('el alta manda también los datos de perfil', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const RegisterScreen(),
      );

      await _fillRegisterDetails(tester, acceptTerms: true);
      await _tapButton(tester, 'Continuar');

      await tester.enterText(find.byType(TextField).at(0), 'contraseña-larga');
      await tester.enterText(find.byType(TextField).at(1), 'contraseña-larga');
      await _tapButton(tester, 'Continuar');

      final PasswordCall call = repository.passwordCalls.single;
      expect(call.method, 'signUpWithPassword');
      expect(call.identifier, 'alguien@correo.com');
      // Estos tres son los que el trigger `on_auth_user_created` copia a
      // `profiles` / `profiles_private`: si dejan de viajar, el perfil se crea
      // vacío y nadie se entera hasta mirar la base de datos.
      expect(call.displayName, 'Alguien de Prueba');
      expect(call.birthDate, DateTime(1998, 4, 19));
      expect(call.gender, 'hombre');
    });

    // Regresión de 20260817090000. `display_name` es `not null` en la base de
    // datos: sin este freno, el alta viajaba al backend y moría en el trigger
    // con un error que el usuario no puede interpretar. Antes de ese cambio el
    // nombre era el único campo del formulario que nadie comprobaba.
    testWidgets('un nombre vacío no llega al backend', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const RegisterScreen(),
      );

      await _fillRegisterDetails(tester, acceptTerms: true, name: '   ');
      await _tapButton(tester, 'Continuar');

      expect(find.textContaining('Completa todos los campos'), findsOneWidget);
      // Sigue en el primer paso.
      expect(find.text('Tu nombre'), findsOneWidget);
      expect(repository.passwordCalls, isEmpty);
    });

    // La constraint de la base de datos compara sobre `btrim`, así que un nombre
    // con espacios alrededor tiene que llegar ya recortado o el cliente y el
    // esquema discreparían sobre qué cuenta como nombre.
    testWidgets('el nombre viaja recortado', (WidgetTester tester) async {
      final FakeAuthRepository repository = await pumpApp(
        tester,
        const RegisterScreen(),
      );

      await _fillRegisterDetails(
        tester,
        acceptTerms: true,
        name: '  Alguien de Prueba  ',
      );
      await _tapButton(tester, 'Continuar');

      await tester.enterText(find.byType(TextField).at(0), 'contraseña-larga');
      await tester.enterText(find.byType(TextField).at(1), 'contraseña-larga');
      await _tapButton(tester, 'Continuar');

      expect(repository.passwordCalls.single.displayName, 'Alguien de Prueba');
    });
  });

  group('accesibilidad', () {
    // Flujo crítico: si estas pantallas no cumplen los tamaños táctiles ni el
    // contraste, no hay forma de entrar en la app con un lector de pantalla.
    testWidgets('Login cumple las guías de accesibilidad de Material', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, const LoginScreen());

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('el paso de contraseña cumple las guías de Material', (
      WidgetTester tester,
    ) async {
      // Paso aparte porque tiene controles que no existen en el primero: el
      // botón de mostrar/ocultar contraseña se quedó sin etiqueta hasta que
      // este test lo destapó.
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, const LoginScreen());

      await tester.enterText(find.byType(TextField), 'alguien@correo.com');
      await _tapButton(tester, 'Iniciar sesión');
      expect(find.text('Contraseña'), findsOneWidget);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('Registro cumple las guías de accesibilidad de Material', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, const RegisterScreen());

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('Start cumple las guías de accesibilidad de Material', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, const StartScreen());

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });
  });
}
