import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/social/social_failure.dart';
import 'package:grasp_mobile/features/profile/application/profile_controller.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/profile_tag_row.dart';

import '../../support/fake_profile_repositories.dart';

/// La fila del tag en el perfil propio — §6.2 y decisión 5 (Tarea 24).
///
/// ## Por qué hay un botón de rotar, si el plan solo pedía copiar
///
/// Porque `profile-tag-rotate` **estaba construido, contratado y probado desde la Tarea 7 y no lo
/// llamaba nadie**: `grep -rn "tag-rotate" apps/mobile/lib` no devolvía ni una línea. El §6.2
/// promete que el usuario «puede solicitar un nuevo tag» y la decisión 5 dice literalmente «se
/// implementa la rotación». Es el mismo fallo que `CLAUDE.md` recoge como principio general —un
/// mecanismo sin puerta de entrada no existe— y que ya mordió a `account-delete` y a
/// `connect_dismissals`. Se detectó igual que aquellos: **por ausencia**.
Future<FakeProfileRepository> _pump(
  WidgetTester tester, {
  String? tag = 'alfon#K7M2QX9F',
  FakeProfileRepository? repo,
}) async {
  final FakeProfileRepository profileRepo =
      repo ?? FakeProfileRepository(profile: fakeProfile(tag: tag));

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        profileRepositoryProvider.overrideWithValue(profileRepo),
      ],
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              final String? actual = ref
                  .watch(profileControllerProvider)
                  .valueOrNull
                  ?.tag;
              return ProfileTagRow(tag: actual);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return profileRepo;
}

/// Lo que se haya mandado al portapapeles, o `null` si nadie lo tocó.
String? _portapapeles(WidgetTester tester) => _copiado;
String? _copiado;

void _espiarPortapapeles(WidgetTester tester) {
  _copiado = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        _copiado = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    },
  );
}

List<String> _todoElTexto(WidgetTester tester) {
  final List<String> out = <String>[];
  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.data != null) out.add(t.data!);
  }
  for (final Tooltip t in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
    if (t.message != null) out.add(t.message!);
  }
  return out;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // §6.2 — EL TAG SE VE Y SE PUEDE COPIAR
  // ══════════════════════════════════════════════════════════════════════════
  group('§6.2 — el tag y su botón de copiar', () {
    testWidgets('el tag se ve tal cual lo acuñó el servidor', (
      WidgetTester tester,
    ) async {
      await _pump(tester, tag: 'alfon#K7M2QX9F');
      expect(find.text('alfon#K7M2QX9F'), findsOneWidget);
    });

    testWidgets('copiar manda al portapapeles EL TAG, no otra cosa', (
      WidgetTester tester,
    ) async {
      // §6.2: teclearlo a mano es la única forma de encontrar a alguien, así que copiarlo no es un
      // adorno. Se comprueba el CONTENIDO copiado: un botón que copiara el nombre, o una cadena
      // vacía, pasaría igual un test que solo mirase que el botón existe.
      _espiarPortapapeles(tester);
      await _pump(tester, tag: 'alfon#K7M2QX9F');

      await tester.tap(find.byKey(ProfileTagRow.copyKey));
      await tester.pumpAndSettle();

      expect(_portapapeles(tester), 'alfon#K7M2QX9F');
    });

    testWidgets('sin tag todavía no se ofrece copiar ni cambiar', (
      WidgetTester tester,
    ) async {
      // `tag` es `null` hasta que el trigger de alta lo acuña. Copiar «null» o rotar lo que no
      // existe son dos botones que no pueden funcionar.
      await _pump(tester, tag: null);
      expect(find.byKey(ProfileTagRow.copyKey), findsNothing);
      expect(find.byKey(ProfileTagRow.rotateKey), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // DECISIÓN 5 — LA ROTACIÓN, QUE NO TENÍA PUERTA DE ENTRADA
  // ══════════════════════════════════════════════════════════════════════════
  group('decisión 5 — cambiar el tag', () {
    testWidgets('pide confirmación antes de rotar', (
      WidgetTester tester,
    ) async {
      final FakeProfileRepository repo = await _pump(tester);

      await tester.tap(find.byKey(ProfileTagRow.rotateKey));
      await tester.pumpAndSettle();

      // Con el modal abierto todavía NO se ha rotado: si se rotara al tocar la entrada, el modal
      // sería decorativo y el tag habría cambiado sin que nadie lo pidiera.
      //
      // OJO CON LO QUE ESTE TEST **NO** PRUEBA, que se descubrió mutando. Una implementación que
      // abriera el modal y luego **ignorase la respuesta** lo pasa igual: el `await showDialog`
      // sigue pendiente mientras nadie cierre el diálogo, así que `rotateCalls` es 0 en los dos
      // casos. Lo que sí distingue las dos es «cancelar NO rota», más abajo — ahí se cierra el
      // modal y se comprueba que la respuesta se respetó. Los dos hacen falta.
      expect(repo.rotateCalls, 0);
      expect(find.text(ProfileTagRow.rotateWarning), findsOneWidget);
    });

    testWidgets('el aviso dice que el tag actual DEJARÁ DE FUNCIONAR', (
      WidgetTester tester,
    ) async {
      // Es lo único que le da a la persona la información para decidir: quien tenga el tag viejo
      // apuntado deja de poder encontrarla. Sin esa frase, «cambiar tag» parece gratis.
      await _pump(tester);
      await tester.tap(find.byKey(ProfileTagRow.rotateKey));
      await tester.pumpAndSettle();

      expect(
        _todoElTexto(tester).join('\n').toLowerCase(),
        contains('dejará de funcionar'),
      );
    });

    testWidgets('confirmar rota de verdad y pinta EL TAG QUE DEVOLVIÓ el servidor', (
      WidgetTester tester,
    ) async {
      // No es optimista a propósito: el tag nuevo lo elige el servidor y aquí no se puede adivinar.
      // Pintar uno provisional enseñaría un identificador que no existe, y el tag es justo el dato
      // que la gente copia y comparte.
      final FakeProfileRepository repo = FakeProfileRepository(
        profile: fakeProfile(tag: 'alfon#K7M2QX9F'),
      )..tagsARotar = <String>['alfon#9K5WZRHJ'];

      await _pump(tester, repo: repo);
      await tester.tap(find.byKey(ProfileTagRow.rotateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileTagRow.rotateConfirmKey));
      await tester.pumpAndSettle();

      expect(repo.rotateCalls, 1);
      expect(find.text('alfon#9K5WZRHJ'), findsOneWidget);
      expect(find.text('alfon#K7M2QX9F'), findsNothing);
    });

    testWidgets('cancelar NO rota', (WidgetTester tester) async {
      final FakeProfileRepository repo = await _pump(tester);
      await tester.tap(find.byKey(ProfileTagRow.rotateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileTagRow.cancelKey));
      await tester.pumpAndSettle();

      expect(repo.rotateCalls, 0);
      expect(find.text('alfon#K7M2QX9F'), findsOneWidget);
    });

    testWidgets('el tope de 24 h se explica, y NO como si fueran solicitudes de seguimiento', (
      WidgetTester tester,
    ) async {
      // TRAMPA REAL: `rate_limited` lo emiten DOS funciones —`profile-tag-rotate` y
      // `follow-toggle`— con la misma forma de `details`, así que `SocialFailure.fromResponse` no
      // puede distinguirlas por el cuerpo y resuelve a favor de la de follows. Dejarlo pasar diría,
      // al topar el cupo del tag, que se enviaron solicitudes que nadie envió: un límite mal
      // nombrado es un fallo mudo con otra ropa, y `RN-21` obliga a decir CUÁL es el límite.
      final FakeProfileRepository repo = FakeProfileRepository()
        ..rotateFailsWith = SocialFailure(
          SocialFailureKind.limitReached,
          'Solo puedes cambiar tu tag una vez cada 24 horas. '
          'Podrás volver a cambiarlo a partir de las 09:30.',
          rawCode: 'rate_limited',
          limit: 1,
          retryAt: DateTime(2026, 8, 28, 9, 30),
        );

      await _pump(tester, repo: repo);
      await tester.tap(find.byKey(ProfileTagRow.rotateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileTagRow.rotateConfirmKey));
      await tester.pumpAndSettle();

      final String todo = _todoElTexto(tester).join('\n').toLowerCase();
      expect(todo, contains('24 horas'));
      expect(
        todo,
        isNot(contains('solicitudes de seguimiento')),
        reason: 'el 422 del tag se está contando como si fuera el de follows',
      );
      // Y el tag no cambió.
      expect(find.text('alfon#K7M2QX9F'), findsOneWidget);
    });

    testWidgets('un fallo cualquiera no deja el tag a medias', (
      WidgetTester tester,
    ) async {
      final FakeProfileRepository repo = FakeProfileRepository()
        ..rotateFailsWith = Exception('la red');

      await _pump(tester, repo: repo);
      await tester.tap(find.byKey(ProfileTagRow.rotateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileTagRow.rotateConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text('alfon#K7M2QX9F'), findsOneWidget);
    });
  });
}
