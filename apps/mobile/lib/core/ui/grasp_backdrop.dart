import 'package:flutter/material.dart';

import '../theming/grasp_palette.dart';
import 'calm_scene.dart';

/// Fondo compartido por Start, Login y Registro.
///
/// Es la traducción directa de `01-Start_Menu.jpeg`: lavado púrpura de arriba
/// abajo y, al pie, la escena del grupo. `sceneHeightFactor` y `sceneOpacity`
/// permiten que Login y Registro la releguen a fondo sin cambiar de identidad.
class GraspBackdrop extends StatelessWidget {
  const GraspBackdrop({
    super.key,
    required this.child,
    this.sceneHeightFactor = 0.42,
    this.sceneOpacity = 1,
  });

  final Widget child;

  /// Altura de la escena como fracción de la pantalla.
  final double sceneHeightFactor;
  final double sceneOpacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: context.palette.backgroundWash,
          stops: <double>[0, 0.45, 1],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.sizeOf(context).height * sceneHeightFactor,
            child: CalmScene(opacity: sceneOpacity),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
