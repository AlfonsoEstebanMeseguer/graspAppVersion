import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/settings/appearance_mode.dart';

/// Dónde vive la elección de tema.
///
/// ## Por qué en el dispositivo y no en `profiles`
///
/// La misma cuenta puede abrirse en un móvil con OLED de noche y en una tablet
/// a plena luz; el tema es una preferencia **del aparato que se está mirando**,
/// no de la persona. Guardarlo en el servidor obligaría además a esperar a la
/// red para pintar el primer frame, y a que la pantalla de login —donde
/// todavía no hay sesión— se quedara sin ajuste.
///
/// El precio, que se acepta: reinstalar la app lo devuelve a `system`.
class AppearanceStore {
  const AppearanceStore(this._prefs);

  static const String _key = 'appearance_mode';

  final SharedPreferences _prefs;

  AppearanceMode read() =>
      AppearanceMode.fromStorage(_prefs.getString(_key));

  Future<void> write(AppearanceMode mode) =>
      _prefs.setString(_key, mode.storageKey);
}
