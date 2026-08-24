import '../data/models.dart';
import 'nbrb_api.dart';

/// Чистые расчёты локального финансового планировщика.
///
/// Все курсы задаются как BYN за одну единицу валюты. Комиссия намеренно
/// равна нулю: это внутренний учёт System Hermes, а не банковская операция.
class BankMath {
  BankMath._();

  static double? convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
    required List<CurrencyRate>? rates,
  }) {
    if (!amount.isFinite || amount <= 0) return null;
    if (fromCurrency == toCurrency) return amount;

    final fromRate = NbrbApi.rateOf(rates, fromCurrency);
    final toRate = NbrbApi.rateOf(rates, toCurrency);
    if (fromRate == null || toRate == null || fromRate <= 0 || toRate <= 0) {
      return null;
    }
    return amount * fromRate / toRate;
  }
}
