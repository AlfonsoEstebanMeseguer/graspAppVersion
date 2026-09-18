import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';

/// Lo que se espera antes de preguntarle al backend, tecleando.
///
/// Constante propia y **no** uno de los tokens de `GraspMotion`: eso mide animaciones, y atar el
/// tráfico de red a un token de estética haría que retocar una transición cambiara en silencio
/// cuántas peticiones salen del móvil. Los tests lo esperan por su nombre, así que dice en voz alta
/// qué están esperando.
const Duration kSearchDebounce = Duration(milliseconds: 250);

/// La búsqueda dentro de la conversación — §9.4.
///
/// Contador `3/12`, flechas para saltar entre coincidencias y **el aviso de la cota**. Sustituye a
/// la cabecera mientras está abierta, como hace cualquier chat: la persona está buscando, no
/// mirando con quién habla.
///
/// ## El aviso de la cota no es decoración
///
/// §9.4 acota la búsqueda a los **últimos 1000 mensajes** y dice explícitamente que *«la cabecera de
/// la búsqueda lo dice»*. Sin ese aviso, una conversación larga devuelve «0 resultados» sobre algo
/// que la persona recuerda haber escrito, y no hay forma de que entienda por qué. El número sale de
/// [searchLimit] —que `MessageSearchResult` trae **justo para esto**, porque con `total` solo no se
/// puede— y no de un literal: un `1000` escrito aquí seguiría diciendo 1000 el día que el backend
/// cambiara la cota.
///
/// ## Por qué el contador puede decir 12 con 6 mensajes
///
/// Cuenta **coincidencias**, no mensajes (§9.4 y `docs/api-contracts.md`): un mensaje con la
/// palabra tres veces aporta tres saltos a las flechas.
class ConversationSearchBar extends StatefulWidget {
  const ConversationSearchBar({
    super.key,
    required this.controller,
    required this.total,
    required this.position,
    required this.searchLimit,
    required this.onClose,
    required this.onQueryChanged,
    this.onPrevious,
    this.onNext,
    this.loading = false,
  });

  static const Key fieldKey = Key('conversation-search-field');
  static const Key counterKey = Key('conversation-search-counter');
  static const Key previousKey = Key('conversation-search-previous');
  static const Key nextKey = Key('conversation-search-next');
  static const Key closeKey = Key('conversation-search-close');
  static const Key limitNoticeKey = Key('conversation-search-limit');

  static const String hint = 'Buscar en la conversación…';

  final TextEditingController controller;

  /// Coincidencias totales — el `12` de `3/12`.
  final int total;

  /// Posición actual, **1-based**, o `0` si no hay ninguna. El `3` de `3/12`.
  final int position;

  /// La cota que aplicó el backend. Se pinta tal cual: ver la nota de arriba.
  ///
  /// `null` mientras no haya respuesta, y entonces **el aviso no se pinta**. Anunciar una cota que
  /// todavía no se conoce obligaría a escribir el número a mano, que es justo lo que este campo
  /// existe para evitar.
  final int? searchLimit;

  final VoidCallback onClose;

  /// Hacia mensajes **más antiguos** (arriba en la conversación).
  final VoidCallback? onPrevious;

  /// Hacia mensajes **más recientes**.
  final VoidCallback? onNext;

  final bool loading;

  /// Se llama con el término ya **rebotado** ([kSearchDebounce]).
  final ValueChanged<String> onQueryChanged;

  @override
  State<ConversationSearchBar> createState() => _ConversationSearchBarState();
}

class _ConversationSearchBarState extends State<ConversationSearchBar> {
  Timer? _rebote;
  String _ultimo = '';

  @override
  void initState() {
    super.initState();
    _ultimo = widget.controller.text;
    widget.controller.addListener(_alTeclear);
  }

  @override
  void dispose() {
    _rebote?.cancel();
    widget.controller.removeListener(_alTeclear);
    super.dispose();
  }

  /// Rebota, y **solo dispara si el término cambió de verdad**.
  ///
  /// El controlador avisa también al mover el cursor o al seleccionar texto; sin la comparación,
  /// mover el cursor por un término ya buscado saldría al backend otra vez y devolvería la
  /// búsqueda a su primera coincidencia con el dedo en otra parte.
  void _alTeclear() {
    final String texto = widget.controller.text;
    if (texto == _ultimo) return;
    _ultimo = texto;

    _rebote?.cancel();
    _rebote = Timer(kSearchDebounce, () {
      if (mounted) widget.onQueryChanged(texto);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = widget.total;
    final int position = widget.position;
    final int? searchLimit = widget.searchLimit;
    final bool loading = widget.loading;
    final TextEditingController controller = widget.controller;
    final VoidCallback onClose = widget.onClose;
    final VoidCallback? onPrevious = widget.onPrevious;
    final VoidCallback? onNext = widget.onNext;

    return Material(
      color: context.palette.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    key: ConversationSearchBar.closeKey,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Cerrar la búsqueda',
                    onPressed: onClose,
                  ),
                  Expanded(
                    child: TextField(
                      key: ConversationSearchBar.fieldKey,
                      controller: controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.palette.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: ConversationSearchBar.hint,
                        // `inputDecorationTheme` gana sobre `InputDecoration.border`, así que
                        // quitar el marco exige apagar los tres explícitamente: con `border`
                        // a secas el campo se queda con su recuadro puesto dentro de la cabecera.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        filled: false,
                      ),
                    ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      child: Text(
                        key: ConversationSearchBar.counterKey,
                        '$position/$total',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: context.palette.textMuted,
                          fontFeatures: const <FontFeature>[
                            // Cifras de ancho fijo: sin esto el contador da un salto lateral al
                            // pasar de `9/12` a `10/12` y la flecha se mueve bajo el dedo.
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  IconButton(
                    key: ConversationSearchBar.previousKey,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    tooltip: 'Coincidencia anterior',
                    onPressed: onPrevious,
                  ),
                  IconButton(
                    key: ConversationSearchBar.nextKey,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    tooltip: 'Coincidencia siguiente',
                    onPressed: onNext,
                  ),
                ],
              ),
            ),
            if (searchLimit != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    key: ConversationSearchBar.limitNoticeKey,
                    'Se buscan los últimos $searchLimit mensajes de la conversación.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
