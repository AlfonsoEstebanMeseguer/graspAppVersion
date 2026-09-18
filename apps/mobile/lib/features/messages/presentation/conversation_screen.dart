import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../domain/profile/avatar_type.dart';
import '../../../domain/social/message.dart';
import '../../../domain/social/message_input_state.dart';
import '../../../domain/social/social_failure.dart';
import '../application/conversation_controller.dart';
import '../../profile/presentation/public_profile_screen.dart';
import 'chat_files_screen.dart';
import 'widgets/activity_dot.dart';
import 'widgets/conversation_menu.dart';
import 'widgets/conversation_search_bar.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_composer.dart';
import 'widgets/request_actions_bar.dart';
import 'widgets/social_avatar.dart';

/// La conversación del §9.
///
/// Boceto: `06-messaging-inbox.jpeg` (derivación declarada en `pictures/screens/README.md`). De él
/// salen el radio de las burbujas, el tinte lila frente al blanco, la hora dentro de la burbuja y
/// la píldora del input con el botón circular. Lo que el boceto no tiene —es un chat de sala, con
/// todos los mensajes del mismo lado— lo pone el §9.1: propios a un lado, ajenos al otro.
///
/// ## Dos entradas, un solo estado
///
/// Se llega desde **Mensajes** con conversación, o desde **Conectar** sin ella (`RN-39`). La
/// diferencia vive entera en [ConversationArgs] y en `ConversationController.build`; a partir de
/// ahí esta pantalla pinta lo mismo.
///
/// ## Lo que devuelve al cerrarse
///
/// `true` si se llegó a enviar algo. Es lo que Conectar necesita para `RN-40` —el botón pasa a
/// `Pendiente` y **la tarjeta sigue en la lista**—, y va por el resultado del `pop` para que
/// también funcione con el botón atrás del sistema, no solo con la flecha de la cabecera.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.args});

  final ConversationArgs args;

  /// El botón de tres puntos del §9.1, que abre el menú del §9.3.
  static const Key menuKey = Key('conversation-menu-button');

  /// Lo que se enseña si el hilo no carga. **Nunca el mensaje del backend**: los literales de
  /// `_shared/http.ts` nombran tablas y policies (hallazgo H-A-02 de la auditoría de 2026-08-15).
  static const String loadError =
      'No se pudo cargar esta conversación. Vuelve a intentarlo.';

  /// El estado de una conversación recién abierta desde Conectar (`RN-39`), que todavía no tiene
  /// ni un mensaje.
  static const String emptyThread =
      'Escribe el primer mensaje para empezar la conversación.';

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  /// Dueño del texto la pantalla y no el compositor: tiene que **sobrevivir a un envío fallido**
  /// para que el reintento tenga qué reintentar, y a que el compositor cambie de forma al cambiar
  /// el estado del §9.2.
  final TextEditingController _texto = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// El término del §9.4. Vive aquí y no en el controlador por lo mismo que [_texto]: tiene que
  /// sobrevivir a que la búsqueda falle, para poder reintentarla sin volver a teclearla.
  final TextEditingController _busqueda = TextEditingController();

  /// Una clave por mensaje **construido**, para que la flecha del §9.4 pueda arrastrar la lista
  /// hasta él con `Scrollable.ensureVisible`. Se limpia sola al cerrar la búsqueda.
  final Map<String, GlobalKey> _clavesDeMensaje = <String, GlobalKey>{};

  /// La posición de búsqueda a la que ya se saltó. Se compara la POSICIÓN y no el mensaje: dos
  /// coincidencias dentro de la misma burbuja son dos saltos distintos, y comparando el id de
  /// mensaje el segundo no se notaría.
  int? _ultimoSalto;

  bool _accionEnVuelo = false;

  /// Qué edición se estaba preparando la última vez que se miró. Sirve para meter el texto
  /// original en el campo **una sola vez**, y no en cada rebuild — que borraría lo que se acabara
  /// de teclear.
  String? _editando;

  @override
  void dispose() {
    _texto.dispose();
    _busqueda.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ConversationController get _controller =>
      ref.read(conversationControllerProvider(widget.args).notifier);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ConversationView> vista = ref.watch(
      conversationControllerProvider(widget.args),
    );

    _sincronizarEdicion(vista.valueOrNull?.target);
    _sincronizarBusqueda(vista.valueOrNull?.search);

    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (bool yaSalio, bool? _) {
        if (yaSalio || !mounted) return;
        Navigator.of(context).pop(vista.valueOrNull?.sentAny ?? false);
      },
      child: Scaffold(
        backgroundColor: context.palette.canvas,
        appBar: _cabecera(vista.valueOrNull),
        body: vista.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) =>
              _Centrado(text: ConversationScreen.loadError),
          data: _cuerpo,
        ),
      ),
    );
  }

  /// Mete el texto original en el campo al empezar una edición, y lo vacía al terminarla.
  ///
  /// Va aquí y no en el `onEdit` porque el estado vive en el controlador: si el usuario sale y
  /// vuelve, o el hilo se refresca, la edición sigue en curso y el campo tiene que seguir
  /// coherente con ella.
  void _sincronizarEdicion(ComposerTarget? target) {
    final String? id = target is ComposerEdit ? target.message.id : null;
    if (id == _editando) return;

    _editando = id;
    if (target is ComposerEdit) {
      final String original = target.message.content ?? '';
      _texto
        ..text = original
        ..selection = TextSelection.collapsed(offset: original.length);
    } else {
      _texto.clear();
    }
  }

  PreferredSizeWidget _cabecera(ConversationView? vista) {
    final ConversationSearchState? busqueda = vista?.search;

    // §9.4: mientras se busca, la cabecera **es** la búsqueda. Quien busca no está mirando con
    // quién habla, y apilar las dos barras deja la conversación en una rendija.
    if (busqueda != null) {
      return PreferredSize(
        preferredSize: const Size.fromHeight(96),
        child: ConversationSearchBar(
          controller: _busqueda,
          total: busqueda.total,
          position: busqueda.position,
          searchLimit: busqueda.searchLimit,
          loading: busqueda.loading,
          onClose: _cerrarBusqueda,
          onQueryChanged: _buscar,
          // Apagadas en los extremos y sin coincidencias: una flecha viva que no lleva a ninguna
          // parte es la misma mentira pequeña que el resto de esta tarea persigue.
          onPrevious: busqueda.position >= 1 &&
                  busqueda.position < busqueda.targets.length
              ? _controller.previousMatch
              : null,
          onNext: busqueda.position > 1 ? _controller.nextMatch : null,
        ),
      );
    }

    final String nombre = vista?.displayName ?? widget.args.displayName;
    final bool? activo = vista?.isActive;

    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Volver',
        onPressed: () =>
            Navigator.of(context).pop(vista?.sentAny ?? false),
      ),
      title: _HeaderTitle(
        displayName: nombre,
        presetAvatar: vista?.presetAvatar ?? widget.args.presetAvatar,
        photoUrl: vista?.photoUrl,
        isActive: activo,
        // La tercera puerta del `RN-38`. El id sale de `widget.args` y no de `vista`: la cabecera
        // se pinta antes de que el hilo cargue, y `ConversationArgs` siempre lo trae —desde
        // Conectar todavía no hay conversación, pero sí hay persona.
        onOpenProfile: () =>
            PublicProfileScreen.open(context, widget.args.otherUserId),
      ),
      actions: <Widget>[
        IconButton(
          key: ConversationScreen.menuKey,
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'Opciones',
          onPressed: _abrirMenu,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // §9.3 — EL MENÚ DE TRES PUNTOS
  // ══════════════════════════════════════════════════════════════════════════

  /// Abre el menú del §9.3, tras leer el valor guardado de la campana.
  ///
  /// La lectura va **antes** de enseñar la hoja, y no dentro de ella: un interruptor que aparece
  /// encendido y se corrige medio segundo después le enseña a la persona un valor que no es el
  /// suyo, y con la mano ya en camino.
  Future<void> _abrirMenu() async {
    await _controller.loadNotifications();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.surface,
      // Sin esto la hoja se queda en 9/16 de la pantalla y las siete entradas del §9.3 no caben:
      // el pánico, que va el último, sería lo primero en quedarse fuera.
      isScrollControlled: true,
      // Y con la altura mandada por el contenido, en una pantalla corta la hoja llegaría al techo
      // y se pintaría bajo la barra de estado. Es el mismo fallo que se vio en `ProfileEditSheet`.
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheet) {
        // Se vuelve a leer del provider DENTRO de la hoja para que el interruptor se mueva al
        // tocarlo: la hoja vive en su propia ruta y no se reconstruye con la pantalla de debajo.
        return Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? _) {
            final ConversationView? vista = ref
                .watch(conversationControllerProvider(widget.args))
                .valueOrNull;

            return ConversationMenu(
              hasConversation: vista?.conversationId != null,
              notificationsEnabled: vista?.notificationsEnabled ?? true,
              onToggleNotifications: (bool valor) =>
                  _accion(() => _controller.setNotifications(valor)),
              onOpenFiles: () {
                Navigator.of(sheet).pop();
                _abrirArchivos();
              },
              onSearch: () {
                Navigator.of(sheet).pop();
                _controller.openSearch();
              },
              onDeleteHistory: () {
                Navigator.of(sheet).pop();
                _confirmarBorrarHistorial();
              },
              onBlock: () {
                Navigator.of(sheet).pop();
                _confirmarBloqueo();
              },
              onReport: () {
                Navigator.of(sheet).pop();
                _confirmarReporte();
              },
              onPanic: () {
                Navigator.of(sheet).pop();
                _abrirPanico();
              },
            );
          },
        );
      },
    );
  }

  void _abrirArchivos() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const ChatFilesScreen(),
      ),
    );
  }

  /// El modal del botón de pánico (§9.3 entrada 7). **No hace nada, y lo dice antes de que nadie
  /// confirme.**
  ///
  /// Un botón «Activar» que no activa nada sería mentir por implicatura, así que el cuerpo del
  /// modal empieza por lo que no ocurre y el botón solo cierra.
  Future<void> _abrirPanico() async {
    await confirmarAccion(
      context,
      title: ConversationMenu.panic,
      warning: ConversationMenu.panicUnavailable,
      confirmLabel: 'Entendido',
      confirmKey: ConversationMenu.panicConfirmKey,
      danger: false,
      // Un solo botón: ver la nota de `dismissOnly`. Con «Cancelar» al lado, la propia forma del
      // diálogo afirmaría que «Entendido» hace algo.
      dismissOnly: true,
    );
  }

  Future<void> _confirmarBorrarHistorial() async {
    final bool si = await confirmarAccion(
      context,
      title: ConversationMenu.deleteHistory,
      warning:
          'Dejarás de ver los mensajes anteriores de esta conversación. '
          'La otra persona seguirá viendo los suyos.',
      confirmLabel: 'Eliminar',
      confirmKey: ConversationMenu.deleteHistoryConfirmKey,
    );
    if (!si || !mounted) return;
    await _accion(_controller.deleteHistory);
  }

  /// `RN-22`/`RN-24`, decisión 6. El modal **está obligado** a decir dónde se deshace (ADR 0027).
  Future<void> _confirmarBloqueo() async {
    final bool si = await confirmarAccion(
      context,
      title: ConversationMenu.block,
      warning: ConversationMenu.blockWarning,
      confirmLabel: 'Bloquear',
      confirmKey: ConversationMenu.blockConfirmKey,
    );
    if (!si || !mounted) return;
    await _accion(_controller.block);
    // `RN-22` archiva la conversación del lado del bloqueador: seguir dentro de un hilo que acaba
    // de salir de la bandeja enseñaría algo que ya no está ahí. Al volver, `messages_screen`
    // vuelve a pedir la bandeja y la fila ya no aparece.
    if (mounted) Navigator.of(context).pop(false);
  }

  /// `RN-25`: reportar persiste el reporte **y ejecuta el mismo bloqueo**, así que se sale igual.
  Future<void> _confirmarReporte() async {
    final bool si = await confirmarAccion(
      context,
      title: ConversationMenu.report,
      warning: ConversationMenu.reportWarning,
      confirmLabel: 'Reportar',
      confirmKey: ConversationMenu.reportConfirmKey,
    );
    if (!si || !mounted) return;
    await _accion(_controller.report);
    if (mounted) Navigator.of(context).pop(false);
  }

  Widget _cuerpo(ConversationView vista) {
    return Column(
      children: <Widget>[
        Expanded(child: _lista(vista)),
        switch (vista.input) {
          // §9.2 fila 4: el input **se sustituye**, no se atenúa.
          MessageInputAwaitingDecision() => RequestActionsBar(
            busy: _accionEnVuelo,
            onAccept: () => _accion(_controller.accept),
            onIgnore: () => _accion(_controller.ignore),
            // Los MISMOS modales que el menú del §9.3, no unos parecidos: un segundo modal de
            // bloqueo sería un segundo sitio donde olvidar la frase obligatoria de la decisión 6.
            onBlock: _confirmarBloqueo,
            onReport: _confirmarReporte,
          ),
          _ => MessageComposer(
            controller: _texto,
            input: vista.input,
            otherDisplayName: vista.displayName,
            target: vista.target,
            onSend: _enviar,
            onCancelTarget: _controller.cancelTarget,
          ),
        },
      ],
    );
  }

  Widget _lista(ConversationView vista) {
    if (vista.messages.isEmpty) {
      return const _Centrado(text: ConversationScreen.emptyThread);
    }

    // `reverse: true` para que el hilo se abra abajo, en el mensaje más reciente, sin tener que
    // medir y saltar después. Con él, el índice 0 es el ÚLTIMO mensaje.
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        // Con la lista invertida, «arriba del todo» es el extremo del scroll: ahí es donde toca
        // pedir la página anterior (`before`).
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
            vista.hasMore &&
            !vista.loadingMore) {
          _controller.loadMore();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: vista.messages.length,
        itemBuilder: (BuildContext context, int index) {
          final Message m = vista.messages[vista.messages.length - 1 - index];
          return MessageBubble(
            key: ValueKey<String>(m.id),
            // La clave de posición es aparte de la `key` de identidad: la primera la usa el
            // `ensureVisible` del §9.4 para encontrar este widget en el árbol, y la segunda la usa
            // Flutter para reconciliar la lista. Reutilizar una sola rompería una de las dos.
            anchor: _anclaDe(m.id),
            highlights: vista.search?.highlightsFor(m.id) ??
                const <({int start, int end})>[],
            message: m,
            otherDisplayName: vista.displayName,
            photoUrl: vista.photoUrl,
            presetAvatar: vista.presetAvatar,
            onReply: _controller.startReply,
            onEdit: _controller.startEdit,
            onDeleteForMe: (Message m) => _accion(() => _controller.deleteForMe(m)),
            onDeleteForAll: (Message m) =>
                _accion(() => _controller.deleteForAll(m)),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // §9.4 — LA BÚSQUEDA
  // ══════════════════════════════════════════════════════════════════════════

  GlobalKey _anclaDe(String messageId) =>
      _clavesDeMensaje.putIfAbsent(messageId, GlobalKey.new);

  Future<void> _buscar(String termino) async {
    try {
      await _controller.search(termino);
    } on Object catch (error) {
      _avisar(error);
    }
  }

  void _cerrarBusqueda() {
    _busqueda.clear();
    _ultimoSalto = null;
    _clavesDeMensaje.clear();
    _controller.closeSearch();
  }

  /// Reacciona a que la búsqueda cambie de coincidencia: arrastra la lista hasta ella (§9.4).
  ///
  /// Se mira en `build` y no en un `listen` por lo mismo que [_sincronizarEdicion]: el estado vive
  /// en el controlador, así que basta con comparar contra lo último que se hizo.
  void _sincronizarBusqueda(ConversationSearchState? busqueda) {
    final int? posicion = busqueda == null || busqueda.position == 0
        ? null
        : busqueda.position;
    if (posicion == _ultimoSalto) return;
    _ultimoSalto = posicion;

    final String? destino = busqueda?.currentTarget?.messageId;
    if (destino == null) return;

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _asegurarVisible(destino, 0),
    );
  }

  /// Deja [messageId] a la vista, construyéndolo antes si hace falta.
  ///
  /// ## Por qué esto no es un `ensureVisible` y ya está
  ///
  /// La lista es un `ListView.builder`: **solo existe en el árbol lo que se ve**, así que una
  /// coincidencia de hace doscientos mensajes no tiene `BuildContext` al que apuntar y
  /// `Scrollable.ensureVisible` no tiene nada que hacer. Se salta primero a una posición estimada
  /// —proporcional dentro del scroll, que con la lista invertida cuenta desde el más reciente—, se
  /// deja que el builder construya ese tramo, y se reintenta. Cada salto refina además el
  /// `maxScrollExtent`, que en un `builder` es una estimación que mejora al recorrerlo, así que
  /// converge en uno o dos intentos.
  ///
  /// Y si el mensaje **no está cargado todavía**, se pide la página anterior: las flechas del §9.4
  /// recorren las coincidencias que contó el backend sobre los últimos 1000 mensajes, no las que
  /// casualmente estén en pantalla. Un contador que dice `12` con flechas que solo alcanzan cuatro
  /// es la misma mentira que el resto de esta tarea persigue.
  ///
  /// [intento] acota el bucle: sin tope, un mensaje que no aparezca nunca dejaría la pantalla
  /// pidiendo fotogramas para siempre.
  Future<void> _asegurarVisible(String messageId, int intento) async {
    if (!mounted || intento > 8) return;

    final BuildContext? ctx = _clavesDeMensaje[messageId]?.currentContext;
    if (ctx != null) {
      final GraspMotion motion =
          Theme.of(context).extension<GraspMotion>() ?? const GraspMotion();
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: motion.medium,
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final ConversationView? vista = ref
        .read(conversationControllerProvider(widget.args))
        .valueOrNull;
    if (vista == null) return;

    final int i = vista.messages.indexWhere((Message m) => m.id == messageId);
    if (i == -1) {
      // Todavía no está cargado. Sin más páginas que pedir, no hay adónde ir.
      if (!vista.hasMore || vista.loadingMore) return;
      await _controller.loadMore();
      if (!mounted) return;
      return _asegurarVisible(messageId, intento + 1);
    }

    if (!_scroll.hasClients) return;
    // Con `reverse: true` el offset 0 es el mensaje MÁS RECIENTE, así que el índice de render se
    // cuenta desde el final.
    final int render = vista.messages.length - 1 - i;
    final double maximo = _scroll.position.maxScrollExtent;
    final int tramos = vista.messages.length - 1;
    _scroll.jumpTo(
      tramos <= 0 ? 0 : (maximo * render / tramos).clamp(0.0, maximo),
    );

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _asegurarVisible(messageId, intento + 1),
    );
  }

  Future<void> _enviar() async {
    try {
      final bool salio = await _controller.send(_texto.text);
      // Solo se vacía si SALIÓ. Vaciarlo siempre haría que un fallo de red se llevara por delante
      // un mensaje largo y dejara al reintento sin nada que reintentar.
      if (salio) _texto.clear();
    } on Object catch (error) {
      _avisar(error);
    }
  }

  Future<void> _accion(Future<void> Function() accion) async {
    if (_accionEnVuelo) return;
    setState(() => _accionEnVuelo = true);
    try {
      await accion();
    } on Object catch (error) {
      _avisar(error);
    } finally {
      if (mounted) setState(() => _accionEnVuelo = false);
    }
  }

  void _avisar(Object error) {
    if (!mounted) return;
    // `SocialFailure` ya trae el texto en castellano y sin nombres de tablas; cualquier otra cosa
    // se traduce a un genérico antes de enseñarla.
    final String texto = error is SocialFailure
        ? error.message
        : ConversationScreen.loadError;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }
}

/// La foto, el nombre y el estado de actividad de la cabecera (§9.1).
///
/// Es un widget y no un `Row` incrustado en el `AppBar` por una razón concreta: así
/// [onOpenProfile] es un **parámetro declarado** y no un `onTap` escondido dentro de un árbol.
/// `RN-38` y el §6.2 quieren que tocar aquí abra el perfil ajeno, esa pantalla la construye la
/// Tarea 24, y su paso 6 encuentra los sitios que faltan por cablear **buscando el nombre de este
/// parámetro puesto a nulo**. Un `InkWell` anónimo con el toque a nulo cumpliría la regla de «un
/// botón que no hace nada se declara» de cara al lector, pero no de cara a ese grep.
class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({
    required this.displayName,
    required this.isActive,
    this.presetAvatar,
    this.photoUrl,
    this.onOpenProfile,
  });

  final String displayName;

  /// `null` = esta respuesta **no trae el dato**, que no es «desconectado» (`RN-30`).
  final bool? isActive;

  final AvatarType? presetAvatar;
  final String? photoUrl;

  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final bool? activo = isActive;
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: onOpenProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                SocialAvatar(
                  displayName: displayName,
                  presetAvatar: presetAvatar,
                  photoUrl: photoUrl,
                  size: 38,
                ),
                // `RN-30`: el punto va en la cabecera de la conversación. Con `null` no se pinta
                // ninguno, **ni siquiera gris**: un punto apagado afirma «está desconectada», y
                // eso es algo que nadie ha dicho.
                if (activo != null)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: ActivityDot(isActive: activo, size: 11),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: context.palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (activo != null)
                    Text(
                      activo ? 'Activo ahora' : 'Inactivo',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: activo
                            ? context.palette.success
                            : context.palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Centrado extends StatelessWidget {
  const _Centrado({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}
