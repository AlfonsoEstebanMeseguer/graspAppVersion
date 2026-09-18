import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/social/conversation_summary.dart';

/// La bandeja del §8 ya lista para pintar: lo que devolvió `messaging-inbox` más las URLs
/// firmadas de las fotos.
///
/// Las fotos van aparte y no dentro de [ConversationSummary] porque **el backend no las manda**:
/// `docs/api-contracts.md` lo dice con esas palabras —*«La foto no viaja: se pide a
/// `profile-photo-view-url`»*—, y con razón, porque una URL firmada caduca en 300 s y no puede
/// viajar cacheada dentro de una lista.
@immutable
class InboxView {
  const InboxView({required this.snapshot, required this.photoUrls});

  final InboxSnapshot snapshot;

  /// `userId` → URL firmada. Quien no tenga foto **no está en el mapa**; no se guarda `null`,
  /// porque «no tiene foto» y «todavía no lo he preguntado» se confunden en cuanto alguien cachea.
  final Map<String, String> photoUrls;

  /// **EL NÚMERO DEL BADGE DE LA BARRA — `RN-55`.**
  ///
  /// Solo los no leídos de conversaciones **aceptadas**. El motivo está en la spec: *no premiar el
  /// spam con una notificación roja*. Quien reciba cincuenta solicitudes de desconocidos no debe
  /// ver un 50 en la barra.
  ///
  /// Filtrar por lista **no basta**, y ahí está la trampa: `RN-02` mete mis solicitudes *enviadas*
  /// dentro de **Contactos**, junto a las aceptadas. Lo que las separa es [pendingAcceptance], que
  /// el backend deriva sin revelar el `status` — que es justo lo que `RN-06` no deja salir de la
  /// base. Por eso el filtro es ese campo y no un `status` que aquí no existe ni puede existir.
  int get unreadBadge => snapshot.contacts
      .where((ConversationSummary c) => !c.pendingAcceptance)
      .fold(0, (int total, ConversationSummary c) => total + c.unreadCount);
}

/// Carga las dos bandejas y sus fotos.
class InboxController extends AutoDisposeAsyncNotifier<InboxView> {
  @override
  Future<InboxView> build() async {
    final InboxSnapshot snapshot = await ref
        .read(messagingRepositoryProvider)
        .inbox();

    // Una sola llamada para todas las caras de las dos listas. `profile-photo-view-url` acepta
    // `user_ids` como array desde el primer día justo para esto: sin lote, una bandeja de 100
    // conversaciones haría 100 peticiones para pintar 100 caras.
    final List<String> userIds = <String>[
      ...snapshot.contacts.map((ConversationSummary c) => c.otherUserId),
      ...snapshot.requests.map((ConversationSummary c) => c.otherUserId),
    ];

    Map<String, String> photos = const <String, String>{};
    if (userIds.isNotEmpty) {
      try {
        photos = await ref.read(avatarRepositoryProvider).photoUrls(userIds);
      } on Object {
        // Que no se pueda firmar una foto NO puede vaciar la bandeja: se pintan las iniciales y
        // la lista sigue siendo utilizable. Un fallo de la parte decorativa que tumbara la parte
        // funcional sería peor que la propia falta de fotos.
        photos = const <String, String>{};
      }
    }

    return InboxView(snapshot: snapshot, photoUrls: photos);
  }

  /// Vuelve a pedirlo todo. Lo usa el `RefreshIndicator`.
  Future<void> refresh() => ref.refresh(inboxControllerProvider.future);
}

final AutoDisposeAsyncNotifierProvider<InboxController, InboxView>
inboxControllerProvider =
    AsyncNotifierProvider.autoDispose<InboxController, InboxView>(
      InboxController.new,
    );

/// El número que va al badge de la pestaña «Mensajes», o `null` si todavía no se sabe.
///
/// Va en su propio provider y no leyendo `inboxControllerProvider` desde la barra por una razón
/// concreta: la barra vive **por encima** del `StatefulShellRoute`, así que se construye siempre,
/// incluso con Mensajes sin abrir. Un provider derivado deja que la barra dependa solo del número
/// y no del ciclo de vida de la pantalla.
///
/// `null` mientras carga o si falla: el badge no pinta nada con `null` ni con `0`, y **un badge
/// equivocado es peor que ninguno**.
final AutoDisposeProvider<int?> messagesBadgeProvider = Provider.autoDispose<int?>(
  (Ref ref) => ref.watch(inboxControllerProvider).valueOrNull?.unreadBadge,
);
