import 'dart:async';
import 'dart:typed_data';

import 'package:grasp_mobile/domain/profile/avatar_repository.dart';
import 'package:grasp_mobile/domain/profile/avatar_type.dart';
import 'package:grasp_mobile/domain/profile/profile_badge.dart';
import 'package:grasp_mobile/domain/social/blocked_user.dart';
import 'package:grasp_mobile/domain/social/conversation_summary.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';
import 'package:grasp_mobile/domain/social/follow_repository.dart';
import 'package:grasp_mobile/domain/social/message.dart';
import 'package:grasp_mobile/domain/social/message_input_state.dart';
import 'package:grasp_mobile/domain/social/messaging_repository.dart';
import 'package:grasp_mobile/domain/social/moderation_repository.dart';
import 'package:grasp_mobile/domain/social/public_profile.dart';

/// Dobles de la capa social para tests de widget.
///
/// Implementan el **contrato del dominio**, no el cliente de Supabase: es lo que pide el punto 6 de
/// la skill `flutter-ui` («los widgets no se testean con mocks de Supabase que oculten fallos de
/// RLS reales»). Lo que estas clases fingen es la respuesta que el backend **ya devuelve
/// proyectada**; las reglas de proyección se prueban en Deno y en el humo de integración, no aquí.
class FakeMessagingRepository implements MessagingRepository {
  FakeMessagingRepository([InboxSnapshot? snapshot])
    : snapshot =
          snapshot ??
          const InboxSnapshot(
            contacts: <ConversationSummary>[],
            requests: <ConversationSummary>[],
            requestsCount: 0,
          );

  InboxSnapshot snapshot;

  /// Cuántas veces se pidió la bandeja. Es lo que distingue un `RefreshIndicator` que refresca de
  /// uno que solo anima.
  int inboxCalls = 0;

  /// Si no es `null`, [inbox] lanza esto.
  Object? failWith;

  // ── Conversación (Tarea 22) ────────────────────────────────────────────────

  /// El JSON **crudo** que devuelve [thread].
  ///
  /// Crudo y no un [MessageThreadPage] ya construido a propósito: así el test pasa por
  /// `MessageThreadPage.fromJson`, que es donde vive la interpretación del §9.2, y **puede meter
  /// campos hostiles** que el backend de hoy no manda. Un doble que devolviera el objeto ya
  /// interpretado saltaría justo la parte que `RN-23` protege.
  Map<String, dynamic> threadJson = threadPageJson(input: inputAccepted);

  /// Si no es `null`, [thread] lanza esto.
  Object? threadFailsWith;

  int threadCalls = 0;
  final List<({int? limit, String? before})> threadArgs =
      <({int? limit, String? before})>[];

  /// Si no es `null`, [send] lanza esto.
  Object? sendFailsWith;

  /// Lo que queda tras el envío (`RN-01`). `null` = sin tope.
  int? messagesLeftAfterSend;

  final List<
    ({String recipientId, String content, String idempotencyKey, String? replyToId})
  >
  sent =
      <({String recipientId, String content, String idempotencyKey, String? replyToId})>[];

  final List<({String messageId, MessageAction action, String? content})>
  messageActions =
      <({String messageId, MessageAction action, String? content})>[];

  final List<
    ({String conversationId, ConversationAction action, bool? notificationsEnabled})
  >
  conversationActions =
      <({String conversationId, ConversationAction action, bool? notificationsEnabled})>[];

  /// Alimenta a [watchMessages]. El test empuja aquí para simular una fila nueva en
  /// `direct_messages`.
  final StreamController<List<Message>> realtime =
      StreamController<List<Message>>.broadcast();

  int watchCalls = 0;

  @override
  Future<InboxSnapshot> inbox() async {
    inboxCalls++;
    final Object? error = failWith;
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<MessageThreadPage> thread(
    String conversationId, {
    int? limit,
    String? before,
  }) async {
    threadCalls++;
    threadArgs.add((limit: limit, before: before));
    final Object? error = threadFailsWith;
    if (error != null) throw error;
    return MessageThreadPage.fromJson(threadJson);
  }

  @override
  Future<({Message message, int? messagesLeft, bool idempotentReplay})> send({
    required String recipientId,
    required String content,
    required String idempotencyKey,
    String? replyToId,
  }) async {
    sent.add((
      recipientId: recipientId,
      content: content,
      idempotencyKey: idempotencyKey,
      replyToId: replyToId,
    ));
    final Object? error = sendFailsWith;
    if (error != null) throw error;

    final String id = 'enviado-${sent.length}';
    final DateTime cuando = DateTime.utc(2026, 8, 26, 12, sent.length);
    final int? quedan = messagesLeftAfterSend;

    // El hilo también lo tiene, porque un backend real lo tendría: `messaging-send` inserta la
    // fila y el `thread()` siguiente la proyecta. Sin esto el doble diría que el envío triunfó y
    // acto seguido devolvería un hilo vacío, un estado que el backend no puede producir — y la
    // pantalla parecería tragarse mensajes por culpa del fixture.
    threadJson = <String, dynamic>{
      ...threadJson,
      // El veredicto del hilo también se mueve, porque en el backend sale de `evaluateSendLimits`,
      // que es **la misma función** que acaba de decidir este envío. Un doble que dejara el input
      // clavado mientras el contador baja inventaría un estado que no existe.
      'input': ?switch (quedan) {
        null => null,
        <= 0 => inputCupoAgotado,
        _ => inputConRestantes(quedan),
      },
      'messages': <Map<String, dynamic>>[
        ...((threadJson['messages'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>(),
        mensajeJson(
          id: id,
          fromMe: true,
          content: content,
          createdAt: cuando,
          replyTo: replyToId == null
              ? null
              : <String, dynamic>{
                  'id': replyToId,
                  'from_me': false,
                  'content': 'citado',
                },
        ),
      ],
    };

    return (
      message: Message(
        id: id,
        fromMe: true,
        content: content,
        deletedForAll: false,
        edited: false,
        createdAt: cuando.toLocal(),
      ),
      messagesLeft: messagesLeftAfterSend,
      idempotentReplay: false,
    );
  }

  @override
  Future<void> conversationAction(
    String conversationId,
    ConversationAction action, {
    bool? notificationsEnabled,
  }) async {
    conversationActions.add((
      conversationId: conversationId,
      action: action,
      notificationsEnabled: notificationsEnabled,
    ));
    // El backend PERSISTE el valor, así que el doble también: sin esto, un test que apaga la
    // campana y vuelve a abrir el menú no distinguiría una pantalla que relee de una que se queda
    // con lo que tenía en memoria.
    if (action == ConversationAction.setNotifications &&
        notificationsEnabled != null) {
      notifications = notificationsEnabled;
    }
  }

  @override
  Future<void> messageAction(
    String messageId,
    MessageAction action, {
    String? content,
  }) async {
    messageActions.add((
      messageId: messageId,
      action: action,
      content: content,
    ));
  }

  /// Lo que devuelve [search]. Se pone por test, y **no se deriva de [threadJson]**: es justo la
  /// diferencia entre las dos que hace que los tests del §9.4 puedan fallar. Ver
  /// [busquedaConCoincidencias].
  MessageSearchResult searchResult = const MessageSearchResult(
    total: 0,
    searchedMessages: 0,
    searchLimit: 1000,
    hits: <MessageSearchHit>[],
  );

  /// Si no es `null`, [search] lanza esto.
  Object? searchFailsWith;

  final List<({String conversationId, String query})> searches =
      <({String conversationId, String query})>[];

  @override
  Future<MessageSearchResult> search(String conversationId, String query) async {
    searches.add((conversationId: conversationId, query: query));
    final Object? error = searchFailsWith;
    if (error != null) throw error;
    return searchResult;
  }

  /// El valor guardado de la campana. Empieza en `true`, el `default` de la columna.
  bool notifications = true;

  int notificationsReads = 0;

  @override
  Future<bool> notificationsEnabled(String conversationId) async {
    notificationsReads++;
    return notifications;
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    watchCalls++;
    return realtime.stream;
  }
}

// ── Fixtures del §9.2, con los cuerpos EXACTOS de `docs/api-contracts.md` ────

/// Fila 1: conversación aceptada.
const Map<String, dynamic> inputAccepted = <String, dynamic>{
  'can_send': true,
  'input_notice': null,
  'messages_left': null,
  'request_actions': false,
};

/// Fila 2: solicitud enviada con [left] mensajes por gastar (`RN-01`).
Map<String, dynamic> inputConRestantes(int left) => <String, dynamic>{
  'can_send': true,
  'input_notice': null,
  'messages_left': left,
  'request_actions': false,
};

/// Fila 3: los 5 gastados.
const Map<String, dynamic> inputCupoAgotado = <String, dynamic>{
  'can_send': false,
  'input_notice': kMessageInputNotice,
  'messages_left': 0,
  'request_actions': false,
};

/// Fila 4: solicitud **recibida** sin aceptar (`RN-04`).
const Map<String, dynamic> inputSolicitudRecibida = <String, dynamic>{
  'can_send': true,
  'input_notice': null,
  'messages_left': null,
  'request_actions': true,
};

/// Fila 5: bloqueado — **el mismo cuerpo que [inputCupoAgotado]**, más tres campos que el backend
/// de hoy NO manda.
///
/// **Es un fixture hostil, y tiene que serlo.** Las filas 3 y 5 son idénticas campo a campo
/// (`RN-23`, ADR 0022), así que comparar dos copias del mismo cuerpo no distinguiría ninguna
/// implementación de otra: sería un test vacuo, exactamente el de la lápida de la Tarea 20. Lo que
/// aquí se prueba es lo único que sí puede fallar de verdad — que **si el motivo volviera a llegar
/// por cualquier vía, la pantalla no lo pintaría**.
const Map<String, dynamic> inputBloqueadoHostil = <String, dynamic>{
  ...inputCupoAgotado,
  'blocked': true,
  'block_reason': 'blocked_by_recipient',
  'internal_reason': 'te ha bloqueado',
};

/// Una respuesta de `messaging-thread` tal y como la documenta `docs/api-contracts.md`.
Map<String, dynamic> threadPageJson({
  required Map<String, dynamic> input,
  List<Map<String, dynamic>> messages = const <Map<String, dynamic>>[],
  String conversationId = 'c1',
  String otherUserId = '00000000-0000-4000-8000-000000000002',
  String displayName = 'Ana',
  bool? isActive,
  int unreadCount = 0,
  bool hasMore = false,
  String? nextBefore,
}) => <String, dynamic>{
  'conversation': <String, dynamic>{
    'conversation_id': conversationId,
    'other_user_id': otherUserId,
    'display_name': displayName,
    'preset_avatar': null,
    // Ausente ≠ `false`: `RN-30` distingue «esta respuesta no trae el dato» de «está desconectado»,
    // y `MessageThreadPage.fromJson` lo mira con `containsKey`. Con `?`, un `null` quita la clave
    // entera y un `false` la deja puesta, que es justo esa diferencia.
    'is_active': ?isActive,
    'unread_count': unreadCount,
  },
  'messages': messages,
  'has_more': hasMore,
  'next_before': nextBefore,
  'input': input,
};

/// Una fila de `messages` del §9.1.
Map<String, dynamic> mensajeJson({
  required String id,
  bool fromMe = false,
  String? content = 'Hola',
  bool deletedForAll = false,
  bool edited = false,
  DateTime? createdAt,
  Map<String, dynamic>? replyTo,
}) => <String, dynamic>{
  'id': id,
  'from_me': fromMe,
  'content': content,
  'deleted_for_all': deletedForAll,
  'edited': edited,
  'created_at': (createdAt ?? DateTime.utc(2026, 8, 26, 10)).toIso8601String(),
  'reply_to': ?replyTo,
};

/// Doble de [ModerationRepository] (`RN-22`..`RN-25`, y desde el ADR 0027 también `unblock`).
class FakeModerationRepository implements ModerationRepository {
  final List<String> blocked = <String>[];
  final List<({String userId, String? conversationId})> reported =
      <({String userId, String? conversationId})>[];

  /// Si no es `null`, las operaciones lanzan esto.
  Object? failWith;

  /// Se llama **después** de registrar el bloqueo. Sirve para que un test simule el efecto de
  /// `RN-22` que vive en el backend —la conversación se archiva del lado del bloqueador— cambiando
  /// lo que la bandeja devolverá la próxima vez que se le pida.
  void Function()? onBlock;

  @override
  Future<void> block(String userId) async {
    final Object? error = failWith;
    if (error != null) throw error;
    blocked.add(userId);
    onBlock?.call();
  }

  @override
  Future<void> report(String userId, {String? conversationId}) async {
    final Object? error = failWith;
    if (error != null) throw error;
    reported.add((userId: userId, conversationId: conversationId));
    // `RN-25`: reportar **ejecuta el mismo bloqueo**. En el backend los efectos salen de la misma
    // función, no de una copia; aquí se refleja igual, o un test podría afirmar que reportar deja
    // la conversación en la bandeja cuando el backend real la archiva.
    blocked.add(userId);
    onBlock?.call();
  }

  @override
  Future<void> unblock(String userId) async {
    final Object? error = failWith;
    if (error != null) throw error;
    blocked.remove(userId);
  }

  @override
  Future<List<BlockedUser>> blockedUsers() async => blocked
      .map(
        (String userId) => BlockedUser(
          profile: SocialProfileRef(userId: userId, displayName: userId),
          blockedAt: DateTime.utc(2026, 8, 20, 10),
        ),
      )
      .toList(growable: false);
}

/// Un resultado de `messaging-search` construido a mano, mensaje a mensaje.
///
/// **Se construye a mano y NO se deriva del hilo a propósito.** Toda la fuerza de los tests del
/// §9.4 está en poder devolver un resultado que **no** case con lo que el hilo contiene: así se
/// distingue una pantalla que pinta lo que el backend le manda de una que se busca la vida
/// recorriendo las burbujas con `findMatches`. Un doble que buscara dentro de [threadPageJson]
/// haría verdes las dos, que es la definición de test vacuo.
MessageSearchResult busquedaConCoincidencias({
  required List<({String messageId, List<({int start, int end})> offsets})> hits,
  int? total,
  int searchedMessages = 0,
  int searchLimit = 1000,
}) => MessageSearchResult(
  // Por defecto, `total` es la suma de OFFSETS y no el número de mensajes: un mensaje con la
  // palabra tres veces aporta tres saltos a las flechas (§9.4 y `docs/api-contracts.md`).
  total:
      total ??
      hits.fold<int>(
        0,
        (int acc, ({String messageId, List<({int start, int end})> offsets}) h) =>
            acc + h.offsets.length,
      ),
  searchedMessages: searchedMessages,
  searchLimit: searchLimit,
  hits: <MessageSearchHit>[
    for (int i = 0; i < hits.length; i++)
      MessageSearchHit(
        messageId: hits[i].messageId,
        // De más reciente a más antiguo, como los devuelve el backend.
        createdAt: DateTime.utc(2026, 8, 26, 12).subtract(Duration(minutes: i)),
        offsets: hits[i].offsets,
      ),
  ],
);

/// Doble de [AvatarRepository]: devuelve las URLs que se le den, sin red.
class FakeAvatarRepository implements AvatarRepository {
  FakeAvatarRepository({this.urls = const <String, String>{}});

  Map<String, String> urls;
  int batchCalls = 0;
  List<String> lastRequestedIds = const <String>[];

  /// Si firmar tiene que fallar. Existe porque **la degradacion a caras sin foto es una rama**, y
  /// sin modo de fallo nadie afirma que una firma rota deje la pantalla pintada en vez de vacia.
  /// Es justo lo que ocurre en produccion cuando el lote pasa del tope del endpoint y cae un 400.
  bool throwOnBatch = false;

  @override
  Future<Map<String, String>> photoUrls(List<String> userIds) async {
    batchCalls++;
    lastRequestedIds = List<String>.unmodifiable(userIds);
    if (throwOnBatch) throw Exception('no se pudo firmar');
    return <String, String>{
      for (final String id in userIds)
        if (urls[id] != null) id: urls[id]!,
    };
  }

  @override
  Future<String?> photoUrl(String userId) async => urls[userId];

  @override
  Future<String> uploadPhoto(Uint8List imageBytes, String mimeType) =>
      throw UnimplementedError();

  @override
  Future<void> setPreset(AvatarType preset) => throw UnimplementedError();
}

/// Constructor de filas de bandeja para los tests, con valores por defecto sensatos.
///
/// Los parámetros que cada test **no** menciona son los que no le importan; los que sí menciona son
/// exactamente lo que está comprobando.
ConversationSummary fakeConversation({
  required String id,
  String otherUserId = '00000000-0000-4000-8000-000000000001',
  String displayName = 'Alguien',
  AvatarType? presetAvatar,
  DateTime? lastMessageAt,
  int unreadCount = 0,
  bool pendingAcceptance = false,
  String? lastMessageContent = 'Hola',
  bool fromMe = false,
  bool deletedForAll = false,
  bool? isActive,
  bool sinUltimoMensaje = false,
}) {
  final DateTime when = lastMessageAt ?? DateTime(2026, 8, 25, 19, 24);
  return ConversationSummary(
    conversationId: id,
    otherUserId: otherUserId,
    displayName: displayName,
    presetAvatar: presetAvatar,
    lastMessageAt: when,
    unreadCount: unreadCount,
    pendingAcceptance: pendingAcceptance,
    isActive: isActive,
    lastMessage: sinUltimoMensaje
        ? null
        : LastMessagePreview(
            // OJO: con `deletedForAll: true` el contenido se conserva A PROPÓSITO, y el backend
            // real **nunca** lo manda así (`messaging-view.ts` fuerza `content: null` en cuanto hay
            // lápida). Es un fixture HOSTIL, y tiene que serlo: si aquí se pusiera `null` como hace
            // el backend, las dos ramas de la fila —fiarse de la bandera o fiarse del contenido—
            // darían el mismo resultado y el test de la lápida no distinguiría ninguna
            // implementación de la otra.
            //
            // Se descubrió mutando la fila para que ignorase la bandera: el test seguía en verde.
            content: lastMessageContent,
            fromMe: fromMe,
            createdAt: when,
            deletedForAll: deletedForAll,
          ),
  );
}

/// Doble de [FollowRepository]: registra las acciones y devuelve el estado que le digan.
class FakeFollowRepository implements FollowRepository {
  FakeFollowRepository({this.resultStatus = FollowState.pending});

  /// El estado que devuelve [toggle]. Por defecto `pending`, que es lo que deja un `request`.
  FollowState resultStatus;

  /// Si no es `null`, [toggle] lanza esto.
  Object? failWith;

  final List<({FollowAction action, String targetId})> toggles =
      <({FollowAction action, String targetId})>[];

  /// Lo que devuelven las tres lecturas. **Tres listas separadas y no una filtrada**: así un test
  /// puede poner filas distintas en cada una y detectar una pantalla que pida la lista equivocada,
  /// que es justo lo que un doble con una sola lista haría indetectable.
  List<FollowEdge> followersList = const <FollowEdge>[];
  List<FollowEdge> followingList = const <FollowEdge>[];
  List<FollowRequest> requestsList = const <FollowRequest>[];

  int followersCalls = 0;
  int followingCalls = 0;
  int requestsCalls = 0;

  @override
  Future<FollowToggleResult> toggle(FollowAction action, String targetId) async {
    toggles.add((action: action, targetId: targetId));
    final Object? error = failWith;
    if (error != null) throw error;

    // El backend REALMENTE quita la fila, así que el doble también: sin esto, una pantalla que
    // volviera a pedir la lista tras la acción seguiría viendo a quien acaba de quitar, y el test
    // fallaría por un estado que el backend no puede producir. Es el mismo criterio que el `send`
    // del doble de mensajería, que añade el mensaje al hilo.
    followersList = followersList
        .where((FollowEdge e) => e.profile.userId != targetId)
        .toList(growable: false);
    followingList = followingList
        .where((FollowEdge e) => e.profile.userId != targetId)
        .toList(growable: false);
    requestsList = requestsList
        .where((FollowRequest r) => r.profile.userId != targetId)
        .toList(growable: false);

    return FollowToggleResult(
      action: action.wireValue,
      status: resultStatus,
      conversationResumed: false,
    );
  }

  @override
  Future<List<FollowEdge>> followers(String userId) async {
    followersCalls++;
    return followersList;
  }

  @override
  Future<List<FollowEdge>> following(String userId) async {
    followingCalls++;
    return followingList;
  }

  @override
  Future<List<FollowRequest>> pendingRequests() async {
    requestsCalls++;
    return requestsList;
  }
}

/// Doble de [PublicProfileRepository]: el perfil ajeno (`RN-38`, §6.2).
///
/// **Devuelve el JSON crudo y no un [PublicProfile] ya construido**, igual que
/// [FakeMessagingRepository.threadJson] y por la misma razón: así el test pasa por
/// `PublicProfile.fromJson`, que es donde vive la interpretación de la respuesta, y **puede meter
/// campos hostiles** que la vista `public_profiles` no manda hoy. Un doble que devolviera el objeto
/// ya interpretado saltaría justo la parte que el ADR 0020 protege — y comprobar que la pantalla
/// «no pinta categorías» con un fixture que no las trae no prueba absolutamente nada.
class FakePublicProfileRepository implements PublicProfileRepository {
  FakePublicProfileRepository({Map<String, dynamic>? json, this.badge})
    : json = json ?? perfilPublicoJson();

  /// No hay ficha que enseñar: [fetch] devuelve `null`.
  ///
  /// Constructor propio y **no `json: null`**: con un parámetro opcional, «no lo he pasado» y «lo
  /// he puesto a nulo» son el mismo valor, así que el `?? perfilPublicoJson()` del constructor de
  /// arriba se tragaba el segundo y devolvía un perfil normal. El test de «no hay ficha» pasaba en
  /// verde contra una pantalla que sí encontraba a alguien.
  FakePublicProfileRepository.sinFicha() : json = null, badge = null;

  /// El cuerpo crudo. `null` = no hay ficha (`fetch` devuelve `null`).
  Map<String, dynamic>? json;

  ProfileBadge? badge;

  /// Si no es `null`, [fetch] lanza esto.
  Object? fetchFailsWith;

  /// Si no es `null`, [followState] lanza esto.
  Object? followStateFailsWith;

  /// Lo que devuelve [followState]. **Se pide aparte de la ficha a propósito**: así un test puede
  /// contar si la pantalla llegó a preguntarlo, y detectar una que suponga `none` sin mirar.
  FollowState state = FollowState.none;

  int fetchCalls = 0;
  int followStateCalls = 0;
  final List<String> fetchedIds = <String>[];

  @override
  Future<PublicProfile?> fetch(String userId) async {
    fetchCalls++;
    fetchedIds.add(userId);
    final Object? error = fetchFailsWith;
    if (error != null) throw error;
    final Map<String, dynamic>? cuerpo = json;
    if (cuerpo == null) return null;
    return PublicProfile.fromJson(cuerpo, featuredBadge: badge);
  }

  @override
  Future<FollowState> followState(String userId) async {
    followStateCalls++;
    final Object? error = followStateFailsWith;
    if (error != null) throw error;
    return state;
  }
}

/// Una fila de `public.public_profiles` tal y como la devuelve PostgREST.
///
/// Los parámetros que un test **no** menciona son los que no le importan; los que menciona son
/// exactamente lo que está comprobando.
Map<String, dynamic> perfilPublicoJson({
  String userId = '00000000-0000-4000-8000-0000000000b2',
  String displayName = 'Bruno',
  String? tag = 'bruno#K7M2QX9F',
  String? bio = 'Aquí para escuchar',
  int? age = 34,
  String? presetAvatar,
  String? photoPath,
  int level = 7,
  int streakDays = 12,
  int timeHelpingSeconds = 7200,
  int followersCount = 42,
  int followingCount = 13,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) => <String, dynamic>{
  'user_id': userId,
  'display_name': displayName,
  'tag': tag,
  'bio': bio,
  'age': age,
  'preset_avatar': presetAvatar,
  'photo_path': photoPath,
  'level': level,
  'streak_days': streakDays,
  'time_helping_seconds': timeHelpingSeconds,
  'followers_count': followersCount,
  'following_count': followingCount,
  ...extra,
};

/// El mismo perfil, pero con los datos del Art. 9 RGPD **puestos en la respuesta**.
///
/// **Es un fixture hostil, y tiene que serlo.** La vista `public_profiles` no manda ninguno de
/// estos campos —los enumera y no están en la lista—, así que un test que comprobara «la pantalla
/// no pinta categorías» con el fixture limpio de arriba **pasaría con cualquier implementación**,
/// incluida una que las pintara en cuanto llegaran. Sería vacuo por la misma razón que
/// `inputBloqueadoHostil` y que la lápida de la Tarea 20.
///
/// Lo que este fixture prueba es lo único que puede fallar de verdad: que **si el dato volviera a
/// llegar por cualquier vía —una vista mal editada, un backend futuro, un `select *`— la pantalla
/// no lo pintaría**.
Map<String, dynamic> perfilPublicoHostilJson() => perfilPublicoJson(
  extra: const <String, dynamic>{
    'birth_date': '1990-08-27',
    'gender': 'hombre',
    'country': 'ES',
    'primary_category_id': '11111111-1111-4111-8111-111111111111',
    'primary_category_slug': 'ansiedad',
    'secondary_categories': <String>['duelo', 'depresion'],
    'experience_cases': <String>['perdida-de-un-ser-querido'],
    'xp': 4321,
    'vip_status': 'gold',
    'reputation_score': 99,
    'last_seen_at': '2026-08-27T10:00:00Z',
  },
);
