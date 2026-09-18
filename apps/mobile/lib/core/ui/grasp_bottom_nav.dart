import 'package:flutter/material.dart';

import '../theming/grasp_palette.dart';
import '../theming/app_motion.dart';

/// Un destino de la barra inferior.
///
/// Ya no existe la noción de destino *deshabilitado*: los cuatro son ramas
/// reales del `StatefulShellRoute` (Fase 4, Tarea 18). Fingir una pestaña que
/// no lleva a ningún sitio fue correcto mientras faltaban las pantallas, y
/// dejar el mecanismo vivo cuando ya no hace falta solo invita a reutilizarlo.
@immutable
class GraspNavDestination {
  const GraspNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Número del badge. `null` o `0` no pintan nada.
  ///
  /// **RN-55**: en Mensajes esto son **solo los no leídos de conversaciones
  /// aceptadas**, nunca las solicitudes pendientes — no se premia el spam con
  /// una notificación roja. Quién alimenta este número es responsabilidad de
  /// quien construye la barra; aquí solo se pinta lo que llega.
  final int? badgeCount;
}

/// Barra inferior de navegación — `Mensajes · Conectar · Salas de voz · Perfil`
/// (§5 de la spec de la Fase 4).
class GraspBottomNav extends StatelessWidget {
  const GraspBottomNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
  });

  final List<GraspNavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(color: context.palette.shadow, blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavItem(
                    destination: destinations[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final GraspNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = selected ? context.palette.brandStrong : context.palette.textMuted;
    final int? badge = destination.badgeCount;
    // `> 0` y no `!= null`: un badge con un 0 dentro es peor que ninguno.
    final bool showBadge = badge != null && badge > 0;

    return Semantics(
      button: true,
      selected: selected,
      label: showBadge
          ? '${destination.label}, $badge sin leer'
          : destination.label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      color: color,
                      size: 24,
                    ),
                    if (showBadge)
                      Positioned(
                        top: -4,
                        right: -10,
                        child: _Badge(
                          key: ValueKey<String>('nav-badge-${destination.label}'),
                          count: badge,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  destination.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // Se corta en 99+ para que el ancho no crezca sin límite y desplace el
    // icono: una bandeja con 1.284 sin leer no necesita el número exacto.
    final String text = count > 99 ? '99+' : '$count';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: context.palette.error,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          // `onBrand`, no blanco: en oscuro `error` es claro y el blanco daba
          // 1.4:1. Asi son 10.5:1 en los dos temas.
          color: context.palette.onBrand,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
