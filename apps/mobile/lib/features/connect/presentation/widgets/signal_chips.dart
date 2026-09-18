import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';

/// Los chips del §6.4: **rectángulos de esquinas redondeadas, no interactivos**, máximo **3
/// visibles + «+N»**.
///
/// ## Qué llevan dentro, y por qué importa tanto
///
/// El §6.4 decía «chips de **intereses**», y los intereses son texto libre de
/// `onboarding_responses`: **categoría especial del Art. 9 RGPD**, igual que la situación sufrida y
/// las experiencias. La enmienda nº 1 conservó el componente visual tal cual y **cambió el
/// contenido** por señales no sensibles que ya eran públicas
/// ([ADR 0020](../../../../../docs/decisions/0020-conectar-no-muestra-datos-del-articulo-9.md)).
///
/// Por eso este widget recibe **cadenas ya formateadas** y no un candidato: no puede leer un campo
/// sensible porque no tiene de dónde. Quien decide qué señales entran es [ConnectCard], y hay un
/// test que enumera todo el texto que la tarjeta pinta.
///
/// **No es interactivo a propósito.** Si respondiera al toque, la tarjeta tendría cuatro destinos y
/// `RN-38` solo define tres.
class SignalChips extends StatelessWidget {
  const SignalChips({super.key, required this.labels, this.maxVisible = 3});

  final List<String> labels;

  /// El «máximo 3» del §6.4.
  ///
  /// Hoy las señales del ADR 0020 son exactamente 3, así que el «+N» no llega a verse en la
  /// tarjeta. El componente lo soporta igual porque el §6.4 lo pide, y se prueba **directamente**
  /// en `connect_card_test.dart` para que no quede como código sin cubrir.
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    final List<String> visibles = labels.take(maxVisible).toList();
    final int ocultos = labels.length - visibles.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final String label in visibles) _Chip(text: label),
        if (ocultos > 0) _Chip(text: '+$ocultos'),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.palette.containerSubtle),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          // `purple500` tiene 4.23:1 y no se usa en texto pequeño sobre fondo claro.
          color: context.palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
