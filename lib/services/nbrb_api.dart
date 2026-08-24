// API Национального банка Республики Беларусь: курсы валют.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';

class NbrbApi {
  final http.Client _client = http.Client();

  /// Локальный снимок официальных курсов НБРБ на дату сборки. Он нужен,
  /// чтобы внутренний финансовый планировщик не переставал работать без
  /// интернета. Это не коммерческий курс БСБ Банка.
  static final List<CurrencyRate> bundledRates = List.unmodifiable([
    CurrencyRate(
      code: 'USD',
      scale: 1,
      rate: 2.9829,
      date: DateTime(2026, 8, 22),
    ),
    CurrencyRate(
      code: 'EUR',
      scale: 1,
      rate: 3.4918,
      date: DateTime(2026, 8, 22),
    ),
    CurrencyRate(
      code: 'RUB',
      scale: 100,
      rate: 3.5784,
      date: DateTime(2026, 8, 22),
    ),
  ]);

  /// Официальные курсы Нацбанка РБ: два зеркала (на случай блокировки одного).
  static const List<String> _urls = [
    'https://www.nbrb.by/api/exrates/rates?periodicity=0',
    'https://api.nbrb.by/exrates/rates?periodicity=0',
  ];

  /// Возвращает актуальные курсы USD, EUR и RUB. Если оба официальных
  /// адреса недоступны, возвращает встроенный датированный снимок.
  Future<List<CurrencyRate>> fetchRates() async {
    for (final url in _urls) {
      try {
        final res = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
          final rates = <CurrencyRate>[];
          for (final item in data) {
            final code = item['Cur_Abbreviation'] as String?;
            if (code != 'USD' && code != 'EUR' && code != 'RUB') continue;
            final date = DateTime.tryParse(item['Date'] as String? ?? '');
            rates.add(CurrencyRate(
              code: code!,
              scale: (item['Cur_Scale'] as num).toInt(),
              rate: (item['Cur_OfficialRate'] as num).toDouble(),
              date: date ?? DateTime.now(),
            ));
          }
          if (rates.length == 3) return rates;
        }
      } catch (_) {}
    }
    return bundledRates;
  }

  /// Курс конкретной валюты из списка, null если нет.
  static double? rateOf(List<CurrencyRate>? rates, String code) {
    if (code == 'BYN') return 1;
    if (rates == null) return null;
    for (final r in rates) {
      if (r.code == code) return r.perUnit;
    }
    return null;
  }

  static bool usesBundledSnapshot(List<CurrencyRate>? rates) {
    if (rates == null || rates.isEmpty) return false;
    final date = rates.first.date;
    return date.year == 2026 && date.month == 8 && date.day == 22;
  }
}

final nbrbApiProvider = Provider<NbrbApi>((ref) => NbrbApi());

/// Курсы валют с автоперезагрузкой (кэш 1 час).
final FutureProvider<List<CurrencyRate>> ratesProvider =
    FutureProvider<List<CurrencyRate>>((ref) async {
  final timer = Timer(const Duration(hours: 1), () {
    ref.invalidate(ratesProvider);
  });
  ref.onDispose(timer.cancel);
  final rates = await ref.watch(nbrbApiProvider).fetchRates();
  return rates;
});

/// Помощник для UI: читает курсы из AsyncValue.
List<CurrencyRate>? ratesOf(AsyncValue<List<CurrencyRate>> async) =>
    async.valueOrNull;
