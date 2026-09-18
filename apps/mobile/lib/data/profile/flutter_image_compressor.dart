import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../domain/profile/avatar_image_format.dart';
import '../../domain/profile/image_compressor.dart';

/// ⚠️ **ESTE FICHERO NO ESTÁ CUBIERTO POR NINGÚN TEST, Y NO PUEDE ESTARLO AQUÍ.**
///
/// Es el único punto de la aplicación que habla con un códec de la plataforma, y por eso se ha
/// dejado tan pequeño como se ha podido: todo lo que se puede razonar (elegir calidad, reintentar
/// por tamaño, decidir qué mime se declara) vive en `data/profile/avatar_upload.dart`, que sí está
/// probado. Aquí solo queda la llamada al plugin.
///
/// Lo que hay que comprobar **en un dispositivo real**, y sigue pendiente
/// (`docs/superpowers/specs/2026-08-13-spike-webp-en-flutter.md`):
///
/// 1. Que el códec de Android y el de iOS produzcan un WebP válido de ≤200 KB desde la cámara.
/// 2. El camino `UnsupportedError`, que **solo existe en móvil**.
/// 3. Cuánto tarda la codificación en iOS.
///
/// En Edge sí se puede probar el camino completo, y ahí el códec es el del navegador.
class FlutterImageCompressor implements ImageCompressor {
  const FlutterImageCompressor();

  @override
  Future<CompressedImage> compress(
    Uint8List source, {
    required int maxSide,
    required int quality,
  }) async {
    // Se pide WebP primero. Puede no salir, y de dos formas distintas:
    //   · en móvil, `UnsupportedError` (lo dice el README del paquete);
    //   · en web, SIN ERROR: `canvas.toDataURL` devuelve PNG en silencio (medido en Edge).
    // Por eso el resultado se comprueba oliendo los bytes y no confiando en que no hubo excepción.
    final CompressedImage? webp = await _tryFormat(
      source,
      format: CompressFormat.webp,
      maxSide: maxSide,
      quality: quality,
      expected: AvatarImageFormat.webp,
    );
    if (webp != null) return webp;

    final CompressedImage? jpeg = await _tryFormat(
      source,
      format: CompressFormat.jpeg,
      maxSide: maxSide,
      quality: quality,
      expected: AvatarImageFormat.jpeg,
    );
    if (jpeg != null) return jpeg;

    throw const ImageCompressionException(
      'Este dispositivo no ha podido convertir la imagen a un formato admitido.',
    );
  }

  /// Comprime pidiendo [format] y devuelve el resultado **solo si los bytes son [expected]**.
  ///
  /// Devolver `null` en vez de lanzar es deliberado: quien llama decide si quedan más formatos que
  /// intentar, y así el fallo de un intento no parece el fallo de la operación.
  Future<CompressedImage?> _tryFormat(
    Uint8List source, {
    required CompressFormat format,
    required int maxSide,
    required int quality,
    required AvatarImageFormat expected,
  }) async {
    final Uint8List result;
    try {
      result = await FlutterImageCompress.compressWithList(
        source,
        minWidth: maxSide,
        minHeight: maxSide,
        quality: quality,
        format: format,
      );
    } on UnsupportedError {
      // Cubre también `UnimplementedError`, que en Dart es subtipo de `UnsupportedError`: el
      // primero lo lanza `flutter_image_compress_web` para los métodos que no implementa, el
      // segundo un móvil sin ese códec. Los dos significan lo mismo aquí — este camino no existe.
      return null;
    }

    // La comprobación que hace que el cliente no pueda mentir sobre el formato.
    if (sniffImageFormat(result) != expected) return null;
    return CompressedImage(bytes: result, format: expected);
  }
}
