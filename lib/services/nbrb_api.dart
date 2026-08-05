// API Национального банка Республики Беларусь: курсы валют.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../data/models.dart';

class NbrbApi {
  final http.Client _client = http.Client();

  /// Возвращает актуальные курсы USD и EUR (столько BYN за 1 единицу).
  Future<List<CurrencyRate>> fetchRates() async {
    final res = await _client
        .get(Uri.parse(AppConstants.nbrbRatesUrl))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Ошибка API НБРБ: HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    final rates = <CurrencyRate>[];
    for (final item in data) {
      final code = item['Cur_Abbreviation'] as String?;
      if (code != 'USD' && code != 'EUR') continue;
      final date = DateTime.tryParse(item['Date'] as String? ?? '');
      rates.add(CurrencyRate(
        code: code!,
        scale: (item['Cur_Scale'] as num).toInt(),
        rate: (item['Cur_OfficialRate'] as num).toDouble(),
        date: date ?? DateTime.now(),
      ));
    }
    return rates;
  }

  /// Курс конкретной валюты из списка, null если нет.
  static double? rateOf(List<CurrencyRate>? rates, String code) {
    if (rates == null) return null;
    for (final r in rates) {
      if (r.code == code) return r.perUnit;
    }
    return null;
  }
}

final nbrbApiProvider = Provider<NbrbApi>((ref) => NbrbApi());

/// Курсы валют с автоперезагрузкой (кэш 1 час).
final ratesProvider = FutureProvider<List<CurrencyRate>>((ref) async {
  final rates = await ref.watch(nbrbApiProvider).fetchRates();
  return rates;
});

/// Помощник для UI: читает курсы из AsyncValue.
List<CurrencyRate>? ratesOf(AsyncValue<List<CurrencyRate>> async) =>
    async.valueOrNull;
