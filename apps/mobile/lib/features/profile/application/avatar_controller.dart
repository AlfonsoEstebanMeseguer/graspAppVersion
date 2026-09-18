import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/profile/avatar_upload.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/profile/avatar_repository.dart';
import '../../../domain/profile/avatar_type.dart';
import '../../../domain/profile/image_compressor.dart';
import 'profile_controller.dart';

/// Estado de la operación de cambiar avatar.
///
/// No es el estado del avatar (ese vive en [profileControllerProvider], que es la única fuente de
/// verdad del perfil): es el estado de **la operación en curso**, para que la hoja pueda
/// deshabilitar los botones y enseñar el error sin cerrarse.
class AvatarController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AvatarRepository get _repository => ref.read(avatarRepositoryProvider);
  ImageCompressor get _compressor => ref.read(imageCompressorProvider);

  /// Fija un avatar predeterminado.
  ///
  /// No hay actualización optimista, al revés que en `updateProfile`: cambiar de avatar **borra la
  /// foto anterior de R2** (decisión 0010), así que enseñar el cambio antes de que el backend lo
  /// confirme podría mostrar como hecho algo que no ocurrió y que además es irreversible.
  Future<bool> setPreset(AvatarType preset) =>
      _run(() => _repository.setPreset(preset));

  /// Comprime y sube una foto.
  ///
  /// El mime que se declara sale del formato que el compresor produjo **de verdad**, nunca del que
  /// se pidió — ver `avatar_upload.dart` y la decisión 0012.
  Future<bool> uploadPhoto(Uint8List imageBytes) => _run(() async {
    final PreparedUpload prepared = await prepareAvatarUpload(
      imageBytes,
      compressor: _compressor,
    );
    await _repository.uploadPhoto(prepared.bytes, prepared.mimeType);
  });

  /// Ejecuta la operación y refresca el perfil si salió bien.
  ///
  /// Devuelve `true` si funcionó, para que la hoja sepa si cerrarse. El error se queda en el estado
  /// (no se relanza) porque la hoja tiene que poder enseñarlo **sin cerrarse**: cerrar la hoja ante
  /// un fallo obligaría a rehacer todo el recorrido para reintentar.
  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading<void>();
    try {
      await action();
      // El perfil lo recarga su propio controlador: `photo_path` y `preset_avatar` los escribe el
      // backend, así que la única forma honesta de saber cómo quedaron es volver a leerlos.
      ref.invalidate(profileControllerProvider);
      state = const AsyncData<void>(null);
      return true;
    } on Object catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return false;
    }
  }
}

final AutoDisposeAsyncNotifierProvider<AvatarController, void>
avatarControllerProvider =
    AsyncNotifierProvider.autoDispose<AvatarController, void>(
      AvatarController.new,
    );
