import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/social/conversation_summary.dart';
import 'package:grasp_mobile/features/messages/presentation/messages_screen.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/activity_dot.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/conversation_tile.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/request_tile.dart';

import '../../support/fake_social_repositories.dart';

/// Tests de la bandeja del §8 (Tarea 20).
///
/// Boceto: `pictures/screens/06-messaging-inbox.jpeg`, con la derivación acordada el 2026-08-23 —
/// sus píldoras «Todos / En el escenario» pasan a **«Contactos / Solicitudes»**.
Future<FakeMessagingRepository> _pumpInbox(
  WidgetTester tester, {
  List<ConversationSummary> contacts = const <ConversationSummary>[],
  List<ConversationSummary> requests = const <ConversationSummary>[],
  int? requestsCount,
  Map<String, String> photos = const <String, String>{},
}) async {
  final FakeMessagingRepository messaging = FakeMessagingRepository(
    InboxSnapshot(
      contacts: contacts,
      requests: requests,
      requestsCount: requestsCount ?? requests.length,
    ),
  );

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        messagingRepositoryProvider.overrideWithValue(messaging),
        avatarRepositoryProvider.overrideWithValue(
          FakeAvatarRepository(urls: photos),
        ),
      ],
      child: MaterialApp(theme: theme, home: const MessagesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return messaging;
}

/// El `FontWeight` con el que se pinta un texto concreto.
FontWeight? _pesoDe(WidgetTester tester, String texto) {
  final Text widget = tester.widget<Text>(find.text(texto));
  return widget.style?.fontWeight;
}

void main() {
  group('§8.1 — la cabecera de dos pestañas', () {
    testWidgets('las dos pestañas son Contactos y Solicitudes', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);
      expect(find.text('Contactos'), findsOneWidget);
      expect(find.text('Solicitudes'), findsOneWidget);
      // Las píldoras del boceto eran «Todos / En el escenario»: son de la pantalla de sala, no de
      // ésta, y no pueden quedar por descuido.
      expect(find.text('Todos'), findsNothing);
      expect(find.text('En el escenario'), findsNothing);
    });

    testWidgets('el contador (N) NO aparece con N = 0', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);
      expect(find.text('Solicitudes'), findsOneWidget);
      expect(find.textContaining('Solicitudes ('), findsNothing);
    });

    testWidgets('el contador (N) aparece con N > 0', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        requests: <ConversationSummary>[
          fakeConversation(id: 'c1', displayName: 'Ana'),
          fakeConversation(id: 'c2', displayName: 'Luis'),
        ],
      );
      expect(find.text('Solicitudes (2)'), findsOneWidget);
    });

    testWidgets('el contador usa requests_count, no el largo de la lista', (
      WidgetTester tester,
    ) async {
      // La bandeja topa a 100 por lista; el `requests_count` del backend es el número real. Si la
      // píldora contara las filas, una bandeja llena mentiría.
      await _pumpInbox(
        tester,
        requests: <ConversationSummary>[fakeConversation(id: 'c1')],
        requestsCount: 7,
      );
      expect(find.text('Solicitudes (7)'), findsOneWidget);
    });
  });

  group('§12 — cada pestaña tiene SU PROPIO empty state', () {
    testWidgets('Contactos vacío enseña su texto', (WidgetTester tester) async {
      await _pumpInbox(tester);
      expect(find.text(MessagesScreen.emptyContacts), findsOneWidget);
    });

    testWidgets('Solicitudes vacío enseña OTRO texto distinto', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);
      await tester.tap(find.text('Solicitudes'));
      await tester.pumpAndSettle();

      expect(find.text(MessagesScreen.emptyRequests), findsOneWidget);
      expect(find.text(MessagesScreen.emptyContacts), findsNothing);
    });

    testWidgets('los dos textos son DISTINTOS entre sí', (
      WidgetTester tester,
    ) async {
      // Sin esto, «cada pestaña tiene su propio empty state» se cumple con la misma cadena dos
      // veces y los dos tests de arriba pasarían igual.
      expect(MessagesScreen.emptyContacts, isNot(MessagesScreen.emptyRequests));
    });
  });

  group('§8.2 — la fila de Contactos', () {
    testWidgets('«Tú: » prefija el último mensaje si lo envié yo', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(
            id: 'c1',
            displayName: 'Ana',
            lastMessageContent: 'Nos vemos',
            fromMe: true,
          ),
        ],
      );
      expect(find.text('Tú: Nos vemos'), findsOneWidget);
    });

    testWidgets('sin «Tú: » si lo envió la otra persona', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(
            id: 'c1',
            displayName: 'Ana',
            lastMessageContent: 'Nos vemos',
          ),
        ],
      );
      expect(find.text('Nos vemos'), findsOneWidget);
      expect(find.text('Tú: Nos vemos'), findsNothing);
    });

    testWidgets('una fila NO leída va en negrita y con punto', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(
            id: 'c1',
            displayName: 'Ana',
            lastMessageContent: 'Hola',
            unreadCount: 3,
          ),
        ],
      );

      expect(_pesoDe(tester, 'Ana'), FontWeight.w700);
      expect(_pesoDe(tester, 'Hola'), FontWeight.w700);
      expect(find.byType(UnreadDot), findsOneWidget);
    });

    testWidgets('una fila LEÍDA no va en negrita ni pinta punto', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(
            id: 'c1',
            displayName: 'Ana',
            lastMessageContent: 'Hola',
          ),
        ],
      );

      expect(_pesoDe(tester, 'Ana'), isNot(FontWeight.w700));
      expect(find.byType(UnreadDot), findsNothing);
    });

    testWidgets('una solicitud enviada dice «Pendiente de aceptación»', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(
            id: 'c1',
            displayName: 'Ana',
            pendingAcceptance: true,
          ),
        ],
      );
      expect(find.text('Pendiente de aceptación'), findsOneWidget);
    });

    testWidgets('una conversación aceptada NO lo dice', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(id: 'c1', displayName: 'Ana'),
        ],
      );
      expect(find.text('Pendiente de aceptación'), findsNothing);
    });

    testWidgets('una lápida no enseña el texto borrado', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(
            id: 'c1',
            displayName: 'Ana',
            lastMessageContent: 'secreto',
            deletedForAll: true,
          ),
        ],
      );
      expect(find.textContaining('secreto'), findsNothing);
      expect(find.text(ConversationTile.deletedMessage), findsOneWidget);
    });

    testWidgets('el orden del backend se respeta tal cual (RN-29)', (
      WidgetTester tester,
    ) async {
      // El backend ya ordena por `last_message_at desc`. Si la pantalla reordenara por su cuenta
      // —o peor, no lo hiciera y el backend cambiase— este test lo delata.
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(
            id: 'c1',
            displayName: 'Reciente',
            lastMessageAt: DateTime(2026, 8, 25, 19, 0),
          ),
          fakeConversation(
            id: 'c2',
            displayName: 'Antigua',
            lastMessageAt: DateTime(2026, 8, 24, 10, 0),
          ),
        ],
      );

      final List<ConversationTile> filas = tester
          .widgetList<ConversationTile>(find.byType(ConversationTile))
          .toList();
      expect(
        filas.map((ConversationTile t) => t.conversation.displayName),
        <String>['Reciente', 'Antigua'],
      );
    });
  });

  group('RN-30 — el punto de actividad', () {
    testWidgets('SÍ aparece en Contactos cuando está activo', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(id: 'c1', displayName: 'Ana', isActive: true),
        ],
      );
      final ActivityDot dot = tester.widget<ActivityDot>(
        find.byType(ActivityDot),
      );
      expect(dot.isActive, isTrue);
    });

    testWidgets('aparece en gris cuando está inactivo', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(id: 'c1', displayName: 'Ana', isActive: false),
        ],
      );
      final ActivityDot dot = tester.widget<ActivityDot>(
        find.byType(ActivityDot),
      );
      expect(dot.isActive, isFalse);
    });

    testWidgets('NO aparece en las filas de Solicitudes', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        requests: <ConversationSummary>[
          // `isActive: true` a propósito: aunque el backend se equivocara y lo mandase, la fila de
          // Solicitudes no puede pintarlo. `RequestTile` ni siquiera acepta el parámetro.
          fakeConversation(id: 'c1', displayName: 'Ana', isActive: true),
        ],
      );
      await tester.tap(find.text('Solicitudes (1)'));
      await tester.pumpAndSettle();

      expect(find.byType(RequestTile), findsOneWidget);
      expect(
        find.byType(ActivityDot),
        findsNothing,
        reason: 'RN-30: el punto de actividad no aparece en Solicitudes.',
      );
    });

    testWidgets('una lápida en Solicitudes tampoco enseña el texto borrado', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        requests: <ConversationSummary>[
          fakeConversation(
            id: 'c1',
            displayName: 'Ana',
            lastMessageContent: 'secreto',
            deletedForAll: true,
          ),
        ],
      );
      await tester.tap(find.text('Solicitudes (1)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('secreto'), findsNothing);
      expect(find.text(ConversationTile.deletedMessage), findsOneWidget);
    });

    testWidgets('tampoco cuando el backend omite la clave (isActive null)', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(id: 'c1', displayName: 'Ana'),
        ],
      );
      // `null` significa «esta lista no lo trae», no «desconectado»: no se pinta punto ninguno,
      // ni siquiera gris.
      expect(find.byType(ActivityDot), findsNothing);
    });
  });

  group('las dos listas no se mezclan', () {
    testWidgets('Contactos no enseña las solicitudes recibidas', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(id: 'c1', displayName: 'EnContactos'),
        ],
        requests: <ConversationSummary>[
          fakeConversation(id: 'c2', displayName: 'EnSolicitudes'),
        ],
      );
      expect(find.text('EnContactos'), findsOneWidget);
      expect(find.text('EnSolicitudes'), findsNothing);
    });

    testWidgets('Solicitudes no enseña los contactos', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(id: 'c1', displayName: 'EnContactos'),
        ],
        requests: <ConversationSummary>[
          fakeConversation(id: 'c2', displayName: 'EnSolicitudes'),
        ],
      );
      await tester.tap(find.text('Solicitudes (1)'));
      await tester.pumpAndSettle();

      expect(find.text('EnSolicitudes'), findsOneWidget);
      expect(find.text('EnContactos'), findsNothing);
    });
  });

  group('carga, error y refresco', () {
    testWidgets('un fallo enseña un texto y no la excepción cruda', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository messaging = FakeMessagingRepository(
        const InboxSnapshot(
          contacts: <ConversationSummary>[],
          requests: <ConversationSummary>[],
          requestsCount: 0,
        ),
      )..failWith = StateError('permission denied for table conversations');

      final ThemeData theme = AppTheme.light().copyWith(
        extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            messagingRepositoryProvider.overrideWithValue(messaging),
            avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
          ],
          child: MaterialApp(theme: theme, home: const MessagesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('permission denied'), findsNothing);
      expect(find.text(MessagesScreen.loadError), findsOneWidget);
    });

    testWidgets('el pull-to-refresh vuelve a pedir la bandeja de verdad', (
      WidgetTester tester,
    ) async {
      final FakeMessagingRepository messaging = await _pumpInbox(
        tester,
        contacts: <ConversationSummary>[
          fakeConversation(id: 'c1', displayName: 'Ana'),
        ],
      );
      expect(messaging.inboxCalls, 1);

      await tester.fling(find.text('Ana'), const Offset(0, 320), 1000);
      await tester.pumpAndSettle();

      expect(
        messaging.inboxCalls,
        2,
        reason: 'El RefreshIndicator tiene que refrescar, no solo animar.',
      );
    });
  });
}
