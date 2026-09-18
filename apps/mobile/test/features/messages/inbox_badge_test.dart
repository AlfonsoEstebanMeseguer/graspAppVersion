import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/router/app_router.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/core/ui/grasp_bottom_nav.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/social/conversation_summary.dart';
import 'package:grasp_mobile/features/messages/application/inbox_controller.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_social_repositories.dart';

/// Tests de `RN-55`: **el badge de Mensajes no cuenta solicitudes.**
///
/// La Tarea 18 dejó el badge pintándose pero alimentado con `null` y un `TODO`, porque el número
/// que lo alimenta no existía. Éste es el test que el plan aplazó hasta aquí.
///
/// El motivo de la regla está en la spec: *no premiar el spam con una notificación roja*. Alguien
/// que reciba cincuenta solicitudes de desconocidos no debe ver un 50 en la barra.
InboxSnapshot _snapshot({
  List<ConversationSummary> contacts = const <ConversationSummary>[],
  List<ConversationSummary> requests = const <ConversationSummary>[],
}) => InboxSnapshot(
  contacts: contacts,
  requests: requests,
  requestsCount: requests.length,
);

void main() {
  group('el número — RN-55, la parte que se puede probar sin pintar nada', () {
    test('suma los no leídos de las conversaciones aceptadas', () {
      final InboxView view = InboxView(
        snapshot: _snapshot(
          contacts: <ConversationSummary>[
            fakeConversation(id: 'c1', unreadCount: 3),
            fakeConversation(id: 'c2', unreadCount: 2),
          ],
        ),
        photoUrls: const <String, String>{},
      );
      expect(view.unreadBadge, 5);
    });

    test('NO cuenta las solicitudes recibidas, por muchas que sean', () {
      final InboxView view = InboxView(
        snapshot: _snapshot(
          requests: <ConversationSummary>[
            fakeConversation(id: 'r1', unreadCount: 9),
            fakeConversation(id: 'r2', unreadCount: 9),
          ],
        ),
        photoUrls: const <String, String>{},
      );
      expect(view.unreadBadge, 0);
    });

    test('NO cuenta una solicitud PROPIA todavía sin aceptar', () {
      // Ésta es la que se escapa: `RN-02` mete mis solicitudes enviadas en **Contactos**, así que
      // filtrar por lista no basta. Lo que las distingue es `pending_acceptance`, que el backend
      // deriva sin revelar el `status`. Una conversación aceptada y una solicitud mía conviven en
      // la misma lista y solo este campo las separa.
      final InboxView view = InboxView(
        snapshot: _snapshot(
          contacts: <ConversationSummary>[
            fakeConversation(id: 'c1', unreadCount: 4),
            fakeConversation(id: 'c2', unreadCount: 6, pendingAcceptance: true),
          ],
        ),
        photoUrls: const <String, String>{},
      );
      expect(
        view.unreadBadge,
        4,
        reason: 'Una solicitud enviada por mí no es una conversación aceptada (RN-55).',
      );
    });

    test('sin nada sin leer, el badge es 0 y no se pinta', () {
      final InboxView view = InboxView(
        snapshot: _snapshot(
          contacts: <ConversationSummary>[fakeConversation(id: 'c1')],
        ),
        photoUrls: const <String, String>{},
      );
      expect(view.unreadBadge, 0);
    });
  });

  group('el badge en la barra de verdad', () {
    Future<void> pumpShell(
      WidgetTester tester,
      InboxSnapshot snapshot,
    ) async {
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
            messagingRepositoryProvider.overrideWithValue(
              FakeMessagingRepository(snapshot),
            ),
            avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
          ],
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                MaterialApp.router(
                  theme: theme,
                  routerConfig: ref.watch(routerProvider),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      fake.emitSignedIn('cf3969f3-6180-4606-9896-f91aaad58fc4');
      await tester.pumpAndSettle();
    }

    int? badgeDeMensajes(WidgetTester tester) {
      final GraspBottomNav nav = tester.widget<GraspBottomNav>(
        find.byType(GraspBottomNav),
      );
      return nav.destinations
          .firstWhere((GraspNavDestination d) => d.label == 'Mensajes')
          .badgeCount;
    }

    testWidgets('la barra recibe los no leídos de las aceptadas', (
      WidgetTester tester,
    ) async {
      await pumpShell(
        tester,
        _snapshot(
          contacts: <ConversationSummary>[
            fakeConversation(id: 'c1', unreadCount: 2),
          ],
        ),
      );
      expect(badgeDeMensajes(tester), 2);
    });

    testWidgets('con solo solicitudes, la barra NO recibe número', (
      WidgetTester tester,
    ) async {
      await pumpShell(
        tester,
        _snapshot(
          requests: <ConversationSummary>[
            fakeConversation(id: 'r1', unreadCount: 5),
            fakeConversation(id: 'r2', unreadCount: 5),
          ],
        ),
      );
      // El badge no pinta con 0, así que da igual `0` que `null`; lo que no puede es ser 10.
      expect(badgeDeMensajes(tester) ?? 0, 0);
    });

    testWidgets('el TODO de la Tarea 18 ya no está: el badge se alimenta', (
      WidgetTester tester,
    ) async {
      // La Tarea 18 pasaba `badgeCount: null` fijo. Un test que solo comprobara «no es 10» seguiría
      // pasando con esa constante, así que hace falta uno que exija un número real.
      await pumpShell(
        tester,
        _snapshot(
          contacts: <ConversationSummary>[
            fakeConversation(id: 'c1', unreadCount: 7),
          ],
        ),
      );
      expect(badgeDeMensajes(tester), isNotNull);
      expect(badgeDeMensajes(tester), 7);
    });
  });
}
