import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theming/grasp_palette.dart';
import '../theming/app_theme.dart';

/// La escena acuarelada del pie de `01-Start_Menu.jpeg`: colinas difusas, un
/// grupo de siluetas sentadas en círculo y vegetación en los bordes.
///
/// Es el ancla visual de toda la zona de autenticación — Start, Login y
/// Registro la comparten, y es lo que hace que las tres se lean como la misma
/// pantalla en tres momentos distintos.
class CalmScene extends StatefulWidget {
  const CalmScene({super.key, this.opacity = 1, this.animate = true});

  /// Se baja en Login/Registro, donde la escena pasa a ser fondo y no
  /// protagonista.
  final double opacity;
  final bool animate;

  @override
  State<CalmScene> createState() => _CalmSceneState();
}

class _CalmSceneState extends State<CalmScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Deliberadamente muy largo: la deriva debe percibirse solo si te quedas
    // mirando, nunca como una animación.
    duration: const Duration(seconds: 40),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(CalmScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final bool shouldAnimate =
        widget.animate &&
        !GraspMotion.of(context).isStill &&
        !MediaQuery.disableAnimationsOf(context);

    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
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
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Opacity(
          opacity: widget.opacity,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) => CustomPaint(
                size: Size.infinite,
                painter: _CalmScenePainter(
                  progress: _controller.value,
                  palette: context.palette,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalmScenePainter extends CustomPainter {
  const _CalmScenePainter({required this.progress, required this.palette});

  /// 0..1 en bucle. Alimenta la deriva de las capas.
  final double progress;

  /// La escena no se puede repintar "con otros colores" sin más: en claro las
  /// siluetas son **más oscuras** que el fondo y en oscuro tienen que ser
  /// **más claras**, o el grupo desaparece en el negro. Por eso el pintor
  /// recibe la paleta entera y no una lista de tonos.
  final GraspPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    if (w <= 0 || h <= 0) return;

    // Línea sobre la que "se sienta" el grupo.
    final double horizon = h * 0.72;

    _paintSkyGlow(canvas, size, horizon);
    _paintHills(canvas, size, horizon);
    _paintGathering(canvas, size, horizon);
    _paintFoliage(canvas, size);
  }

  /// Resplandor cálido detrás del grupo: da profundidad y separa las siluetas
  /// de las colinas sin necesitar contorno.
  void _paintSkyGlow(Canvas canvas, Size size, double horizon) {
    final Rect area = Rect.fromCircle(
      center: Offset(size.width * 0.5, horizon),
      radius: size.width * 0.62,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            // En oscuro el resplandor es un halo de marca muy tenue: si se
            // pintara con la misma opacidad que en claro sería una mancha
            // lechosa en mitad de la pantalla.
            palette.isDark
                ? palette.brand.withValues(alpha: 0.16)
                : palette.containerSubtle.withValues(alpha: 0.95),
            palette.isDark
                ? palette.brand.withValues(alpha: 0.06)
                : palette.outline.withValues(alpha: 0.35),
            palette.outline.withValues(alpha: 0),
          ],
          stops: const <double>[0, 0.55, 1],
        ).createShader(area),
    );
  }

  /// Tres bandas de colina, cada una más oscura y más lenta que la anterior.
  void _paintHills(Canvas canvas, Size size, double horizon) {
    // En claro las colinas se van oscureciendo hacia el frente; en oscuro se
    // van **aclarando**, que es como la profundidad se lee sobre fondo negro.
    final List<double> alphas = palette.isDark
        ? const <double>[0.20, 0.28, 0.38]
        : const <double>[0.28, 0.40, 0.55];
    final List<Color> tints = palette.isDark
        ? <Color>[palette.chip, palette.iconSoft, palette.brandStrong]
        : <Color>[palette.outline, palette.chip, palette.iconSoft];

    for (int layer = 0; layer < 3; layer++) {
      // Cada capa deriva a distinta velocidad: eso es lo que produce la
      // sensación de profundidad (parallax).
      final double drift =
          math.sin((progress * 2 * math.pi) + layer * 1.7) * size.width * 0.02;
      final double baseY = horizon - size.height * (0.26 - layer * 0.08);
      final double amplitude = size.height * (0.09 - layer * 0.02);

      final Path path = Path()..moveTo(-size.width * 0.1, size.height);
      path.lineTo(-size.width * 0.1, baseY);

      const int steps = 24;
      for (int i = 0; i <= steps; i++) {
        final double t = i / steps;
        final double x = -size.width * 0.1 + size.width * 1.2 * t;
        final double y =
            baseY -
            math.sin(t * math.pi * (1.6 + layer * 0.7) + drift + layer) *
                amplitude;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width * 1.1, size.height)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = tints[layer].withValues(alpha: alphas[layer])
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0 - layer * 1.5),
      );
    }
  }

  /// Las cuatro siluetas sentadas, mirándose. Las de fuera algo más pequeñas
  /// para insinuar el círculo en perspectiva.
  void _paintGathering(Canvas canvas, Size size, double horizon) {
    final double unit = size.height * 0.30;
    final List<({double x, double scale, double alpha})> people =
        <({double x, double scale, double alpha})>[
          (x: 0.28, scale: 0.88, alpha: 0.72),
          (x: 0.43, scale: 1.00, alpha: 0.82),
          (x: 0.58, scale: 1.00, alpha: 0.82),
          (x: 0.73, scale: 0.88, alpha: 0.72),
        ];

    for (final ({double x, double scale, double alpha}) person in people) {
      _paintSeatedPerson(
        canvas,
        center: Offset(size.width * person.x, horizon),
        height: unit * person.scale,
        paint: Paint()
          ..color = palette.brandStrong.withValues(alpha: person.alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  void _paintSeatedPerson(
    Canvas canvas, {
    required Offset center,
    required double height,
    required Paint paint,
  }) {
    final double x = center.dx;
    final double y = center.dy;

    // Torso: base ancha (piernas cruzadas) que se estrecha en los hombros.
    final Path body = Path()
      ..moveTo(x - height * 0.40, y)
      ..quadraticBezierTo(
        x - height * 0.34,
        y - height * 0.42,
        x - height * 0.20,
        y - height * 0.58,
      )
      ..quadraticBezierTo(
        x,
        y - height * 0.74,
        x + height * 0.20,
        y - height * 0.58,
      )
      ..quadraticBezierTo(
        x + height * 0.34,
        y - height * 0.42,
        x + height * 0.40,
        y,
      )
      ..close();

    canvas.drawPath(body, paint);
    canvas.drawCircle(Offset(x, y - height * 0.82), height * 0.16, paint);
  }

  /// Vegetación en las esquinas inferiores: enmarca la escena, como en el
  /// boceto, y evita que las siluetas queden flotando.
  void _paintFoliage(Canvas canvas, Size size) {
    final double sway = math.sin(progress * 2 * math.pi) * 0.05;

    // Izquierda y derecha, en espejo.
    for (final ({double x, double direction}) side
        in <({double x, double direction})>[
          (x: size.width * 0.06, direction: 1),
          (x: size.width * 0.94, direction: -1),
        ]) {
      for (int i = 0; i < 5; i++) {
        final double angle =
            side.direction * (-1.35 + i * 0.30) + sway * (1 + i * 0.2);
        final double length = size.height * (0.30 - i * 0.03);
        _paintLeaf(
          canvas,
          origin: Offset(side.x, size.height * 1.02),
          angle: angle,
          length: length,
          width: length * 0.20,
          paint: Paint()
            ..color = palette.brandStrong.withValues(alpha: 0.30 - i * 0.03)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
        );
      }
    }
  }

  void _paintLeaf(
    Canvas canvas, {
    required Offset origin,
    required double angle,
    required double length,
    required double width,
    required Paint paint,
  }) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    // -pi/2 para que el ángulo 0 apunte hacia arriba.
    canvas.rotate(angle - math.pi / 2);

    final Path leaf = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(length * 0.45, -width, length, 0)
      ..quadraticBezierTo(length * 0.45, width, 0, 0)
      ..close();

    canvas.drawPath(leaf, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CalmScenePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.palette != palette;
}
