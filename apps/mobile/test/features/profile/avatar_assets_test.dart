import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/domain/profile/avatar_type.dart';

/// Los avatares se pintan con `Image.asset(...)` bajo un `errorBuilder` que
/// sustituye la imagen rota por un icono. Eso significa que un PNG corrupto NO
/// se ve como un fallo en pantalla: se ve como un icono gris plausible.
///
/// Por eso los assets se validan aquí, contra el decodificador real de Flutter,
/// y no mirando la UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('assets de avatares', () {
    testWidgets('cada avatar declarado se decodifica como imagen válida', (
      WidgetTester tester,
    ) async {
      final List<String> rotos = <String>[];

      await tester.runAsync(() async {
        for (final AvatarType avatar in AvatarType.values) {
          try {
            final ByteData data = await rootBundle.load(avatar.assetPath);
            final ui.Codec codec = await ui.instantiateImageCodec(
              data.buffer.asUint8List(),
            );
            final ui.FrameInfo frame = await codec.getNextFrame();
            if (frame.image.width <= 0 || frame.image.height <= 0) {
              rotos.add('${avatar.assetPath}: dimensiones inválidas');
            }
            frame.image.dispose();
            codec.dispose();
          } catch (e) {
            rotos.add('${avatar.assetPath}: $e');
          }
        }
      });

      expect(
        rotos,
        isEmpty,
        reason: 'Assets que Flutter no puede decodificar:\n${rotos.join('\n')}',
      );
    });

    testWidgets('los 8 avatares son imágenes distintas entre sí', (
      WidgetTester tester,
    ) async {
      final Map<String, List<String>> porContenido = <String, List<String>>{};

      await tester.runAsync(() async {
        for (final AvatarType avatar in AvatarType.values) {
          final ByteData data = await rootBundle.load(avatar.assetPath);
          final Uint8List bytes = data.buffer.asUint8List();
          // Huella barata pero suficiente para detectar ficheros clonados.
          final String huella = '${bytes.length}:'
              '${bytes.fold<int>(0, (int a, int b) => (a * 31 + b) & 0x7fffffff)}';
          porContenido.putIfAbsent(huella, () => <String>[]).add(avatar.name);
        }
      });

      final Iterable<List<String>> duplicados =
          porContenido.values.where((List<String> g) => g.length > 1);

      expect(
        duplicados,
        isEmpty,
        reason: 'Hay avatares con bytes idénticos (placeholders sin generar): '
            '${duplicados.map((List<String> g) => g.join(' == ')).join(' | ')}',
      );
    });
  });

  /// Los slugs son un contrato con la base de datos, no un detalle de la app: el
  /// `check` `profiles_preset_avatar_valid` (20260813090000) sólo acepta estos ocho
  /// valores. Si alguien renombra uno aquí, el backend rechazará el `UPDATE` y el
  /// usuario no podrá cambiar de avatar — un fallo que se descubriría en ejecución.
  /// Este grupo lo convierte en un test rojo.
  group('slugs de avatar (contrato con profiles.preset_avatar)', () {
    test('el conjunto de slugs es exactamente el dominio del check', () {
      expect(
        AvatarType.values.map((AvatarType a) => a.slug).toSet(),
        <String>{
          'gym',
          'reader',
          'music',
          'coding',
          'animal',
          'normal_1',
          'normal_2',
          'normal_3',
        },
        reason: 'Divergen de profiles_preset_avatar_valid en '
            '20260813090000_add_preset_avatar_to_profiles.sql',
      );
    });

    test('los slugs no se derivan del nombre de la constante', () {
      // Si alguien "simplifica" usando `avatar.name`, esto se pone rojo: en Dart es
      // normalOne y en SQL normal_1.
      expect(AvatarType.normalOne.slug, 'normal_1');
      expect(AvatarType.normalOne.name, 'normalOne');
    });

    test('cada slug es único', () {
      expect(
        AvatarType.values.map((AvatarType a) => a.slug).toSet().length,
        AvatarType.values.length,
      );
    });

    test('fromSlug resuelve todos los avatares declarados', () {
      for (final AvatarType avatar in AvatarType.values) {
        expect(AvatarType.fromSlug(avatar.slug), avatar);
      }
    });

    test('fromSlug devuelve null si el backend manda algo que la app no conoce', () {
      // Una app vieja contra un backend nuevo: cae al placeholder, no revienta.
      expect(AvatarType.fromSlug('avatar_del_futuro'), isNull);
      expect(AvatarType.fromSlug(null), isNull);
      expect(AvatarType.fromSlug('normalOne'), isNull);
    });
  });
}