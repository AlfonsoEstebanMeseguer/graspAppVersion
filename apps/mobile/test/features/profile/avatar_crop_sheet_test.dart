import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/avatar_crop_sheet.dart';

/// Un PNG de verdad, generado con el motor. La hoja decodifica la imagen antes de pintarla, así
/// que un buffer inventado no serviría: fallaría al decodificar y no llegaríamos a probar el gesto.
Future<Uint8List> _realPng({int width = 400, int height = 300}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF7C3AED),
  );
  final ui.Image image = await recorder.endRecording().toImage(width, height);
  final ByteData data = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!;
  image.dispose();
  return data.buffer.asUint8List();
}

/// Abre la hoja con una imagen real dentro y espera a que esté decodificada.
///
/// El baile de fases no es capricho, son dos reglas de `flutter_test` que chocan:
///
/// - **Nada de `pumpAndSettle`**: mientras decodifica se pinta un `CircularProgressIndicator`, que
///   es una animación infinita, y `pumpAndSettle` espera a que TODAS terminen. Se colgaría.
/// - **Nada de `pump` dentro de `runAsync`**, que lo prohíbe. Pero generar el PNG y decodificarlo
///   son trabajo asíncrono de verdad (el códec del motor) y **solo** avanzan dentro de `runAsync`.
///
/// De ahí el orden: montar → generar bytes (async) → tocar y pintar → esperar al códec (async) →
/// pintar otra vez.
Future<void> _openSheet(WidgetTester tester) async {
  Uint8List? bytes;
  await tester.runAsync(() async {
    bytes = await _realPng();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => AvatarCropSheet.show(context, bytes!),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await _pumpFrames(tester);

  // El códec corre aquí: `initState` de la hoja ya lo ha lanzado.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  await _pumpFrames(tester);
}

/// Avanza unos cuantos frames. Sustituye a `pumpAndSettle`, que aquí no puede usarse.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('la hoja se abre y decodifica la imagen', (
    WidgetTester tester,
  ) async {
    await _openSheet(tester);

    expect(find.text('Ajusta tu foto'), findsOneWidget);
    expect(find.text('Usar esta foto'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  // EL BUG QUE ESTE TEST FIJA: arrastrar hacia abajo para mover la foto cerraba la hoja, porque
  // ese gesto es el mismo con el que una hoja modal se descarta. Con dos cosas arrastrables una
  // encima de otra gana la de fuera, asi que se quedaba el gesto a medio encuadre.
  testWidgets('arrastrar hacia abajo NO cierra la hoja', (
    WidgetTester tester,
  ) async {
    await _openSheet(tester);

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 300));
    await _pumpFrames(tester);

    expect(
      find.text('Ajusta tu foto'),
      findsOneWidget,
      reason: 'el arrastre es para encuadrar, no para cerrar',
    );
  });

  testWidgets('tocar fuera tampoco la cierra', (WidgetTester tester) async {
    await _openSheet(tester);

    // Arriba del todo, fuera de la hoja: la zona del barrier.
    await tester.tapAt(const Offset(10, 10));
    await _pumpFrames(tester);

    expect(find.text('Ajusta tu foto'), findsOneWidget);
  });

  testWidgets('"Cancelar" SI la cierra, y es la salida', (
    WidgetTester tester,
  ) async {
    await _openSheet(tester);

    await tester.tap(find.text('Cancelar'));
    await _pumpFrames(tester);

    expect(find.text('Ajusta tu foto'), findsNothing);
  });

  testWidgets('el zoom con rueda es progresivo tambien al recortar', (
    WidgetTester tester,
  ) async {
    await _openSheet(tester);

    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.scaleFactor, greaterThanOrEqualTo(800));
  });
}
