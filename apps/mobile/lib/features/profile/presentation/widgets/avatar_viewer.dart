import 'package:flutter/material.dart';

import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/profile.dart';
import 'profile_avatar.dart';

/// Cuánto scroll de rueda hace falta por unidad de zoom. Más alto = más progresivo.
const double _wheelScaleFactor = 1000;

/// Enseña el avatar en grande, a pantalla casi completa.
///
/// Separado del lápiz a propósito: **tocar la foto la mira, tocar el lápiz la cambia**. Son dos
/// intenciones distintas y meterlas en el mismo gesto obliga a adivinar cuál quería la persona.
///
/// Se puede acercar y arrastrar, igual que en cualquier visor de fotos: una foto de perfil recortada
/// a un círculo pequeño esconde detalle, y ampliarla es justo lo que se viene a hacer aquí.
///
/// Aquí el avatar se dibuja **cuadrado**: lo que se sube es un recorte cuadrado, y el círculo del
/// perfil se come las esquinas. Ampliarlo para volver a ver el mismo recorte no enseñaría nada nuevo.
class AvatarViewer extends StatelessWidget {
  const AvatarViewer({super.key, required this.profile});

  final Profile profile;

  static Future<void> show(BuildContext context, Profile profile) {
    return showDialog<void>(
      context: context,
      // El fondo oscuro no es estética: quita de en medio el resto de la pantalla para que la foto
      // sea lo único que se mira.
      barrierColor: Colors.black87,
      builder: (BuildContext context) => AvatarViewer(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String name = profile.displayName?.trim() ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Toda la superficie cierra: en un visor, tocar fuera es la forma natural de salir.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                // Por defecto son 200, y con eso cada muesca de rueda salta casi un 40%
                // (`exp(-scrollDelta / scaleFactor)`). Subirlo lo deja en torno al 10%, que es
                // lo que se siente progresivo en vez de a saltos.
                scaleFactor: _wheelScaleFactor,
                child: ProfileAvatar(
                  profile: profile,
                  // CUADRADO y no círculo: la foto se sube recortada a un cuadrado, así que el
                  // círculo del perfil esconde las esquinas. Al ampliarla se quiere ver todo lo
                  // que se subió.
                  shape: AvatarShape.rounded,
                  // Grande, pero acotado: en una pantalla ancha una foto de 512 px estirada a
                  // pantalla completa se vería borrosa.
                  size: MediaQuery.sizeOf(context).width.clamp(0.0, 320.0),
                ),
              ),
              if (name.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  name,
                  // Blanco literal, no `onBrand`: esto cae sobre el velo negro del
                  // `barrierColor`, que es igual de negro en los dos temas. `onBrand`
                  // aqui seria un texto casi invisible en modo oscuro.
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
              ],
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Semantics(
              button: true,
              label: 'Cerrar',
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
