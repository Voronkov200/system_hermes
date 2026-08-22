import 'package:flutter_test/flutter_test.dart';
import 'package:system_hermes/data/models.dart';
import 'package:system_hermes/services/bank_math.dart';

void main() {
  final rates = [
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
  ];

  test('конвертирует BYN в валюту и обратно через один базовый курс', () {
    final usd = BankMath.convert(
      amount: 100,
      fromCurrency: 'BYN',
      toCurrency: 'USD',
      rates: rates,
    );
    final byn = BankMath.convert(
      amount: usd!,
      fromCurrency: 'USD',
      toCurrency: 'BYN',
      rates: rates,
    );

    expect(usd, closeTo(100 / 2.9829, 0.000001));
    expect(byn, closeTo(100, 0.000001));
  });

  test('конвертирует USD в EUR через BYN', () {
    final eur = BankMath.convert(
      amount: 10,
      fromCurrency: 'USD',
      toCurrency: 'EUR',
      rates: rates,
    );
    expect(eur, closeTo(10 * 2.9829 / 3.4918, 0.000001));
  });

  test('одинаковая валюта не требует курса', () {
    expect(
      BankMath.convert(
        amount: 25,
        fromCurrency: 'BYN',
        toCurrency: 'BYN',
        rates: null,
      ),
      25,
    );
  });

  test('не выполняет расчёт без нужного курса или с неверной суммой', () {
    expect(
      BankMath.convert(
        amount: 10,
        fromCurrency: 'USD',
        toCurrency: 'EUR',
        rates: const [],
      ),
      isNull,
    );
    expect(
      BankMath.convert(
        amount: 0,
        fromCurrency: 'BYN',
        toCurrency: 'USD',
        rates: rates,
      ),
      isNull,
    );
  });
}
