import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_motion.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/social/connect_candidate.dart';

/// La fila horizontal de chips del §6.3: `Todos` · `Edad` · `Intereses` · `Situación sufrida` ·
/// `Situación correspondida`.
///
/// ## `Todos` es la lista VACÍA, no un valor más
///
/// [ConnectFilter] no tiene variante `all`, y por eso `RN-36` —«pulsar `Todos` desactiva el
/// resto»— no es disciplina de este widget: es lo que significa el conjunto vacío. Si `Todos`
/// fuera un chip como los demás habría que decidir qué quiere decir `{all, age}`, y alguien
/// acabaría decidiéndolo distinto en dos sitios.
class ConnectFilterChips extends StatelessWidget {
  const ConnectFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Los chips activos. **Vacío = `Todos`** (`RN-35`, estado por defecto).
  final Set<ConnectFilter> selected;

  final ValueChanged<Set<ConnectFilter>> onChanged;

  /// El orden del §6.3, con `Todos` el primero.
  static const List<({ConnectFilter? filter, String label})> entries =
      <({ConnectFilter? filter, String label})>[
        (filter: null, label: 'Todos'),
        (filter: ConnectFilter.age, label: 'Edad'),
        (filter: ConnectFilter.interests, label: 'Intereses'),
        (filter: ConnectFilter.suffered, label: 'Situación sufrida'),
        (filter: ConnectFilter.current, label: 'Situación correspondida'),
      ];

  void _toggle(ConnectFilter? filter) {
    // RN-36 en una línea: `Todos` no "apaga el resto", **es** el resto apagado.
    if (filter == null) {
      onChanged(const <ConnectFilter>{});
      return;
    }

    final Set<ConnectFilter> next = Set<ConnectFilter>.of(selected);
    if (!next.remove(filter)) next.add(filter);
    // Quedarse con cero chips sería un estado que la spec no define y que el backend interpreta
    // igual que `Todos`; se colapsa aquí para que la pantalla no mienta sobre lo que filtra.
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        itemCount: entries.length,
        separatorBuilder: (BuildContext context, int _) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final ({ConnectFilter? filter, String label}) entry = entries[index];
          final bool isSelected = entry.filter == null
              ? selected.isEmpty
              : selected.contains(entry.filter);

          return ConnectFilterChip(
            label: entry.label,
            selected: isSelected,
            onTap: () => _toggle(entry.filter),
          );
        },
      ),
    );
  }
}

/// Un chip suelto. Es un tipo propio para que los tests puedan preguntarle **cuál está activo** sin
/// depender del color con el que se pinte hoy.
class ConnectFilterChip extends StatelessWidget {
  const ConnectFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: theme.extension<GraspMotion>()?.fast ?? AppMotion.fast,
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.palette.outline : context.palette.canvas,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? context.palette.iconSoft : context.palette.containerSubtle,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? context.palette.textPrimary : context.palette.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
