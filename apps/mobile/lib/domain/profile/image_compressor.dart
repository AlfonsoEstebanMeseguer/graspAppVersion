import 'dart:typed_data';

import 'avatar_image_format.dart';

/// Una imagen ya comprimida, con el formato que la plataforma **realmente** produjo.
///
/// El formato es un dato de salida, no de entrada: se pide WebP, pero lo que llega puede ser otra
/// cosa (ver [ImageCompressor.compress]). Declarar al backend el formato que se pretendía en vez del
/// que se obtuvo es exactamente el fallo que la decisión 0012 corrige.
class CompressedImage {
  const CompressedImage({required this.bytes, required this.format});

  final Uint8List bytes;
  final AvatarImageFormat format;

  /// Lo que se declara como `file_size`. Tiene que ser **exacto**: `ContentLength` va firmado en la
  /// URL de subida, así que un byte de diferencia es un fallo de firma en R2.
  int get sizeInBytes => bytes.length;
}

/// Comprime una imagen a un formato que el backend admite.
///
/// Existe como interfaz porque su única implementación real habla con códecs de la plataforma:
/// `canvas` en web, `Bitmap`/`ImageIO` en móvil. Toda la lógica que se puede razonar vive en
/// `data/profile/avatar_upload.dart`, que recibe esto por parámetro — el mismo patrón que
/// `photo-view.ts` en el backend con su `SignerFn`, y lo que permite probarlo sin dispositivo.
///
/// **Trabaja con bytes, no con rutas**: en web `compressWithFile` lanza `UnimplementedError` (solo
/// está implementado `compressWithList`) y el `path` de un `XFile` es una URL de blob.
abstract interface class ImageCompressor {
  /// Comprime [source] para que su lado mayor no pase de [maxSide], con [quality] (1-100).
  ///
  /// **El formato del resultado se determina oliendo los bytes devueltos**, nunca suponiendo que
  /// salió lo que se pidió — los dos caminos de fallo son distintos y solo uno avisa:
  ///
  /// - Android/iOS: si el dispositivo no sabe codificar WebP, lanza `UnsupportedError`.
  /// - Web: **no lanza**; `canvas.toDataURL` devuelve PNG en silencio.
  ///
  /// Si lo producido no es WebP ni JPEG, la implementación reintenta pidiendo JPEG explícitamente.
  /// Lanza [ImageCompressionException] si no consigue ninguno de los dos.
  Future<CompressedImage> compress(
    Uint8List source, {
    required int maxSide,
    required int quality,
  });
}

/// Error de dominio: la imagen no se pudo dejar en un formato y tamaño admisibles.
///
/// Existe para que la UI tenga algo que enseñar en español y para que el fallo no llegue como un
/// error críptico de firma desde R2, que es donde acabaría si se subiera igualmente.
class ImageCompressionException implements Exception {
  const ImageCompressionException(this.message);

  final String message;

  @override
  String toString() => message;
}
