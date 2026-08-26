// Общий набор анимированных виджетов для всего приложения.
// Единый источник: плавное появление (FadeSlideIn), анимированные числа
// (AnimatedCounter / AnimatedCountText), ступенчатое проявление списков
// (staggerChildren), эффект нажатия (TappableScale) и кольцо прогресса
// (AnimatedRing). Без внешних пакетов — чистые Flutter-анимации.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Плавное появление (fade + slide up) с задержкой [delayMs] для ступенчатости.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final double slide;
  final Duration duration;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.slide = 24,
    this.duration = const Duration(milliseconds: 480),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _op;
  late final Animation<Offset> _pos;
  late final double _delayFrac;

  @override
  void initState() {
    super.initState();
    final delay = widget.delayMs.clamp(0, 4000);
    final total = widget.duration.inMilliseconds + delay;
    _delayFrac = total == 0 ? 0 : delay / total;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    // Задержка «вшита» в Interval, поэтому нет отдельного Timer — анимация
    // идёт кадрами (их pumpAndSettle доводит до конца).
    _op = CurvedAnimation(
      parent: _c,
      curve: Interval(_delayFrac, 1, curve: Curves.easeOutCubic),
    );
    _pos = Tween<Offset>(
      begin: Offset(0, widget.slide / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _c,
      curve: Interval(_delayFrac, 1, curve: Curves.easeOutCubic),
    ));
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _op,
      child: SlideTransition(position: _pos, child: widget.child),
    );
  }
}

/// Анимированный счётчик (count-up) до [target] — целое/дробное число.
class AnimatedCountText extends StatelessWidget {
  final double target;
  final int decimals;
  final String suffix;
  final TextStyle? style;

  const AnimatedCountText({
    super.key,
    required this.target,
    this.decimals = 0,
    this.suffix = '',
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = decimals == 0
        ? (double v) => v.toStringAsFixed(0)
        : (double v) => v.toStringAsFixed(decimals);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        '${fmt(v)}$suffix',
        style: style ?? const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
      ),
    );
  }
}

/// Оборачивает список [Widget]-ов в ступенчатое появление (fade + slide).
List<Widget> staggerChildren(
  List<Widget> children, {
  int intervalMs = 70,
  int startMs = 0,
}) {
  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    out.add(FadeSlideIn(
      delayMs: startMs + i * intervalMs,
      child: children[i],
    ));
  }
  return out;
}

/// Анимированное число (count-up) до [value] с форматтером.
class AnimatedCounter extends StatelessWidget {
  final double value;
  final String Function(double value)? formatter;
  final String suffix;
  final Duration duration;
  final TextStyle? style;
  final int decimals;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.formatter,
    this.suffix = '',
    this.decimals = 0,
    this.duration = const Duration(milliseconds: 850),
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = formatter ??
        (decimals == 0
            ? (double v) => v == v.roundToDouble()
                ? v.toInt().toString()
                : v.toStringAsFixed(decimals)
            : (double v) => v.toStringAsFixed(decimals));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) =>
          Text('${fmt(v)}$suffix', style: style),
    );
  }
}

/// Эффект «нажатия»: карточка слегка сжимается при press и возвращается.
/// Использует Listener (сырые pointer-события), поэтому НЕ конфликтует
/// с вложенным InkWell/GestureDetector — тап обрабатывает ребёнок.
class TappableScale extends StatefulWidget {
  final Widget child;
  final double scale;
  final double top;

  const TappableScale({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.top = 1.0,
  });

  @override
  State<TappableScale> createState() => _TappableScaleState();
}

class _TappableScaleState extends State<TappableScale> {
  bool _pressed = false;

  double get _value => _pressed ? widget.scale : widget.top;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _value,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Кольцо прогресса (от 0 до [progress]) вокруг [child] с плавной отрисовкой.
class AnimatedRing extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final double stroke;
  final Color color;
  final Color trackColor;
  final Widget? child;

  const AnimatedRing({
    super.key,
    required this.progress,
    this.size = 64,
    this.stroke = 8,
    this.color = AppColors.accent,
    this.trackColor = const Color(0xFF2A2A3A),
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _RingPainter(
              progress: value,
              stroke: stroke,
              color: color,
              trackColor: trackColor,
            ),
            child: Center(child: child),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double stroke;
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.stroke,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = color;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
