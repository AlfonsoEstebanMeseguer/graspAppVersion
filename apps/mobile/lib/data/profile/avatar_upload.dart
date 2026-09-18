import 'dart:typed_data';

import '../../domain/profile/avatar_image_format.dart';
import '../../domain/profile/image_compressor.dart';

/// Una imagen lista para subir: los bytes exactos y el mime que los describe **de verdad**.
class PreparedUpload {
  const PreparedUpload({required this.bytes, required this.format});

  final Uint8List bytes;
  final AvatarImageFormat format;

  /// Lo que va en `mime_type` y en el `Content-Type` del `PUT`. Sale del formato **medido**.
  String get mimeType => format.mimeType;

  /// Lo que va en `file_size`. Exacto: `ContentLength` va firmado.
  int get sizeInBytes => bytes.length;
}

/// Tope del backend (`MAX_FILE_SIZE` en `_shared/photo-upload.ts`). Si se supera, la firma se pide
/// para un tamaño que R2 rechazará, así que el recorte se hace **antes** de pedirla.
const int maxAvatarBytes = 200 * 1024;

/// Lado máximo del avatar. Se pinta a 96 px lógicos; 512 da margen para pantallas densas.
const int avatarMaxSide = 512;

/// Calidades que se prueban, de mejor a peor.
///
/// No es una búsqueda binaria a propósito: cada intento es una codificación real y cara (en móvil,
/// decenas o centenas de milisegundos), y tres pasos bastan para bajar una foto de cámara por debajo
/// de 200 KB a 512 px. Más intentos costarían más de lo que ahorran.
const List<int> _qualityLadder = <int>[85, 70, 55];

/// Comprime hasta que quepa, y devuelve el formato que **realmente** salió.
///
/// Dos cosas que parecen detalles y no lo son:
///
/// 1. **El mime se deduce de los bytes**, nunca del formato que se pidió. En móvil un dispositivo
///    sin WebP lanza `UnsupportedError` (y el compresor cae a JPEG); en web no lanza nada y
///    `canvas.toDataURL` devuelve PNG en silencio. Declarar `image/webp` con bytes que no lo son es
///    justo lo que la decisión 0012 corrige, y el backend lo rechazaría con un 400 (decisión 0013).
/// 2. **El recorte va antes de pedir la firma.** La URL se firma con `ContentLength`, así que subir
///    un byte de más no da un error de validación sino un `SignatureDoesNotMatch` de R2 — un fallo
///    en el sistema equivocado y con un mensaje que no dice nada.
Future<PreparedUpload> prepareAvatarUpload(
  Uint8List source, {
  required ImageCompressor compressor,
}) async {
  CompressedImage? best;

  for (final int quality in _qualityLadder) {
    final CompressedImage attempt = await compressor.compress(
      source,
      maxSide: avatarMaxSide,
      quality: quality,
    );
    best = attempt;
    if (attempt.sizeInBytes <= maxAvatarBytes) {
      return PreparedUpload(bytes: attempt.bytes, format: attempt.format);
    }
  }

  final int kb = ((best?.sizeInBytes ?? 0) / 1024).round();
  throw ImageCompressionException(
    'La imagen sigue pesando $kb KB tras comprimirla y no se puede subir '
    '(el máximo son ${maxAvatarBytes ~/ 1024} KB). Prueba con otra foto.',
  );
}
