import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/rooms/room_summary.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/social_avatar.dart';
import 'package:grasp_mobile/features/rooms/presentation/rooms_screen.dart';
import 'package:grasp_mobile/features/rooms/presentation/widgets/room_card.dart';
import 'package:grasp_mobile/features/rooms/presentation/widgets/room_category_chips.dart';

import '../../support/fake_rooms_repository.dart';
import '../../support/fake_social_repositories.dart';

/// OJO CON LO QUE ESTE ARNÉS **NO** PRUEBA.
///
/// Un test de widget corre a **800×600** —más ancho que cualquier móvil— y con una fuente de
/// *fallback*, porque `google_fonts` no descarga nada en tests. Sirve como **cota conservadora** del
/// overflow (si aquí desborda, en un móvil desborda seguro) y **no sirve** para decidir sobre
/// truncado: dónde corta un título de 80 caracteres se mira en el emulador.
///
/// Además un overflow **no tumba el test**: hay que recogerlo con `tester.takeException()`.
ThemeData _theme() => AppTheme.light().copyWith(
  extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
);

/// Monta un widget suelto (la tarjeta) con el tema real.
Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: _theme(),
    home: Scaffold(body: Center(child: child)),
  ),
);

Future<void> _pumpScreen(
  WidgetTester tester,
  FakeRoomsRepository repository, {
  FakeAvatarRepository? avatars,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        roomsRepositoryProvider.overrideWithValue(repository),
        avatarRepositoryProvider.overrideWithValue(
          avatars ?? FakeAvatarRepository(),
        ),
      ],
      child: MaterialApp(theme: _theme(), home: const RoomsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// El chip de la FILA DE FILTROS con ese texto.
///
/// No vale `find.text('Duelo')` a secas: la tarjeta de una sala de ese tema pinta el mismo texto en
/// su propio chip, y el `tap` se vuelve ambiguo. El fallo es del test, no de la pantalla — pero
/// tocar el chip de la tarjeta tampoco filtraría nada, y por eso ese chip no es interactivo.
Finder _chip(String label) => find.descendant(
  of: find.byType(RoomCategoryChips),
  matching: find.text(label),
);

/// Los títulos **pintados**, en orden.
///
/// Lee el `Text` de dentro de cada tarjeta y no `RoomCard.room.title`: leer el objeto widget
/// devuelve el dato que se le PASÓ, así que seguiría verde con una tarjeta que no pintara el
/// título. Es la misma trampa que la del widget vacío, en su versión callada.
///
/// Busca dentro de la `Expanded` que contiene la `Column` del contenido, y luego el primer `Text`
/// dentro — que es el título. No busca en el host ni en el chip del tema.
List<String> _titulos(WidgetTester tester) => <String>[
  for (final Element card in find.byType(RoomCard).evaluate())
    tester
        .widgetList<Text>(
          find.descendant(
            of: find.descendant(
              of: find.byWidget(card.widget),
              matching: find.byType(Expanded),
            ),
            matching: find.byType(Text),
          ),
        )
        .first
        .data ??
        '',
];

void main() {
  group('la tarjeta — ADR 0032 § 4', () {
    testWidgets('la cadena muestra 4 avatares y el resto va al +N', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RoomCard(
            room: fakeRoom(
              occupants: 12,
              avatars: const <String>['a', 'b', 'c', 'd'],
              overflow: 8,
            ),
          ),
        ),
      );

      expect(find.byType(RoomAvatar), findsNWidgets(4));
      // `+8`, LOS QUE NO CABEN. Con 12 dentro, un `+12` sería el total y un `+11` el total menos el
      // host: los tres números son distintos y solo uno lo decidió el backend.
      expect(find.text('+8'), findsOneWidget);
      expect(find.text('+12'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con 4 o menos dentro no se pinta el +N', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RoomCard(
            room: fakeRoom(
              occupants: 3,
              avatars: const <String>['a', 'b'],
              overflow: 0,
            ),
          ),
        ),
      );

      expect(find.textContaining('+'), findsNothing);
      // Y se pintan DOS caras, no cuatro huecos rellenados: la cadena pinta a quien hay.
      expect(find.byType(RoomAvatar), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin nadie más que el host no hay cadena en absoluto', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _RoomCardHarness(
            room: fakeRoom(title: 'A solas', hostName: 'Ana', occupants: 1),
          ),
        ),
      );

      expect(find.byType(RoomAvatar), findsNothing);
      expect(find.textContaining('+'), findsNothing);
      // CONTROL POSITIVO. Sin esto el caso lo cumple una tarjeta que no pinte NADA, que es la
      // mutacion equivalente a quitar el `sort` de una lista: `findsNothing` es cierto sobre el
      // vacio. Todo caso que afirme una ausencia lleva al lado la presencia de lo que sí debe
      // pintarse.
      expect(find.text('A solas'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    });

    testWidgets('pinta el título, el host y el chip del tema', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RoomCard(
            room: fakeRoom(title: 'Me cuesta estar solo/a', hostName: 'Ana'),
            categoryName: 'Soledad',
          ),
        ),
      );

      expect(find.text('Me cuesta estar solo/a'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Soledad'), findsOneWidget);
    });

    testWidgets('pinta la foto del host EN GRANDE, con su URL firmada', (
      WidgetTester tester,
    ) async {
      // Primer bullet del §4 del ADR 0032 —«izquierda: la foto de perfil de quien creó la sala, en
      // grande»— y es justo la corrección que el ADR trae sobre el boceto, que la pintaba pequeña.
      //
      // NO SE AFIRMA SOBRE EL NOMBRE: `find.text('Ana')` cae en la línea de debajo del título, así
      // que borrar el avatar entero lo dejaba verde. Se afirma sobre el widget y sobre el tamaño.
      await tester.pumpWidget(
        _wrap(
          RoomCard(
            room: fakeRoom(hostName: 'Ana', hostPhotoPath: 'avatars/ana.webp'),
            hostPhotoUrl: 'https://r2.example/ana.webp',
          ),
        ),
      );

      final SocialAvatar avatar = tester.widget<SocialAvatar>(
        find.byType(SocialAvatar),
      );
      expect(avatar.size, 64, reason: 'El ADR 0032 lo pide EN GRANDE.');
      // Y CONSUME LA FIRMA: sin esto se podría pedir la URL —la que acabamos de acotar con el
      // troceo— y tirarla sin que nadie protestara.
      expect(avatar.photoUrl, 'https://r2.example/ana.webp');
      expect(avatar.displayName, 'Ana');
    });

    testWidgets('sin catálogo no se pinta un chip con el uuid dentro', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RoomCard(
            room: fakeRoom(
              title: 'Sin tema resuelto',
              categoryId: 'cat-uuid-1',
            ),
          ),
        ),
      );

      expect(find.textContaining('cat-uuid-1'), findsNothing);
      // CONTROL POSITIVO: la tarjeta sí se pinta, solo le falta el chip.
      expect(find.text('Sin tema resuelto'), findsOneWidget);
    });

    testWidgets('un título de 80 caracteres no desborda a 800×600', (
      WidgetTester tester,
    ) async {
      // COTA CONSERVADORA, no una promesa sobre el móvil: 800 px es más ancho que cualquier
      // teléfono. Lo que dice es que si aquí ya desbordara, en un móvil desbordaría seguro.
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 360,
            child: RoomCard(
              room: fakeRoom(
                title: 'A' * 80,
                avatars: const <String>['a', 'b', 'c', 'd'],
                overflow: 16,
              ),
              categoryName: 'Ansiedad y estrés cotidiano',
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // CONTROL POSITIVO, Y AQUÍ ES EL MÁS IMPORTANTE DEL FICHERO: `takeException(), isNull` es
      // cierto para un widget que no pinte nada, y un widget vacío no desborda jamás. Sin estas
      // tres líneas, el caso que se usa para hablar de overflow no afirma nada.
      expect(find.text('A' * 80), findsOneWidget);
      expect(find.byType(RoomAvatar), findsNWidgets(4));
      expect(find.text('+16'), findsOneWidget);
    });
  });

  group('lo que se ANUNCIA, que no es lo que se ve', () {
    testWidgets('la etiqueta da la gente REAL de la sala, host incluido', (
      WidgetTester tester,
    ) async {
      // `occupants` viaja en el contrato y no se pinta: el ADR 0032 cambió el «18 en la sala» del
      // boceto por la cadena, y eso es una decisión VISUAL. Quien no ve las caras se quedaría sin
      // el dato, y ni la cadena (corta en 4) ni el `+N` (no cuenta al host) lo dan.
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          RoomCard(
            room: fakeRoom(
              occupants: 12,
              avatars: const <String>['a', 'b', 'c', 'd'],
              overflow: 7,
            ),
          ),
        ),
      );

      // `getSemantics` y no `bySemanticsLabel`: el nodo de la cadena tiene HIJOS —las caras y el
      // `+7`— así que su etiqueta no es la del nodo hoja que busca ese finder.
      final SemanticsNode nodo = tester.getSemantics(
        find.byType(RoomAvatarChain),
      );
      expect(nodo.label, contains('12 personas en la sala'));
      // Y NINGUNO de los números que se ven es el bueno: 4 caras, `+7`, y son 12.
      expect(nodo.label, isNot(contains('4 personas')));
      expect(nodo.label, isNot(contains('7 personas')));

      // A mano y no con `addTearDown`: la verificación de handles del arnés corre ANTES de los
      // tearDown y falla el caso aunque el handle se acabe cerrando.
      handle.dispose();
    });

    test('el singular no dice «1 personas»', () {
      expect(occupantsLabel(1), '1 persona en la sala');
      expect(occupantsLabel(2), '2 personas en la sala');
    });
  });

  group('la lista', () {
    testWidgets('una tarjeta por sala, en el orden que mandó el backend', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(
        tester,
        FakeRoomsRepository(
          rooms: <RoomSummary>[
            fakeRoom(id: 'r1', title: 'Primera'),
            fakeRoom(id: 'r2', title: 'Segunda'),
            fakeRoom(id: 'r3', title: 'Tercera'),
          ],
        ),
      );

      // El orden es el de `rooms_feed` (actividad reciente, ADR 0032 § 3) y no se reordena aquí.
      expect(_titulos(tester), <String>['Primera', 'Segunda', 'Tercera']);
    });

    testWidgets('el nombre del tema sale del catálogo, no del uuid', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(
        tester,
        FakeRoomsRepository(
          rooms: <RoomSummary>[fakeRoom(categoryId: 'c-ansiedad')],
          categoryList: const <RoomCategory>[
            RoomCategory(id: 'c-ansiedad', name: 'Ansiedad'),
          ],
        ),
      );

      // Dos veces: el chip de la fila de filtros y el de la tarjeta.
      expect(find.text('Ansiedad'), findsNWidgets(2));
    });

    testWidgets('una sola tanda de firmas para toda la página, no una por tarjeta', (
      WidgetTester tester,
    ) async {
      // Cinco caras por tarjeta × N tarjetas serían 5N peticiones para pintar una pantalla.
      final FakeAvatarRepository avatars = FakeAvatarRepository();
      await _pumpScreen(
        tester,
        FakeRoomsRepository(
          rooms: <RoomSummary>[
            for (int i = 0; i < 4; i++)
              fakeRoom(
                id: 'r$i',
                hostId: 'host-$i',
                hostPhotoPath: 'avatars/host-$i.jpg',
                avatars: <String>['u$i-a', 'u$i-b'],
              ),
          ],
        ),
        avatars: avatars,
      );

      expect(avatars.batchCalls, 1);
      expect(avatars.lastRequestedIds, hasLength(12));
      // Los hosts SIN foto no entran en la tanda: no hay nada que firmar.
      expect(avatars.lastRequestedIds, contains('host-0'));
    });

    testWidgets('la URL firmada del host llega desde el controlador a la tarjeta', (
      WidgetTester tester,
    ) async {
      // El recorrido entero: `hostPhotoPath` decide que se pida la firma, la firma vuelve en el
      // mapa, y la tarjeta la consume. Cada tramo tenía su caso; el pegado, ninguno.
      await _pumpScreen(
        tester,
        FakeRoomsRepository(
          rooms: <RoomSummary>[
            fakeRoom(hostId: 'host-1', hostPhotoPath: 'avatars/host-1.webp'),
          ],
        ),
        avatars: FakeAvatarRepository(
          urls: const <String, String>{'host-1': 'https://r2.example/h1.webp'},
        ),
      );

      final SocialAvatar avatar = tester.widget<SocialAvatar>(
        find
            .descendant(
              of: find.byType(RoomCard),
              matching: find.byType(SocialAvatar),
            )
            .first,
      );
      expect(avatar.photoUrl, 'https://r2.example/h1.webp');
    });

    testWidgets('un host sin foto no gasta una firma', (
      WidgetTester tester,
    ) async {
      final FakeAvatarRepository avatars = FakeAvatarRepository();
      await _pumpScreen(
        tester,
        FakeRoomsRepository(
          rooms: <RoomSummary>[fakeRoom(hostId: 'host-sin-foto')],
        ),
        avatars: avatars,
      );

      expect(avatars.lastRequestedIds, isNot(contains('host-sin-foto')));
    });
  });

  group('degradación — una firma rota no puede vaciar la pantalla', () {
    testWidgets('si `photoUrls` lanza, las salas se siguen viendo con siluetas', (
      WidgetTester tester,
    ) async {
      // ES LA RAMA QUE DISPARA EL FALLO REAL: con más de 50 ids `profile-photo-view-url` devuelve
      // 400, y el `catch` del controlador lo absorbe. Lo que este caso fija es que absorberlo deje
      // la lista PINTADA — no una pantalla vacía sin ningún error a la vista.
      final FakeAvatarRepository avatars = FakeAvatarRepository()
        ..throwOnBatch = true;

      await _pumpScreen(
        tester,
        FakeRoomsRepository(
          rooms: <RoomSummary>[
            fakeRoom(
              id: 'r1',
              title: 'Sigue viéndose',
              hostPhotoPath: 'avatars/host-1.webp',
              avatars: const <String>['u1', 'u2'],
              occupants: 3,
            ),
          ],
        ),
        avatars: avatars,
      );

      expect(avatars.batchCalls, 1);
      expect(find.byType(RoomCard), findsOneWidget);
      expect(find.text('Sigue viéndose'), findsOneWidget);
      // Las caras siguen ahí, sin foto: el marcador neutro es honesto, un hueco no.
      expect(find.byType(RoomAvatar), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('el estado vacío es honesto', () {
    testWidgets('dice que no hay ninguna sala abierta', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, FakeRoomsRepository());

      expect(find.text(RoomsScreen.emptyState), findsOneWidget);
      expect(find.byType(RoomCard), findsNothing);
    });

    testWidgets('y NO ofrece ningún botón, porque no hay ninguna acción real', (
      WidgetTester tester,
    ) async {
      // Crear una sala existe en `room-actions`, pero en la app no hay ni formulario que pida
      // título y tema ni pantalla de sala a la que llevar (Tarea 8). Un «Crear una sala» aquí sería
      // un control que no hace nada afirmando que la función existe.
      //
      // SE COMPRUEBA EL AFFORDANCE, NO EL TEXTO: buscar `findsNothing` sobre la cadena «Crear una
      // sala» pasaría igual con un botón que dijera «Empezar», y ese es el fallo que este caso
      // existe para atrapar.
      await _pumpScreen(tester, FakeRoomsRepository());

      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('los chips de tema — el filtro lo hace el BACKEND', () {
    List<RoomCategory> catalogo() => const <RoomCategory>[
      RoomCategory(id: 'c-ansiedad', name: 'Ansiedad'),
      RoomCategory(id: 'c-duelo', name: 'Duelo'),
    ];

    testWidgets('`Todas` + una píldora por categoría', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(
        tester,
        FakeRoomsRepository(
          rooms: <RoomSummary>[fakeRoom()],
          categoryList: catalogo(),
        ),
      );

      expect(find.text(RoomCategoryChips.allLabel), findsOneWidget);
      expect(find.text('Ansiedad'), findsOneWidget);
      expect(find.text('Duelo'), findsOneWidget);
    });

    testWidgets('pulsar un tema vuelve a PEDIR el feed con ese categoryId', (
      WidgetTester tester,
    ) async {
      final FakeRoomsRepository repository = FakeRoomsRepository(
        rooms: <RoomSummary>[
          fakeRoom(id: 'r1', title: 'De ansiedad', categoryId: 'c-ansiedad'),
          fakeRoom(id: 'r2', title: 'De duelo', categoryId: 'c-duelo'),
        ],
        categoryList: catalogo(),
        byCategory: <String, List<RoomSummary>>{
          'c-duelo': <RoomSummary>[
            fakeRoom(id: 'r2', title: 'De duelo', categoryId: 'c-duelo'),
          ],
        },
      );
      await _pumpScreen(tester, repository);
      expect(repository.feedCalls, <String?>[null]);
      expect(_titulos(tester), <String>['De ansiedad', 'De duelo']);

      await tester.tap(_chip('Duelo'));
      await tester.pumpAndSettle();

      // LO QUE SE AFIRMA ES LA PETICIÓN, no solo lo que quedó en pantalla: una pantalla que
      // filtrase la lista en el cliente pasaría el segundo `expect` y fallaría el primero.
      expect(repository.feedCalls, <String?>[null, 'c-duelo']);
      expect(_titulos(tester), <String>['De duelo']);
    });

    testWidgets('volver a `Todas` pide el feed sin filtro', (
      WidgetTester tester,
    ) async {
      final FakeRoomsRepository repository = FakeRoomsRepository(
        rooms: <RoomSummary>[fakeRoom(id: 'r1', title: 'De ansiedad')],
        categoryList: catalogo(),
      );
      await _pumpScreen(tester, repository);

      await tester.tap(_chip('Duelo'));
      await tester.pumpAndSettle();
      await tester.tap(_chip(RoomCategoryChips.allLabel));
      await tester.pumpAndSettle();

      expect(repository.feedCalls, <String?>[null, 'c-duelo', null]);
      expect(_titulos(tester), <String>['De ansiedad']);
    });

    testWidgets('el catálogo se pide UNA vez, no en cada cambio de filtro', (
      WidgetTester tester,
    ) async {
      final FakeRoomsRepository repository = FakeRoomsRepository(
        rooms: <RoomSummary>[fakeRoom()],
        categoryList: catalogo(),
      );
      await _pumpScreen(tester, repository);

      await tester.tap(_chip('Duelo'));
      await tester.pumpAndSettle();

      expect(repository.categoryCalls, 1);
    });

    testWidgets('sin catálogo NO se pinta la fila: filtrar no es posible', (
      WidgetTester tester,
    ) async {
      // Pasa de verdad: `onboarding-catalogs` desplegado sin el `id` de categoría devuelve un
      // catálogo que esta pantalla no puede usar. Unos chips inertes afirmarían que se puede
      // filtrar por tema.
      await _pumpScreen(
        tester,
        FakeRoomsRepository(
          rooms: <RoomSummary>[fakeRoom()],
          categoriesThrow: true,
        ),
      );

      expect(find.byType(RoomCategoryChips), findsNothing);
      expect(find.text(RoomCategoryChips.allLabel), findsNothing);
      // Y la lista se sigue viendo entera: el catálogo no puede tumbar la pantalla.
      expect(find.byType(RoomCard), findsOneWidget);
    });
  });

  group('errores', () {
    testWidgets('un feed que falla se explica y se puede reintentar', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, _FailingFeed());

      expect(find.text(RoomsScreen.loadError), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });
}

/// La tarjeta con `categoryName` a `null`, para el caso «sin nadie más que el host».
class _RoomCardHarness extends StatelessWidget {
  const _RoomCardHarness({required this.room});

  final RoomSummary room;

  @override
  Widget build(BuildContext context) => RoomCard(room: room);
}

class _FailingFeed extends FakeRoomsRepository {
  @override
  Future<List<RoomSummary>> feed({String? categoryId}) async {
    feedCalls.add(categoryId);
    throw Exception('sin red');
  }
}
