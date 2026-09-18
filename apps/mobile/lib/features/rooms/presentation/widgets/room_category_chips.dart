import 'package:flutter/material.dart';

import '../../../../core/theming/app_theme.dart';
import '../../../../domain/rooms/room_summary.dart';
import '../../../connect/presentation/widgets/connect_filter_chips.dart';

/// La fila de temas: `Todas` + una píldora por categoría (ADR 0032 § 6).
///
/// ## Reutiliza el chip de Conectar, no su fila
///
/// [ConnectFilterChip] es el mismo control visual y ya está probado; [ConnectFilterChips] no sirve
/// porque está atado al `enum ConnectFilter` y a la semántica de **multi**selección. Aquí la
/// selección es **única** —`rooms-feed` acepta un `categoryId`, no una lista— así que un conjunto
/// de chips activos no sería representable en la petición.
///
/// `Todas` es `null`, igual que `Todos` es el conjunto vacío en Conectar: no es un valor más del
/// catálogo, es la ausencia de filtro. Si fuera un elemento habría que decidir qué significa
/// `{Todas, Ansiedad}` y alguien lo decidiría distinto en dos sitios.
class RoomCategoryChips extends StatelessWidget {
  const RoomCategoryChips({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onChanged,
  });

  static const String allLabel = 'Todas';

  final List<RoomCategory> categories;

  /// `null` = `Todas`.
  final String? selectedId;

  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        itemCount: categories.length + 1,
        separatorBuilder: (BuildContext context, int _) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return ConnectFilterChip(
              label: allLabel,
              selected: selectedId == null,
              // Volver a pulsar `Todas` estando en `Todas` no es un cambio; el controlador ya lo
              // ignora, y aquí se manda el mismo valor sin inventar un "deseleccionar".
              onTap: () => onChanged(null),
            );
          }

          final RoomCategory category = categories[index - 1];
          final bool selected = category.id == selectedId;

          return ConnectFilterChip(
            label: category.name,
            selected: selected,
            // Pulsar el chip activo vuelve a `Todas`: es la única forma de quitar un filtro de
            // selección única sin un botón «quitar filtro» aparte.
            onTap: () => onChanged(selected ? null : category.id),
          );
        },
      ),
    );
  }
}
