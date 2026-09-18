import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/profile/profile_badge.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';
import 'package:grasp_mobile/features/profile/presentation/public_profile_screen.dart';

import '../../support/fake_profile_repositories.dart';
import '../../support/fake_social_repositories.dart';

/// El perfil ajeno — `RN-38`, §6.2, y el ADR 0020.
///
/// Boceto: `08-profile.jpeg`, la misma derivación que las listas de follows (cabecera centrada,
/// tarjetas blancas de radio ~20).
///
/// ## Lo que estos tests protegen de verdad
///
/// El grupo del ADR 0020 es el que puede volverse vacuo, y por eso usa
/// [perfilPublicoHostilJson]: comprobar que la pantalla «no pinta categorías» con un fixture que no
/// las trae no distingue ninguna implementación de otra. El fixture **las trae** y la pantalla
/// tiene que ignorarlas.
const String _bruno = '00000000-0000-4000-8000-0000000000b2';

typedef _Dobles = ({
  FakePublicProfileRepository perfiles,
  FakeFollowRepository follows,
  FakeAvatarRepository avatars,
  FakeActivityRepository actividad,
});

Future<_Dobles> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? json,
  ProfileBadge? badge,
  FollowState follow = FollowState.none,
  Map<String, String> photos = const <String, String>{},
  Map<String, bool> activos = const <String, bool>{},
  FakePublicProfileRepository? repo,
  String userId = _bruno,
}) async {
  final FakePublicProfileRepository perfiles =
      repo ??
      FakePublicProfileRepository(json: json ?? perfilPublicoJson(), badge: badge);
  perfiles.state = follow;

  final FakeFollowRepository follows = FakeFollowRepository();
  final FakeAvatarRepository avatars = FakeAvatarRepository(urls: photos);
  final FakeActivityRepository actividad = FakeActivityRepository()
    ..statuses = activos;

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        publicProfileRepositoryProvider.overrideWithValue(perfiles),
        followRepositoryProvider.overrideWithValue(follows),
        avatarRepositoryProvider.overrideWithValue(avatars),
        activityRepositoryProvider.overrideWithValue(actividad),
      ],
      child: MaterialApp(
        theme: theme,
        home: PublicProfileScreen(userId: userId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    perfiles: perfiles,
    follows: follows,
    avatars: avatars,
    actividad: actividad,
  );
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // §6.2 — LO QUE LA FICHA ENSEÑA
  // ══════════════════════════════════════════════════════════════════════════
  group('§6.2 — la ficha', () {
    testWidgets('enseña nombre, edad, tag, bio y nivel', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        json: perfilPublicoJson(
          displayName: 'Bruno',
          age: 34,
          tag: 'bruno#K7M2QX9F',
          bio: 'Aquí para escuchar',
          level: 7,
        ),
      );

      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('bruno#K7M2QX9F'), findsOneWidget);
      expect(find.text('Aquí para escuchar'), findsOneWidget);
      expect(find.textContaining('34'), findsWidgets, reason: 'la edad (ADR 0025)');
      expect(find.textContaining('7'), findsWidgets, reason: 'el nivel');
    });

    testWidgets('la insignia destacada se pinta, y va SOLO aquí (decisión 1)', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        badge: const ProfileBadge(
          slug: 'primera-sala',
          name: 'Primera sala',
          description: 'Entró en su primera sala de voz',
          icon: 'local_fire_department',
          earned: true,
        ),
      );

      // `scrollUntilVisible` y no `find.text` a secas: la insignia va al final del `ListView` y
      // sus hijos no se construyen hasta que entran en pantalla, así que un `findsOneWidget`
      // directo fallaría por el motivo equivocado — no por que la pantalla no la pinte.
      await tester.scrollUntilVisible(
        find.byKey(PublicProfileScreen.badgeKey),
        200,
      );
      await tester.pumpAndSettle();

      expect(find.text('Primera sala'), findsOneWidget);
    });

    testWidgets('sin insignias no se pinta un hueco vacío', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      expect(find.byKey(PublicProfileScreen.badgeKey), findsNothing);
    });

    testWidgets('SIN edad no se pinta un cero ni un guion: se omite', (
      WidgetTester tester,
    ) async {
      // `age` es `null` cuando esa persona no tiene fecha de nacimiento registrada. «Edad
      // desconocida» y «cero años» no son lo mismo, y la vista devuelve NULL justo para no
      // confundirlos: la pantalla tiene que respetarlo.
      await _pump(tester, json: perfilPublicoJson(age: null));

      expect(find.byKey(PublicProfileScreen.ageKey), findsNothing);
      expect(find.textContaining('0 años'), findsNothing);
    });

    testWidgets('la bio vacía no deja una tarjeta en blanco', (
      WidgetTester tester,
    ) async {
      await _pump(tester, json: perfilPublicoJson(bio: null));
      expect(find.byKey(PublicProfileScreen.bioKey), findsNothing);
    });

    testWidgets('la foto se pide POR LOTE cuando la hay', (
      WidgetTester tester,
    ) async {
      // `PublicProfile` trae la CLAVE del objeto en R2, no una URL: la firma
      // `profile-photo-view-url`, que acepta un array justo para esto, y caduca en 300 s.
      final _Dobles d = await _pump(
        tester,
        json: perfilPublicoJson(photoPath: 'avatars/$_bruno/a.webp'),
        photos: <String, String>{_bruno: 'https://r2.example/firmada.webp'},
      );

      expect(d.avatars.batchCalls, 1);
      expect(d.avatars.lastRequestedIds, <String>[_bruno]);
    });

    testWidgets('sin foto NO se pide ninguna firma', (
      WidgetTester tester,
    ) async {
      // Test aparte y no una segunda mitad del anterior: dos `pumpWidget` en el mismo test
      // comparten `WidgetTester` y el segundo montaje no arranca de cero, así que el conteo del
      // doble mezclaba los dos casos. Separarlos es lo que hace que cada mitad pueda fallar sola.
      final _Dobles d = await _pump(
        tester,
        json: perfilPublicoJson(photoPath: null),
      );

      expect(
        d.avatars.batchCalls,
        0,
        reason: 'sin foto no hay nada que firmar; pedirla gasta una firma para nada',
      );
    });

    testWidgets('no hay ficha: lo dice, y no se queda en blanco', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        repo: FakePublicProfileRepository.sinFicha(),
      );
      expect(find.text(PublicProfileScreen.notFound), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ADR 0020 — NI UNA CATEGORÍA NI UNA EXPERIENCIA
  // ══════════════════════════════════════════════════════════════════════════
  group('ADR 0020 — el fixture las TRAE y la pantalla las ignora', () {
    testWidgets('ningún dato del Art. 9 llega a pintarse', (
      WidgetTester tester,
    ) async {
      // Éste es el test que se vuelve vacuo si el fixture no es hostil. La vista
      // `public_profiles` no manda ninguno de estos campos —los enumera y no están—, así que con
      // el fixture limpio pasaría hasta una pantalla que los pintara en cuanto llegaran.
      await _pump(tester, json: perfilPublicoHostilJson());

      for (final String prohibido in <String>[
        'ansiedad',
        'duelo',
        'depresion',
        'perdida-de-un-ser-querido',
        '11111111-1111-4111-8111-111111111111',
      ]) {
        expect(
          find.textContaining(prohibido, skipOffstage: false),
          findsNothing,
          reason:
              '«$prohibido» llegó en la respuesta y la pantalla lo pintó. Es dato del Art. 9 '
              'RGPD de otra persona y el ADR 0020 lo prohíbe en el cliente.',
        );
      }
    });

    testWidgets('tampoco se pintan xp, vip ni reputación, que no son del §6.2', (
      WidgetTester tester,
    ) async {
      await _pump(tester, json: perfilPublicoHostilJson());

      expect(find.textContaining('4321', skipOffstage: false), findsNothing);
      expect(find.textContaining('gold', skipOffstage: false), findsNothing);
      expect(find.textContaining('99', skipOffstage: false), findsNothing);
    });

    testWidgets('la marca de actividad no se pinta: RN-30 es un BOOLEANO', (
      WidgetTester tester,
    ) async {
      // `last_seen_at` vive en `profiles_private` justo para que no se pueda enseñar «hace N
      // minutos», ni siquiera redondeado. Si la respuesta lo trajera, la pantalla no puede usarlo.
      await _pump(tester, json: perfilPublicoHostilJson(), activos: <String, bool>{_bruno: true});

      expect(find.textContaining('2026-08-27', skipOffstage: false), findsNothing);
      expect(find.textContaining('10:00', skipOffstage: false), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §6.2 — EL BOTÓN DE SEGUIR, CON SUS TRES ESTADOS
  // ══════════════════════════════════════════════════════════════════════════
  group('§6.2 — el botón de seguir', () {
    testWidgets('`none` → Seguir, y al pulsarlo manda `request`', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester, follow: FollowState.none);

      expect(find.text(PublicProfileScreen.followLabel), findsOneWidget);

      await tester.tap(find.byKey(PublicProfileScreen.followKey));
      await tester.pumpAndSettle();

      expect(d.follows.toggles, hasLength(1));
      expect(d.follows.toggles.single.action, FollowAction.request);
      expect(d.follows.toggles.single.targetId, _bruno);
    });

    testWidgets('tras solicitar, el botón pasa a Pendiente y se DESHABILITA', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester, follow: FollowState.none);
      d.follows.resultStatus = FollowState.pending;

      await tester.tap(find.byKey(PublicProfileScreen.followKey));
      await tester.pumpAndSettle();

      expect(find.text(PublicProfileScreen.pendingLabel), findsOneWidget);

      // Deshabilitado de verdad, no solo con otro texto: se afirma sobre el `onPressed`, que es el
      // affordance. Un botón que dice «Pendiente» y sigue mandando solicitudes miente.
      final ButtonStyleButton boton = tester.widget<ButtonStyleButton>(
        find.byKey(PublicProfileScreen.followKey),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets('`pending` de entrada ya llega deshabilitado', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester, follow: FollowState.pending);

      expect(find.text(PublicProfileScreen.pendingLabel), findsOneWidget);
      final ButtonStyleButton boton = tester.widget<ButtonStyleButton>(
        find.byKey(PublicProfileScreen.followKey),
      );
      expect(boton.onPressed, isNull);
      expect(d.follows.toggles, isEmpty);
    });

    testWidgets('`following` → Siguiendo', (WidgetTester tester) async {
      await _pump(tester, follow: FollowState.following);
      expect(find.text(PublicProfileScreen.followingLabel), findsOneWidget);
    });

    testWidgets('el estado del botón SE PREGUNTA, no se supone', (
      WidgetTester tester,
    ) async {
      // Sin esto, una pantalla que pintara siempre `Seguir` pasaría el primer test del grupo: el
      // estado por defecto del doble es `none`. Lo que distingue una implementación de otra es que
      // llegue a preguntarlo.
      final _Dobles d = await _pump(tester, follow: FollowState.following);

      expect(d.perfiles.followStateCalls, 1);
      expect(find.text(PublicProfileScreen.followLabel), findsNothing);
    });

    testWidgets('si falla la solicitud, el botón vuelve a Seguir y lo dice', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester, follow: FollowState.none);
      d.follows.failWith = Exception('sin red');

      await tester.tap(find.byKey(PublicProfileScreen.followKey));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(PublicProfileScreen.followLabel), findsOneWidget);

      // Y sigue siendo pulsable: un fallo de red no puede dejar el botón muerto para siempre.
      final ButtonStyleButton boton = tester.widget<ButtonStyleButton>(
        find.byKey(PublicProfileScreen.followKey),
      );
      expect(boton.onPressed, isNotNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-30 — EL PUNTO DE ACTIVIDAD
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-30 — el punto de actividad', () {
    testWidgets('se pide por el RPC, con el id de quien se mira', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(
        tester,
        activos: <String, bool>{_bruno: true},
      );

      expect(d.actividad.statusCalls, hasLength(1));
      expect(d.actividad.statusCalls.single, <String>[_bruno]);
    });

    testWidgets('quien no aparece en la respuesta se pinta inactivo, no roto', (
      WidgetTester tester,
    ) async {
      await _pump(tester, activos: const <String, bool>{});
      expect(find.byKey(PublicProfileScreen.activityKey), findsOneWidget);
    });
  });
}
