import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/uuid_v4.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/profile/avatar_type.dart';
import '../../../domain/social/message.dart';
import '../../../domain/social/message_input_state.dart';
import '../../../domain/social/messaging_repository.dart';

/// Con qué se abre la conversación del §9.
///
/// ## Dos formas de entrar, y solo una tiene `conversationId`
///
/// Desde **Mensajes** hay conversación: se pide su hilo. Desde **Conectar** (`RN-39`) todavía no
/// existe ninguna —la crea el primer mensaje—, así que no hay nada que pedirle a
/// `messaging-thread`: llamarlo con un `conversation_id` inventado es un 400 garantizado, y con uno
/// vacío un 404.
///
/// Por eso [conversationId] es opcional y no un `String` con centinela: el tipo dice cuál de las
/// dos entradas es, y el `null` se comprueba una vez al construir el estado.
@immutable
class ConversationArgs {
  const ConversationArgs.existing({
    required String this.conversationId,
    required this.otherUserId,
    required this.displayName,
    this.presetAvatar,
  });

  /// Desde Conectar (`RN-39`): no hay conversación todavía.
  const ConversationArgs.fresh({
    required this.otherUserId,
    required this.displayName,
    this.presetAvatar,
  }) : conversationId = null;

  final String? conversationId;
  final String otherUserId;
  final String displayName;
  final AvatarType? presetAvatar;

  @override
  bool operator ==(Object other) =>
      other is ConversationArgs &&
      other.conversationId == conversationId &&
      other.otherUserId == otherUserId &&
      other.displayName == displayName &&
      other.presetAvatar == presetAvatar;

  @override
  int get hashCode =>
      Object.hash(conversationId, otherUserId, displayName, presetAvatar);
}

/// Lo que el compositor tiene apuntado: responder a un mensaje o editar uno propio.
///
/// Es un tipo sellado y no dos campos sueltos porque **son excluyentes**: con `replyingTo` y
/// `editing` como dos `Message?` independientes, el estado «editando *y* citando» es representable
/// y nadie lo impide; enviar entonces tendría que elegir uno de los dos en silencio.
@immutable
sealed class ComposerTarget {
  const ComposerTarget(this.message);

  final Message message;
}

/// Se está escribiendo una respuesta a [ComposerTarget.message] (`RN-28`).
final class ComposerReply extends ComposerTarget {
  const ComposerReply(super.message);
}

/// Se está editando [ComposerTarget.message], que es **propio** (`RN-28`).
final class ComposerEdit extends ComposerTarget {
  const ComposerEdit(super.message);
}

/// La búsqueda del §9.4 mientras está abierta.
///
/// ## Todo lo que se pinta sale de [result], y nunca del hilo
///
/// Es la decisión que gobierna el fichero. §9.4 dice que la búsqueda **no encuentra nada en
/// mensajes borrados para mí, ni anteriores a mi `cleared_at`, ni en lápidas**, y esas tres reglas
/// las conoce `messaging-search` —que las reutiliza de `projectMessages`— y no el cliente:
/// `deleted_for` no viaja proyectado y `cleared_at` vive en `conversation_states`. Una pantalla que
/// se buscara la vida recorriendo las burbujas con `findMatches` resaltaría un mensaje que quien
/// mira ya no debería poder encontrar.
///
/// Por eso aquí no hay ni una llamada a `findMatches`: [MatchOffset] existe para lo que **no** pasa
/// por esta llamada (resaltar una fila que entra por `stream()` con la búsqueda abierta), y ese
/// camino no lo estrena la Tarea 23.
@immutable
class ConversationSearchState {
  const ConversationSearchState({
    this.query = '',
    this.result,
    this.position = 0,
    this.loading = false,
  });

  final String query;

  /// Lo que devolvió `messaging-search`. `null` = todavía no se ha buscado nada.
  final MessageSearchResult? result;

  /// Posición actual **1-based** dentro de [targets]. `0` = ninguna.
  final int position;

  final bool loading;

  /// El `12` de `3/12`: **coincidencias**, no mensajes (§9.4).
  int get total => result?.total ?? 0;

  /// La cota que aplicó el backend. `null` mientras no haya respuesta: la cabecera no puede
  /// anunciar un número que todavía no conoce, y escribir `1000` a mano seguiría diciendo 1000 el
  /// día que el backend cambiara la cota.
  int? get searchLimit => result?.searchLimit;

  /// Las coincidencias **aplanadas**: una entrada por cada offset, no por cada mensaje.
  ///
  /// Aplanadas porque las flechas del §9.4 saltan entre *coincidencias*: un mensaje con la palabra
  /// tres veces son tres saltos, y una lista por mensaje se saltaría dos de cada tres.
  List<({String messageId, int start, int end})> get targets =>
      <({String messageId, int start, int end})>[
        for (final MessageSearchHit hit in result?.hits ?? const <MessageSearchHit>[])
          for (final ({int start, int end}) o in hit.offsets)
            (messageId: hit.messageId, start: o.start, end: o.end),
      ];

  ({String messageId, int start, int end})? get currentTarget {
    final List<({String messageId, int start, int end})> t = targets;
    if (position < 1 || position > t.length) return null;
    return t[position - 1];
  }

  /// Los tramos a resaltar dentro de [messageId], **tal y como los mandó el backend**.
  ///
  /// Se devuelven sin tocar: son offsets del texto ORIGINAL y en unidades UTF-16, y recalcularlos
  /// aquí con otra normalización los desplaza — el fallo que `_shared/text-search.ts` documenta
  /// arriba del todo.
  List<({int start, int end})> highlightsFor(String messageId) =>
      <({int start, int end})>[
        for (final MessageSearchHit hit in result?.hits ?? const <MessageSearchHit>[])
          if (hit.messageId == messageId) ...hit.offsets,
      ];

  ConversationSearchState copyWith({
    String? query,
    MessageSearchResult? result,
    bool limpiarResult = false,
    int? position,
    bool? loading,
  }) => ConversationSearchState(
    query: query ?? this.query,
    result: limpiarResult ? null : (result ?? this.result),
    position: position ?? this.position,
    loading: loading ?? this.loading,
  );
}

/// La conversación entera lista para pintar.
@immutable
class ConversationView {
  const ConversationView({
    required this.otherUserId,
    required this.displayName,
    required this.messages,
    required this.input,
    required this.hasMore,
    this.conversationId,
    this.presetAvatar,
    this.photoUrl,
    this.isActive,
    this.nextBefore,
    this.target,
    this.sentAny = false,
    this.loadingMore = false,
    this.notificationsEnabled,
    this.search,
  });

  /// `null` mientras se entra desde Conectar y no se ha escrito nada (`RN-39`).
  final String? conversationId;

  final String otherUserId;
  final String displayName;
  final AvatarType? presetAvatar;

  /// URL firmada de la foto. Caduca en 300 s; se pide una vez al abrir.
  final String? photoUrl;

  /// `null` = esta respuesta no trae el dato, que **no** es lo mismo que «inactivo» (`RN-30`).
  final bool? isActive;

  /// Orden **cronológico ascendente**, como los devuelve el backend.
  final List<Message> messages;

  final MessageInputState input;
  final bool hasMore;
  final String? nextBefore;

  /// La cita o la edición en curso.
  final ComposerTarget? target;

  /// `RN-40`: si se ha llegado a enviar algo. Es lo que Conectar necesita saber al volver, y por
  /// eso viaja en el estado y no en una variable de la pantalla: sobrevive a un rebuild.
  final bool sentAny;

  final bool loadingMore;

  /// El valor guardado de la campana (§9.3 punto 1). `null` = **todavía no se ha leído**, que no es
  /// «apagadas»: se pide al abrir el menú y no al abrir la conversación, porque es lo único que lo
  /// mira y una conversación se abre muchas más veces que su menú.
  final bool? notificationsEnabled;

  /// `null` mientras la búsqueda del §9.4 está cerrada.
  final ConversationSearchState? search;

  ConversationView copyWith({
    String? conversationId,
    List<Message>? messages,
    MessageInputState? input,
    bool? hasMore,
    String? nextBefore,
    ComposerTarget? target,
    bool limpiarTarget = false,
    bool? sentAny,
    bool? loadingMore,
    bool? isActive,
    String? photoUrl,
    bool? notificationsEnabled,
    ConversationSearchState? search,
    bool cerrarBusqueda = false,
  }) => ConversationView(
    conversationId: conversationId ?? this.conversationId,
    otherUserId: otherUserId,
    displayName: displayName,
    presetAvatar: presetAvatar,
    photoUrl: photoUrl ?? this.photoUrl,
    isActive: isActive ?? this.isActive,
    messages: messages ?? this.messages,
    input: input ?? this.input,
    hasMore: hasMore ?? this.hasMore,
    nextBefore: nextBefore ?? this.nextBefore,
    target: limpiarTarget ? null : (target ?? this.target),
    sentAny: sentAny ?? this.sentAny,
    loadingMore: loadingMore ?? this.loadingMore,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    search: cerrarBusqueda ? null : (search ?? this.search),
  );
}

/// La conversación del §9: carga el hilo, envía, edita, borra y escucha el tiempo real.
class ConversationController
    extends AutoDisposeFamilyAsyncNotifier<ConversationView, ConversationArgs> {
  /// La clave de idempotencia **del mensaje que se está intentando enviar**.
  ///
  /// Vive aquí y no dentro de [send] porque el invariante de `CLAUDE.md` dice que quien llama la
  /// genera **una vez** y la conserva durante los reintentos. Generarla dentro de `send` es
  /// exactamente lo mismo que no tenerla: el reintento del quinto mensaje se evaluaría como el
  /// sexto y devolvería un 422 por un mensaje que sí se entregó.
  ///
  /// Se pone a `null` cuando el envío triunfa, para que el siguiente mensaje estrene la suya.
  String? _idempotencyKey;

  StreamSubscription<List<Message>>? _realtime;

  MessagingRepository get _repo => ref.read(messagingRepositoryProvider);

  @override
  Future<ConversationView> build(ConversationArgs args) async {
    ref.onDispose(() => _realtime?.cancel());

    final String? conversationId = args.conversationId;

    // Desde Conectar no hay hilo que pedir. El estado del input se construye en el cliente porque
    // no hay backend a quien preguntárselo, y `MessageInputState.newConversation` existe justo
    // para que ese valor coincida con el que devolverá `messaging-thread` en cuanto haya
    // conversación.
    if (conversationId == null) {
      return ConversationView(
        otherUserId: args.otherUserId,
        displayName: args.displayName,
        presetAvatar: args.presetAvatar,
        photoUrl: await _foto(args.otherUserId),
        messages: const <Message>[],
        input: MessageInputState.newConversation,
        hasMore: false,
      );
    }

    final MessageThreadPage page = await _repo.thread(conversationId);
    _escuchar(conversationId);

    // `RN-31`: el contador es **estrictamente local del receptor**. Ponerlo a cero al abrir no
    // toca ninguna fila del otro ni le dice nada; sin esta llamada, el badge de la barra nunca
    // bajaría y el mecanismo no tendría puerta de entrada.
    if (page.unreadCount > 0) unawaited(_marcarLeido(conversationId));

    return ConversationView(
      conversationId: conversationId,
      otherUserId: page.otherUserId.isNotEmpty
          ? page.otherUserId
          : args.otherUserId,
      displayName: page.displayName.isNotEmpty
          ? page.displayName
          : args.displayName,
      presetAvatar: args.presetAvatar,
      photoUrl: await _foto(args.otherUserId),
      isActive: page.isActive,
      messages: page.messages,
      input: page.input,
      hasMore: page.hasMore,
      nextBefore: page.nextBefore,
    );
  }

  Future<String?> _foto(String userId) async {
    try {
      final Map<String, String> urls = await ref
          .read(avatarRepositoryProvider)
          .photoUrls(<String>[userId]);
      return urls[userId];
    } on Object {
      // Que no se pueda firmar una foto no puede dejar sin conversación a nadie: se pinta la
      // inicial y el hilo sigue siendo utilizable.
      return null;
    }
  }

  Future<void> _marcarLeido(String conversationId) async {
    try {
      await _repo.conversationAction(
        conversationId,
        ConversationAction.markRead,
      );
    } on Object {
      // Un contador que no baja es molesto; una conversación que no abre por eso, inaceptable.
    }
  }

  /// Escucha `direct_messages` y **refresca el hilo proyectado** en cuanto aparece algo que no
  /// tenemos.
  ///
  /// No pinta lo que llega. Las filas del stream son **crudas**: no pasan por `projectMessages`,
  /// así que no llevan aplicado el `cleared_at` de `RN-27` —que vive en `conversation_states` y no
  /// viaja con la fila— ni las citas resueltas contra su prueba de visibilidad. Pintarlas
  /// directamente haría reaparecer mensajes que quien mira ya no puede ver, que es justo lo que
  /// `RN-27` promete que no pasa. El stream sirve para **saber que hay algo nuevo**; la verdad la
  /// da `thread()`.
  void _escuchar(String conversationId) {
    _realtime?.cancel();
    _realtime = _repo
        .watchMessages(conversationId)
        .listen(
          (List<Message> filas) {
            final ConversationView? actual = state.valueOrNull;
            if (actual == null) return;

            final Set<String> conocidos = actual.messages
                .map((Message m) => m.id)
                .toSet();
            final bool hayAlgoNuevo = filas.any(
              (Message m) => !conocidos.contains(m.id),
            );
            if (hayAlgoNuevo) unawaited(_refrescarCabeza(conversationId));
          },
          // Que se caiga el tiempo real deja la conversación estática, no rota.
          onError: (Object _) {},
        );
  }

  /// Vuelve a pedir la primera página y la funde con lo que ya hubiera.
  ///
  /// Fundir y no reemplazar: quien haya paginado hacia atrás tiene mensajes más antiguos que esta
  /// página no trae, y reemplazar se los borraría de la pantalla a mitad de lectura.
  Future<void> _refrescarCabeza(String conversationId) async {
    try {
      final MessageThreadPage page = await _repo.thread(conversationId);
      final ConversationView? actual = state.valueOrNull;
      if (actual == null) return;

      state = AsyncValue<ConversationView>.data(
        actual.copyWith(
          messages: _fundir(actual.messages, page.messages),
          input: page.input,
          hasMore: page.hasMore,
        ),
      );
    } on Object {
      // Un refresco fallido no puede tirar una conversación que ya está pintada.
    }
  }

  /// Conserva lo anterior a [frescos] y **deja que la página nueva mande** en su propio tramo.
  ///
  /// Que mande la nueva es lo que hace que un borrado o una edición se vean: un `merge` que
  /// prefiriera lo que ya estaba pintado dejaría la lápida sin aparecer hasta salir y volver a
  /// entrar. Y lo que la página nueva **no** trae dentro de su tramo se va, que es como se aplica
  /// un borrado «para mí».
  static List<Message> _fundir(List<Message> previos, List<Message> frescos) {
    // Una cabeza vacía **no** es «no hay novedades»: `thread()` sin `before` devuelve la ventana
    // MÁS RECIENTE, así que vacía significa que el backend ya no proyecta nada — es exactamente lo
    // que se ve tras borrar «para mí» el último mensaje que quedaba, o tras vaciar el historial
    // (`RN-27`). Conservar lo anterior dejaría en pantalla justo lo que se acaba de borrar.
    if (frescos.isEmpty) return const <Message>[];

    final DateTime corte = frescos.first.createdAt;
    return <Message>[
      ...previos.where((Message m) => m.createdAt.isBefore(corte)),
      ...frescos,
    ];
  }

  /// Envía, o **guarda la edición en curso** si la hay (`RN-28`).
  ///
  /// Devuelve `true` si el texto salió, para que el compositor sepa si puede vaciarse. Ante un
  /// fallo devuelve `false` y **conserva la clave de idempotencia**: sin texto y sin clave no hay
  /// reintento posible, solo un mensaje perdido.
  Future<bool> send(String texto) async {
    final ConversationView? actual = state.valueOrNull;
    if (actual == null) return false;

    // El backend recorta y mide sobre el texto recortado (`normalizeMessageContent`). Medir aquí
    // sobre el crudo dejaría pasar un mensaje de solo espacios, que allí es un 400.
    final String content = texto.trim();
    if (content.isEmpty) return false;

    final ComposerTarget? target = actual.target;
    if (target is ComposerEdit) return _guardarEdicion(target.message, content);

    if (!actual.input.canType) return false;

    final String key = _idempotencyKey ??= newUuidV4();

    try {
      final ({Message message, int? messagesLeft, bool idempotentReplay}) res =
          await _repo.send(
            recipientId: actual.otherUserId,
            content: content,
            idempotencyKey: key,
            replyToId: target is ComposerReply ? target.message.id : null,
          );

      _idempotencyKey = null;

      final ConversationView vivo = state.valueOrNull ?? actual;
      final String? conversationId = vivo.conversationId;

      // Primer mensaje desde Conectar: hasta ahora no había conversación a la que suscribirse.
      // Ahora sí, y hay que pedir el hilo entero —no basta con añadir la burbuja optimista—
      // porque el estado del input lo decide el backend y aquí acaba de cambiar.
      if (conversationId == null) {
        state = AsyncValue<ConversationView>.data(
          vivo.copyWith(
            messages: <Message>[...vivo.messages, res.message],
            input: _tras(vivo.input, res.messagesLeft),
            sentAny: true,
            limpiarTarget: true,
          ),
        );
        return true;
      }

      state = AsyncValue<ConversationView>.data(
        vivo.copyWith(
          messages: <Message>[...vivo.messages, res.message],
          input: _tras(vivo.input, res.messagesLeft),
          sentAny: true,
          limpiarTarget: true,
        ),
      );

      // Y se pide la verdad proyectada: la burbuja optimista no lleva la cita resuelta, que solo
      // el backend puede montar contra su prueba de visibilidad.
      unawaited(_refrescarCabeza(conversationId));
      return true;
    } on Object {
      // La clave NO se toca: el reintento tiene que llevar la misma.
      await _refrescarInput();
      rethrow;
    }
  }

  /// El input tras un envío, con lo que el backend acaba de decir que queda (`RN-01`).
  ///
  /// Se deriva del **veredicto** que vino en la respuesta y no restando uno al contador local: el
  /// `0` de un cupo agotado y el `0` de un bloqueo son el mismo byte a propósito (`RN-23`), y una
  /// resta local reconstruiría la diferencia que el backend se niega a emitir.
  static MessageInputState _tras(MessageInputState previo, int? messagesLeft) {
    if (messagesLeft == null) return previo;
    if (messagesLeft <= 0) return const MessageInputInert(kMessageInputNotice);
    return MessageInputLimited(messagesLeft);
  }

  Future<bool> _guardarEdicion(Message original, String content) async {
    // Editar con el mismo texto es un no-op: el tag «editado» lo ven los dos, y ponerlo por un
    // guardado idéntico diría que hubo una edición que no hubo.
    if (content == original.content) {
      _limpiarTarget();
      return true;
    }

    await _repo.messageAction(
      original.id,
      MessageAction.edit,
      content: content,
    );
    _limpiarTarget();
    await _recargar();
    return true;
  }

  /// `RN-28`: quita el mensaje **de mi lado**. Vale para cualquier participante, autor o no.
  Future<void> deleteForMe(Message message) async {
    await _repo.messageAction(message.id, MessageAction.deleteForMe);
    await _recargar();
  }

  /// `RN-28`: lápida para los dos. **Solo el autor**, y por eso la pantalla no ofrece el botón
  /// sobre un mensaje ajeno — el backend lo rechazaría igual.
  Future<void> deleteForAll(Message message) async {
    await _repo.messageAction(message.id, MessageAction.deleteForAll);
    await _recargar();
  }

  /// `RN-05`: la conversación pasa a Contactos y los dos escriben sin tope.
  Future<void> accept() => _accionDeConversacion(ConversationAction.accept);

  /// `RN-06`: desaparece de mis Solicitudes. **El emisor no se entera de nada**.
  Future<void> ignore() => _accionDeConversacion(ConversationAction.ignore);

  Future<void> _accionDeConversacion(ConversationAction action) async {
    final String? conversationId = state.valueOrNull?.conversationId;
    if (conversationId == null) return;
    await _repo.conversationAction(conversationId, action);
    await _recargar();
  }

  // ── §9.3 — el menú de tres puntos ─────────────────────────────────────────

  /// Lee el valor guardado de la campana y lo deja en el estado (§9.3 punto 1).
  ///
  /// Se llama **al abrir el menú**, que es lo único que lo mira. Ante un fallo se asume `true`, el
  /// `default` de la columna: un menú que no abre porque no se pudo leer un ajuste cosmético sería
  /// peor que un toggle que empieza donde empieza la columna.
  Future<void> loadNotifications() async {
    final ConversationView? actual = state.valueOrNull;
    final String? conversationId = actual?.conversationId;
    if (actual == null || conversationId == null) return;

    bool valor = true;
    try {
      valor = await _repo.notificationsEnabled(conversationId);
    } on Object {
      // Se queda en el `default`.
    }
    final ConversationView vivo = state.valueOrNull ?? actual;
    state = AsyncValue<ConversationView>.data(
      vivo.copyWith(notificationsEnabled: valor),
    );
  }

  /// Persiste el toggle (§9.3 punto 1). **Sin efecto funcional**: no hay push todavía.
  ///
  /// El booleano viaja obligatoriamente: `messaging-actions` devuelve 400 si llega sin él, en vez
  /// de asumir un valor por defecto. Se pinta el valor nuevo antes de la llamada para que el
  /// interruptor no se quede quieto bajo el dedo, y se deshace si la llamada falla — un toggle que
  /// se queda encendido tras un error diría que guardó algo que no guardó.
  Future<void> setNotifications(bool enabled) async {
    final ConversationView? actual = state.valueOrNull;
    final String? conversationId = actual?.conversationId;
    if (actual == null || conversationId == null) return;

    state = AsyncValue<ConversationView>.data(
      actual.copyWith(notificationsEnabled: enabled),
    );
    try {
      await _repo.conversationAction(
        conversationId,
        ConversationAction.setNotifications,
        notificationsEnabled: enabled,
      );
    } on Object {
      final ConversationView vivo = state.valueOrNull ?? actual;
      state = AsyncValue<ConversationView>.data(
        vivo.copyWith(notificationsEnabled: !enabled),
      );
      rethrow;
    }
  }

  /// `RN-27`: `cleared_at = now()` + archivada, **solo de quien lo pide**.
  Future<void> deleteHistory() =>
      _accionDeConversacion(ConversationAction.deleteHistory);

  /// `RN-22`/`RN-24`: bloquea, y la conversación se archiva del lado del bloqueador.
  ///
  /// Se puede deshacer (ADR 0027): `ModerationRepository.unblock` existe desde el 2026-08-28. Quien
  /// llame a esto tiene que haber enseñado antes el modal que dice dónde se deshace.
  Future<void> block() async {
    final ConversationView? actual = state.valueOrNull;
    if (actual == null) return;
    await ref.read(moderationRepositoryProvider).block(actual.otherUserId);
  }

  /// `RN-25`: persiste el reporte y **ejecuta el mismo bloqueo**.
  ///
  /// El `conversation_id` va solo si existe: es el enlace de contexto que un humano de la cola de
  /// moderación abriría, y `report-create` devuelve 404 si no es de quien reporta — así que
  /// inventárselo desde Conectar (`RN-39`, todavía sin hilo) sería un 404 garantizado.
  Future<void> report() async {
    final ConversationView? actual = state.valueOrNull;
    if (actual == null) return;
    await ref
        .read(moderationRepositoryProvider)
        .report(actual.otherUserId, conversationId: actual.conversationId);
  }

  // ── §9.4 — la búsqueda ────────────────────────────────────────────────────

  void openSearch() {
    final ConversationView? actual = state.valueOrNull;
    if (actual == null || actual.conversationId == null) return;
    state = AsyncValue<ConversationView>.data(
      actual.copyWith(search: const ConversationSearchState()),
    );
  }

  void closeSearch() {
    final ConversationView? actual = state.valueOrNull;
    if (actual == null) return;
    state = AsyncValue<ConversationView>.data(
      actual.copyWith(cerrarBusqueda: true),
    );
  }

  /// Busca [query] y **se coloca en la coincidencia más reciente**.
  ///
  /// La cota, el filtrado por `cleared_at`/`deleted_for`/lápidas y los offsets los pone entero
  /// `messaging-search`: aquí no se recuenta ni se recalcula nada.
  Future<void> search(String query) async {
    final ConversationView? actual = state.valueOrNull;
    final String? conversationId = actual?.conversationId;
    if (actual == null || conversationId == null || actual.search == null) {
      return;
    }

    final String termino = query.trim();
    if (termino.isEmpty) {
      state = AsyncValue<ConversationView>.data(
        actual.copyWith(
          search: const ConversationSearchState(),
        ),
      );
      return;
    }

    state = AsyncValue<ConversationView>.data(
      actual.copyWith(
        search: actual.search!.copyWith(query: termino, loading: true),
      ),
    );

    try {
      final MessageSearchResult res = await _repo.search(
        conversationId,
        termino,
      );
      final ConversationView vivo = state.valueOrNull ?? actual;
      final ConversationSearchState? abierta = vivo.search;
      // Si la búsqueda se cerró mientras la respuesta venía de camino, no se reabre.
      if (abierta == null) return;

      state = AsyncValue<ConversationView>.data(
        vivo.copyWith(
          search: abierta.copyWith(
            result: res,
            loading: false,
            position: res.total > 0 ? 1 : 0,
          ),
        ),
      );
    } on Object {
      final ConversationView vivo = state.valueOrNull ?? actual;
      final ConversationSearchState? abierta = vivo.search;
      if (abierta == null) return;
      state = AsyncValue<ConversationView>.data(
        vivo.copyWith(
          search: abierta.copyWith(loading: false, limpiarResult: true, position: 0),
        ),
      );
      rethrow;
    }
  }

  /// Hacia una coincidencia **más antigua**. Las del backend vienen de más reciente a más antigua,
  /// así que «arriba» en la conversación es **avanzar** en esa lista.
  void previousMatch() => _moverBusqueda(1);

  /// Hacia una coincidencia **más reciente**.
  void nextMatch() => _moverBusqueda(-1);

  void _moverBusqueda(int delta) {
    final ConversationView? actual = state.valueOrNull;
    final ConversationSearchState? busqueda = actual?.search;
    if (actual == null || busqueda == null) return;

    final int destino = busqueda.position + delta;
    if (destino < 1 || destino > busqueda.targets.length) return;
    state = AsyncValue<ConversationView>.data(
      actual.copyWith(search: busqueda.copyWith(position: destino)),
    );
  }

  void startReply(Message message) => _ponerTarget(ComposerReply(message));

  void startEdit(Message message) => _ponerTarget(ComposerEdit(message));

  void cancelTarget() => _limpiarTarget();

  void _ponerTarget(ComposerTarget target) {
    final ConversationView? actual = state.valueOrNull;
    if (actual == null) return;
    state = AsyncValue<ConversationView>.data(actual.copyWith(target: target));
  }

  void _limpiarTarget() {
    final ConversationView? actual = state.valueOrNull;
    if (actual == null) return;
    state = AsyncValue<ConversationView>.data(
      actual.copyWith(limpiarTarget: true),
    );
  }

  /// Página anterior (`before`). El cursor se reenvía **tal cual**: sale de la fila cruda más
  /// antigua y no del mensaje proyectado, porque la proyección descarta filas (`RN-27`, `RN-28`) y
  /// un cursor sacado de la lista ya filtrada saltaría por encima de ellas.
  Future<void> loadMore() async {
    final ConversationView? actual = state.valueOrNull;
    final String? conversationId = actual?.conversationId;
    final String? before = actual?.nextBefore;
    if (actual == null || conversationId == null || before == null) return;
    if (!actual.hasMore || actual.loadingMore) return;

    state = AsyncValue<ConversationView>.data(
      actual.copyWith(loadingMore: true),
    );
    try {
      final MessageThreadPage page = await _repo.thread(
        conversationId,
        before: before,
      );
      final ConversationView vivo = state.valueOrNull ?? actual;
      state = AsyncValue<ConversationView>.data(
        vivo.copyWith(
          messages: <Message>[...page.messages, ...vivo.messages],
          hasMore: page.hasMore,
          nextBefore: page.nextBefore,
          loadingMore: false,
        ),
      );
    } on Object {
      final ConversationView vivo = state.valueOrNull ?? actual;
      state = AsyncValue<ConversationView>.data(
        vivo.copyWith(loadingMore: false),
      );
    }
  }

  /// Vuelve a pedir el hilo conservando lo que la pantalla ya tiene alrededor.
  Future<void> _recargar() async {
    final String? conversationId = state.valueOrNull?.conversationId;
    if (conversationId == null) return;
    await _refrescarCabeza(conversationId);
  }

  /// Tras un envío fallido, el input puede haber cambiado (un 422 de `RN-01`/`RN-18`/`RN-19`).
  Future<void> _refrescarInput() async {
    final String? conversationId = state.valueOrNull?.conversationId;
    if (conversationId == null) return;
    await _refrescarCabeza(conversationId);
  }
}

final AutoDisposeAsyncNotifierProviderFamily<
  ConversationController,
  ConversationView,
  ConversationArgs
>
conversationControllerProvider =
    AsyncNotifierProvider.autoDispose
        .family<ConversationController, ConversationView, ConversationArgs>(
          ConversationController.new,
        );
