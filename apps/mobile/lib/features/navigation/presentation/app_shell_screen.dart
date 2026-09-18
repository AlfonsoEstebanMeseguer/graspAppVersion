import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/grasp_bottom_nav.dart';
import '../../messages/application/inbox_controller.dart';
import 'widgets/activity_heartbeat.dart';

/// Envoltorio de la barra inferior de navegación.
///
/// Recibe el `StatefulShellRoute` de `core/router/app_router.dart` con las
/// **cuatro ramas reales** del §5: `Mensajes · Conectar · Salas de voz ·
/// Perfil`.
///
/// Hasta la Tarea 18 había 2 ramas y 4 destinos, dos de ellos pintados
/// deshabilitados, y hacían falta `_navBarIndexFor` y `_disabledNavIndexes`
/// para mapear un índice sobre otro. **Los dos han desaparecido**: con una rama
/// por destino, el índice de la barra *es* el del shell, y ese mapeo era el
/// único sitio donde un descuadre podía llevar a la pestaña equivocada.
class AppShellScreen extends ConsumerWidget {
  const AppShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// El orden importa: **es** el orden de las ramas del shell, y `Mensajes` va
  /// primero porque es el destino de aterrizaje tras iniciar sesión (§5).
  ///
  /// `badgeCount` se rellena en [build] porque depende del estado de la bandeja
  /// (`RN-55`); el resto es constante.
  static List<GraspNavDestination> _destinations(int? unread) =>
      <GraspNavDestination>[
        GraspNavDestination(
          icon: Icons.chat_bubble_outline_rounded,
          selectedIcon: Icons.chat_bubble_rounded,
          label: 'Mensajes',
          // RN-55: SOLO los no leídos de conversaciones **aceptadas**. El
          // número lo calcula `InboxView.unreadBadge`, que excluye las
          // solicitudes recibidas (otra lista) **y** las enviadas por uno mismo
          // (misma lista, `pending_acceptance`). El motivo está en la spec: no
          // premiar el spam con una notificación roja.
          badgeCount: unread,
        ),
        const GraspNavDestination(
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
          label: 'Conectar',
        ),
        const GraspNavDestination(
          icon: Icons.mic_none_rounded,
          selectedIcon: Icons.mic_rounded,
          label: 'Salas de voz',
        ),
        const GraspNavDestination(
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          label: 'Perfil',
        ),
      ];

  /// Volver a tocar la pestaña activa la devuelve a su raíz, que es el gesto
  /// esperado en una barra inferior (salir de una conversación abierta, por
  /// ejemplo). Cambiar de pestaña conserva el estado de la que se deja.
  void _onNavTap(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La barra vive POR ENCIMA del shell, así que se construye aunque Mensajes
    // no esté abierta: por eso el número sale de su propio provider derivado y
    // no de leer el controlador de la pantalla.
    final int? unread = ref.watch(messagesBadgeProvider);

    // El latido de `RN-30` va aquí y no en cada pantalla: el shell existe **exactamente** mientras
    // hay sesión y envuelve a las cuatro pestañas, así que es el único sitio donde «la app está en
    // primer plano» significa lo mismo que «esta persona está presente».
    return ActivityHeartbeat(
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: GraspBottomNav(
          destinations: _destinations(unread),
          currentIndex: navigationShell.currentIndex,
          onTap: _onNavTap,
        ),
      ),
    );
  }
}
