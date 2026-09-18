import 'package:flutter/material.dart';

/// Cómo decide Grasp entre el tema claro y el oscuro.
///
/// Son **tres** opciones y no un interruptor de dos porque «seguir al sistema»
/// no es ninguno de los otros dos estados: es la ausencia de decisión, y es lo
/// que quiere la mayoría de la gente que tiene el móvil programado para
/// oscurecerse de noche. Un interruptor binario obliga a elegir un bando y deja
/// a esa persona con la app en claro a las tres de la mañana.
enum AppearanceMode {
  /// Lo que diga el sistema operativo, momento a momento. Valor por defecto.
  system,
  light,
  dark;

  /// El valor guardado. Es el `name` del enum y no su índice: reordenar el enum
  /// no puede cambiar el tema de nadie.
  String get storageKey => name;

  static AppearanceMode fromStorage(String? raw) {
    for (final AppearanceMode m in AppearanceMode.values) {
      if (m.storageKey == raw) return m;
    }
    // Incluye el caso de que no haya nada guardado y el de un valor de una
    // versión futura instalada y luego revertida.
    return AppearanceMode.system;
  }

  ThemeMode get themeMode => switch (this) {
    AppearanceMode.system => ThemeMode.system,
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark => ThemeMode.dark,
  };

  String get label => switch (this) {
    AppearanceMode.system => 'Automático',
    AppearanceMode.light => 'Claro',
    AppearanceMode.dark => 'Oscuro',
  };

  String get description => switch (this) {
    AppearanceMode.system => 'Sigue el ajuste de tu teléfono',
    AppearanceMode.light => 'Siempre en claro',
    AppearanceMode.dark => 'Siempre en oscuro',
  };

  IconData get icon => switch (this) {
    AppearanceMode.system => Icons.brightness_auto_rounded,
    AppearanceMode.light => Icons.light_mode_rounded,
    AppearanceMode.dark => Icons.dark_mode_rounded,
  };
}
