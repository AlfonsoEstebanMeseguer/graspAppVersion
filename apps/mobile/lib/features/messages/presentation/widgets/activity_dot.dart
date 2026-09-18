import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';

/// El punto de estado del `RN-30`: **verde = activo en la aplicación, gris = inactivo**.
///
/// ## Es un widget propio para que se pueda buscar
///
/// `RN-30` dice dónde aparece (Contactos, cabecera de conversación, tarjetas de Conectar) y, sobre
/// todo, **dónde no**: en la pestaña Solicitudes. Un `Container` circular incrustado dentro de una
/// fila no se puede buscar en un test —`find.byType(Container)` encuentra veinte—, así que la
/// regla quedaría en manos de quien lea el código. Con un tipo propio,
/// `expect(find.byType(ActivityDot), findsNothing)` es una comprobación exacta.
///
/// Lo que de verdad impide pintarlo donde no toca es que `RequestTile` **no reciba** el dato; esto
/// solo hace que el test pueda demostrarlo.
class ActivityDot extends StatelessWidget {
  const ActivityDot({super.key, required this.isActive, this.size = 12});

  final bool isActive;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isActive ? 'Activo ahora' : 'Inactivo',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isActive ? context.palette.success : context.palette.outline,
          shape: BoxShape.circle,
          // El borde del color del fondo separa el punto de la foto cuando se solapan.
          border: Border.all(color: context.palette.surface, width: 2),
        ),
      ),
    );
  }
}

/// El punto de «no leído» del §8.2, que acompaña a la negrita.
///
/// **No es lo mismo que [ActivityDot] y no comparten widget a propósito.** Uno dice «esta persona
/// está conectada» y el otro «tienes mensajes sin leer»: mezclarlos en un widget con un `enum`
/// haría que un descuido pintara el de actividad en Solicitudes, que es justo lo que `RN-30`
/// prohíbe.
///
/// El número **nunca se muestra aquí**: es el contador estrictamente local de `RN-31`, y lo único
/// que la fila necesita es «hay algo sin leer».
class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sin leer',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.palette.brand,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
