import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/core/router/app_router.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/features/auth/presentation/start_screen.dart';
import 'package:grasp_mobile/features/messages/presentation/messages_screen.dart';

import '../../support/fake_auth_repository.dart';

/// Los dos usuarios reales del proyecto Supabase (creados el 2026-08-07).
///
/// Se usan sus `userId` de verdad en vez de `'user-test'` para que el test
/// falle si alguien cambia el tipo de la sesión (por ejemplo, pasar a emitir el
/// email en lugar del uuid): un literal cualquiera no lo detectaría.
const Map<String, String> _realUsers = <String, String>{
  'alfonso19.aem@gmail.com': 'cf3969f3-6180-4606-9896-f91aaad58fc4',
  'alfonsoestebanmeseguer@gmail.com': 'cfd2b9f2-b2d1-4f2f-8b91-813eafc9e715',
};

/// Monta la app con el router **real** y el repositorio de auth sustituido.
///
/// A diferencia de `pumpApp`, aquí no se monta una pantalla suelta: lo que se
/// prueba es precisamente el `redirect` de `routerProvider`, así que hace falta
/// el `GoRouter` de producción.
Future<FakeAuthRepository> _pumpRoutedApp(WidgetTester tester) async {
  final FakeAuthRepository fake = FakeAuthRepository();
  addTearDown(fake.dispose);

  final ThemeData theme = AppTheme.light().copyWith(
    // Sin `still()` la marca respira y la escena deriva en bucle: con esas
    // animaciones vivas `pumpAndSettle` no termina nunca.
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authRepositoryProvider.overrideWith((Ref ref) => fake),
        // Estos tests cubren el redirect por sesión, no el de onboarding
        // (ver `onboarding_redirect_test.dart`): se fuerza "ya completado"
        // para que no interfiera y no haga falta un Supabase real.
        hasCompletedOnboardingProvider.overrideWith((Ref ref) async => true),
      ],
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) =>
            MaterialApp.router(
              theme: theme,
              routerConfig: ref.watch(routerProvider),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return fake;
}

void main() {
  group('redirección por sesión', () {
    testWidgets('sin sesión arranca en Start, no en Login', (
      WidgetTester tester,
    ) async {
      await _pumpRoutedApp(tester);

      expect(find.byType(StartScreen), findsOneWidget);
      expect(find.byType(MessagesScreen), findsNothing);
    });

    for (final MapEntry<String, String> user in _realUsers.entries) {
      testWidgets('${user.key} llega a /messages al iniciar sesión', (
        WidgetTester tester,
      ) async {
        final FakeAuthRepository fake = await _pumpRoutedApp(tester);
        expect(find.byType(StartScreen), findsOneWidget);

        fake.emitSignedIn(user.value);
        await tester.pumpAndSettle();

        expect(find.byType(MessagesScreen), findsOneWidget);
        expect(find.byType(StartScreen), findsNothing);
      });
    }

    testWidgets('cerrar sesión devuelve a Start', (WidgetTester tester) async {
      final FakeAuthRepository fake = await _pumpRoutedApp(tester);

      fake.emitSignedIn(_realUsers.values.first);
      await tester.pumpAndSettle();
      expect(find.byType(MessagesScreen), findsOneWidget);

      // Cerrar sesión vive en Perfil, no en Inicio (ver
      // `features/profile/presentation/profile_screen.dart`).
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(find.byType(StartScreen), findsOneWidget);
      expect(find.byType(MessagesScreen), findsNothing);
    });
  });
}
