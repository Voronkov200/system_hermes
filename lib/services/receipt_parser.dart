// Парсеры чеков покупок (TXT / XLSX) и каталога цен (JSON).
//
// Файл — «чистые» функции без обращения к файловой системе и без записи
// в Hive: разбирают содержимое (строку / байты) в модели. Это позволяет
// покрыть их юнит-тестами и не завязывать логику на Android/Desktop.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../data/models.dart';

/// Разобрать число из строки вида «1,93», «42,10», «2.14», «−0,6»,
/// «31,94 BYN», «1,70 кг». Возвращает последнюю найденную величину.
double parseAmount(dynamic value) {
  if (value == null) return 0;
  var s = value.toString().trim();
  if (s.isEmpty) return 0;
  // Унифицируем минусы-тире (минус U+2212, тире, но не «дефис» внутри слов).
  s = s.replaceAll(RegExp('[−–—–]'), '-');
  final matches =
      RegExp(r'-?\d+[.,]?\d*').allMatches(s).map((m) => m.group(0)!).toList();
  if (matches.isEmpty) return 0;
  var num = matches.last;
  num = num.replaceAll(',', '.').replaceAll(' ', '');
  final d = double.tryParse(num);
  return d ?? 0;
}

/// Разобрать дату из строк вида «21.07.2026 12:52», «11.07.2026 21:15:30»,
/// «2026-07-15», «16.07.2026». При неудаче возвращает null.
DateTime? parseDate(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  var m = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})(?:[ ](\d{1,2}):(\d{2})(?::(\d{2}))?)?')
      .firstMatch(s);
  if (m != null) {
    return DateTime(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
      int.parse(m.group(4) ?? '0'),
      int.parse(m.group(5) ?? '0'),
      int.parse(m.group(6) ?? '0'),
    );
  }
  m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (m != null) {
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }
  return null;
}

// =====================================================================
// Разбор листа XLSX в сетку (имя листа + строки ячеек)
// =====================================================================

class XlsxSheetData {
  final String name;
  final List<List<String>> rows;
  XlsxSheetData(this.name, this.rows);
}

int _colIndex(String ref) {
  final letters = ref.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
  var n = 0;
  for (final ch in letters.codeUnits) {
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

XmlElement? _first(Iterable<XmlElement> it) => it.isEmpty ? null : it.first;

String _cellText(XmlElement c, List<String> shared) {
  final t = c.getAttribute('t');
  if (t == 'inlineStr') {
    final isEl = _first(c.findElements('is', namespace: '*'));
    if (isEl == null) return '';
    return isEl
        .findAllElements('t', namespace: '*')
        .map((e) => e.innerText)
        .join();
  }
  if (t == 's') {
    final v = _first(c.findElements('v', namespace: '*'));
    if (v == null) return '';
    final idx = int.tryParse(v.innerText);
    if (idx == null || idx < 0 || idx >= shared.length) return '';
    return shared[idx];
  }
  final v = _first(c.findElements('v', namespace: '*'));
  return v?.innerText ?? '';
}

/// Прочитать все листы XLSX как сетки строк. Названия товаров в этом формате
/// хранятся как inline-строки (`t="inlineStr"`), поэтому sharedStrings не обязателен.
List<XlsxSheetData> readXlsxSheets(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  final shared = <String>[];
  final sf = archive.findFile('xl/sharedStrings.xml');
  if (sf != null) {
    final doc = XmlDocument.parse(utf8.decode(sf.readBytes()!));
    for (final si in doc.findAllElements('si', namespace: '*')) {
      shared.add(si
          .findAllElements('t', namespace: '*')
          .map((e) => e.innerText)
          .join());
    }
  }

  final sheetRefs = <MapEntry<String, String>>[];
  final wb = archive.findFile('xl/workbook.xml');
  if (wb != null) {
    final doc = XmlDocument.parse(utf8.decode(wb.readBytes()!));
    for (final s in doc.findAllElements('sheet', namespace: '*')) {
      final name = s.getAttribute('name') ?? '';
      final rid = s.getAttribute('r:id') ??
          s.getAttribute('id') ??
          '';
      if (name.isNotEmpty && rid.isNotEmpty) {
        sheetRefs.add(MapEntry(name, rid));
      }
    }
  }

  final rels = <String, String>{};
  final relFile = archive.findFile('xl/_rels/workbook.xml.rels');
  if (relFile != null) {
    final doc = XmlDocument.parse(utf8.decode(relFile.readBytes()!));
    for (final r in doc.findAllElements('Relationship', namespace: '*')) {
      rels[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
    }
  }

  final result = <XlsxSheetData>[];
  for (final ref in sheetRefs) {
    var target = rels[ref.value] ?? '';
    if (target.isEmpty) continue;
    target = target.startsWith('/')
        ? target.substring(1)
        : (target.startsWith('xl/') ? target : 'xl/$target');
    final f = archive.findFile(target);
    if (f == null) continue;
    final doc = XmlDocument.parse(utf8.decode(f.readBytes()!));
    final grid = <List<String>>[];
    for (final row in doc.findAllElements('row', namespace: '*')) {
      final cells = <String>[];
      for (final c in row.findElements('c', namespace: '*')) {
        final col = _colIndex(c.getAttribute('r') ?? '');
        while (cells.length <= col) {
          cells.add('');
        }
        cells[col] = _cellText(c, shared);
      }
      grid.add(cells);
    }
    result.add(XlsxSheetData(ref.key, grid));
  }
  return result;
}

// =====================================================================
// Разбор TXT-чека (одномагазинный)
// =====================================================================

Receipt? parseTxtReceipt(String content, String sourcePath,
    {DateTime? now}) {
  final lines = content.split(RegExp(r'\r?\n'));
  String? store;
  String? address;
  DateTime? dt;
  String? payment;
  double total = 0;
  final items = <ReceiptItem>[];
  var order = 0;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('Магазин:')) {
      store = line.substring('Магазин:'.length).trim();
      continue;
    }
    if (line.startsWith('Адрес:')) {
      address = line.substring('Адрес:'.length).trim();
      continue;
    }
    if (line.startsWith('Дата:')) {
      dt = parseDate(line);
      continue;
    }
    // Позиция: «N. Название — 12.34»
    final item = RegExp(r'^\s*(\d+)\.\s+(.+?)\s+[—–-]\s+([\d.,]+)\s*$')
        .firstMatch(line);
    if (item != null) {
      order++;
      final name = item.group(2)!.trim();
      final amount = parseAmount(item.group(3));
      final weight = RegExp(r'([\d.,]+)\s*кг').firstMatch(name);
      double qty = weight != null ? parseAmount(weight.group(1)) : 1;
      final mul = RegExp(r'[×xх*]\s*([\d.,]+)').firstMatch(name);
      double unitPrice = 0;
      if (mul != null) {
        if (weight != null) {
          unitPrice = parseAmount(mul.group(1)); // вес × цена за кг
        } else {
          qty = parseAmount(mul.group(1)); // «×2» — количество штук
        }
      }
      if (unitPrice <= 0) unitPrice = amount / (qty > 0 ? qty : 1);
      items.add(ReceiptItem(
        order: order,
        name: name,
        quantity: qty,
        unitPrice: unitPrice,
        amount: amount,
      ));
      continue;
    }
    if (line.startsWith('ИТОГО:')) {
      total = parseAmount(line);
      final pm = RegExp(r'\((.*?)\)').firstMatch(line);
      if (pm != null) payment = pm.group(1);
    }
  }

  if (store == null || store.isEmpty) return null;
  final nowActual = now ?? DateTime.now();
  return Receipt(
    id: genId(),
    store: store,
    address: address,
    dateTime: dt ?? nowActual,
    total: total,
    discount: 0,
    paymentMethod: payment,
    items: items,
    sourcePath: sourcePath,
    sourceType: 'txt',
    importedAt: nowActual,
  );
}

// =====================================================================
// Разбор XLSX-чеков (одно- и мульти-магазинный)
// =====================================================================

class _Cols {
  int? order;
  int? name;
  int? qty;
  int? price;
  int? amount;
  int? barcode;
  int? discount;

  bool get valid => name != null && (qty != null || amount != null);
}

class _Meta {
  String? store;
  String? address;
  String? payment;
  DateTime? date;
  double? total;
}

bool _isSummarySheet(String name) {
  final n = name.toLowerCase();
  return n.contains('сводка') ||
      n.contains('статистика') ||
      n.contains('история')||
      n.contains('товары');
}

bool _rowHas(List<String> row, Pattern p) =>
    row.join(' ').toLowerCase().contains(p);

double _lastNumeric(List<String> row) {
  for (var i = row.length - 1; i >= 0; i--) {
    final v = parseAmount(row[i]);
    if (v != 0 && row[i].trim().isNotEmpty) return v;
  }
  return 0;
}

_Cols? _detectCols(List<String> row) {
  final cols = _Cols();
  for (var i = 0; i < row.length; i++) {
    final h = row[i].trim().toLowerCase();
    if (h.isEmpty) continue;
    if (h == '№' || h == '#' || h == 'n') {
      cols.order ??= i;
      continue;
    }
    if (h.contains('штрихкод') ||
        h.contains('баркод') ||
        h.contains('barcode')) {
      cols.barcode ??= i;
      continue;
    }
    if (h.contains('наименование') || h.contains('наим') || h.contains('товар')) {
      cols.name ??= i;
      continue;
    }
    if (h.contains('кол-во') ||
        h.contains('кол.во') ||
        h == 'кол' ||
        h.contains('колво')) {
      cols.qty ??= i;
      continue;
    }
    if (h.contains('сумма')) {
      cols.amount ??= i;
      continue;
    }
    if (h.contains('скидка')) {
      cols.discount ??= i;
      continue;
    }
    if (h.contains('цена')) {
      cols.price ??= i;
      continue;
    }
  }
  if (!cols.valid) return null;
  return cols;
}

ReceiptItem? _rowItem(List<String> row, _Cols c, int order) {
  if (c.name == null || c.name! >= row.length) return null;
  final name = row[c.name!].trim();
  if (name.isEmpty) return null;

  double qty = 1;
  if (c.qty != null && c.qty! < row.length && row[c.qty!].trim().isNotEmpty) {
    qty = parseAmount(row[c.qty!]);
  }
  double amount;
  if (c.amount != null && c.amount! < row.length && row[c.amount!].trim().isNotEmpty) {
    amount = parseAmount(row[c.amount!]);
  } else if (c.price != null && c.price! < row.length && row[c.price!].trim().isNotEmpty) {
    amount = parseAmount(row[c.price!]);
  } else {
    amount = _lastNumeric(row);
  }
  double unitPrice = 0;
  if (c.price != null && c.price! < row.length) {
    unitPrice = parseAmount(row[c.price!]);
  }
  if (unitPrice <= 0 && qty > 0) unitPrice = amount / qty;
  final barcode = (c.barcode != null && c.barcode! < row.length &&
          row[c.barcode!].trim().isNotEmpty)
      ? row[c.barcode!].trim()
      : null;
  double? discount;
  if (c.discount != null &&
      c.discount! < row.length &&
      row[c.discount!].trim().isNotEmpty) {
    final d = parseAmount(row[c.discount!]);
    discount = d == 0 ? null : d.abs();
  }
  return ReceiptItem(
    order: order,
    name: name,
    barcode: barcode,
    quantity: qty,
    unitPrice: unitPrice,
    amount: amount,
    discount: discount,
  );
}

String? _cleanStore(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  // Срезаем ведущую метку «Магазин:» / «Магазин» / «Торговая точка:».
  s = s.replaceFirst(
      RegExp(r'^(магазин|торговая точка)\s*[:»"]*\s*', caseSensitive: false), '');
  // До первой «|» или «(» — у нас адрес в скобках/через пайп.
  final cut = s.indexOf(RegExp(r'[|(]'));
  if (cut >= 0) s = s.substring(0, cut);
  // Убираем кавычки/ёлочки внутри и по краям: «...» "..." „...“.
  s = s.replaceAll(RegExp(r'[«»„“”"]'), '').trim();
  return s.isEmpty ? null : s;
}

String? _cleanAddress(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  s = s.replaceFirst(RegExp(r'^адрес\s*[:»"«]*\s*', caseSensitive: false), '');
  return s.trim().isEmpty ? null : s.trim();
}

String? _cleanPayment(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  s = s.replaceFirst(
      RegExp(r'^(способ оплаты|оплата|оплачено)\s*[:»"]*\s*', caseSensitive: false),
      '');
  // Убираем хвост с суммой: «... 53,54 BYN» / «КАРТА 31,94».
  s = s.replaceFirst(
      RegExp(r'\s+\d[\d.,]*\s*(?:BYN)?\s*$', caseSensitive: false), '');
  s = s.trim();
  return s.isEmpty ? null : s;
}

/// Служебные метки листа — не считаем их магазином при фолбэке.
const _labelWords = [
  'магазин', 'адрес', 'дата', 'сумма', 'итого', 'оплата', 'скидка', 'кассир',
  'уи', 'унп', 'юрлицо', 'телефон', 'карта', 'чек', 'время', 'документ', 'рн',
  'товар', 'количество', 'цена', 'штрихкод', 'точка', 'банк', 'терминал',
  'код', 'ввод', 'статус', 'номер',
];

const _kws = [
  'дата и время', 'итого к оплате', 'торговая точка', 'магазин', 'адрес',
  'оплата', 'сумма', 'итого', 'дата', 'время', 'скидка', 'фикс прайс',
];

/// Валидность значения для ключевого слова: дата должна парситься, сумма —
/// быть числом > 0, магазин — непустой очищенной строкой.
bool _kwValid(String kw, String v) {
  switch (kw) {
    case 'дата':
    case 'дата и время':
    case 'время':
      return parseDate(v) != null;
    case 'сумма':
    case 'итого':
    case 'итого к оплате':
      return parseAmount(v) != 0;
    case 'магазин':
    case 'торговая точка':
      return _cleanStore(v) != null;
    default:
      return v.trim().isNotEmpty;
  }
}

void _applyMeta(_Meta meta, String kw, String val) {
  switch (kw) {
    case 'магазин':
    case 'торговая точка':
      meta.store ??= _cleanStore(val);
      break;
    case 'адрес':
      meta.address ??= _cleanAddress(val);
      break;
    case 'дата':
    case 'дата и время':
      meta.date ??= parseDate(val);
      break;
    case 'время':
      meta.date ??= parseDate(val);
      break;
    case 'оплата':
      meta.payment ??= _cleanPayment(val);
      break;
    case 'сумма':
    case 'итого':
    case 'итого к оплате':
      final v = parseAmount(val);
      // Игнорируем пустые/нулевые (иначе шапка «Сумма» перебьёт реальную сумму).
      if (v != 0 && (meta.total == null || meta.total == 0)) meta.total = v;
      break;
    case 'скидка':
    case 'фикс прайс':
      break;
  }
}

_Meta _metaFromRows(List<List<String>> rows) {
  final meta = _Meta();
  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      final cell = row[i].trim();
      if (cell.isEmpty) continue;
      final lower = cell.toLowerCase();
      String? kw;
      for (final k in _kws) {
        if (lower.startsWith(k)) {
          kw = k;
          break;
        }
      }
      if (kw == null) continue;
      var rest = cell.substring(kw.length).trim();
      rest = rest.replaceAll(RegExp(r'^[:\s">«]+'), '').trim();
      String? val = rest.isNotEmpty ? rest : null;
      if (val == null || !_kwValid(kw, val)) {
        // Значение может стоять не в той же ячейке («Итого | | | 38.35»,
        // «Дата/время | 15.07.2026»): ищем первую ВАЛИДНУЮ ячейку вправо.
        for (var j = i + 1; j < row.length; j++) {
          final cand = row[j].trim();
          if (cand.isNotEmpty && _kwValid(kw, cand)) {
            val = cand;
            break;
          }
        }
      }
      if (val == null || !_kwValid(kw, val)) continue;
      _applyMeta(meta, kw, val);
    }
  }
  return meta;
}

_Meta _extractMeta(List<List<String>> grid) {
  final meta = _metaFromRows(grid);
  // Фолбэк магазина: первая содержательная ячейка листа (без служебных меток).
  if (meta.store == null) {
    for (final row in grid) {
      for (final c in row) {
        final s = c.trim();
        if (s.isEmpty) continue;
        final lower = s.toLowerCase();
        if (lower.startsWith('чек') || lower.startsWith('итого') ||
            lower == '№' || lower == '#' || RegExp(r'^\d').hasMatch(s) ||
            _labelWords.any(lower.startsWith)) {
          continue;
        }
        meta.store = _cleanStore(s);
        break;
      }
      if (meta.store != null) break;
    }
  }
  // Фолбэк даты: первая ячейка, распознанная как дата.
  if (meta.date == null) {
    outer:
    for (final row in grid) {
      for (final c in row) {
        final d = parseDate(c);
        if (d != null) {
          meta.date = d;
          break outer;
        }
      }
    }
  }
  return meta;
}

/// Собрать чеки из одного листа. Лист-«Сводка» и каталоги пропускаются,
/// чтобы не задваивать позиции. Проходит по шапкам (таблицы товаров) и по
/// мета-кластерам (чек без таблицы — карточный чек, квитанция).
List<Receipt> _receiptsFromSheet(
    XlsxSheetData sheet, String sourcePath, DateTime now) {
  if (_isSummarySheet(sheet.name)) return [];
  final rows = sheet.rows;
  final result = <Receipt>[];
  final seen = <String>{};
  final gmeta = _extractMeta(rows);

  int i = 0;
  while (i < rows.length) {
    final cols = _detectCols(rows[i]);
    if (cols != null) {
      // Таблица: товары до строки с «итого».
      final items = <ReceiptItem>[];
      var discount = 0.0;
      double total = 0;
      var order = 0;
      var j = i + 1;
      while (j < rows.length) {
        final row = rows[j];
        if (_detectCols(row) != null) break; // новая шапка — конец таблицы
        if (_rowHas(row, 'итого')) {
          final amtCell = (cols.amount != null && cols.amount! < row.length)
              ? row[cols.amount!]
              : '';
          total = amtCell.trim().isNotEmpty ? parseAmount(amtCell) : _lastNumeric(row);
          // скидка, если рядом есть «Скидка:»
          discount = _nearDiscount(row, cols) ?? discount;
          j++;
          break;
        }
        final it = _rowItem(row, cols, ++order);
        if (it != null) {
          if (it.amount < 0 ||
              it.name.toLowerCase().contains('скидка') ||
              it.name.toLowerCase().contains('срок')) {
            discount += it.amount.abs();
          } else {
            items.add(it);
          }
        }
        j++;
      }
      final meta = _extractMeta(rows.sublist(i, j));
      final store = _cleanStore(gmeta.store) ?? _cleanStore(meta.store) ??
          _cleanStore(sheet.name) ??
          'Неизвестен';
      final dt = meta.date ?? gmeta.date ?? now;
      final key = '$store|${dt.toIso8601String()}|${total.toStringAsFixed(2)}';
      if (total > 0 && seen.add(key)) {
        result.add(_mkReceipt(
          store: store,
          address: gmeta.address ?? meta.address,
          dateTime: dt,
          total: total,
          discount: discount,
          payment: meta.payment ?? gmeta.payment,
          items: items,
          sourcePath: sourcePath,
          needsOcr: false,
          now: now,
        ));
      }
      i = j;
      continue;
    }
    // Чек без таблицы: ищем мета-кластер «Магазин + сумма».
    final cluster = _detectMetaCluster(rows, i, gmeta);
    if (cluster != null) {
      final store = _cleanStore(cluster.meta.store) ?? _cleanStore(sheet.name);
      final dt = cluster.meta.date ?? now;
      final total = cluster.total;
      final key = '$store|${dt.toIso8601String()}|${total.toStringAsFixed(2)}';
      if (store != null && total > 0 && seen.add(key)) {
        result.add(_mkReceipt(
          store: store,
          address: cluster.meta.address,
          dateTime: dt,
          total: total,
          discount: cluster.discount,
          payment: cluster.meta.payment,
          items: const [],
          sourcePath: sourcePath,
          needsOcr: false,
          now: now,
        ));
      }
      i = cluster.end;
      continue;
    }
    i++;
  }
  return result;
}

class _MetaCluster {
  final _Meta meta;
  final double total;
  final double discount;
  final int end;
  _MetaCluster(this.meta, this.total, this.discount, this.end);
}

double? _nearDiscount(List<String> row, _Cols c) {
  if (c.discount != null && c.discount! < row.length) {
    final d = parseAmount(row[c.discount!]);
    if (d != 0) return d.abs();
  }
  return null;
}

_MetaCluster? _detectMetaCluster(
    List<List<String>> rows, int start, _Meta global) {
  final window = <List<String>>[];
  for (var i = start; i < rows.length && window.length < 16; i++) {
    window.add(rows[i]);
  }
  if (window.isEmpty) return null;
  // Если в окне есть шапка таблицы товаров — это не мета-кластер: пусть
  // основной проход (таблица) заберёт позиции и мету. Иначе кластер «съест»
  // чек с товарами и оставит 0 позиций.
  for (final r in window) {
    if (_detectCols(r) != null) return null;
  }
  // Строгий разбор: берём ТОЛЬКО явные метки (магазин/дата/сумма),
  // без фолбэка на произвольную ячейку — иначе ловим названия товаров.
  final meta = _metaFromRows(window);
  final total = meta.total ?? 0;
  if (meta.store != null && (total > 0 || meta.date != null)) {
    return _MetaCluster(meta, total, 0, start + window.length);
  }
  return null;
}

Receipt _mkReceipt({
  required String store,
  String? address,
  required DateTime dateTime,
  required double total,
  double discount = 0,
  String? payment,
  List<ReceiptItem> items = const [],
  required String sourcePath,
  bool needsOcr = false,
  required DateTime now,
}) {
  return Receipt(
    id: genId(),
    store: store,
    address: address,
    dateTime: dateTime,
    total: total,
    discount: discount,
    paymentMethod: payment,
    items: items,
    sourcePath: sourcePath,
    sourceType: 'xlsx',
    needsOcr: needsOcr,
    importedAt: now,
  );
}

/// Все чеки из XLSX: проходит по листам и собирает чеки.
List<Receipt> parseXlsxReceipts(List<int> bytes, String sourcePath,
    {DateTime? now}) {
  final sheets = readXlsxSheets(bytes);
  final result = <Receipt>[];
  final nowActual = now ?? DateTime.now();
  for (final sheet in sheets) {
    result.addAll(_receiptsFromSheet(sheet, sourcePath, nowActual));
  }
  return result;
}

/// Чек-скан (JPG): сам текст не распознаём без OCR, поэтому помечаем чек
/// как требующий распознавания и НЕ выдумываем позиции.
Receipt markOcrReceipt({
  required String store,
  DateTime? date,
  double? total,
  required String sourcePath,
  required DateTime now,
}) {
  return Receipt(
    id: genId(),
    store: store.isEmpty ? 'Скан чека' : store,
    dateTime: date ?? now,
    total: total ?? 0,
    items: const [],
    sourcePath: sourcePath,
    sourceType: 'jpg',
    needsOcr: true,
    importedAt: now,
  );
}

// =====================================================================
// Каталог цен (all_products_clean.json)
// =====================================================================

/// Разобрать JSON-каталог цен в записи [PriceEntry].
/// Дедупликация по (shop, name) выполняется на этапе импорта, здесь — только
/// валидация и разбор. Невалидные записи помещаются в [errors].
List<PriceEntry> parsePricesJson(String content, {DateTime? now}) {
  final nowActual = now ?? DateTime.now();
  final list = jsonDecode(content);
  final out = <PriceEntry>[];
  if (list is! List) return out;
  for (final raw in list) {
    if (raw is! Map) continue;
    final shop = (raw['shop'] as String?)?.trim() ?? '';
    final name = (raw['name'] as String?)?.trim() ?? '';
    final price = num.tryParse('${raw['price']}')?.toDouble() ?? 0;
    if (shop.isEmpty || name.isEmpty || price <= 0) continue;
    final oldRaw = raw['old_price'];
    double? oldPrice;
    if (oldRaw != null) {
      oldPrice = num.tryParse('$oldRaw')?.toDouble();
      if (oldPrice != null && oldPrice <= 0) oldPrice = null;
    }
    final discRaw = raw['discount'];
    String? discount;
    if (discRaw != null && '$discRaw'.trim().isNotEmpty) {
      discount = '$discRaw'.trim();
    }
    final dt = parseDate(raw['date'] ?? '') ?? nowActual;
    out.add(PriceEntry(
      id: genId(),
      shop: shop,
      name: name,
      price: price,
      oldPrice: oldPrice,
      discount: discount,
      date: dt,
      updatedAt: nowActual,
    ));
  }
  return out;
}
