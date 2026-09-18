import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/preferences/appearance_store.dart';
import '../../../domain/settings/appearance_mode.dart';

/// El almacén de la preferencia.
///
/// Se sobrescribe en `main()` con la instancia ya abierta (ver
/// `appearanceStoreOverride`). Si alguien lo lee sin ese override —un test que
/// se olvide— revienta con un mensaje que dice exactamente qué falta, en vez de
/// devolver silenciosamente el tema claro y hacer creer que el ajuste no
/// persiste.
final Provider<AppearanceStore> appearanceStoreProvider =
    Provider<AppearanceStore>((Ref ref) {
      throw UnimplementedError(
        'appearanceStoreProvider no tiene override. Se inyecta en main() con '
        'las SharedPreferences ya abiertas, y en los tests con '
        'SharedPreferences.setMockInitialValues().',
      );
    });

/// El modo activo. Síncrono a propósito.
///
/// La preferencia se lee **antes** de `runApp` (`main()` abre las
/// `SharedPreferences` y las inyecta), así que aquí no hay `AsyncValue` ni
/// estado de carga: el primer frame ya se pinta con el tema correcto. Un
/// `FutureProvider` habría costado un parpadeo blanco al arrancar en oscuro —
/// que es justo el momento en que más molesta.
class AppearanceController extends Notifier<AppearanceMode> {
  @override
  AppearanceMode build() => ref.read(appearanceStoreProvider).read();

  /// Cambia el tema y lo persiste.
  ///
  /// El estado se actualiza **antes** de esperar al disco: la app tiene que
  /// oscurecerse en el mismo gesto, no cuando conteste el almacenamiento. Si la
  /// escritura fallara, lo perdido sería la persistencia entre arranques, no la
  /// sesión en curso.
  Future<void> set(AppearanceMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(appearanceStoreProvider).write(mode);
  }
}

final NotifierProvider<AppearanceController, AppearanceMode>
appearanceControllerProvider =
    NotifierProvider<AppearanceController, AppearanceMode>(
      AppearanceController.new,
    );
