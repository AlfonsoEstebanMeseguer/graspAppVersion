import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/router/app_router.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/core/ui/grasp_bottom_nav.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/features/connect/presentation/connect_screen.dart';
import 'package:grasp_mobile/features/messages/presentation/messages_screen.dart';
import 'package:grasp_mobile/features/profile/presentation/profile_screen.dart';
import 'package:grasp_mobile/features/rooms/presentation/rooms_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/pump_app.dart';

/// Monta la app con el router real y una sesión ya iniciada, que es la única
/// forma de que el `StatefulShellRoute` de la barra llegue a construirse.
Future<void> _pumpShell(WidgetTester tester) async {
  final FakeAuthRepository fake = FakeAuthRepository();
  addTearDown(fake.dispose);

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authRepositoryProvider.overrideWith((Ref ref) => fake),
        hasCompletedOnboardingProvider.overrideWith((Ref ref) async => true),
      ],
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) =>
            MaterialApp.router(theme: theme, routerConfig: ref.watch(routerProvider)),
      ),
    ),
  );
  await tester.pumpAndSettle();

  fake.emitSignedIn('cf3969f3-6180-4606-9896-f91aaad58fc4');
  await tester.pumpAndSettle();
}

void main() {
  group('barra de navegación de 4 pestañas', () {
    testWidgets('los cuatro destinos, en el orden del §5', (WidgetTester tester) async {
      await _pumpShell(tester);

      final GraspBottomNav nav = tester.widget<GraspBottomNav>(find.byType(GraspBottomNav));
      expect(
        nav.destinations.map((GraspNavDestination d) => d.label).toList(),
        <String>['Mensajes', 'Conectar', 'Salas de voz', 'Perfil'],
      );
    });

    testWidgets('NINGUNA pestaña está deshabilitada — hoy dos lo estaban', (
      WidgetTester tester,
    ) async {
      // No basta con mirar una bandera: se toca cada una y se comprueba que
      // llega a su pantalla. Una pestaña «habilitada» que no navega a ningún
      // sitio es exactamente el estado del que venimos.
      await _pumpShell(tester);

      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectScreen), findsOneWidget);

      await tester.tap(find.text('Salas de voz'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomsScreen), findsOneWidget);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.tap(find.text('Mensajes'));
      await tester.pumpAndSettle();
      expect(find.byType(MessagesScreen), findsOneWidget);
    });

    testWidgets('Mensajes es la pestaña de aterrizaje tras iniciar sesión', (
      WidgetTester tester,
    ) async {
      // §5: la tab bar empieza por Mensajes. Antes se aterrizaba en `Inicio`,
      // que era el placeholder de mensajería.
      await _pumpShell(tester);
      expect(find.byType(MessagesScreen), findsOneWidget);
    });

    testWidgets('cada rama conserva su subárbol al volver a ella', (WidgetTester tester) async {
      // Es lo que aporta `StatefulShellBranch` frente a cuatro rutas sueltas, y
      // se rompería sin que ningún otro test lo notara.
      //
      // SE COMPARAN `Element`s, NO WIDGETS. Comparar `tester.widget<ProfileScreen>()`
      // con `same()` seria VACUO: la pantalla se construye como `const
      // ProfileScreen()` y Dart canoniza las instancias `const`, asi que las dos
      // lecturas devuelven el MISMO objeto aunque la rama se hubiera destruido y
      // reconstruido entera. El `Element` sí es por instancia montada: si el
      // subarbol se desmonta, el nuevo es otro.
      await _pumpShell(tester);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      final Element antes = tester.element(find.byType(ProfileScreen));

      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(tester.element(find.byType(ProfileScreen)), same(antes));
    });
  });

  group('badge de Mensajes (RN-55)', () {
    Future<void> pumpNav(WidgetTester tester, {int? badge}) async {
      await pumpApp(
        tester,
        Scaffold(
          bottomNavigationBar: GraspBottomNav(
            currentIndex: 0,
            onTap: (int _) {},
            destinations: <GraspNavDestination>[
              GraspNavDestination(
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                label: 'Mensajes',
                badgeCount: badge,
              ),
              const GraspNavDestination(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'Perfil',
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('sin no leídos no se pinta ningún badge', (WidgetTester tester) async {
      await pumpNav(tester, badge: null);
      expect(find.byKey(const ValueKey<String>('nav-badge-Mensajes')), findsNothing);
    });

    testWidgets('un cero tampoco pinta badge', (WidgetTester tester) async {
      // El caso que se cuela: `if (badge != null)` pintaria un circulo con un 0
      // dentro, que es peor que no pintar nada.
      await pumpNav(tester, badge: 0);
      expect(find.byKey(const ValueKey<String>('nav-badge-Mensajes')), findsNothing);
    });

    testWidgets('con no leídos se pinta el número', (WidgetTester tester) async {
      await pumpNav(tester, badge: 3);
      expect(find.byKey(const ValueKey<String>('nav-badge-Mensajes')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('por encima de 99 se corta en «99+»', (WidgetTester tester) async {
      await pumpNav(tester, badge: 250);
      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('§12: «Explorar» ya no existe en ninguna parte del código', () {
    test('ningún fichero de lib/ menciona Explorar', () {
      // El primer criterio de aceptación del §12, escrito como test para que no
      // dependa de que alguien se acuerde de correr un grep. Se mira el código
      // fuente porque la comprobación es sobre AUSENCIA, y una ausencia no la
      // detecta ningún test de widget.
      final Directory lib = Directory('lib');
      expect(lib.existsSync(), isTrue, reason: 'el test debe correr desde apps/mobile');

      final List<String> culpables = <String>[];
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().toLowerCase().contains('explorar')) {
          culpables.add(entity.path);
        }
      }

      expect(culpables, isEmpty, reason: 'todavía se menciona «Explorar» en: $culpables');
    });
  });
}
