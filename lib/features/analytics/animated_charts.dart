// Анимированные виджеты для модуля «Аналитика»: плавное появление карточек,
// "растущие" графики (вертикальный и горизонтальный) с stagger-анимацией,
// анимированный счётчик. Без внешних пакетов — чистые Flutter-анимации.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

export '../../core/animations.dart' show FadeSlideIn, AnimatedCountText;

/// Элемент графика: подпись + значение.
class BarDatum {
  final String label;
  final double value;
  const BarDatum(this.label, this.value);
}

double _easeOut(double t) => Curves.easeOutCubic.transform(t);

/// Вертикальный растущий бар-график со stagger-анимацией.
class GrowingBarChart extends StatefulWidget {
  final List<BarDatum> data;
  final double height;
  final Color color;
  final int labelEvery; // показывать подпись каждые N столбцов
  final bool showValues;

  const GrowingBarChart({
    super.key,
    required this.data,
    this.height = 150,
    this.color = AppColors.accent,
    this.labelEvery = 1,
    this.showValues = false,
  });

  @override
  State<GrowingBarChart> createState() => _GrowingBarChartState();
}

class _GrowingBarChartState extends State<GrowingBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxV = data.map((d) => d.value).reduce(math.max);
    final n = data.length;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.showValues)
                          Text(
                            _fmt(data[i].value),
                            style: const TextStyle(
                                fontSize: 8.5, color: AppColors.textDim),
                          ),
                        const SizedBox(height: 3),
                        _bar(i, data[i].value, maxV, n),
                        const SizedBox(height: 4),
                        if (i % (widget.labelEvery <= 0 ? 1 : widget.labelEvery) == 0)
                          Text(
                            data[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 8.5, color: AppColors.textDim),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(int i, double v, double maxV, int n) {
    final p = _stagger(i, n);
    final h = (widget.height - 40) * (v / maxV) * p;
    final color = widget.color;
    return Container(
      width: double.infinity,
      height: h.clamp(0, widget.height - 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [color.withValues(alpha: .35), color],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      ),
    );
  }

  double _stagger(int i, int n) {
    final s = (i / n) * 0.55;
    final e = 0.55 + ((i + 1) / n) * 0.45;
    final raw = ((_c.value - s) / (e - s)).clamp(0.0, 1.0);
    return _easeOut(raw);
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}

/// Горизонтальный растущий бар-график со stagger-анимацией (по темам).
class GrowingHBarChart extends StatefulWidget {
  final List<BarDatum> data;
  final Color color;
  final String Function(double)? valueFormatter;
  final double itemHeight;

  const GrowingHBarChart({
    super.key,
    required this.data,
    this.color = AppColors.violet,
    this.valueFormatter,
    this.itemHeight = 26,
  });

  @override
  State<GrowingHBarChart> createState() => _GrowingHBarChartState();
}

class _GrowingHBarChartState extends State<GrowingHBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return const SizedBox.shrink();
    final maxV = data.map((d) => d.value).reduce(math.max);
    final n = data.length;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Column(
          children: [
            for (var i = 0; i < n; i++)
              Padding(
                padding: EdgeInsets.only(
                    bottom:
                        i == n - 1 ? 0 : widget.itemHeight * 0.18),
                child: _row(i, data[i], maxV, n),
              ),
          ],
        );
      },
    );
  }

  Widget _row(int i, BarDatum d, double maxV, int n) {
    final p = _stagger(i, n);
    final frac = (d.value / maxV).clamp(0.0, 1.0);
    final fmt = widget.valueFormatter ?? (v) => v.toStringAsFixed(0);
    return Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(
            d.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              final w = (cons.maxWidth * frac * p).clamp(0.0, cons.maxWidth);
              return Container(
                height: widget.itemHeight,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  height: widget.itemHeight,
                  width: w,
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.color.withValues(alpha: .4),
                        widget.color,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            fmt(d.value),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: widget.color,
            ),
          ),
        ),
      ],
    );
  }

  double _stagger(int i, int n) {
    final s = (i / n) * 0.6;
    final e = 0.6 + ((i + 1) / n) * 0.4;
    final raw = ((_c.value - s) / (e - s)).clamp(0.0, 1.0);
    return _easeOut(raw);
  }
}

