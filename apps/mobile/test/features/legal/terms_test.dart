import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/features/auth/presentation/register_screen.dart';
import 'package:grasp_mobile/features/legal/presentation/terms_screen.dart';

import '../../support/pump_app.dart';

/// Monta [TermsScreen] detrás de una pantalla que la abre con `push`, y
/// devuelve lo que la pantalla entrega al cerrarse.
///
/// Hace falta un `GoRouter` de verdad: el veredicto viaja como resultado del
/// `push`, así que un `MaterialApp(home:)` pelado no probaría nada.
Future<bool?> _openTermsAndTap(WidgetTester tester, String? buttonLabel) async {
  bool? result;
  bool returned = false;

  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async {
                result = await context.push<bool>('/terms');
                returned = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/terms',
        builder: (BuildContext context, GoRouterState state) =>
            const TermsScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      // Sin `still()` la escena del fondo anima en bucle y `pumpAndSettle`
      // no termina nunca.
      theme: AppTheme.light().copyWith(
        extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
      ),
      routerConfig: router,
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(find.text('Términos de uso'), findsOneWidget);

  if (buttonLabel == null) {
    await tester.tap(find.byTooltip('Volver'));
  } else {
    await tester.tap(find.text(buttonLabel));
  }
  await tester.pumpAndSettle();

  expect(returned, isTrue, reason: 'la pantalla no llegó a cerrarse');
  return result;
}

void main() {
  group('TermsScreen', () {
    testWidgets('«Aceptar» devuelve true', (WidgetTester tester) async {
      expect(await _openTermsAndTap(tester, 'Aceptar'), isTrue);
    });

    testWidgets('«Rechazar» devuelve false', (WidgetTester tester) async {
      expect(await _openTermsAndTap(tester, 'Rechazar'), isFalse);
    });

    testWidgets('salir por «Volver» no decide: devuelve null', (
      WidgetTester tester,
    ) async {
      // Importa que sea distinguible de `false`: quien la abrió debe conservar
      // lo que el usuario ya tuviera marcado, no darlo por rechazado.
      expect(await _openTermsAndTap(tester, null), isNull);
    });
  });

  group('casilla de términos en Registro', () {
    testWidgets('se puede marcar y desmarcar', (WidgetTester tester) async {
      // Regresión: el `onChanged` de la casilla estaba vacío, así que
      // `acceptedTerms` no cambiaba nunca y era imposible aceptar.
      await pumpApp(tester, const RegisterScreen());

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets('ofrece el enlace para leer los términos', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, const RegisterScreen());

      expect(find.text('Leer términos de uso'), findsOneWidget);
    });
  });
}
