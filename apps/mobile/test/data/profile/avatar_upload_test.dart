import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/profile/avatar_upload.dart';
import 'package:grasp_mobile/domain/profile/avatar_image_format.dart';
import 'package:grasp_mobile/domain/profile/image_compressor.dart';

/// Construye bytes con la cabecera real de cada formato. Lo que va detrás da igual: nada de esto
/// decodifica la imagen, igual que el backend.
Uint8List _webp(int size) {
  final Uint8List b = Uint8List(size);
  b.setAll(0, <int>[0x52, 0x49, 0x46, 0x46]); // "RIFF"
  b.setAll(8, <int>[0x57, 0x45, 0x42, 0x50]); // "WEBP"
  return b;
}

Uint8List _jpeg(int size) {
  final Uint8List b = Uint8List(size);
  b.setAll(0, <int>[0xFF, 0xD8, 0xFF]);
  return b;
}

Uint8List _png(int size) {
  final Uint8List b = Uint8List(size);
  b.setAll(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return b;
}

/// Compresor falso: devuelve lo que se le diga, sin tocar ningún códec.
///
/// `onCompress` recibe la calidad pedida, para poder afirmar sobre los reintentos.
class _FakeCompressor implements ImageCompressor {
  _FakeCompressor(this.onCompress);

  final Uint8List Function(int quality) onCompress;
  final List<int> qualitiesUsed = <int>[];

  @override
  Future<CompressedImage> compress(
    Uint8List source, {
    required int maxSide,
    required int quality,
  }) async {
    qualitiesUsed.add(quality);
    final Uint8List bytes = onCompress(quality);
    // Igual que la implementación real: el formato sale de los bytes, no de lo que se pidió.
    final AvatarImageFormat? format = sniffImageFormat(bytes);
    if (format == null) {
      throw const ImageCompressionException('formato no admitido');
    }
    return CompressedImage(bytes: bytes, format: format);
  }
}

void main() {
  group('sniffImageFormat', () {
    test('reconoce un WebP por RIFF/WEBP', () {
      expect(sniffImageFormat(_webp(64)), AvatarImageFormat.webp);
    });

    test('reconoce un JPEG por FF D8 FF', () {
      expect(sniffImageFormat(_jpeg(64)), AvatarImageFormat.jpeg);
    });

    // El caso de web: pedir WebP a un navegador que no sabe devuelve PNG SIN error.
    test('un PNG no es un formato admitido', () {
      expect(sniffImageFormat(_png(64)), isNull);
    });

    test('un RIFF que no es WEBP (un WAV) no cuela', () {
      final Uint8List wav = Uint8List(16);
      wav.setAll(0, <int>[0x52, 0x49, 0x46, 0x46]);
      wav.setAll(8, <int>[0x57, 0x41, 0x56, 0x45]); // "WAVE"
      expect(sniffImageFormat(wav), isNull);
    });

    test('un buffer mas corto que la firma no revienta', () {
      for (final int n in <int>[0, 1, 2, 3, 7, 11]) {
        expect(sniffImageFormat(Uint8List(n)), isNull, reason: 'longitud $n');
      }
    });
  });

  group('prepareAvatarUpload', () {
    test('un WebP que cabe se declara como image/webp', () async {
      final _FakeCompressor c = _FakeCompressor((int q) => _webp(1024));
      final PreparedUpload r = await prepareAvatarUpload(Uint8List(0), compressor: c);

      expect(r.format, AvatarImageFormat.webp);
      expect(r.mimeType, 'image/webp');
      expect(r.bytes.length, 1024);
    });

    // ESTE es el test de la decisión 0012 en el cliente: si el dispositivo produjo JPEG,
    // se declara JPEG. Declarar webp aquí es lo que provocaba el SignatureDoesNotMatch.
    test('si la plataforma produjo JPEG, se declara image/jpeg y NO image/webp', () async {
      final _FakeCompressor c = _FakeCompressor((int q) => _jpeg(1024));
      final PreparedUpload r = await prepareAvatarUpload(Uint8List(0), compressor: c);

      expect(r.format, AvatarImageFormat.jpeg);
      expect(r.mimeType, 'image/jpeg');
    });

    test('el tamano declarado es exactamente el numero de bytes', () async {
      final _FakeCompressor c = _FakeCompressor((int q) => _webp(4321));
      final PreparedUpload r = await prepareAvatarUpload(Uint8List(0), compressor: c);

      // ContentLength va firmado: un byte de diferencia es un 403 de R2.
      expect(r.sizeInBytes, 4321);
      expect(r.sizeInBytes, r.bytes.length);
    });

    test('si el resultado pasa de 200 KB, reintenta con menos calidad', () async {
      // Grande con la primera calidad, aceptable en cuanto baja.
      final _FakeCompressor c = _FakeCompressor(
        (int q) => q >= 85 ? _webp(300 * 1024) : _webp(150 * 1024),
      );
      final PreparedUpload r = await prepareAvatarUpload(Uint8List(0), compressor: c);

      expect(r.sizeInBytes, 150 * 1024);
      expect(c.qualitiesUsed.length, greaterThan(1));
      expect(c.qualitiesUsed.first, greaterThan(c.qualitiesUsed[1]));
    });

    test('exactamente 200 KB se acepta, no se reintenta', () async {
      final _FakeCompressor c = _FakeCompressor((int q) => _webp(200 * 1024));
      final PreparedUpload r = await prepareAvatarUpload(Uint8List(0), compressor: c);

      expect(r.sizeInBytes, 200 * 1024);
      expect(c.qualitiesUsed.length, 1);
    });

    test('si nunca baja de 200 KB, falla con un error legible y no sube nada', () async {
      final _FakeCompressor c = _FakeCompressor((int q) => _webp(500 * 1024));

      await expectLater(
        prepareAvatarUpload(Uint8List(0), compressor: c),
        throwsA(isA<ImageCompressionException>()),
      );
    });

    test('el error de compresion sube tal cual, no se traga', () async {
      final _FakeCompressor c = _FakeCompressor((int q) => _png(1024));

      await expectLater(
        prepareAvatarUpload(Uint8List(0), compressor: c),
        throwsA(isA<ImageCompressionException>()),
      );
    });
  });
}
