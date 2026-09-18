import 'package:flutter/material.dart';

/// Duraciones y curvas compartidas.
///
/// Tener el movimiento centralizado evita que cada pantalla invente su propio
/// timing: es lo que hace que la app se sienta como un solo producto y no como
/// una colección de pantallas.
abstract final class AppMotion {
  const AppMotion._();

  /// Micro-interacciones: pressed de un botón, cambio de un chip.
  static const Duration fast = Duration(milliseconds: 180);

  /// Transiciones dentro de una pantalla: aparición de un bloque, switcher.
  static const Duration medium = Duration(milliseconds: 340);

  /// Entradas de pantalla completa y revelados escalonados.
  static const Duration slow = Duration(milliseconds: 620);

  /// Animaciones ambientales en bucle (respiración de la marca, parallax).
  static const Duration ambient = Duration(seconds: 6);

  /// Curva por defecto: aceleración suave, sin rebote. Calmada, como el producto.
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Curves.easeOutBack;
}
