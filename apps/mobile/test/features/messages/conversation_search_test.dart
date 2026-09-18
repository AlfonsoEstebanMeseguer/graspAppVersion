import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/social/messaging_repository.dart';
import 'package:grasp_mobile/features/messages/application/conversation_controller.dart';
import 'package:grasp_mobile/features/messages/presentation/conversation_screen.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/conversation_menu.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/conversation_search_bar.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/message_bubble.dart';

import '../../support/fake_social_repositories.dart';

/// Tests de la búsqueda dentro de la conversación — §9.4 (Tarea 23).
///
/// ## Dónde se vuelve vacua esta suite, y cómo se evita
///
/// El §9.4 dice que la búsqueda **no encuentra nada en mensajes borrados para mí, ni anteriores a
/// mi `cleared_at`, ni en lápidas**. Esas tres reglas las aplica `messaging-search` en el servidor,
/// así que un doble que devolviera una lista vacía haría verde **cualquier** implementación — la
/// que pinta lo que el backend manda y la que se busca la vida recorriendo las burbujas con
/// `findMatches`.
///
/// Por eso los fixtures de esta suite son **hostiles**: el hilo contiene mensajes que **sí llevan el
/// término** y que el doble de `search()` **no devuelve**. Es la única forma de que el test
/// distinga las dos implementaciones. Misma lección que la lápida de la Tarea 20 y que
/// `inputBloqueadoHostil`.
const String _otro = '00000000-0000-4000-8000-000000000002';

ConversationArgs get _args => const ConversationArgs.existing(
  conversationId: 'c1',
  otherUserId: _otro,
  displayName: 'Ana',
);

Future<FakeMessagingRepository> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> messages,
  required MessageSearchResult resultado,
  bool hasMore = false,
  String? nextBefore,
}) async {
  final FakeMessagingRepository messaging = FakeMessagingRepository()
    ..searchResult = resultado;
  messaging.threadJson = threadPageJson(
    input: inputAccepted,
    messages: messages,
    hasMore: hasMore,
    nextBefore: nextBefore,
  );

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        messagingRepositoryProvider.overrideWithValue(messaging),
        moderationRepositoryProvider.overrideWithValue(
          FakeModerationRepository(),
        ),
        avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
      ],
      child: MaterialApp(
        theme: theme,
        home: ConversationScreen(args: _args),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return messaging;
}

/// Abre la búsqueda por donde la abre una persona: el menú de tres puntos → la lupa.
Future<void> _abrirBusqueda(WidgetTester tester) async {
  await tester.tap(find.byKey(ConversationScreen.menuKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ConversationMenu.searchKey));
  await tester.pumpAndSettle();
}

Future<void> _buscar(WidgetTester tester, String termino) async {
  await tester.enterText(find.byKey(ConversationSearchBar.fieldKey), termino);
  // El rebote de la barra: sin esperarlo, la petición no llega a salir y el test comprobaría el
  // estado anterior creyendo que mira el nuevo.
  await tester.pump(kSearchDebounce);
  await tester.pumpAndSettle();
}

/// Los trozos resaltados dentro de las burbujas, con el texto que llevan dentro.
///
/// Se recorre el `InlineSpan` de verdad: el resaltado del §9.4 es un tramo con fondo **dentro** de
/// la misma burbuja, no un widget aparte, así que `find.text` no lo ve.
List<String> _resaltados(WidgetTester tester) {
  final List<String> out = <String>[];
  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    final InlineSpan? raiz = t.textSpan;
    if (raiz == null) continue;
    raiz.visitChildren((InlineSpan span) {
      if (span is TextSpan &&
          span.text != null &&
          span.style?.backgroundColor != null) {
        out.add(span.text!);
      }
      return true;
    });
  }
  return out;
}

/// Si el widget que pinta [texto] está dentro de la parte visible de la pantalla.
bool _visible(WidgetTester tester, String texto) {
  final Finder f = find.text(texto);
  if (f.evaluate().isEmpty) return false;
  final Rect r = tester.getRect(f);
  final Size pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
  return r.top >= 0 && r.bottom <= pantalla.height;
}

/// 12 coincidencias repartidas en 6 mensajes, a 2 por mensaje — el `12` del contador `3/12`.
///
/// Dos por mensaje **a propósito**: el §9.4 cuenta *coincidencias*, no mensajes, así que un
/// contador que contara `hits.length` diría 6 y una implementación así pasaría desapercibida con
/// una coincidencia por mensaje.
List<Map<String, dynamic>> get _seisMensajes => <Map<String, dynamic>>[
  for (int i = 1; i <= 6; i++)
    mensajeJson(
      id: 'm$i',
      content: 'café y más café, ronda $i',
      createdAt: DateTime.utc(2026, 8, 26, 10, i),
    ),
];

MessageSearchResult get _doceCoincidencias => busquedaConCoincidencias(
  searchedMessages: 6,
  hits: <({String messageId, List<({int start, int end})> offsets})>[
    // De más reciente a más antiguo, como los devuelve el backend.
    for (int i = 6; i >= 1; i--)
      (
        messageId: 'm$i',
        offsets: <({int start, int end})>[
          (start: 0, end: 4),
          (start: 12, end: 16),
        ],
      ),
  ],
);

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // ABRIR Y CERRAR
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.4 — abrir la búsqueda', () {
    testWidgets('la lupa del §9.3 abre la barra de búsqueda', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        messages: _seisMensajes,
        resultado: _doceCoincidencias,
      );

      expect(find.byType(ConversationSearchBar), findsNothing);
      await _abrirBusqueda(tester);
      expect(find.byType(ConversationSearchBar), findsOneWidget);
    });

    testWidgets('cerrarla quita el resaltado y no deja la búsqueda viva', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        messages: _seisMensajes,
        resultado: _doceCoincidencias,
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'café');
      expect(_resaltados(tester), isNotEmpty);

      await tester.tap(find.byKey(ConversationSearchBar.closeKey));
      await tester.pumpAndSettle();

      expect(find.byType(ConversationSearchBar), findsNothing);
      expect(
        _resaltados(tester),
        isEmpty,
        reason: 'el resaltado sobrevivió a cerrar la búsqueda',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §9.4 — LA CABECERA DICE LA COTA
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.4 — la cota de 1000', () {
    testWidgets('la cabecera avisa de que se buscan los últimos 1000', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        messages: _seisMensajes,
        resultado: _doceCoincidencias,
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'café');

      expect(find.byKey(ConversationSearchBar.limitNoticeKey), findsOneWidget);
      expect(find.textContaining('1000'), findsWidgets);
    });

    testWidgets('la cota sale de `search_limit`, no de un 1000 escrito a mano', (
      WidgetTester tester,
    ) async {
      // `MessageSearchResult` trae `searchLimit` justo para esto: con `total` solo no se puede
      // decir la cota. Un literal en la UI diría «1000» aunque el backend cambiara la cota, que es
      // exactamente la clase de mentira que este aviso existe para evitar.
      await _pump(
        tester,
        messages: _seisMensajes,
        resultado: busquedaConCoincidencias(
          searchLimit: 500,
          hits: <({String messageId, List<({int start, int end})> offsets})>[
            (messageId: 'm1', offsets: <({int start, int end})>[(start: 0, end: 4)]),
          ],
        ),
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'café');

      final Text aviso = tester.widget<Text>(
        find.byKey(ConversationSearchBar.limitNoticeKey),
      );
      expect(aviso.data, contains('500'));
      expect(aviso.data, isNot(contains('1000')));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §9.4 — EL CONTADOR 3/12 Y LAS FLECHAS
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.4 — contador y flechas', () {
    testWidgets('el contador cuenta COINCIDENCIAS, no mensajes', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        messages: _seisMensajes,
        resultado: _doceCoincidencias,
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'café');

      // 6 mensajes, 12 coincidencias. Un contador que contara mensajes diría «1/6».
      expect(find.text('1/12'), findsOneWidget);
    });

    testWidgets('las flechas llevan el contador hasta `3/12`', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        messages: _seisMensajes,
        resultado: _doceCoincidencias,
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'café');

      await tester.tap(find.byKey(ConversationSearchBar.previousKey));
      await tester.pumpAndSettle();
      expect(find.text('2/12'), findsOneWidget);

      await tester.tap(find.byKey(ConversationSearchBar.previousKey));
      await tester.pumpAndSettle();
      expect(find.text('3/12'), findsOneWidget);

      // Y vuelve. Sin esta mitad, una flecha que solo supiera avanzar pasaría igual.
      await tester.tap(find.byKey(ConversationSearchBar.nextKey));
      await tester.pumpAndSettle();
      expect(find.text('2/12'), findsOneWidget);
    });

    testWidgets('sin coincidencias el contador dice `0/0` y las flechas se apagan', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        messages: _seisMensajes,
        resultado: busquedaConCoincidencias(
          hits: <({String messageId, List<({int start, int end})> offsets})>[],
        ),
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'gazpacho');

      expect(find.text('0/0'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(ConversationSearchBar.previousKey))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(ConversationSearchBar.nextKey))
            .onPressed,
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §9.4 — SCROLL AUTOMÁTICO
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.4 — scroll automático', () {
    testWidgets('la flecha arrastra la conversación hasta la coincidencia', (
      WidgetTester tester,
    ) async {
      // 40 mensajes: la conversación se abre abajo (en el más reciente) y la única coincidencia
      // está en el más antiguo, que NO cabe en la pantalla. Sin scroll automático, saltar a ella
      // no enseña nada — que es justo el fallo que este test tiene que poder ver.
      final List<Map<String, dynamic>> largos = <Map<String, dynamic>>[
        mensajeJson(
          id: 'viejo',
          content: 'la aguja en el pajar',
          createdAt: DateTime.utc(2026, 8, 26, 9),
        ),
        for (int i = 1; i <= 40; i++)
          mensajeJson(
            id: 'm$i',
            content: 'relleno número $i',
            createdAt: DateTime.utc(2026, 8, 26, 10, i),
          ),
      ];

      await _pump(
        tester,
        messages: largos,
        resultado: busquedaConCoincidencias(
          searchedMessages: 41,
          hits: <({String messageId, List<({int start, int end})> offsets})>[
            (
              messageId: 'viejo',
              offsets: <({int start, int end})>[(start: 3, end: 8)],
            ),
          ],
        ),
      );

      await _abrirBusqueda(tester);
      expect(
        _visible(tester, 'la aguja en el pajar'),
        isFalse,
        reason: 'el fixture no sirve: la coincidencia ya se veía sin buscar',
      );

      await _buscar(tester, 'aguja');

      expect(
        _visible(tester, 'la aguja en el pajar'),
        isTrue,
        reason: '§9.4 pide «scroll automático al mensaje»',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §9.4 — RESALTADO DENTRO DE LA BURBUJA
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.4 — resaltado', () {
    testWidgets('el término va resaltado DENTRO de la burbuja', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', content: 'café con leche'),
        ],
        resultado: busquedaConCoincidencias(
          hits: <({String messageId, List<({int start, int end})> offsets})>[
            (messageId: 'm1', offsets: <({int start, int end})>[(start: 0, end: 4)]),
          ],
        ),
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'café');

      expect(_resaltados(tester), <String>['café']);

      // Y el mensaje sigue ENTERO: partirlo en tramos para resaltar uno no puede comerse el resto.
      // Se recogen los textos de la burbuja en vez de coger «el primero»: el primer `Text` de una
      // burbuja ajena es la inicial del avatar, no el mensaje.
      expect(find.byType(MessageBubble), findsOneWidget);
      final List<String> textosDeLaBurbuja = <String>[
        for (final Text t in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Text),
          ),
        ))
          t.data ?? t.textSpan?.toPlainText() ?? '',
      ];
      expect(textosDeLaBurbuja, contains('café con leche'));
    });

    testWidgets('los offsets se usan TAL CUAL, en unidades UTF-16 del original', (
      WidgetTester tester,
    ) async {
      // El backend manda los offsets del texto ORIGINAL en UTF-16. Recalcularlos aquí con otra
      // normalización los desplaza, que es el fallo que `_shared/text-search.ts` documenta: con un
      // emoji delante —2 unidades UTF-16, 1 punto de código— una implementación que contara puntos
      // de código resaltaría un carácter antes.
      await _pump(
        tester,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', content: '😀 café'),
        ],
        resultado: busquedaConCoincidencias(
          hits: <({String messageId, List<({int start, int end})> offsets})>[
            (messageId: 'm1', offsets: <({int start, int end})>[(start: 3, end: 7)]),
          ],
        ),
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'café');

      expect(_resaltados(tester), <String>['café']);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §9.4 — LO QUE EL BACKEND NO DEVUELVE, NO EXISTE
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.4 — no busca donde no debe', () {
    testWidgets('no encuentra en una LÁPIDA aunque el fixture le ponga texto', (
      WidgetTester tester,
    ) async {
      // FIXTURE HOSTIL, y tiene que serlo. El §9.4 dice «tampoco en lápidas», y el backend real
      // manda `content: null` en cuanto hay lápida — así que con `null` las dos implementaciones
      // posibles darían lo mismo y el test no distinguiría ninguna. Con texto dentro, una pantalla
      // que se buscara la vida con `findMatches` sobre las burbujas resaltaría un mensaje
      // eliminado. Es la lección de la Tarea 20.
      final FakeMessagingRepository repo = await _pump(
        tester,
        messages: <Map<String, dynamic>>[
          mensajeJson(
            id: 'lapida',
            content: 'café que nadie puede leer',
            deletedForAll: true,
          ),
          mensajeJson(id: 'vivo', content: 'café de verdad'),
        ],
        resultado: busquedaConCoincidencias(
          searchedMessages: 1,
          hits: <({String messageId, List<({int start, int end})> offsets})>[
            (messageId: 'vivo', offsets: <({int start, int end})>[(start: 0, end: 4)]),
          ],
        ),
      );
      await _abrirBusqueda(tester);
      await _buscar(tester, 'café');

      // La búsqueda se le PIDE al backend: es él quien conoce `deleted_for` y `cleared_at`.
      expect(repo.searches.single.query, 'café');
      expect(repo.searches.single.conversationId, 'c1');

      // Una sola coincidencia, la del mensaje vivo.
      expect(find.text('1/1'), findsOneWidget);
      expect(_resaltados(tester), <String>['café']);
      // Y el texto de la lápida ni se pinta ni se resalta.
      expect(find.text('café que nadie puede leer'), findsNothing);
    });

    testWidgets(
      'un mensaje visible que el backend NO devuelve no cuenta ni se resalta',
      (WidgetTester tester) async {
        // Cubre «ni borrados para mí ni anteriores a mi `cleared_at`»: las tres reglas viven en
        // `messaging-search`, y lo único que la pantalla puede hacer mal es fabricarse sus propias
        // coincidencias. El hilo lleva DOS mensajes con el término y el backend devuelve UNO.
        await _pump(
          tester,
          messages: <Map<String, dynamic>>[
            mensajeJson(id: 'excluido', content: 'café excluido'),
            mensajeJson(id: 'vivo', content: 'café incluido'),
          ],
          resultado: busquedaConCoincidencias(
            searchedMessages: 1,
            hits: <({String messageId, List<({int start, int end})> offsets})>[
              (
                messageId: 'vivo',
                offsets: <({int start, int end})>[(start: 0, end: 4)],
              ),
            ],
          ),
        );
        await _abrirBusqueda(tester);
        await _buscar(tester, 'café');

        expect(
          find.text('1/1'),
          findsOneWidget,
          reason: 'la pantalla se inventó coincidencias que el backend no dio',
        );
        expect(_resaltados(tester), <String>['café']);
        // El excluido sigue en pantalla —no se borra de la conversación— pero SIN resaltar.
        expect(find.text('café excluido'), findsOneWidget);
      },
    );
  });
}
