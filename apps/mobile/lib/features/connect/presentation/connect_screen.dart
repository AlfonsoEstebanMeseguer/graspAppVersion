import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../domain/social/connect_candidate.dart';
import '../../messages/application/conversation_controller.dart';
import '../../profile/presentation/public_profile_screen.dart';
import '../application/connect_controller.dart';
import '../application/tag_search_controller.dart';
import 'widgets/connect_card.dart';
import 'widgets/connect_filter_chips.dart';
import 'widgets/tag_result_card.dart';
import 'widgets/tag_search_field.dart';

/// Pestaña **Conectar** — §6 de la spec.
///
/// Boceto: `pictures/screens/03-feed-rooms.jpeg`, que es literalmente la pantalla que sustituye —
/// buscador arriba, fila de píldoras y lista vertical—; cambia lo que va dentro de cada fila.
///
/// **Su nombre anterior no aparece aquí a propósito.** El primer criterio del §12 es que no exista
/// en ninguna parte del código, y hay un test que recorre `lib/` buscándolo: escribirlo, aunque
/// fuera para contar la historia, haría fallar esa comprobación.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  /// `RN-49`: **nunca una lista vacía sin explicación**.
  static const String emptyState =
      'Ahora mismo no hay nadie nuevo que mostrarte. Vuelve a intentarlo más tarde.';

  /// `RN-49` + ADR 0024: la tanda se puntuó sin dar tanto peso al filtro. Hay que decirlo o
  /// parecerá que el filtro no funciona.
  static const String relaxedNotice =
      'Había pocas personas con ese filtro, así que también te mostramos otras.';

  /// §6.2. **El mismo texto para «no existe» y para «hay bloqueo»** (`RN-23`), pintado con el mismo
  /// widget y sin rama propia: una rama distinta acaba divergiendo en un detalle visible.
  static const String tagNotFound = 'No existe ningún usuario con ese tag.';

  static const String loadError =
      'No se pudo cargar. Desliza hacia abajo para reintentar.';

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  Set<ConnectFilter> _filters = const <ConnectFilter>{};

  /// Si la pestaña estaba visible en la pasada anterior. `null` = todavía no se sabe.
  bool? _wasVisible;

  /// `RN-37` — «el filtro no persiste: cada vez que se **entra** en Conectar se resetea a `Todos`».
  ///
  /// ## Por qué no basta con reiniciarlo en `initState`
  ///
  /// El shell es `StatefulShellRoute.indexedStack`: **las cuatro ramas siguen montadas** al cambiar
  /// de pestaña. Ir a Mensajes y volver **no desmonta** esta pantalla, así que un filtro guardado en
  /// el `State` sobreviviría — y eso es exactamente lo que `RN-37` prohíbe.
  ///
  /// `TickerMode` es la señal: go_router envuelve cada rama en un `Visibility`, que apaga el
  /// `TickerMode` de las que no se ven. Es API pública y cambia justo cuando la pestaña entra y
  /// sale, que es lo que aquí significa «entrar en Conectar».
  ///
  /// **Y no se confía en el mecanismo, se confía en el test**: `connect_filters_test.dart` monta el
  /// router entero, cambia de pestaña y vuelve. Si algún día `TickerMode` deja de servir, ese test
  /// se pone rojo — el de desmontar y remontar, que es el que pedía el plan, seguiría pasando.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // `valuesOf` y no el `of` de siempre: `TickerMode.of` está deprecado desde 3.35. Solo interesa
    // `enabled`, que es lo que apaga `Visibility` en la rama que no se ve.
    final bool visible = TickerMode.valuesOf(context).enabled;
    final bool? antes = _wasVisible;
    _wasVisible = visible;

    if (antes == false && visible && _filters.isNotEmpty) {
      // Después del frame: tocar un provider durante `didChangeDependencies` lanza en Riverpod.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) return;
        setState(() => _filters = const <ConnectFilter>{});
        ref.read(connectControllerProvider.notifier).resetFilters();
      });
    }
  }

  void _onFiltersChanged(Set<ConnectFilter> next) {
    setState(() => _filters = next);
    ref.read(connectControllerProvider.notifier).applyFilters(next);
  }

  @override
  Widget build(BuildContext context) {
    final TagSearchState search = ref.watch(tagSearchControllerProvider);

    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: AppBar(title: const Text('Conectar')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            TagSearchField(
              onSubmit: (String tag) =>
                  ref.read(tagSearchControllerProvider.notifier).search(tag),
              onClear: () =>
                  ref.read(tagSearchControllerProvider.notifier).clear(),
            ),
            // Los chips solo tienen sentido sobre el feed: con una búsqueda por tag en pantalla no
            // filtran nada, y dejarlos activos haría creer que sí.
            if (search is TagSearchIdle)
              ConnectFilterChips(
                selected: _filters,
                onChanged: _onFiltersChanged,
              ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: search is TagSearchIdle
                  ? _Feed(filtersActive: _filters.isNotEmpty)
                  : _SearchResult(state: search),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResult extends ConsumerWidget {
  const _SearchResult({required this.state});

  final TagSearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      TagSearchIdle() => const SizedBox.shrink(),
      TagSearchLoading() => const Center(child: CircularProgressIndicator()),
      // «No existe» y «hay bloqueo» comparten este widget y este texto. No hay dos ramas porque no
      // hay dos datos: el repositorio devuelve `null` en los dos casos (RN-23).
      TagSearchNotFound() => const _Notice(text: ConnectScreen.tagNotFound),
      TagSearchError(:final String message) => _Notice(text: message),
      TagSearchFound(:final result, :final followState) => ListView(
        children: <Widget>[
          TagResultCard(
            result: result,
            followState: followState,
            onFollow: () =>
                ref.read(tagSearchControllerProvider.notifier).follow(),
            onOpenProfile: () =>
                PublicProfileScreen.open(context, result.userId),
          ),
        ],
      ),
    };
  }
}

class _Feed extends ConsumerWidget {
  const _Feed({required this.filtersActive});

  final bool filtersActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ConnectFeedView> feed = ref.watch(connectControllerProvider);

    return RefreshIndicator(
      color: context.palette.brandStrong,
      onRefresh: () => ref.read(connectControllerProvider.notifier).refresh(),
      child: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) =>
            const _Notice(text: ConnectScreen.loadError),
        data: (ConnectFeedView view) =>
            _FeedList(view: view, filtersActive: filtersActive),
      ),
    );
  }
}

/// `RN-39`: abre la conversación para escribir el **primer** mensaje.
///
/// Se entra **sin `conversation_id`**, porque todavía no hay ninguna: la crea el primer mensaje
/// (§4.2). Eso lo dice `ConversationArgs.fresh`.
///
/// Al volver, `RN-40`: si se llegó a enviar algo, el botón pasa a `Pendiente` y **la tarjeta sigue
/// en la lista** —desaparece «en el siguiente refresco», que es cuando `connect-feed` la excluirá
/// por `RN-47`(3)—. Quitarla ya dejaría a quien escribe sin la confirmación de que su mensaje salió.
///
/// El aviso llega por el resultado del `pop` y no por un callback metido en `extra`: así también
/// funciona con el botón atrás del sistema, que es como se sale de un chat la mayoría de las veces.
Future<void> _abrirChat(
  BuildContext context,
  WidgetRef ref,
  ConnectCandidate c,
) async {
  final bool? enviado = await context.push<bool>(
    AppRoute.conversation,
    extra: ConversationArgs.fresh(
      otherUserId: c.userId,
      displayName: c.displayName,
      presetAvatar: c.presetAvatar,
    ),
  );
  if (enviado != true || !context.mounted) return;
  ref.read(connectControllerProvider.notifier).markMessaged(c.userId);
}

class _FeedList extends ConsumerWidget {
  const _FeedList({required this.view, required this.filtersActive});

  final ConnectFeedView view;

  /// Si hay algún chip encendido. Decide si el aviso de `relaxed` tiene sentido — ver abajo.
  final bool filtersActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view.candidates.isEmpty) {
      return const _Notice(text: ConnectScreen.emptyState);
    }

    // Los avisos van como primer elemento de la lista para que sigan siendo scrolleables y el
    // `RefreshIndicator` funcione encima de ellos.
    final List<Widget> header = <Widget>[
      if (view.notice != null) _InlineNotice(text: view.notice!),
      // EL AVISO SOLO TIENE SENTIDO SI HAY UN FILTRO QUE RELAJAR.
      //
      // El ADR 0024 dejó `relaxed` en «puntuado **sin el cuadrado del filtro**». Con `Todos` no hay
      // filtro que elevar al cuadrado, así que relajar es un no-op: enseñar el aviso ahí sería
      // hablar de «ese filtro» cuando no hay ninguno, y además saldría **siempre** en una base
      // pequeña, porque el backend marca `relaxed` en cuanto hay menos de 20 elegibles.
      //
      // Salió mirando el emulador, no de un test: la regla se cumplía, la frase mentía.
      if (view.relaxed && filtersActive)
        const _InlineNotice(text: ConnectScreen.relaxedNotice),
    ];

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: header.length + view.candidates.length,
      itemBuilder: (BuildContext context, int index) {
        if (index < header.length) return header[index];

        // Sin ordenar ni remuestrear aquí: la tanda viene ya muestreada del backend (RN-44) y
        // reordenarla en el cliente sería una segunda fuente de verdad para el mismo orden — y
        // rompería RN-45 en cuanto dependiera de algo que cambia al hacer scroll.
        final ConnectCandidate c = view.candidates[index - header.length];
        return ConnectCard(
          candidate: c,
          photoUrl: view.photoUrls[c.userId],
          messaged: view.messaged.contains(c.userId),
          onDismiss: () =>
              ref.read(connectControllerProvider.notifier).dismiss(c.userId),
          onChat: () => _abrirChat(context, ref, c),
          // `RN-38`: tocar la tarjeta abre el perfil completo. El botón de chat y el `✕` son
          // acciones directas y NO pasan por aquí — lo garantiza que cada uno tenga su propio
          // callback en `ConnectCard`, no un `onTap` que los envuelva a todos.
          onOpenProfile: () => PublicProfileScreen.open(context, c.userId),
        );
      },
    );
  }
}

/// Un aviso a pantalla completa, dentro de algo scrolleable para no romper el `RefreshIndicator`.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

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

/// Un aviso en línea sobre la lista, que se queda hasta la siguiente carga.
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm + 4),
        decoration: BoxDecoration(
          color: context.palette.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.palette.containerSubtle),
        ),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary),
        ),
      ),
    );
  }
}
