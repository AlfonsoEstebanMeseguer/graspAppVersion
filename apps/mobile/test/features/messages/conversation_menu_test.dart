import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_colors.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/social/messaging_repository.dart';
import 'package:grasp_mobile/features/messages/application/conversation_controller.dart';
import 'package:grasp_mobile/features/messages/presentation/chat_files_screen.dart';
import 'package:grasp_mobile/features/messages/presentation/conversation_screen.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/conversation_menu.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/request_actions_bar.dart';

import '../../support/fake_social_repositories.dart';

/// Tests del menú de tres puntos del §9.3 (Tarea 23).
///
/// Las siete entradas, su orden, el pánico separado y en rojo, y —lo que de verdad importa— que
/// **las tres sin efecto no afirmen tener uno** y que **el modal de bloqueo diga que no se puede
/// deshacer todavía** (decisión 6 del plan). Esa frase es lo único que le da a la persona la
/// información para decidir sobre algo irreversible.
const String _otro = '00000000-0000-4000-8000-000000000002';

ConversationArgs get _args => const ConversationArgs.existing(
  conversationId: 'c1',
  otherUserId: _otro,
  displayName: 'Ana',
);

typedef _Dobles = ({
  FakeMessagingRepository messaging,
  FakeModerationRepository moderation,
});

Future<_Dobles> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? input,
  List<Map<String, dynamic>> messages = const <Map<String, dynamic>>[],
  ConversationArgs? args,
  FakeMessagingRepository? repo,
  FakeModerationRepository? moderation,
}) async {
  final FakeMessagingRepository messaging = repo ?? FakeMessagingRepository();
  messaging.threadJson = threadPageJson(
    input: input ?? inputAccepted,
    messages: messages,
  );
  final FakeModerationRepository mod = moderation ?? FakeModerationRepository();

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        messagingRepositoryProvider.overrideWithValue(messaging),
        moderationRepositoryProvider.overrideWithValue(mod),
        avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
      ],
      child: MaterialApp(
        theme: theme,
        home: ConversationScreen(args: args ?? _args),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (messaging: messaging, moderation: mod);
}

Future<void> _abrirMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(ConversationScreen.menuKey));
  await tester.pumpAndSettle();
}

/// Todo el texto visible, mirado en el árbol ya construido.
///
/// Mismo barrido que el de `conversation_screen_test.dart`: un `find.text` solo vería los `Text`, y
/// aquí se comprueba que una afirmación falsa **no aparezca por ninguna vía**.
List<String> _todoElTexto(WidgetTester tester) {
  final List<String> out = <String>[];
  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.data != null) out.add(t.data!);
    final InlineSpan? span = t.textSpan;
    if (span != null) out.add(span.toPlainText());
  }
  for (final Semantics s in tester.widgetList<Semantics>(
    find.byType(Semantics),
  )) {
    final String? label = s.properties.label;
    if (label != null) out.add(label);
  }
  for (final Tooltip t in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
    if (t.message != null) out.add(t.message!);
  }
  return out;
}

/// Monta la pantalla con [input], abre el menú, apunta todo su texto y **vuelve a cerrarlo**.
///
/// El cierre es la parte que importa: `pumpWidget` no reinicia el `Navigator`, así que una hoja que
/// se deje abierta sobrevive al siguiente montaje y su scrim se traga el toque siguiente.
Future<List<String>> _textoDelMenu(
  WidgetTester tester,
  Map<String, dynamic> input,
) async {
  await _pump(tester, input: input);
  await _abrirMenu(tester);
  final List<String> texto = _todoElTexto(tester);

  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
  return texto;
}

/// La `y` del borde superior de una entrada del menú.
double _arribaDe(WidgetTester tester, Key k) => tester.getTopLeft(find.byKey(k)).dy;

double _abajoDe(WidgetTester tester, Key k) =>
    tester.getBottomLeft(find.byKey(k)).dy;

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // §9.3 — LAS SIETE ENTRADAS Y SU ORDEN
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.3 — las siete entradas', () {
    testWidgets('el botón de tres puntos abre el menú', (
      WidgetTester tester,
    ) async {
      await _pump(tester);

      // Antes de tocarlo no hay menú. Sin esta mitad, un menú pintado siempre pasaría igual.
      expect(find.byType(ConversationMenu), findsNothing);
      // Y el botón está CABLEADO: encontrarlo solo demuestra que se pinta; con `onPressed: null`
      // —que es como lo dejó la Tarea 22— seguiría encontrándose, apagado y mudo.
      expect(
        tester.widget<IconButton>(find.byKey(ConversationScreen.menuKey)).onPressed,
        isNotNull,
      );

      await _abrirMenu(tester);
      expect(find.byType(ConversationMenu), findsOneWidget);
    });

    testWidgets('están las SIETE, en el orden del §9.3', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await _abrirMenu(tester);

      // El orden del §9.3: campana, carpeta, lupa, papelera, bloqueo, megáfono, pánico.
      const List<Key> orden = <Key>[
        ConversationMenu.notificationsKey,
        ConversationMenu.filesKey,
        ConversationMenu.searchKey,
        ConversationMenu.deleteHistoryKey,
        ConversationMenu.blockKey,
        ConversationMenu.reportKey,
        ConversationMenu.panicKey,
      ];

      for (final Key k in orden) {
        expect(find.byKey(k), findsOneWidget, reason: 'falta la entrada $k');
      }

      // Se mide la POSICIÓN pintada, no el orden en el código: una `Column` reordenada por un
      // `Spacer` o un `Wrap` daría el mismo árbol y otro orden en pantalla.
      final List<double> alturas = <double>[
        for (final Key k in orden) _arribaDe(tester, k),
      ];
      for (int i = 1; i < alturas.length; i++) {
        expect(
          alturas[i],
          greaterThan(alturas[i - 1]),
          reason:
              'la entrada ${orden[i]} no va debajo de ${orden[i - 1]} (§9.3)',
        );
      }
    });

    testWidgets('el pánico va el ÚLTIMO y en rojo', (WidgetTester tester) async {
      await _pump(tester);
      await _abrirMenu(tester);

      final double panico = _arribaDe(tester, ConversationMenu.panicKey);
      for (final Key k in <Key>[
        ConversationMenu.notificationsKey,
        ConversationMenu.filesKey,
        ConversationMenu.searchKey,
        ConversationMenu.deleteHistoryKey,
        ConversationMenu.blockKey,
        ConversationMenu.reportKey,
      ]) {
        expect(_arribaDe(tester, k), lessThan(panico));
      }

      // «En rojo», dice el §9.3. Se mira el color con el que se pintó el texto de verdad.
      final Text etiqueta = tester.widget<Text>(
        find.descendant(
          of: find.byKey(ConversationMenu.panicKey),
          matching: find.text(ConversationMenu.panic),
        ),
      );
      expect(etiqueta.style?.color, AppColors.error);
    });

    testWidgets('el pánico está VISUALMENTE SEPARADO del resto', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await _abrirMenu(tester);

      // «Visualmente separado» se mide, no se declara: el hueco entre Reportar y Pánico tiene que
      // ser mayor que el que hay entre dos entradas corrientes. Sin esta comparación, un menú con
      // las siete pegadas y el pánico en rojo pasaría el resto de tests igual.
      final double huecoNormal =
          _arribaDe(tester, ConversationMenu.reportKey) -
          _abajoDe(tester, ConversationMenu.blockKey);
      final double huecoDelPanico =
          _arribaDe(tester, ConversationMenu.panicKey) -
          _abajoDe(tester, ConversationMenu.reportKey);

      expect(
        huecoDelPanico,
        greaterThan(huecoNormal),
        reason:
            'el §9.3 pide el pánico «visualmente separado»: hueco normal '
            '$huecoNormal, hueco del pánico $huecoDelPanico',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // LO QUE NO HACE NADA, NO PUEDE DECIR QUE LO HACE
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.3 — los tres sin efecto', () {
    testWidgets('el pánico abre su modal y NO toca ninguna repository', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester);
      await _abrirMenu(tester);

      await tester.tap(find.byKey(ConversationMenu.panicKey));
      await tester.pumpAndSettle();

      // El modal existe y dice la verdad ANTES de que nadie confirme nada.
      expect(find.text(ConversationMenu.panicUnavailable), findsOneWidget);

      await tester.tap(find.byKey(ConversationMenu.panicConfirmKey));
      await tester.pumpAndSettle();

      expect(d.messaging.conversationActions, isEmpty);
      expect(d.moderation.blocked, isEmpty);
      expect(d.moderation.reported, isEmpty);
      expect(d.messaging.sent, isEmpty);
    });

    testWidgets('el modal del pánico tiene UN SOLO botón, no dos', (
      WidgetTester tester,
    ) async {
      // Encontrado mirando la app, no con un test. Un modal que no hace nada no puede ofrecer
      // «Cancelar» y «Entendido»: dar a elegir entre dos botones afirma, **por la forma del
      // diálogo**, que uno de los dos hace algo — justo lo que el texto acaba de desmentir. Los
      // tests de arriba seguían verdes con los dos botones puestos: comprobaban el texto y que no
      // se llamara a ninguna repository, y las dos cosas eran ciertas igual.
      await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.panicKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ConversationMenu.panicConfirmKey), findsOneWidget);
      expect(find.byKey(ConversationMenu.cancelKey), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
    });

    testWidgets('los que SÍ hacen algo conservan su «Cancelar»', (
      WidgetTester tester,
    ) async {
      // La otra mitad: sin ella, quitar «Cancelar» de todos los modales pasaría el test de arriba
      // y dejaría el bloqueo irreversible sin salida.
      await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.blockKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ConversationMenu.cancelKey), findsOneWidget);
    });

    testWidgets('el pánico no afirma haber avisado a nadie', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.panicKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ConversationMenu.panicConfirmKey));
      await tester.pumpAndSettle();

      final String todo = _todoElTexto(tester).join('\n').toLowerCase();
      for (final String mentira in <String>[
        'hemos avisado',
        'aviso enviado',
        'se ha enviado',
        'alerta enviada',
        'ya está activo',
        'se ha activado',
      ]) {
        expect(todo, isNot(contains(mentira)), reason: 'el pánico afirma «$mentira»');
      }
    });

    testWidgets('la carpeta navega a los archivos, que están VACÍOS y lo dicen', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester);
      await _abrirMenu(tester);

      await tester.tap(find.byKey(ConversationMenu.filesKey));
      await tester.pumpAndSettle();

      expect(find.byType(ChatFilesScreen), findsOneWidget);
      expect(find.text(ChatFilesScreen.empty), findsOneWidget);
      // Y no ha tocado nada: es una pantalla vacía, no una que borre o mande algo.
      expect(d.messaging.conversationActions, isEmpty);
      expect(d.moderation.blocked, isEmpty);
    });

    testWidgets('los archivos no prometen archivos que no hay', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.filesKey));
      await tester.pumpAndSettle();

      final String todo = _todoElTexto(tester).join('\n').toLowerCase();
      expect(todo, contains('todavía'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §9.3 PUNTO 1 — LA CAMPANA PERSISTE SU VALOR
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.3 punto 1 — la campana', () {
    testWidgets('abre con el valor GUARDADO, no con el de por defecto', (
      WidgetTester tester,
    ) async {
      // Éste es el test que obliga a LEER. Sin lectura, la campana se abriría siempre en
      // «activadas» aunque se apagara ayer, y «persistir el valor» del §9.3 sería mentira. El
      // backend no devuelve este dato por ninguna Edge Function: se lee de `conversation_states`,
      // que sí concede `select` sobre esta columna.
      final FakeMessagingRepository repo = FakeMessagingRepository()
        ..notifications = false;
      await _pump(tester, repo: repo);
      await _abrirMenu(tester);

      expect(repo.notificationsReads, greaterThan(0));
      expect(
        tester.widget<Switch>(find.byKey(ConversationMenu.notificationsSwitchKey)).value,
        isFalse,
        reason: 'la campana ignoró el valor guardado',
      );
    });

    testWidgets('encendida se pinta encendida', (WidgetTester tester) async {
      // La otra mitad: sin ella, un `Switch` clavado en `false` pasaría el test de arriba.
      final FakeMessagingRepository repo = FakeMessagingRepository()
        ..notifications = true;
      await _pump(tester, repo: repo);
      await _abrirMenu(tester);

      expect(
        tester.widget<Switch>(find.byKey(ConversationMenu.notificationsSwitchKey)).value,
        isTrue,
      );
    });

    testWidgets('apagarla PERSISTE el booleano, no una acción muda', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester);
      await _abrirMenu(tester);

      await tester.tap(find.byKey(ConversationMenu.notificationsSwitchKey));
      await tester.pumpAndSettle();

      final ({
        ConversationAction action,
        String conversationId,
        bool? notificationsEnabled,
      })
      llamada = d.messaging.conversationActions.single;

      expect(llamada.action, ConversationAction.setNotifications);
      expect(llamada.conversationId, 'c1');
      // `messaging-actions` devuelve 400 si llega sin booleano en vez de asumir un valor por
      // defecto: mandarlo a nulo sería un 400 garantizado.
      expect(llamada.notificationsEnabled, isFalse);
    });

    testWidgets('el valor sobrevive a cerrar y volver a abrir el menú', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await _abrirMenu(tester);

      await tester.tap(find.byKey(ConversationMenu.notificationsSwitchKey));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(find.byKey(ConversationMenu.notificationsSwitchKey)).value,
        isFalse,
        reason: 'el toggle ni siquiera se movió al tocarlo',
      );

      // Cerrar el menú y volver a abrirlo: el doble persiste como el backend, así que lo que se
      // vea aquí es lo que se guardó.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await _abrirMenu(tester);

      expect(
        tester.widget<Switch>(find.byKey(ConversationMenu.notificationsSwitchKey)).value,
        isFalse,
      );
    });

    testWidgets('la campana dice que las push todavía no existen', (
      WidgetTester tester,
    ) async {
      // §9.3 punto 1 es «sin efecto funcional». Un toggle que se pudiera encender sin decirlo
      // prometería avisos que nunca llegan, que es la misma mentira que el plan prohíbe en el
      // pánico y en los archivos — solo que aquí el botón sí guarda algo.
      await _pump(tester);
      await _abrirMenu(tester);
      expect(find.text(ConversationMenu.notificationsUnavailable), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-27 — ELIMINAR HISTORIAL
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-27 — eliminar historial', () {
    testWidgets('pide confirmación y solo entonces llama a `delete_history`', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester);
      await _abrirMenu(tester);

      await tester.tap(find.byKey(ConversationMenu.deleteHistoryKey));
      await tester.pumpAndSettle();
      // Con el modal abierto todavía NO se ha llamado a nada: si se llamara al tocar la entrada,
      // el modal sería decorativo.
      expect(d.messaging.conversationActions, isEmpty);

      await tester.tap(find.byKey(ConversationMenu.deleteHistoryConfirmKey));
      await tester.pumpAndSettle();

      expect(
        d.messaging.conversationActions.single.action,
        ConversationAction.deleteHistory,
      );
    });

    testWidgets('cancelar NO borra nada', (WidgetTester tester) async {
      final _Dobles d = await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.deleteHistoryKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ConversationMenu.cancelKey));
      await tester.pumpAndSettle();

      expect(d.messaging.conversationActions, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // DECISIÓN 6 — BLOQUEO Y REPORTE
  // ══════════════════════════════════════════════════════════════════════════
  group('decisión 6 — bloqueo', () {
    testWidgets('el modal dice DÓNDE SE DESHACE el bloqueo', (
      WidgetTester tester,
    ) async {
      // Es lo único que le da a la persona la información para decidir, y por eso se comprueba por
      // TEXTO y no por «se llamó a block-create»: llamar a la función no prueba nada sobre lo único
      // que le importa a quien está a punto de pulsar.
      await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.blockKey));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Perfil → Privacidad → Usuarios bloqueados'),
        findsOneWidget,
        reason: 'ADR 0027: el modal está OBLIGADO a decir dónde se deshace',
      );
    });

    testWidgets('confirmar bloquea de verdad y sale de la conversación (RN-22)', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.blockKey));
      await tester.pumpAndSettle();

      expect(d.moderation.blocked, isEmpty, reason: 'ha bloqueado sin confirmar');

      await tester.tap(find.byKey(ConversationMenu.blockConfirmKey));
      await tester.pumpAndSettle();

      expect(d.moderation.blocked, <String>[_otro]);
      // `RN-22` archiva la conversación del lado del bloqueador: quedarse dentro de un hilo que
      // acaba de salir de la bandeja enseñaría algo que ya no está.
      expect(find.byType(ConversationScreen), findsNothing);
    });

    testWidgets('cancelar NO bloquea', (WidgetTester tester) async {
      final _Dobles d = await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.blockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ConversationMenu.cancelKey));
      await tester.pumpAndSettle();

      expect(d.moderation.blocked, isEmpty);
      expect(find.byType(ConversationScreen), findsOneWidget);
    });

    testWidgets('el modal no ofrece desbloquear AHÍ MISMO: solo apunta a la pantalla', (
      WidgetTester tester,
    ) async {
      // Desde el ADR 0027 el desbloqueo existe de verdad, así que el modal SÍ promete poder
      // deshacerlo — lo que no hace es ofrecer un atajo para hacerlo desde aquí: eso vive en
      // `BlockedUsersScreen`, con su propia confirmación (ADR 0027, punto 3).
      await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.blockKey));
      await tester.pumpAndSettle();

      // Los dos botones del modal siguen siendo Cancelar y Bloquear.
      expect(find.widgetWithText(FilledButton, 'Desbloquear'), findsNothing);
      expect(find.byKey(ConversationMenu.cancelKey), findsOneWidget);
      expect(find.byKey(ConversationMenu.blockConfirmKey), findsOneWidget);
    });
  });

  group('RN-25 — reporte', () {
    testWidgets('reporta CON la conversación y bloquea (RN-25)', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester);
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.reportKey));
      await tester.pumpAndSettle();

      expect(d.moderation.reported, isEmpty, reason: 'ha reportado sin confirmar');

      await tester.tap(find.byKey(ConversationMenu.reportConfirmKey));
      await tester.pumpAndSettle();

      expect(d.moderation.reported.single.userId, _otro);
      // El enlace de contexto que un humano de la cola de moderación abriría. Sin él, el reporte
      // llega sin nada que leer.
      expect(d.moderation.reported.single.conversationId, 'c1');
    });

    testWidgets('sin conversación todavía (RN-39) reporta SIN colgar un id', (
      WidgetTester tester,
    ) async {
      // Desde Conectar se puede reportar antes de escribir nada. `report-create` devuelve 404 si
      // el `conversation_id` no es de quien reporta, así que inventarse uno sería un 404 seguro.
      final _Dobles d = await _pump(
        tester,
        args: const ConversationArgs.fresh(
          otherUserId: _otro,
          displayName: 'Ana',
        ),
      );
      await _abrirMenu(tester);
      await tester.tap(find.byKey(ConversationMenu.reportKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ConversationMenu.reportConfirmKey));
      await tester.pumpAndSettle();

      expect(d.moderation.reported.single.conversationId, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-04 — LAS DOS ACCIONES QUE LA TAREA 22 DEJÓ APAGADAS
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-04 — bloquear y reportar desde una solicitud', () {
    testWidgets('las cuatro acciones están CABLEADAS', (
      WidgetTester tester,
    ) async {
      await _pump(tester, input: inputSolicitudRecibida);

      for (final Key k in <Key>[
        RequestActionsBar.acceptKey,
        RequestActionsBar.ignoreKey,
        RequestActionsBar.blockKey,
        RequestActionsBar.reportKey,
      ]) {
        expect(
          tester.widget<ButtonStyleButton>(find.byKey(k)).onPressed,
          isNotNull,
          reason: '$k sigue apagado',
        );
      }
    });

    testWidgets('Bloquear desde la solicitud pasa por el MISMO modal', (
      WidgetTester tester,
    ) async {
      // El mismo, no uno parecido: un segundo modal es un segundo sitio donde olvidar dónde se
      // deshace.
      final _Dobles d = await _pump(tester, input: inputSolicitudRecibida);

      await tester.tap(find.byKey(RequestActionsBar.blockKey));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Perfil → Privacidad → Usuarios bloqueados'),
        findsOneWidget,
      );
      expect(d.moderation.blocked, isEmpty);

      await tester.tap(find.byKey(ConversationMenu.blockConfirmKey));
      await tester.pumpAndSettle();
      expect(d.moderation.blocked, <String>[_otro]);
    });

    testWidgets('Reportar desde la solicitud persiste el reporte', (
      WidgetTester tester,
    ) async {
      final _Dobles d = await _pump(tester, input: inputSolicitudRecibida);

      await tester.tap(find.byKey(RequestActionsBar.reportKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ConversationMenu.reportConfirmKey));
      await tester.pumpAndSettle();

      expect(d.moderation.reported.single.userId, _otro);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-23 — EL MENÚ NO PUEDE DELATAR UN BLOQUEO AJENO
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-23 — el menú no revela nada', () {
    testWidgets('el menú del bloqueado es EL MISMO que el del cupo agotado', (
      WidgetTester tester,
    ) async {
      // El menú se pinta en los cinco estados del §9.2. Si alguna entrada cambiara de forma con el
      // bloqueo —una menos, una apagada, un texto distinto— sería un oráculo tan bueno como el que
      // el ADR 0022 cerró en el input.
      // OJO al cierre de la hoja entre las dos mitades: `pumpWidget` **no** reinicia el
      // `Navigator`, así que sin él la primera hoja sigue puesta, su scrim se come el toque de la
      // segunda y el test comparaba un menú abierto contra una pantalla sin menú. Falla por el
      // motivo equivocado y parece un hallazgo de `RN-23` cuando no lo es.
      final List<String> textoCupo = await _textoDelMenu(tester, inputCupoAgotado);
      final List<String> textoBloqueo = await _textoDelMenu(
        tester,
        inputBloqueadoHostil,
      );

      expect(textoBloqueo, equals(textoCupo));
      // Y la mitad que impide que el test se vuelva trivial: el menú se pintó de verdad en las
      // dos. Dos listas vacías también serían iguales.
      expect(textoCupo, contains(ConversationMenu.block));
    });
  });
}
