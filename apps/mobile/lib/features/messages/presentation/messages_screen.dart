import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../domain/social/conversation_summary.dart';
import '../application/conversation_controller.dart';
import '../application/inbox_controller.dart';
import 'widgets/conversation_tile.dart';
import 'widgets/inbox_tabs.dart';
import 'widgets/request_tile.dart';

/// Pestaña **Mensajes** — la bandeja del §8, con sus dos pestañas `Contactos` / `Solicitudes`.
///
/// Boceto: `pictures/screens/06-messaging-inbox.jpeg`. La derivación está acordada y anotada en
/// `pictures/screens/README.md` (2026-08-23): sus dos píldoras superiores «Todos / En el escenario»
/// —que son de la pantalla de sala— pasan a ser «Contactos / Solicitudes», y el resto de la fila
/// (foto, nombre, último mensaje a 1 línea, hora) se mantiene tal cual.
///
/// ## Las dos listas son dos tipos de fila, no una con un booleano
///
/// `ConversationTile` y `RequestTile` son widgets distintos porque `RN-30` prohíbe el punto de
/// actividad en Solicitudes. Con un solo widget parametrizado la regla dependería de que cada sitio
/// pasara el booleano bueno; con dos, la fila de Solicitudes **no recibe el dato**.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  /// Empty state de **Contactos** (§12). Es una constante y no un literal suelto para que el test
  /// pueda comprobar que los dos son **distintos**: con la misma cadena repetida, «cada pestaña
  /// tiene su propio empty state» se cumpliría sobre el papel y no en la pantalla.
  static const String emptyContacts =
      'Todavía no tienes conversaciones. Ve a Conectar para encontrar a alguien con quien hablar.';

  /// Empty state de **Solicitudes** (§12).
  static const String emptyRequests =
      'No tienes solicitudes de mensaje pendientes.';

  /// Lo que se enseña si la bandeja no carga. **Nunca el mensaje del backend**: los literales de
  /// `_shared/http.ts` nombran tablas y policies (hallazgo H-A-02 de la auditoría de 2026-08-15).
  static const String loadError =
      'No se pudieron cargar tus mensajes. Desliza hacia abajo para reintentar.';

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<InboxView> inbox = ref.watch(inboxControllerProvider);

    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: AppBar(title: const Text('Mensajes')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            InboxTabs(
              selectedIndex: _tab,
              // Del backend, no del largo de la lista. Mientras carga, 0: una píldora que promete
              // solicitudes antes de saber si las hay es peor que una que espera.
              requestsCount: inbox.valueOrNull?.snapshot.requestsCount ?? 0,
              onSelected: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: inbox.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace _) => _Refreshable(
                  onRefresh: _refresh,
                  child: _Message(text: MessagesScreen.loadError),
                ),
                data: (InboxView view) => _Refreshable(
                  onRefresh: _refresh,
                  child: _tab == 0
                      ? _ContactsList(view: view)
                      : _RequestsList(view: view),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() =>
      ref.read(inboxControllerProvider.notifier).refresh();
}

/// Envuelve en `RefreshIndicator`, con el mismo patrón que `ProfileScreen`.
///
/// El `AlwaysScrollableScrollPhysics` es lo que hace que el gesto funcione **también con la lista
/// vacía**: sin él, un `ListView` que no desborda no scrollea y el empty state no se puede
/// refrescar — que es justo la pantalla en la que más falta hace reintentar.
class _Refreshable extends StatelessWidget {
  const _Refreshable({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: context.palette.brandStrong,
      child: child,
    );
  }
}

/// Abre la conversación de [c] y, al volver, **vuelve a pedir la bandeja**.
///
/// El refresco no es cosmético: dentro del hilo pueden haber pasado tres cosas que la bandeja
/// pinta —el contador propio se puso a cero (`RN-31`), una solicitud se aceptó y cambia de pestaña
/// (`RN-05`) o se ignoró y desaparece de Solicitudes (`RN-06`)—. Sin volver a pedirla, la lista
/// seguiría enseñando el estado anterior hasta el siguiente arrastre.
Future<void> _abrir(
  BuildContext context,
  WidgetRef ref,
  ConversationSummary c,
) async {
  await context.push<bool>(
    AppRoute.conversation,
    extra: ConversationArgs.existing(
      conversationId: c.conversationId,
      otherUserId: c.otherUserId,
      displayName: c.displayName,
      presetAvatar: c.presetAvatar,
    ),
  );
  if (!context.mounted) return;
  await ref.read(inboxControllerProvider.notifier).refresh();
}

class _ContactsList extends ConsumerWidget {
  const _ContactsList({required this.view});

  final InboxView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ConversationSummary> contacts = view.snapshot.contacts;
    if (contacts.isEmpty) {
      return const _Message(text: MessagesScreen.emptyContacts);
    }

    // `builder` y no un `Column`: la bandeja llega hasta 100 filas (punto 4 de la skill
    // `flutter-ui`).
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: contacts.length,
      itemBuilder: (BuildContext context, int index) {
        // Sin ordenar aquí: el backend ya devuelve `last_message_at desc` (`RN-29`). Reordenar en
        // el cliente crearía una segunda fuente de verdad para el mismo orden.
        final ConversationSummary c = contacts[index];
        return ConversationTile(
          conversation: c,
          photoUrl: view.photoUrls[c.otherUserId],
          onTap: () => _abrir(context, ref, c),
        );
      },
    );
  }
}

class _RequestsList extends ConsumerWidget {
  const _RequestsList({required this.view});

  final InboxView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ConversationSummary> requests = view.snapshot.requests;
    if (requests.isEmpty) {
      return const _Message(text: MessagesScreen.emptyRequests);
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: requests.length,
      itemBuilder: (BuildContext context, int index) {
        final ConversationSummary r = requests[index];
        return RequestTile(
          request: r,
          photoUrl: view.photoUrls[r.otherUserId],
          // Mismo destino que Contactos, y no una pantalla aparte: lo que cambia entre las dos es
          // el estado del input, que lo decide el backend (§9.2 fila 4). Una «pantalla de
          // solicitud» separada tendría que deducir ese estado por su cuenta y podría discrepar.
          onTap: () => _abrir(context, ref, r),
        );
      },
    );
  }
}

/// Texto centrado dentro de algo scrolleable, para que el `RefreshIndicator` siga funcionando.
class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
