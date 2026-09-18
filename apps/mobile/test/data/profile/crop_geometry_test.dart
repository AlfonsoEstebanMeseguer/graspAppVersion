import 'dart:ui';

import 'package:flutter/widgets.dart' show Matrix4;
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/profile/crop_geometry.dart';

/// Tolerancia para comparar dobles: las matrices arrastran error de coma flotante.
void expectRect(Rect actual, Rect expected, {double tolerance = 0.01}) {
  expect(actual.left, closeTo(expected.left, tolerance), reason: 'left');
  expect(actual.top, closeTo(expected.top, tolerance), reason: 'top');
  expect(actual.right, closeTo(expected.right, tolerance), reason: 'right');
  expect(actual.bottom, closeTo(expected.bottom, tolerance), reason: 'bottom');
}

void main() {
  group('coverSize', () {
    test('una imagen apaisada se ajusta por el alto y se sale por los lados', () {
      // 800x400 en una ventana de 300: el lado corto (400) manda.
      final Size s = coverSize(
        imageSize: const Size(800, 400),
        viewportSide: 300,
      );
      expect(s.height, closeTo(300, 0.01));
      expect(s.width, closeTo(600, 0.01));
    });

    test('una imagen vertical se ajusta por el ancho', () {
      final Size s = coverSize(
        imageSize: const Size(400, 800),
        viewportSide: 300,
      );
      expect(s.width, closeTo(300, 0.01));
      expect(s.height, closeTo(600, 0.01));
    });

    test('una imagen cuadrada llena la ventana exactamente', () {
      final Size s = coverSize(
        imageSize: const Size(500, 500),
        viewportSide: 300,
      );
      expect(s.width, closeTo(300, 0.01));
      expect(s.height, closeTo(300, 0.01));
    });

    // Nunca deja franjas vacías dentro del círculo del avatar.
    test('el resultado siempre cubre la ventana entera', () {
      for (final Size image in <Size>[
        const Size(1000, 200),
        const Size(200, 1000),
        const Size(37, 41),
      ]) {
        final Size s = coverSize(imageSize: image, viewportSide: 300);
        expect(s.width, greaterThanOrEqualTo(299.99), reason: '$image');
        expect(s.height, greaterThanOrEqualTo(299.99), reason: '$image');
      }
    });

    test('una imagen degenerada no revienta', () {
      expect(
        coverSize(imageSize: const Size(0, 0), viewportSide: 300),
        const Size(300, 300),
      );
    });
  });

  group('computeCropRect', () {
    // Caso base: imagen cuadrada, sin tocar nada. Se recorta la imagen entera.
    test('sin gesto y con imagen cuadrada, el recorte es la imagen entera', () {
      final Rect r = computeCropRect(
        matrix: Matrix4.identity(),
        viewportSide: 300,
        childSize: const Size(300, 300),
        imageSize: const Size(600, 600),
      );
      expectRect(r, const Rect.fromLTRB(0, 0, 600, 600));
    });

    // Apaisada sin tocar: la ventana ve la franja central... no, ve la IZQUIERDA, porque el hijo
    // se dibuja desde su origen. Es lo que hay que fijar para que nadie lo "arregle" al revés.
    test('apaisada sin gesto: se ve la parte izquierda, no la central', () {
      final Rect r = computeCropRect(
        matrix: Matrix4.identity(),
        viewportSide: 300,
        childSize: const Size(600, 300), // cover de una 800x400
        imageSize: const Size(800, 400),
      );
      // La ventana (0..300) sobre un hijo de 600 de ancho = la mitad izquierda de la imagen.
      expectRect(r, const Rect.fromLTRB(0, 0, 400, 400));
    });

    test('un desplazamiento mueve el recorte en sentido contrario', () {
      // Arrastrar el contenido 150 px a la IZQUIERDA enseña la parte derecha.
      final Matrix4 m = Matrix4.identity()..translateByDouble(-150.0, 0.0, 0.0, 1.0);
      final Rect r = computeCropRect(
        matrix: m,
        viewportSide: 300,
        childSize: const Size(600, 300),
        imageSize: const Size(800, 400),
      );
      // Ventana 150..450 del hijo -> 200..600 de la imagen.
      expectRect(r, const Rect.fromLTRB(200, 0, 600, 400));
    });

    test('el zoom encoge el recorte: se ve menos imagen', () {
      final Matrix4 m = Matrix4.identity()..scaleByDouble(2.0, 2.0, 1.0, 1.0);
      final Rect r = computeCropRect(
        matrix: m,
        viewportSide: 300,
        childSize: const Size(300, 300),
        imageSize: const Size(600, 600),
      );
      // Con doble zoom se ve la cuarta parte: el cuadrante superior izquierdo.
      expectRect(r, const Rect.fromLTRB(0, 0, 300, 300));
    });

    test('zoom mas desplazamiento se combinan', () {
      final Matrix4 m = Matrix4.identity()
        ..translateByDouble(-150.0, -150.0, 0.0, 1.0)
        ..scaleByDouble(2.0, 2.0, 1.0, 1.0);
      final Rect r = computeCropRect(
        matrix: m,
        viewportSide: 300,
        childSize: const Size(300, 300),
        imageSize: const Size(600, 600),
      );
      expectRect(r, const Rect.fromLTRB(150, 150, 450, 450));
    });

    // Un gesto puede sacar el encuadre fuera de la imagen; pedirle esa región a drawImageRect
    // da un resultado indefinido.
    test('un encuadre que se sale se recorta contra los limites de la imagen', () {
      final Matrix4 m = Matrix4.identity()..translateByDouble(200.0, 200.0, 0.0, 1.0);
      final Rect r = computeCropRect(
        matrix: m,
        viewportSide: 300,
        childSize: const Size(300, 300),
        imageSize: const Size(600, 600),
      );
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(600));
      expect(r.bottom, lessThanOrEqualTo(600));
    });

    test('un encuadre completamente fuera cae a la imagen entera, no a un rect vacio', () {
      final Matrix4 m = Matrix4.identity()..translateByDouble(5000.0, 5000.0, 0.0, 1.0);
      final Rect r = computeCropRect(
        matrix: m,
        viewportSide: 300,
        childSize: const Size(300, 300),
        imageSize: const Size(600, 600),
      );
      expectRect(r, const Rect.fromLTRB(0, 0, 600, 600));
    });

    test('el recorte nunca tiene lado cero o negativo', () {
      for (final double dx in <double>[-10000, -500, 0, 500, 10000]) {
        final Rect r = computeCropRect(
          matrix: Matrix4.identity()..translateByDouble(dx, 0.0, 0.0, 1.0),
          viewportSide: 300,
          childSize: const Size(600, 300),
          imageSize: const Size(800, 400),
        );
        expect(r.width, greaterThan(0), reason: 'dx=$dx');
        expect(r.height, greaterThan(0), reason: 'dx=$dx');
      }
    });
  });
}
