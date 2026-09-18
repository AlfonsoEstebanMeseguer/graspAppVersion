import 'package:flutter/material.dart';

import '../theming/app_motion.dart';
import '../theming/app_theme.dart';

/// Aparición escalonada: cada hijo entra con un desfase, desvaneciéndose y
/// subiendo unos píxeles.
///
/// Es el gesto de entrada de todas las pantallas de autenticación. Está en un
/// solo sitio para que el ritmo sea idéntico en las tres y no se convierta en
/// "cada pantalla anima como le apetece".
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.children,
    this.interval = const Duration(milliseconds: 90),
    this.offset = 24,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.min,
  });

  final List<Widget> children;

  /// Desfase entre un hijo y el siguiente.
  final Duration interval;

  /// Cuánto sube cada hijo al entrar, en píxeles lógicos.
  final double offset;

  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow + widget.interval * widget.children.length,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final bool skip =
        GraspMotion.of(context).isStill ||
        MediaQuery.disableAnimationsOf(context);
    // Sin animación, el contenido debe estar visible desde el primer frame:
    // nunca invisible esperando a un controlador que no va a correr.
    _controller.value = skip ? 1 : 0;
    if (!skip) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int count = widget.children.length;
    final double totalMs = _controller.duration!.inMilliseconds.toDouble();
    final double stepMs = widget.interval.inMilliseconds.toDouble();

    return Column(
      mainAxisSize: widget.mainAxisSize,
      crossAxisAlignment: widget.crossAxisAlignment,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          _RevealSlot(
            controller: _controller,
            begin: (stepMs * i) / totalMs,
            end: ((stepMs * i) + AppMotion.slow.inMilliseconds) / totalMs,
            offset: widget.offset,
            child: widget.children[i],
          ),
      ],
    );
  }
}

class _RevealSlot extends StatelessWidget {
  const _RevealSlot({
    required this.controller,
    required this.begin,
    required this.end,
    required this.offset,
    required this.child,
  });

  final AnimationController controller;
  final double begin;
  final double end;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Interval(
        begin.clamp(0, 1),
        end.clamp(0, 1),
        curve: AppMotion.enter,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, (1 - animation.value) * offset),
          child: child,
        ),
      ),
    );
  }
}
