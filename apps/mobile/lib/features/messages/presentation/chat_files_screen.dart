import 'package:flutter/material.dart';

import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';

/// Archivos del chat — §9.3, entrada 2 de siete.
///
/// **Está vacía a propósito y lo dice en pantalla.** El §9.3 la marca «Solo frontend»: *«navega a
/// una pantalla de multimedia compartida ordenada por fecha, vacía por ahora»*. Existe porque un
/// botón que no lleva a ninguna parte es peor que uno que lleva a un sitio honesto, y porque el
/// principio general de `CLAUDE.md` vale en las dos direcciones: un mecanismo sin puerta de entrada
/// no existe, y una puerta de entrada sin mecanismo detrás **tiene que decir que no lo hay**.
///
/// TODO(§13 · `docs/pending-messaging.md` § 7 «Archivos del chat»): falta el almacenamiento de
/// multimedia entero (punto 9 de ese documento), la ordenación por fecha y —lo que no es
/// trivial— los **permisos de acceso al historial compartido**: esta pantalla es una **segunda vía
/// de lectura** sobre los mismos mensajes, así que tiene que respetar `cleared_at` (`RN-27`) y
/// `deleted_for` (`RN-28`) o los burla. Un fichero de un mensaje que alguien borró para sí no puede
/// reaparecerle aquí.
class ChatFilesScreen extends StatelessWidget {
  const ChatFilesScreen({super.key});

  static const String title = 'Archivos del chat';

  /// Lo que se enseña, y **no promete ningún archivo**. La palabra «todavía» es lo que separa un
  /// placeholder honesto de una pantalla que parece rota.
  static const String empty =
      'Aquí aparecerán las fotos y los archivos que compartáis.\n'
      'Todavía no se pueden enviar archivos en Grasp.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(
        title: const Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.folder_open_outlined,
                size: 56,
                color: context.palette.chip,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                empty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
