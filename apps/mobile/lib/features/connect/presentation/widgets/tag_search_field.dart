import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';

/// La barra de búsqueda del §6.2.
///
/// ## El placeholder tiene que decir que es por TAG, no por nombre
///
/// `RN-11`: **no hay búsqueda difusa**. Teclear el tag a mano es la única forma de encontrar a
/// alguien, así que un placeholder tipo «Buscar personas» prometería algo que no existe y dejaría a
/// la gente escribiendo nombres que nunca van a encontrar nada.
///
/// El formato del tag es `nombre#XXXXXXXX` (enmienda nº 5), con alfabeto Crockford base32 — sin `I`,
/// `L`, `O` ni `U` para que nadie confunda un `0` con una `O` al teclearlo.
class TagSearchField extends StatefulWidget {
  const TagSearchField({
    super.key,
    required this.onSubmit,
    required this.onClear,
  });

  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  static const String hint = 'Busca por tag exacto: nombre#XXXXXXXX';

  @override
  State<TagSearchField> createState() => _TagSearchFieldState();
}

class _TagSearchFieldState extends State<TagSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final String tag = value.trim();
    if (tag.isEmpty) {
      widget.onClear();
      return;
    }
    // No se valida el formato aquí a propósito: un tag imposible devuelve el MISMO 404 que uno
    // inexistente (§6.2), así que rechazarlo antes de llamar cambiaría el mensaje según la forma de
    // lo tecleado — y ésa es una diferencia observable donde no debe haberla.
    widget.onSubmit(tag);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: _submit,
        decoration: InputDecoration(
          hintText: TagSearchField.hint,
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: context.palette.canvas,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: context.palette.containerSubtle),
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (BuildContext context, TextEditingValue value, Widget? _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Borrar la búsqueda',
                onPressed: () {
                  _controller.clear();
                  widget.onClear();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
