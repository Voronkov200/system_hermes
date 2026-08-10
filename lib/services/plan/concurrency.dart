// Пул конкурентности и retry (спецификация, раздел 6, задача 2):
// MAX_CONCURRENT_TAVILY = 4, MAX_CONCURRENT_OPENCODE = 2.
// Все параллельные вызовы идут через пул с ограничением, а не через
// Future.wait/Promise.all без лимита. Единый retry с экспоненциальной
// задержкой (1с → 2с → 4с, максимум 3 попытки) для 429/5xx применяется
// на всех стадиях «Поиска» и «Исследования».

import 'dart:async';
import 'dart:collection';

/// Ограничитель параллельных задач: задачи сверх лимита встают в очередь.
class ConcurrencyLimiter {
  ConcurrencyLimiter(this.maxConcurrent);

  final int maxConcurrent;
  int _active = 0;
  final Queue<void Function()> _queue = Queue();

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();

    void start() {
      _active++;
      Future.sync(task).then(
        (v) {
          _active--;
          completer.complete(v);
          _next();
        },
        onError: (Object e, StackTrace st) {
          _active--;
          completer.completeError(e, st);
          _next();
        },
      );
    }

    if (_active < maxConcurrent) {
      start();
    } else {
      _queue.add(start);
    }
    return completer.future;
  }

  void _next() {
    if (_queue.isNotEmpty && _active < maxConcurrent) {
      _queue.removeFirst()();
    }
  }
}

/// Единая функция retry: экспоненциальная задержка 1с → 2с → 4с,
/// максимум [attempts] попыток. Повторяет только при 429/5xx
/// (HTTP-статус в тексте исключения), остальные ошибки — сразу наверх.
/// При исчерпании попыток — бросает исходную ошибку, конвейер помечает
/// стадию «не обработано» и продолжает работу.
Future<T> retry<T>(
  Future<T> Function() task, {
  int attempts = 3,
  void Function(int attempt, Object error)? onRetry,
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await task();
    } catch (e) {
      attempt++;
      if (attempt >= attempts || !_isRetryable(e)) rethrow;
      onRetry?.call(attempt, e);
      await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
    }
  }
}

/// Стоит ли повторять: 429 или 5xx в тексте исключения.
bool _isRetryable(Object e) {
  final s = '$e';
  return s.contains('429') || RegExp(r'HTTP 5\d\d|5\d\d|Server Error')
      .hasMatch(s);
}
