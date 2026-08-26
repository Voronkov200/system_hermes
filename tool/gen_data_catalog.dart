// DEV: генерирует канонический каталог данных для синка.
//
// Читает реальные файлы чеков из test/fixtures/ (TXT + XLSX), распознаёт их
// парсером и пишет data/receipts.json в каноническом формате, который
// использует и агент-издатель (PCLite), и приложение (pull + upsert).
// Также копирует каталог цен в data/prices.json.
//
// Формат записи data/receipts.json:
//   {"store","address","dateTime":"21.07.2026 12:52","total","discount",
//    "paymentMethod","sourceType","confidence","items":[{"name","qty","unitPrice","amount"}]}
//
// Запуск: dart run tool/gen_data_catalog.dart
//
// ignore_for_file: avoid_print // CLI-утилита, выводит отчёт в консоль.

import 'dart:convert';
import 'dart:io';

import 'package:system_hermes/data/models.dart';
import 'package:system_hermes/services/receipt_parser.dart';

String _pad(int n) => n.toString().padLeft(2, '0');

String _fmtDateTime(DateTime d) =>
    '${_pad(d.day)}.${_pad(d.month)}.${d.year} ${_pad(d.hour)}:${_pad(d.minute)}';

Map<String, Object?> _canonical(Receipt r) => {
      'store': r.store,
      if (r.address != null && r.address!.isNotEmpty) 'address': r.address,
      'dateTime': _fmtDateTime(r.dateTime),
      'total': r.total,
      if (r.discount != 0) 'discount': r.discount,
      if (r.paymentMethod != null && r.paymentMethod!.isNotEmpty)
        'paymentMethod': r.paymentMethod,
      'sourceType': r.sourceType,
      'confidence': 0.98, // получено из структурированного файла — уверенно
      'items': [
        for (final it in r.items)
          {
            'name': it.name,
            'qty': it.quantity,
            'unitPrice': it.unitPrice,
            'amount': it.amount,
          },
      ],
    };

List<Object?> _collect() {
  final out = <Object?>[];

  final txt = File('test/fixtures/Чек_2026-07-21_ТРОЙКА.txt');
  if (txt.existsSync()) {
    final r = parseTxtReceipt(txt.readAsStringSync(), txt.path);
    if (r != null) out.add(_canonical(r));
  }

  const singleXlsx = 'test/fixtures/Чек_2026-07-12_ЕВРООПТ.xlsx';
  if (File(singleXlsx).existsSync()) {
    for (final r in parseXlsxReceipts(File(singleXlsx).readAsBytesSync(),
        singleXlsx)) {
      out.add(_canonical(r));
    }
  }

  const multiXlsx = 'test/fixtures/Чеки_2026-07-14_ТРОЙКА_ГИППО_МЯСТОРГ.xlsx';
  if (File(multiXlsx).existsSync()) {
    for (final r in parseXlsxReceipts(
        File(multiXlsx).readAsBytesSync(), multiXlsx)) {
      out.add(_canonical(r));
    }
  }

  return out;
}

void main() {
  final receipts = _collect();
  final dir = Directory('data');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  File('data/receipts.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(receipts),
  );
  print('data/receipts.json: ${receipts.length} чек(а/ов)');

  const pricesAsset = 'assets/data/prices/prices.json';
  if (File(pricesAsset).existsSync()) {
    File('data/prices.json').writeAsStringSync(
      File(pricesAsset).readAsStringSync(),
    );
    print('data/prices.json: скопирован из assets');
  } else {
    print('data/prices.json: НЕ найден исходник $pricesAsset');
  }
}
