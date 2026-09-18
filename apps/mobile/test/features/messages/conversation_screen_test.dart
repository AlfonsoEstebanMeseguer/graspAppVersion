import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_colors.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/social/message.dart';
import 'package:grasp_mobile/domain/social/message_input_state.dart';
import 'package:grasp_mobile/domain/social/messaging_repository.dart';
import 'package:grasp_mobile/features/messages/application/conversation_controller.dart';
import 'package:grasp_mobile/features/messages/presentation/conversation_screen.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/activity_dot.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/message_bubble.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/message_composer.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/request_actions_bar.dart';

import '../../support/fake_social_repositories.dart';

const String _otro = '00000000-0000-4000-8000-000000000002';

ConversationArgs get _args => const ConversationArgs.existing(
  conversationId: 'c1',
  otherUserId: _otro,
  displayName: 'Ana',
);

Future<FakeMessagingRepository> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> input,
  List<Map<String, dynamic>> messages = const <Map<String, dynamic>>[],
  ConversationArgs? args,
  FakeMessagingRepository? repo,
  bool? isActive,
  int unreadCount = 0,
}) async {
  final FakeMessagingRepository messaging = repo ?? FakeMessagingRepository();
  messaging.threadJson = threadPageJson(
    input: input,
    messages: messages,
    isActive: isActive,
    unreadCount: unreadCount,
  );

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        messagingRepositoryProvider.overrideWithValue(messaging),
        avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
      ],
      child: MaterialApp(
        theme: theme,
        home: ConversationScreen(args: args ?? _args),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return messaging;
}

/// Escribe en el campo **y pinta un fotograma**.
///
/// El `pump` no es adorno: `enterText` no reconstruye el árbol, así que sin él el botón de enviar
/// sigue con el `onPressed: null` que tenía cuando el campo estaba vacío y el toque no llega a
/// ninguna parte. En la app real ese fotograma lo pinta el propio teclado.
Future<void> _escribir(WidgetTester tester, String texto) async {
  await tester.enterText(find.byKey(MessageComposer.fieldKey), texto);
  await tester.pump();
}

/// **Todo** el texto que la pantalla enseña, mirado en el árbol ya construido.
///
/// Recoge de los cinco sitios por los que una palabra puede llegar a un ojo o a un lector de
/// pantalla: `Text`, el texto editable, las etiquetas de `Semantics`, los `Tooltip` y la decoración
/// de los campos. Un `find.text('bloqueado')` solo mira el primero, y `RN-23` dice **«en ninguna
/// parte»**.
List<String> _todoElTexto(WidgetTester tester) {
  final List<String> out = <String>[];

  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.data != null) out.add(t.data!);
    final InlineSpan? span = t.textSpan;
    if (span != null) out.add(span.toPlainText());
  }
  for (final EditableText e in tester.widgetList<EditableText>(
    find.byType(EditableText),
  )) {
    out.add(e.controller.text);
  }
  for (final Semantics s in tester.widgetList<Semantics>(
    find.byType(Semantics),
  )) {
    final String? label = s.properties.label;
    if (label != null) out.add(label);
    final String? hint = s.properties.hint;
    if (hint != null) out.add(hint);
  }
  for (final Tooltip t in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
    if (t.message != null) out.add(t.message!);
  }
  for (final TextField f in tester.widgetList<TextField>(
    find.byType(TextField),
  )) {
    final InputDecoration? d = f.decoration;
    if (d == null) continue;
    for (final String? s in <String?>[
      d.hintText,
      d.labelText,
      d.helperText,
      d.errorText,
      d.counterText,
      d.prefixText,
      d.suffixText,
    ]) {
      if (s != null) out.add(s);
    }
  }

  return out;
}

/// Los iconos pintados, en orden. `RN-23` prohíbe que el bloqueo tenga uno propio.
List<IconData> _iconos(WidgetTester tester) => tester
    .widgetList<Icon>(find.byType(Icon))
    .map((Icon i) => i.icon)
    .whereType<IconData>()
    .toList(growable: false);

/// El `TextStyle` con el que se pintó un texto concreto.
TextStyle _estiloDe(WidgetTester tester, String texto) {
  final Text widget = tester.widget<Text>(find.text(texto));
  final TextStyle? propio = widget.style;
  return propio ?? const TextStyle();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // §9.2 — UN TEST POR CADA FILA
  // ══════════════════════════════════════════════════════════════════════════
  group('§9.2 — estados del input', () {
    testWidgets('fila 1: conversación aceptada → input ACTIVO y sin aviso', (
      WidgetTester tester,
    ) async {
      await _pump(tester, input: inputAccepted);

      final TextField campo = tester.widget<TextField>(
        find.byKey(MessageComposer.fieldKey),
      );
      expect(campo.enabled, isTrue);
      expect(find.byKey(MessageComposer.noticeKey), findsNothing);
      expect(find.byType(RequestActionsBar), findsNothing);
      // Sin tope no hay nada que contar: el contador de RN-26 aparece por longitud, no por estado.
      expect(find.byKey(MessageComposer.counterKey), findsNothing);
    });

    testWidgets(
      'fila 2: solicitud enviada CON restantes → input ACTIVO (RN-01)',
      (WidgetTester tester) async {
        await _pump(tester, input: inputConRestantes(3));

        final TextField campo = tester.widget<TextField>(
          find.byKey(MessageComposer.fieldKey),
        );
        expect(campo.enabled, isTrue);
        expect(find.byKey(MessageComposer.noticeKey), findsNothing);
        expect(find.byType(RequestActionsBar), findsNothing);
      },
    );

    testWidgets(
      'fila 2: con 5 de 5 el input sigue activo — la enmienda nº 2 manda',
      (WidgetTester tester) async {
        // La spec ORIGINAL deshabilitaba tras el PRIMER mensaje. Gana `RN-01`: son 5. Si alguien
        // reinstaura la regla vieja, esto se pone rojo.
        await _pump(tester, input: inputConRestantes(4));
        expect(
          tester
              .widget<TextField>(find.byKey(MessageComposer.fieldKey))
              .enabled,
          isTrue,
        );
      },
    );

    testWidgets(
      'fila 3: los 5 gastados → DESHABILITADO con el texto del ADR 0022',
      (WidgetTester tester) async {
        await _pump(tester, input: inputCupoAgotado);

        expect(find.text(kMessageInputNotice), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(MessageComposer.fieldKey))
              .enabled,
          isFalse,
        );
        // El botón de enviar no puede quedar vivo junto a un campo muerto.
        expect(
          tester
              .widget<IconButton>(find.byKey(MessageComposer.sendKey))
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'fila 4: solicitud recibida → las CUATRO acciones de RN-04, sin campo de texto',
      (WidgetTester tester) async {
        await _pump(tester, input: inputSolicitudRecibida);

        expect(find.byType(RequestActionsBar), findsOneWidget);
        for (final Key k in <Key>[
          RequestActionsBar.acceptKey,
          RequestActionsBar.ignoreKey,
          RequestActionsBar.blockKey,
          RequestActionsBar.reportKey,
        ]) {
          expect(find.byKey(k), findsOneWidget, reason: 'falta $k');
        }

        // Y las dos que esta tarea implementa están CABLEADAS. Buscar la tecla solo demuestra que
        // el botón se pinta: con `onPressed: null` seguiría encontrándose, apagado y mudo.
        expect(
          tester
              .widget<ButtonStyleButton>(find.byKey(RequestActionsBar.acceptKey))
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<ButtonStyleButton>(find.byKey(RequestActionsBar.ignoreKey))
              .onPressed,
          isNotNull,
        );

        // Bloquear y Reportar estuvieron APAGADOS a propósito toda la Tarea 22: los dos son
        // acciones fuertes y su modal —el de bloqueo está obligado a decir dónde se deshace (ADR
        // 0027)— no existía. La Tarea 23 montó ese modal, así que ahora están cableados; que la
        // frase obligatoria esté de verdad en él lo comprueban, por texto,
        // `conversation_menu_test.dart` («el modal dice DÓNDE SE DESHACE el bloqueo») y
        // («Bloquear desde la solicitud pasa por el MISMO modal»).
        expect(
          tester
              .widget<ButtonStyleButton>(find.byKey(RequestActionsBar.blockKey))
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<ButtonStyleButton>(find.byKey(RequestActionsBar.reportKey))
              .onPressed,
          isNotNull,
        );
        // «Sustituido por», dice el §9.2: el campo no está atenuado, NO ESTÁ.
        expect(find.byKey(MessageComposer.fieldKey), findsNothing);
        expect(find.byKey(MessageComposer.noticeKey), findsNothing);
      },
    );

    testWidgets(
      'fila 5: bloqueado → ni la palabra «bloque» ni un icono propio (RN-23)',
      (WidgetTester tester) async {
        // FIXTURE HOSTIL: el cuerpo del cupo agotado MÁS los tres campos que delatarían el
        // bloqueo. El backend de hoy no los manda; si alguien los reintroduce y la pantalla los
        // lee, este test cae. Comparar dos copias del mismo cuerpo limpio no probaría nada.
        await _pump(tester, input: inputBloqueadoHostil);

        final List<String> textos = _todoElTexto(tester);
        for (final String t in textos) {
          expect(
            t.toLowerCase(),
            isNot(contains('bloque')),
            reason: 'la pantalla enseña «$t»',
          );
        }
        // Los motivos del fixture hostil tampoco pueden aparecer por otra vía.
        expect(textos.join('\n'), isNot(contains('blocked_by_recipient')));
        expect(textos.join('\n'), isNot(contains('te ha bloqueado')));

        // Y el texto que sí se ve es EL MISMO que el del cupo agotado.
        expect(find.text(kMessageInputNotice), findsOneWidget);
      },
    );

    testWidgets(
      'filas 3 y 5: el árbol pintado es IDÉNTICO, texto e iconos (RN-23)',
      (WidgetTester tester) async {
        await _pump(tester, input: inputCupoAgotado);
        final List<String> textoCupo = _todoElTexto(tester);
        final List<IconData> iconosCupo = _iconos(tester);

        await _pump(tester, input: inputBloqueadoHostil);

        expect(_todoElTexto(tester), equals(textoCupo));
        expect(_iconos(tester), equals(iconosCupo));
      },
    );

    testWidgets('el estado inerte no usa ningún icono de prohibición', (
      WidgetTester tester,
    ) async {
      // Lo anterior compara los dos casos entre sí; esto mira el icono ELEGIDO. Sin esto, cambiar
      // el icono del estado inerte a `Icons.block` para los DOS casos pasaría desapercibido: los
      // dos árboles seguirían siendo idénticos.
      await _pump(tester, input: inputCupoAgotado);
      expect(
        _iconos(tester),
        isNot(
          anyElement(
            isIn(<IconData>[
              Icons.block,
              Icons.block_flipped,
              Icons.do_not_disturb,
              Icons.do_not_disturb_alt,
              Icons.do_not_disturb_on,
              Icons.report,
              Icons.report_gmailerrorred,
              Icons.person_off,
            ]),
          ),
        ),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-26 — EL CONTADOR
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-26 — contador de caracteres', () {
    testWidgets('a 899 NO hay contador; a 900 SÍ', (WidgetTester tester) async {
      await _pump(tester, input: inputAccepted);

      await _escribir(tester, 'a' * 899);
      expect(
        find.byKey(MessageComposer.counterKey),
        findsNothing,
        reason: 'RN-26: «visible solo a partir de los 900»',
      );

      await _escribir(tester, 'a' * 900);
      expect(find.byKey(MessageComposer.counterKey), findsOneWidget);
      expect(find.text('900/1000'), findsOneWidget);
    });

    testWidgets('a 1000 no se puede seguir escribiendo, y no se trunca calladamente', (
      WidgetTester tester,
    ) async {
      await _pump(tester, input: inputAccepted);

      final String mil = 'a' * 1000;
      await _escribir(tester, mil);
      expect(find.text('1000/1000'), findsOneWidget);

      // Intentar pasarse deja el texto EXACTAMENTE como estaba: no se acepta y luego se recorta a
      // escondidas, se impide entrar.
      await _escribir(tester, '$mil bcde');
      final EditableText campo = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(campo.controller.text.runes.length, 1000);
      expect(campo.controller.text, mil);
      // El contador sigue a la vista en el tope: un límite mudo es justo lo que RN-21 prohíbe.
      expect(find.text('1000/1000'), findsOneWidget);
    });

    testWidgets('cuenta PUNTOS DE CÓDIGO, como `char_length` en Postgres', (
      WidgetTester tester,
    ) async {
      // 450 emojis + 450 letras = 900 puntos de código, pero 1350 unidades UTF-16. Contar con
      // `String.length` diría 1350 y taparía el contador a destiempo — y, peor, cortaría mensajes
      // que la base acepta. Es la misma cuenta que `normalizeMessageContent`.
      await _pump(tester, input: inputAccepted);
      await _escribir(tester, '${'😀' * 450}${'a' * 450}');
      expect(find.text('900/1000'), findsOneWidget);
    });

    testWidgets('el tope son 1000 puntos de código, no 1000 unidades UTF-16', (
      WidgetTester tester,
    ) async {
      // 600 emojis = 600 puntos de código = 1200 UTF-16. Un limitador que contara UTF-16 habría
      // cortado en 500. Cabe entero.
      await _pump(tester, input: inputAccepted);
      await _escribir(tester, '😀' * 600);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .text
            .runes
            .length,
        600,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-33 — EMOJIS DEL TECLADO DEL SISTEMA, SIN SELECTOR PROPIO
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-33 — emojis', () {
    testWidgets('un emoji tecleado se pinta en la burbuja', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
      );

      await _escribir(tester, 'Gracias 🌈💜');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(repo.sent.single.content, 'Gracias 🌈💜');
      expect(find.text('Gracias 🌈💜'), findsOneWidget);
    });

    testWidgets('no hay NINGÚN botón selector de emojis (enmienda nº 10)', (
      WidgetTester tester,
    ) async {
      await _pump(tester, input: inputAccepted);
      expect(
        _iconos(tester),
        isNot(
          anyElement(
            isIn(<IconData>[
              Icons.emoji_emotions,
              Icons.emoji_emotions_outlined,
              Icons.sentiment_satisfied,
              Icons.sentiment_satisfied_alt,
              Icons.mood,
              Icons.tag_faces,
              Icons.insert_emoticon,
            ]),
          ),
        ),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RN-28 — BORRAR, EDITAR, RESPONDER
  // ══════════════════════════════════════════════════════════════════════════
  group('RN-28 — acciones sobre un mensaje', () {
    testWidgets('la lápida va en cursiva y en OTRO color', (
      WidgetTester tester,
    ) async {
      // FIXTURE HOSTIL: `content` con texto DE VERDAD junto a la lápida. El backend manda
      // `content: null` en cuanto hay lápida, así que con `null` las dos implementaciones —fiarse
      // de la bandera o fiarse del contenido— darían lo mismo y el test no distinguiría ninguna.
      // Es la lección de la Tarea 20.
      await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(
            id: 'm1',
            fromMe: true,
            content: 'el secreto que no se puede leer',
            deletedForAll: true,
          ),
        ],
      );

      expect(find.text('el secreto que no se puede leer'), findsNothing);
      expect(find.text(MessageBubble.tombstone), findsOneWidget);

      final TextStyle estilo = _estiloDe(tester, MessageBubble.tombstone);
      expect(estilo.fontStyle, FontStyle.italic);
      expect(estilo.color, isNotNull);
      expect(
        estilo.color,
        isNot(AppColors.textPrimary),
        reason: 'RN-28 pide «un color de fuente diferente»',
      );
    });

    testWidgets('«editado» se ve, y en un mensaje del OTRO también', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: false, content: 'Corregido', edited: true),
        ],
      );
      expect(find.text(MessageBubble.editedTag), findsOneWidget);
    });

    testWidgets('sin editar NO aparece el tag', (WidgetTester tester) async {
      await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', content: 'Intacto'),
        ],
      );
      expect(find.text(MessageBubble.editedTag), findsNothing);
    });

    testWidgets('responder pinta la cita del mensaje citado', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(
            id: 'm2',
            fromMe: true,
            content: 'Claro que sí',
            replyTo: <String, dynamic>{
              'id': 'm1',
              'from_me': false,
              'content': 'Lo que dijo ella',
            },
          ),
        ],
      );

      expect(find.text('Claro que sí'), findsOneWidget);
      expect(find.text('Lo que dijo ella'), findsOneWidget);
    });

    testWidgets('una cita que no se puede ver conserva el hilo y lo dice', (
      WidgetTester tester,
    ) async {
      // `content: null` = borrado «para mí», anterior a mi `cleared_at`, o lápida. La burbuja lo
      // dice en vez de omitir la cita y romper el hilo.
      await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(
            id: 'm2',
            content: 'Respondo',
            replyTo: <String, dynamic>{
              'id': 'm1',
              'from_me': true,
              'content': null,
            },
          ),
        ],
      );
      expect(find.text(MessageBubble.quoteUnavailable), findsOneWidget);
    });

    testWidgets('borrar para mí llama a `delete_for_me` y lo quita de MI lado', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: true, content: 'Se va'),
        ],
      );

      // Al volver a pedir el hilo, el backend ya no lo proyecta.
      repo.threadJson = threadPageJson(input: inputAccepted);

      await tester.longPress(find.text('Se va'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MessageBubble.deleteForMeKey));
      await tester.pumpAndSettle();

      expect(repo.messageActions.single.action, MessageAction.deleteForMe);
      expect(repo.messageActions.single.messageId, 'm1');
      expect(find.text('Se va'), findsNothing);
    });

    testWidgets('borrar para todos llama a `delete_for_all`', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: true, content: 'Para todos'),
        ],
      );

      repo.threadJson = threadPageJson(
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: true, content: null, deletedForAll: true),
        ],
      );

      await tester.longPress(find.text('Para todos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MessageBubble.deleteForAllKey));
      await tester.pumpAndSettle();

      expect(repo.messageActions.single.action, MessageAction.deleteForAll);
      expect(find.text(MessageBubble.tombstone), findsOneWidget);
    });

    testWidgets('un mensaje del OTRO solo ofrece «borrar para mí»', (
      WidgetTester tester,
    ) async {
      // `delete_for_all` y `edit` son **solo del autor** (`messaging_repository.dart`). Ofrecerlos
      // sobre un mensaje ajeno sería un botón que el backend rechaza siempre.
      await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: false, content: 'De ella'),
        ],
      );

      await tester.longPress(find.text('De ella'));
      await tester.pumpAndSettle();

      expect(find.byKey(MessageBubble.deleteForMeKey), findsOneWidget);
      expect(find.byKey(MessageBubble.deleteForAllKey), findsNothing);
      expect(find.byKey(MessageBubble.editKey), findsNothing);
    });

    testWidgets('editar manda el texto nuevo por `edit`, no un mensaje nuevo', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: true, content: 'Con erratas'),
        ],
      );

      repo.threadJson = threadPageJson(
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: true, content: 'Sin erratas', edited: true),
        ],
      );

      await tester.longPress(find.text('Con erratas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MessageBubble.editKey));
      await tester.pumpAndSettle();

      // El texto viejo entra en el campo para no obligar a reescribirlo.
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Con erratas',
      );

      await _escribir(tester, 'Sin erratas');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(repo.messageActions.single.action, MessageAction.edit);
      expect(repo.messageActions.single.content, 'Sin erratas');
      expect(
        repo.sent,
        isEmpty,
        reason: 'editar NO puede crear un mensaje nuevo',
      );
      expect(find.text(MessageBubble.editedTag), findsOneWidget);
    });

    testWidgets('responder manda `reply_to_id` y enseña la cita mientras se escribe', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: false, content: 'La pregunta'),
        ],
      );

      await tester.longPress(find.text('La pregunta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MessageBubble.replyKey));
      await tester.pumpAndSettle();

      expect(find.byKey(MessageComposer.replyPreviewKey), findsOneWidget);

      await _escribir(tester, 'La respuesta');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(repo.sent.single.replyToId, 'm1');
      // Y la cita se recoge: dejarla puesta encadenaría el siguiente mensaje a la misma.
      expect(find.byKey(MessageComposer.replyPreviewKey), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ENVÍO, TIEMPO REAL Y RN-04
  // ══════════════════════════════════════════════════════════════════════════
  group('envío', () {
    testWidgets('la clave de idempotencia se CONSERVA durante los reintentos', (
      WidgetTester tester,
    ) async {
      // Generarla de nuevo en cada intento es exactamente lo mismo que no tenerla: el reintento
      // del quinto mensaje se evaluaría como el sexto (invariante de CLAUDE.md).
      final FakeMessagingRepository repo = FakeMessagingRepository();
      repo.sendFailsWith = Exception('la red');
      await _pump(tester, input: inputAccepted, repo: repo);

      await _escribir(tester, 'Hola');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      // El texto se conserva para poder reintentar; si se hubiera perdido, no habría reintento.
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Hola',
      );

      // El aviso del fallo tapa el botón de enviar mientras dura, así que se deja pasar antes de
      // reintentar; en la app es lo mismo que esperar cuatro segundos.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      repo.sendFailsWith = null;
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(repo.sent.length, 2);
      expect(repo.sent[0].idempotencyKey, repo.sent[1].idempotencyKey);
    });

    testWidgets('dos mensajes distintos llevan claves DISTINTAS', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
      );

      await _escribir(tester, 'Uno');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();
      await _escribir(tester, 'Dos');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(repo.sent[0].idempotencyKey, isNot(repo.sent[1].idempotencyKey));
    });

    testWidgets('RN-01: al gastar el quinto, el input queda inerte sin salir', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = FakeMessagingRepository()
        ..messagesLeftAfterSend = 0;
      await _pump(tester, input: inputConRestantes(1), repo: repo);

      await _escribir(tester, 'El quinto');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(find.text(kMessageInputNotice), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(MessageComposer.fieldKey)).enabled,
        isFalse,
      );
    });

    testWidgets('el veredicto del envío manda aunque el hilo no se pueda releer', (
      WidgetTester tester,
    ) async {
      // Tras enviar se vuelve a pedir el hilo, y ese refresco **se traga sus errores** para no
      // tirar una conversación ya pintada. Si el cierre del input dependiera solo de ese refresco,
      // una red que falla justo ahí dejaría el campo vivo con el cupo agotado: la persona escribe,
      // envía, y se come un 422 que no puede entender. Lo cierra el veredicto que vino CON el
      // envío, que es de la misma función que lo decidió (`evaluateSendLimits`).
      final FakeMessagingRepository repo = FakeMessagingRepository()
        ..messagesLeftAfterSend = 0;
      await _pump(tester, input: inputConRestantes(1), repo: repo);

      repo.threadFailsWith = Exception('la red se cae justo ahora');
      await _escribir(tester, 'El quinto');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(find.text(kMessageInputNotice), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(MessageComposer.fieldKey)).enabled,
        isFalse,
      );
    });

    testWidgets('un campo vacío o solo con espacios no envía nada', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
      );

      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();
      await _escribir(tester, '    ');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(repo.sent, isEmpty);
    });

    testWidgets('desde Conectar (RN-39) se abre SIN conversación y con 5 (RN-01)', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
        args: const ConversationArgs.fresh(
          otherUserId: _otro,
          displayName: 'Ana',
        ),
      );

      // Sin `conversation_id` no hay hilo que pedir: pedirlo sería un 400 garantizado.
      expect(repo.threadCalls, 0);
      expect(find.text('Ana'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byKey(MessageComposer.fieldKey)).enabled,
        isTrue,
      );

      await _escribir(tester, 'Hola');
      await tester.tap(find.byKey(MessageComposer.sendKey));
      await tester.pumpAndSettle();

      expect(repo.sent.single.recipientId, _otro);
    });
  });

  group('tiempo real', () {
    testWidgets('una fila nueva en el stream refresca el hilo PROYECTADO', (
      WidgetTester tester,
    ) async {
      // El stream llega CRUDO: no aplica `cleared_at` (RN-27) porque vive en `conversation_states`
      // y no viaja con la fila. Sirve para saber que hay algo nuevo; la verdad la da `thread()`.
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[mensajeJson(id: 'm1', content: 'Uno')],
      );
      expect(repo.threadCalls, 1);

      repo.threadJson = threadPageJson(
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', content: 'Uno'),
          mensajeJson(id: 'm2', content: 'Dos'),
        ],
      );
      repo.realtime.add(<Message>[
        Message(
          id: 'm2',
          fromMe: false,
          content: 'Dos',
          deletedForAll: false,
          edited: false,
          createdAt: DateTime(2026, 8, 26, 11),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(repo.threadCalls, 2);
      expect(find.text('Dos'), findsOneWidget);
    });

    testWidgets('el stream NO pinta sus filas crudas por su cuenta', (
      WidgetTester tester,
    ) async {
      // Si la pantalla pintara lo que llega por el stream, un mensaje anterior al `cleared_at`
      // reaparecería — y RN-27 dice que la conversación vuelve VACÍA.
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
      );

      // El backend sigue proyectando cero mensajes: para quien mira, ese mensaje no existe.
      repo.realtime.add(<Message>[
        Message(
          id: 'viejo',
          fromMe: false,
          content: 'anterior a mi cleared_at',
          deletedForAll: false,
          edited: false,
          createdAt: DateTime(2026, 8, 20),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('anterior a mi cleared_at'), findsNothing);
    });
  });

  group('RN-04 — las cuatro acciones de una solicitud recibida', () {
    testWidgets('Aceptar llama a `accept` y deja escribir (RN-05)', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputSolicitudRecibida,
      );

      repo.threadJson = threadPageJson(input: inputAccepted);
      await tester.tap(find.byKey(RequestActionsBar.acceptKey));
      await tester.pumpAndSettle();

      expect(repo.conversationActions.single.action, ConversationAction.accept);
      expect(find.byType(RequestActionsBar), findsNothing);
      expect(find.byKey(MessageComposer.fieldKey), findsOneWidget);
    });

    testWidgets('Ignorar llama a `ignore` (RN-06)', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputSolicitudRecibida,
      );

      await tester.tap(find.byKey(RequestActionsBar.ignoreKey));
      await tester.pumpAndSettle();

      expect(repo.conversationActions.single.action, ConversationAction.ignore);
      expect(repo.conversationActions.single.conversationId, 'c1');
    });

    testWidgets('el mensaje se lee ENTERO antes de decidir (RN-04)', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        input: inputSolicitudRecibida,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', content: 'Hola, te escribo porque…'),
        ],
      );
      expect(find.text('Hola, te escribo porque…'), findsOneWidget);
    });
  });

  group('RN-31 — sin confirmación de lectura', () {
    testWidgets('abrir la conversación pone a cero MI contador y nada más', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository repo = await _pump(
        tester,
        input: inputAccepted,
        unreadCount: 3,
      );

      expect(
        repo.conversationActions.map(
          (
            ({
              ConversationAction action,
              String conversationId,
              bool? notificationsEnabled,
            })
            a,
          ) => a.action,
        ),
        contains(ConversationAction.markRead),
      );
    });

    testWidgets('no se pinta ningún «visto», «leído» ni tic', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: true, content: 'Mío'),
        ],
      );

      final String todo = _todoElTexto(tester).join('\n').toLowerCase();
      for (final String prohibido in <String>['visto', 'leído', 'entregado']) {
        expect(todo, isNot(contains(prohibido)));
      }
      expect(
        _iconos(tester),
        isNot(anyElement(isIn(<IconData>[Icons.done_all, Icons.check_circle]))),
      );
    });
  });

  group('§9.1 — las burbujas', () {
    testWidgets('las propias y las del otro no se pintan igual', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        input: inputAccepted,
        messages: <Map<String, dynamic>>[
          mensajeJson(id: 'm1', fromMe: true, content: 'Mío'),
          mensajeJson(id: 'm2', fromMe: false, content: 'Suyo'),
        ],
      );

      expect(find.byType(MessageBubble), findsNWidgets(2));

      // Se busca POR CONTENIDO y no por el orden del árbol: la lista va invertida (`reverse`)
      // para abrirse en el mensaje más reciente, así que el orden de construcción no es el
      // cronológico y compararlo mediría otra cosa.
      Finder burbujaDe(String texto) => find.ancestor(
        of: find.text(texto),
        matching: find.byType(MessageBubble),
      );

      Alignment lado(String texto) =>
          tester
                  .widget<Align>(
                    find
                        .descendant(
                          of: burbujaDe(texto),
                          matching: find.byType(Align),
                        )
                        .first,
                  )
                  .alignment
              as Alignment;

      Color fondo(String texto) =>
          (tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: burbujaDe(texto),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;

      // §9.1: «propios alineados a un lado con un color; los del otro al contrario».
      expect(lado('Mío'), Alignment.centerRight);
      expect(lado('Suyo'), Alignment.centerLeft);
      expect(fondo('Mío'), isNot(fondo('Suyo')));
    });

    testWidgets('la cabecera lleva el nombre y el punto de actividad (RN-30)', (
      WidgetTester tester,
    ) async {
      await _pump(tester, input: inputAccepted, isActive: true);

      expect(find.text('Ana'), findsWidgets);
      expect(find.byType(ActivityDot), findsOneWidget);
      expect(tester.widget<ActivityDot>(find.byType(ActivityDot)).isActive, isTrue);
    });

    testWidgets('sin dato de actividad NO se pinta punto, ni siquiera gris (RN-30)', (
      WidgetTester tester,
    ) async {
      // `null` significa «esta respuesta no trae el dato», no «desconectado». Pintar un punto gris
      // afirmaría algo que nadie ha dicho.
      await _pump(tester, input: inputAccepted);
      expect(find.byType(ActivityDot), findsNothing);
    });
  });
}
