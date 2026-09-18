import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/features/navigation/presentation/widgets/activity_heartbeat.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/privacy_section.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/profile_bio_field.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/profile_metrics_row.dart';

import '../../support/fake_profile_repositories.dart';

/// La bio del §6.4, el ajuste de actividad (`RN-32`/`RN-54`), la rejilla navegable (`RN-50`) y el
/// latido (paso 4 de la Tarea 24).
ThemeData get _theme => AppTheme.light().copyWith(
  extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
);

Future<void> _pumpConProvider(
  WidgetTester tester,
  Widget child, {
  required FakeProfileRepository profile,
  FakeActivityRepository? activity,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        profileRepositoryProvider.overrideWithValue(profile),
        activityRepositoryProvider.overrideWithValue(
          activity ?? FakeActivityRepository(),
        ),
      ],
      child: MaterialApp(theme: _theme, home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // §6.4 — LA BIO, CON SU CONTADOR DE 160
  // ══════════════════════════════════════════════════════════════════════════
  group('§6.4 — la biografía', () {
    testWidgets('el contador aparece y cuenta lo escrito', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Scaffold(body: ProfileBioField(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ProfileBioField.fieldKey),
        'Aquí estoy para escuchar.',
      );
      await tester.pump();

      expect(find.text('25/160'), findsOneWidget);
    });

    testWidgets('a 160 no se puede seguir escribiendo, y no se trunca callado', (
      WidgetTester tester,
    ) async {
      // Mismo criterio que `RN-26` en el compositor: no se acepta y luego se recorta a escondidas,
      // se impide entrar. Y el tope de verdad **no lo guarda este contador**: lo guarda
      // `profiles_bio_length_chk` en la base. Éste solo evita que la persona escriba de más para
      // luego comerse un error.
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Scaffold(body: ProfileBioField(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      final String tope = 'a' * 160;
      await tester.enterText(find.byKey(ProfileBioField.fieldKey), tope);
      await tester.pump();
      expect(find.text('160/160'), findsOneWidget);

      await tester.enterText(find.byKey(ProfileBioField.fieldKey), '$tope bcde');
      await tester.pump();
      expect(controller.text, tope);
      expect(find.text('160/160'), findsOneWidget);
    });

    testWidgets('cuenta PUNTOS DE CÓDIGO, como `char_length` en Postgres', (
      WidgetTester tester,
    ) async {
      // 80 emojis + 80 letras = 160 puntos de código pero 240 unidades UTF-16. Contar con
      // `String.length` diría 240 y cortaría un texto que la base acepta — el mismo fallo que ya
      // se corrigió en el contador de mensajes.
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Scaffold(body: ProfileBioField(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ProfileBioField.fieldKey),
        '${'😀' * 80}${'a' * 80}',
      );
      await tester.pump();
      expect(find.text('160/160'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-32 / RN-54 — OCULTAR EL ESTADO DE ACTIVIDAD
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-54 — el ajuste de actividad', () {
    testWidgets('abre con el valor GUARDADO, no con el de por defecto', (
      WidgetTester tester,
    ) async {
      final FakeProfileRepository repo = FakeProfileRepository(
        profile: fakeProfile(hideActivityStatus: true),
      );
      await _pumpConProvider(tester, const PrivacySection(), profile: repo);

      expect(
        tester.widget<Switch>(find.byKey(PrivacySection.hideActivityKey)).value,
        isTrue,
      );
    });

    testWidgets('apagado se pinta apagado', (WidgetTester tester) async {
      // La otra mitad: sin ella, un `Switch` clavado en `true` pasaría el test de arriba.
      final FakeProfileRepository repo = FakeProfileRepository(
        profile: fakeProfile(hideActivityStatus: false),
      );
      await _pumpConProvider(tester, const PrivacySection(), profile: repo);

      expect(
        tester.widget<Switch>(find.byKey(PrivacySection.hideActivityKey)).value,
        isFalse,
      );
    });

    testWidgets('activarlo lo PERSISTE', (WidgetTester tester) async {
      final FakeProfileRepository repo = FakeProfileRepository();
      await _pumpConProvider(tester, const PrivacySection(), profile: repo);

      await tester.tap(find.byKey(PrivacySection.hideActivityKey));
      await tester.pumpAndSettle();

      expect(repo.hideActivityWrites, <bool>[true]);
    });

    testWidgets('si la escritura falla, el interruptor VUELVE atrás', (
      WidgetTester tester,
    ) async {
      // Un interruptor que se queda encendido tras un error diría que guardó algo que no guardó, y
      // en un ajuste de privacidad esa mentira es la peor de todas: la persona creería estar
      // oculta sin estarlo.
      final FakeProfileRepository repo = FakeProfileRepository()
        ..hideActivityFailsWith = Exception('la red');
      await _pumpConProvider(tester, const PrivacySection(), profile: repo);

      await tester.tap(find.byKey(PrivacySection.hideActivityKey));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Switch>(find.byKey(PrivacySection.hideActivityKey)).value,
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-50 — LOS NÚMEROS DEJAN DE SER INERTES
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-50 — la rejilla navega', () {
    testWidgets('Seguidores y Seguidos son tocables y van a sitios DISTINTOS', (
      WidgetTester tester,
    ) async {
      // «La UI ya existe», decía el §0 de la spec. Era falso: eran dos números sin `onTap`. Esto
      // fija que dejaron de serlo — y que cada uno lleva a su lista, no los dos a la misma.
      final List<String> tocados = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Scaffold(
            body: ProfileStatsGrid(
              roomsJoinedCount: 0,
              timeHelpingSeconds: 0,
              followersCount: 3,
              followingCount: 7,
              onTapFollowers: () => tocados.add('seguidores'),
              onTapFollowing: () => tocados.add('seguidos'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ProfileStatsGrid.followersKey));
      await tester.pump();
      await tester.tap(find.byKey(ProfileStatsGrid.followingKey));
      await tester.pump();

      expect(tocados, <String>['seguidores', 'seguidos']);
    });

    testWidgets('las otras dos tarjetas siguen sin `onTap`', (
      WidgetTester tester,
    ) async {
      // «Salas participadas» y «Tiempo escuchando» no llevan a ninguna parte todavía. Un `InkWell`
      // que no hace nada enseña un efecto de pulsación y no pasa nada: es un botón muerto.
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: const Scaffold(
            body: ProfileStatsGrid(
              roomsJoinedCount: 0,
              timeHelpingSeconds: 0,
              followersCount: 0,
              followingCount: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Se cuentan los que están VIVOS, no los que existen: las cuatro tarjetas comparten widget,
      // así que las cuatro tienen su `InkWell` — pero solo responde el que tiene callback. Contar
      // widgets mediría la forma del árbol; contar callbacks mide lo que se puede tocar.
      int vivos(WidgetTester t) => t
          .widgetList<InkWell>(find.byType(InkWell))
          .where((InkWell w) => w.onTap != null)
          .length;

      expect(
        vivos(tester),
        0,
        reason: 'sin callbacks no puede haber ninguna tarjeta tocable',
      );
      expect(
        tester.widget<InkWell>(find.byKey(ProfileStatsGrid.followersKey)).onTap,
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-30 — EL LATIDO
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-30 — latido de actividad', () {
    testWidgets('late UNA vez al arrancar, no en bucle', (
      WidgetTester tester,
    ) async {
      final FakeActivityRepository activity = FakeActivityRepository();
      await _pumpConProvider(
        tester,
        const ActivityHeartbeat(child: SizedBox.shrink()),
        profile: FakeProfileRepository(),
        activity: activity,
      );

      expect(activity.heartbeats, 1);

      // Y no hay temporizador detrás: dejar correr el reloj no produce más latidos. El plan lo
      // prohíbe explícitamente, y con razón — un latido por minuto son ~1.400 escrituras al día
      // por usuario para un dato que solo devuelve un booleano.
      await tester.pump(const Duration(minutes: 5));
      expect(activity.heartbeats, 1);
    });

    testWidgets('late al volver a primer plano', (WidgetTester tester) async {
      final FakeActivityRepository activity = FakeActivityRepository();
      await _pumpConProvider(
        tester,
        const ActivityHeartbeat(child: SizedBox.shrink()),
        profile: FakeProfileRepository(),
        activity: activity,
      );
      expect(activity.heartbeats, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(activity.heartbeats, 1, reason: 'irse al fondo no es estar presente');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(activity.heartbeats, 2);
    });

    testWidgets('un latido que falla no rompe nada', (
      WidgetTester tester,
    ) async {
      final FakeActivityRepository activity = FakeActivityRepository()
        ..failWith = Exception('la red');

      await _pumpConProvider(
        tester,
        const ActivityHeartbeat(child: Text('la app sigue viva')),
        profile: FakeProfileRepository(),
        activity: activity,
      );

      expect(find.text('la app sigue viva'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
