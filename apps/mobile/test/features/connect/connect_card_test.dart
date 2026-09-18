import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/domain/social/connect_candidate.dart';
import 'package:grasp_mobile/features/connect/presentation/widgets/connect_card.dart';
import 'package:grasp_mobile/features/connect/presentation/widgets/signal_chips.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/activity_dot.dart';

import '../../support/fake_connect_repository.dart';

/// Tests de la tarjeta del §6.4.
Future<void> _pumpCard(
  WidgetTester tester,
  ConnectCandidate candidate, {
  bool messaged = false,
  VoidCallback? onOpenProfile,
  VoidCallback? onChat,
  VoidCallback? onDismiss,
}) async {
  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ConnectCard(
            candidate: candidate,
            messaged: messaged,
            onOpenProfile: onOpenProfile,
            onChat: onChat,
            onDismiss: onDismiss,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RN-38 — los tres destinos del toque son distintos', () {
    testWidgets('tocar la tarjeta abre el perfil', (WidgetTester tester) async {
      int perfil = 0;
      await _pumpCard(
        tester,
        fakeCandidate(userId: 'u1', displayName: 'Ana'),
        onOpenProfile: () => perfil++,
      );

      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      expect(perfil, 1);
    });

    testWidgets('tocar el botón de chat NO abre el perfil', (
      WidgetTester tester,
    ) async {
      int perfil = 0;
      int chat = 0;
      await _pumpCard(
        tester,
        fakeCandidate(userId: 'u1', displayName: 'Ana'),
        onOpenProfile: () => perfil++,
        onChat: () => chat++,
      );

      await tester.tap(find.byKey(ConnectCard.chatButtonKey));
      await tester.pumpAndSettle();

      expect(chat, 1);
      expect(
        perfil,
        0,
        reason: 'RN-38: el botón de chat es acción directa, no abre el perfil.',
      );
    });

    testWidgets('tocar el ✕ NO abre el perfil', (WidgetTester tester) async {
      int perfil = 0;
      int descartes = 0;
      await _pumpCard(
        tester,
        fakeCandidate(userId: 'u1', displayName: 'Ana'),
        onOpenProfile: () => perfil++,
        onDismiss: () => descartes++,
      );

      await tester.tap(find.byKey(ConnectCard.dismissButtonKey));
      await tester.pumpAndSettle();

      expect(descartes, 1);
      expect(perfil, 0);
    });

    testWidgets('el ✕ tiene etiqueta para lector de pantalla (decisión 8)', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, fakeCandidate(userId: 'u1'), onDismiss: () {});
      expect(
        find.bySemanticsLabel('No mostrar más a Alguien'),
        findsOneWidget,
      );
    });
  });

  group('§6.4 — lo que pinta la tarjeta', () {
    testWidgets('nombre y edad', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        fakeCandidate(userId: 'u1', displayName: 'Ana', age: 29),
      );
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('29'), findsOneWidget);
    });

    testWidgets('sin edad, no se pinta un hueco raro', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        fakeCandidate(userId: 'u1', displayName: 'Ana', age: null),
      );
      expect(find.text('Ana'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('la bio va a DOS líneas con elipsis', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        fakeCandidate(userId: 'u1', bio: 'Una bio larguísima ' * 20),
      );
      final Text bio = tester.widget<Text>(
        find.textContaining('Una bio larguísima'),
      );
      expect(bio.maxLines, 2);
      expect(bio.overflow, TextOverflow.ellipsis);
    });

    testWidgets('el punto de actividad está (RN-30)', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, fakeCandidate(userId: 'u1', isActive: true));
      expect(
        tester.widget<ActivityDot>(find.byType(ActivityDot)).isActive,
        isTrue,
      );
    });
  });

  group('ADR 0020 — las señales de la tarjeta son las NO sensibles', () {
    testWidgets('perfil de oyente, tiempo escuchando y racha', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        fakeCandidate(
          userId: 'u1',
          listenerProfile: 'Empático y cercano',
          timeHelpingSeconds: 7200,
          streakDays: 12,
        ),
      );

      expect(find.text('Empático y cercano'), findsOneWidget);
      expect(find.textContaining('2 h'), findsOneWidget);
      expect(find.textContaining('12'), findsOneWidget);
    });

    testWidgets('una señal ausente no pinta un chip vacío', (
      WidgetTester tester,
    ) async {
      // Sin tiempo escuchando ni racha, un chip «0 h» diría algo que no es útil y ocuparía el sitio
      // de una señal que sí lo es.
      await _pumpCard(
        tester,
        fakeCandidate(
          userId: 'u1',
          listenerProfile: 'Directo y práctico',
          timeHelpingSeconds: 0,
          streakDays: 0,
        ),
      );

      final SignalChips chips = tester.widget<SignalChips>(
        find.byType(SignalChips),
      );
      expect(chips.labels, <String>['Directo y práctico']);
    });

    testWidgets('LA TARJETA NO PINTA NADA MÁS que esas señales', (
      WidgetTester tester,
    ) async {
      // Este es el test que impide que una categoría vuelva por la puerta de atrás: enumera TODO
      // el texto que la tarjeta pinta y lo compara con la lista permitida. Si alguien añade un
      // campo —una categoría, una experiencia, un desglose del scoring— aparecerá aquí.
      await _pumpCard(
        tester,
        fakeCandidate(
          userId: 'u1',
          displayName: 'Ana',
          age: 29,
          bio: 'Me gusta escuchar.',
          listenerProfile: 'Empático y cercano',
          timeHelpingSeconds: 7200,
          streakDays: 12,
        ),
        onDismiss: () {},
      );

      final Set<String> pintado = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .where((String s) => s.isNotEmpty)
          .toSet();

      expect(pintado, <String>{
        // La inicial del avatar. `SocialAvatar` la pinta cuando no hay foto ni dibujo, y es texto
        // como cualquier otro: si no estuviera en la lista, el test fallaria por el motivo
        // equivocado y alguien lo "arreglaria" relajando la comparacion — que es como estos tests
        // dejan de servir.
        'A',
        'Ana',
        '29',
        'Me gusta escuchar.',
        'Empático y cercano',
        '2 h escuchando',
        '12 días de racha',
      });
    });
  });

  group('RN-40 — tras el primer mensaje', () {
    testWidgets('el botón dice `Pendiente` y está deshabilitado', (
      WidgetTester tester,
    ) async {
      int chat = 0;
      await _pumpCard(
        tester,
        fakeCandidate(userId: 'u1'),
        messaged: true,
        onChat: () => chat++,
      );

      expect(find.text('Pendiente'), findsOneWidget);
      await tester.tap(
        find.byKey(ConnectCard.chatButtonKey),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(chat, 0, reason: 'RN-40: el botón queda deshabilitado.');
    });

    testWidgets('«Pendiente» cabe ENTERO en el botón', (
      WidgetTester tester,
    ) async {
      // En la app se leía «Pendie…». `find.text` no lo ve —compara el dato del `Text`, no los
      // glifos pintados—, así que el test de arriba pasaba con la palabra cortada por la mitad.
      // Y hasta la Tarea 22 el estado era inalcanzable desde la app: el botón de chat no llevaba
      // a ninguna parte, así que tampoco lo veía nadie mirando. Esto mira el renderizado.
      await _pumpCard(
        tester,
        fakeCandidate(userId: 'u1'),
        messaged: true,
        onChat: () {},
      );

      final RenderParagraph parrafo = tester.renderObject<RenderParagraph>(
        find.text(ConnectCard.pendingLabel),
      );
      expect(
        parrafo.didExceedMaxLines,
        isFalse,
        reason: 'el botón es más estrecho que la palabra y la recorta',
      );
    });

    testWidgets('sin mensaje enviado, el botón NO dice Pendiente', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, fakeCandidate(userId: 'u1'), onChat: () {});
      expect(find.text('Pendiente'), findsNothing);
    });
  });

  group('§6.4 — el componente de chips: máximo 3 + «+N»', () {
    Future<void> pumpChips(WidgetTester tester, List<String> labels) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: SignalChips(labels: labels)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('con 3 o menos, se pintan todos y no hay «+N»', (
      WidgetTester tester,
    ) async {
      await pumpChips(tester, <String>['A', 'B', 'C']);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('con 5, se pintan 3 y un «+2»', (WidgetTester tester) async {
      // Hoy las señales del ADR 0020 son 3, así que el «+N» no llega a verse en la tarjeta. El
      // componente lo soporta igual —lo pide el §6.4— y se prueba aquí directamente para que no
      // sea código sin cubrir.
      await pumpChips(tester, <String>['A', 'B', 'C', 'D', 'E']);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('con 4, el «+1» dice 1 y no 2', (WidgetTester tester) async {
      await pumpChips(tester, <String>['A', 'B', 'C', 'D']);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('sin señales, no se pinta nada', (WidgetTester tester) async {
      await pumpChips(tester, const <String>[]);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('los chips NO son interactivos (§6.4)', (
      WidgetTester tester,
    ) async {
      // «rectángulos de esquinas redondeadas», no botones: si respondieran al toque, la tarjeta
      // tendría cuatro destinos y RN-38 solo define tres.
      await pumpChips(tester, <String>['A', 'B']);
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });
  });
}
