import 'dart:ui';

import 'package:flutter/widgets.dart' show Matrix4;

/// Qué trozo de la imagen original queda dentro de la ventana de recorte.
///
/// POR QUÉ ESTO ES UNA FUNCIÓN PURA Y NO UN TROZO DEL WIDGET
///
/// Es la única parte del recorte que puede estar mal de forma silenciosa: si la conversión de
/// coordenadas se equivoca, no se rompe nada — simplemente se sube un encuadre distinto del que la
/// persona vio, y eso no lo detecta ningún test de widget ni salta a la vista en una prueba rápida.
/// Sacarla aquí permite comprobarla con números.
///
/// El recorrido de coordenadas tiene tres sistemas y hay que cruzarlos en orden:
///
///   1. **Ventana** — el cuadrado que se ve, de lado [viewportSide] y origen (0,0).
///   2. **Hijo** — la imagen ya escalada para cubrir la ventana, de tamaño [childSize].
///      [matrix] va de hijo → ventana; se invierte para ir al revés.
///   3. **Imagen** — píxeles reales del fichero, [imageSize]. Del hijo se pasa por un factor.
///
/// El rectángulo devuelto se recorta contra los límites de la imagen: un gesto puede sacar el
/// encuadre fuera, y pedirle a `drawImageRect` una región de fuera da un resultado indefinido.
Rect computeCropRect({
  required Matrix4 matrix,
  required double viewportSide,
  required Size childSize,
  required Size imageSize,
}) {
  // La inversa lleva un punto de la ventana al sistema del hijo. Con `InteractiveViewer` la matriz
  // solo tiene escala y traslación uniformes, así que basta con las dos esquinas.
  final Matrix4 inverse = Matrix4.inverted(matrix);

  final Vector3Like topLeft = _transform(inverse, 0, 0);
  final Vector3Like bottomRight = _transform(inverse, viewportSide, viewportSide);

  // Hijo → imagen. El hijo se dibuja con la imagen entera, así que el factor es uniforme.
  final double toImageX = imageSize.width / childSize.width;
  final double toImageY = imageSize.height / childSize.height;

  final double left = topLeft.x * toImageX;
  final double top = topLeft.y * toImageY;
  final double right = bottomRight.x * toImageX;
  final double bottom = bottomRight.y * toImageY;

  // Recorte contra la imagen: fuera de sus límites no hay píxeles que copiar.
  final double clampedLeft = left.clamp(0.0, imageSize.width);
  final double clampedTop = top.clamp(0.0, imageSize.height);
  final double clampedRight = right.clamp(0.0, imageSize.width);
  final double clampedBottom = bottom.clamp(0.0, imageSize.height);

  // Un rectángulo vacío o invertido reventaría el pintado; se devuelve la imagen entera, que es el
  // encuadre por defecto y nunca es peor que fallar.
  if (clampedRight <= clampedLeft || clampedBottom <= clampedTop) {
    return Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
  }

  return Rect.fromLTRB(clampedLeft, clampedTop, clampedRight, clampedBottom);
}

/// Tamaño con el que se dibuja la imagen dentro de la ventana antes de que nadie la toque.
///
/// Equivale a `BoxFit.cover`: el lado corto de la imagen se ajusta a la ventana y el largo se sale.
/// Así el encuadre inicial siempre llena el círculo — si se usara `contain`, una foto apaisada
/// dejaría dos franjas vacías dentro del avatar.
Size coverSize({required Size imageSize, required double viewportSide}) {
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    return Size(viewportSide, viewportSide);
  }
  final double scale = imageSize.width < imageSize.height
      ? viewportSide / imageSize.width
      : viewportSide / imageSize.height;
  return Size(imageSize.width * scale, imageSize.height * scale);
}

/// Punto transformado. `Matrix4.transform3` necesita un `Vector3` y aquí solo interesan x e y.
class Vector3Like {
  const Vector3Like(this.x, this.y);
  final double x;
  final double y;
}

Vector3Like _transform(Matrix4 m, double x, double y) {
  final List<double> s = m.storage;
  // Fila 0 y 1 de una transformación afín 2D: [sx 0 0 tx; 0 sy 0 ty; ...]
  final double nx = s[0] * x + s[4] * y + s[12];
  final double ny = s[1] * x + s[5] * y + s[13];
  return Vector3Like(nx, ny);
}
