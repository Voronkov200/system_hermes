// Утилиты форматирования (без внешних локалей — всё вручную).

import 'package:flutter/material.dart';

/// Формат числа с 2 знаками.
String fmt2(double v) => v.toStringAsFixed(2);

/// Формат числа с 0 знаков.
String fmt0(double v) => v.round().toString();

/// Дата вида 05.08.2026.
String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Время вида 14:05.
String fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Дата+время.
String fmtDateTime(DateTime d) => '${fmtDate(d)} ${fmtTime(d)}';

/// Ключ текущего месяца вида 2026-08.
String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Название месяца по-русски.
const ruMonths = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

/// Человекочитаемый интервал (например, "1 ч 20 мин").
String fmtDuration(DateTime from, DateTime to) {
  final d = to.difference(from);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '$h ч $m мин';
  if (m > 0) return '$m мин';
  return '${d.inSeconds} сек';
}

/// Показ тоста.
void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
