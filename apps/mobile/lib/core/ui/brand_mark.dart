import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theming/grasp_palette.dart';
import '../theming/app_theme.dart';

/// La marca de Grasp: el cerebro de contorno de `pictures/icons/icon-sketches.jpeg`
/// y `01-Start_Menu.jpeg`.
///
/// Se dibuja con `CustomPainter` en vez de con un asset raster para que escale
/// sin pixelar, herede el color del tema y pueda animarse (el trazo "respira",
/// que es lo que le da a la pantalla de bienvenida su carácter calmado).
class BrandMark extends StatefulWidget {
  const BrandMark({
    super.key,
    this.size = 88,
    this.color,
    this.animate = true,
  });

  final double size;

  /// Nulo = "el de la marca en el tema activo". No puede tener un valor por
  /// defecto constante: el trazo es `purple700` en claro y `lavender200` en
  /// oscuro, y un `const` no ve el tema.
  final Color? color;

  /// Desactivable para tests y para `MediaQuery.disableAnimations`.
  final bool animate;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(BrandMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final bool shouldAnimate =
        widget.animate &&
        !GraspMotion.of(context).isStill &&
        !MediaQuery.disableAnimationsOf(context);

    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Grasp',
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            // Respiración muy contenida: 3% de escala. Más se nota como "algo
            // se mueve"; así solo se percibe que la pantalla está viva.
            final double breath = math.sin(_controller.value * math.pi);
            return Transform.scale(
              scale: 1 + breath * 0.03,
              child: CustomPaint(
                painter: _BrainPainter(
                  color: widget.color ?? context.palette.brandStrong,
                  haloColor: context.palette.chip,
                  fillColor: context.palette.containerSubtle,
                  glow: 0.35 + breath * 0.35,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrainPainter extends CustomPainter {
  const _BrainPainter({
    required this.color,
    required this.haloColor,
    required this.fillColor,
    required this.glow,
  });

  final Color color;

  /// El halo y el relleno se pasan resueltos: un `CustomPainter` no tiene
  /// contexto, así que la paleta se lee arriba, en el `build`.
  final Color haloColor;
  final Color fillColor;

  /// 0..1 — intensidad del halo que rodea al trazo.
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    // Todo el dibujo está definido en una caja de 100×100 y se escala aquí, de
    // forma que los números del path se puedan leer como porcentajes.
    final double scale = size.shortestSide / 100;
    canvas.save();
    canvas.translate(
      (size.width - 100 * scale) / 2,
      (size.height - 100 * scale) / 2,
    );
    canvas.scale(scale);

    final double stroke = 4.2;

    // Halo: el mismo trazo, difuminado y muy transparente.
    final Paint haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = haloColor.withValues(alpha: 0.30 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final Paint fill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor.withValues(alpha: 0.55);

    for (final bool mirrored in <bool>[false, true]) {
      canvas.save();
      if (mirrored) {
        // La segunda mitad es la primera reflejada sobre el eje vertical.
        canvas.translate(100, 0);
        canvas.scale(-1, 1);
      }
      final Path outline = _hemisphereOutline();
      canvas.drawPath(outline, fill);
      canvas.drawPath(outline, haloPaint);
      canvas.drawPath(outline, line);
      canvas.drawPath(_hemisphereFolds(), line);
      canvas.drawPath(_stem(), line);
      canvas.restore();
    }

    canvas.restore();
  }

  /// Contorno de la mitad izquierda, de la coronilla a la base, cerrando por el
  /// eje central (que así queda dibujado como la separación entre hemisferios).
  Path _hemisphereOutline() => Path()
    ..moveTo(50, 7)
    ..cubicTo(42, 1, 29, 2, 25, 10)
    ..cubicTo(15, 8, 8, 17, 11, 26)
    ..cubicTo(3, 31, 3, 43, 11, 48)
    ..cubicTo(5, 54, 7, 65, 15, 69)
    ..cubicTo(14, 79, 24, 87, 34, 84)
    ..cubicTo(38, 89, 46, 90, 50, 85)
    ..lineTo(50, 7)
    ..close();

  /// Los pliegues internos. Son trazos sueltos, no un contorno cerrado.
  Path _hemisphereFolds() => Path()
    ..moveTo(25, 10)
    ..cubicTo(31, 17, 25, 23, 18, 21)
    ..moveTo(11, 26)
    ..cubicTo(21, 28, 27, 34, 24, 41)
    ..moveTo(24, 41)
    ..cubicTo(33, 42, 39, 36, 38, 28)
    ..moveTo(11, 48)
    ..cubicTo(21, 46, 31, 50, 31, 58)
    ..moveTo(31, 58)
    ..cubicTo(39, 57, 43, 52, 41, 46)
    ..moveTo(15, 69)
    ..cubicTo(23, 66, 33, 71, 33, 79);

  /// El tallo bajo la base, apenas insinuado.
  Path _stem() => Path()
    ..moveTo(44, 85)
    ..cubicTo(44, 91, 47, 95, 50, 96);

  @override
  bool shouldRepaint(_BrainPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.glow != glow ||
      oldDelegate.haloColor != haloColor ||
      oldDelegate.fillColor != fillColor;
}
