// Автоматическая фоновая подготовка учебников и ГДЗ для «Учёбы».
//
// Ничего не блокирует интерфейс: PDF скачиваются максимум по два одновременно,
// каталоги ГДЗ — максимум по три. Повторные вызовы безопасны и только добавляют
// ещё не подготовленные материалы в очередь.

import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'resheba_service.dart';
import 'study_textbook_catalog.dart';
import 'study_textbook_service.dart';

class StudyAutoCacheService {
  static const _retryDelay = Duration(minutes: 5);

  final StudyTextbookService _textbooks;
  final ReshebaService _resheba;
  final _pdfQueue = _AsyncWorkQueue(2);
  final _gdzQueue = _AsyncWorkQueue(3);
  final Set<String> _scheduledBooks = <String>{};
  final Set<String> _scheduledGdz = <String>{};
  final Map<String, DateTime> _retryBooksAfter = <String, DateTime>{};
  final Map<String, DateTime> _retryGdzAfter = <String, DateTime>{};

  StudyAutoCacheService(this._textbooks, [ReshebaService? resheba])
      : _resheba = resheba ?? ReshebaService();

  /// Запускает фоновую подготовку уже известных учебников и ГДЗ.
  /// Метод можно вызывать на каждом rebuild: дубликаты не ставятся в очередь.
  /// После сетевой ошибки используется пауза, чтобы rebuild экрана не создавал
  /// бесконечный цикл запросов при плохом интернете.
  void warmStudy({
    required Iterable<String> subjectTitles,
    required Iterable<String> paragraphChapters,
  }) {
    // Не запускаем реальные сетевые запросы из flutter test.
    if (const bool.fromEnvironment('FLUTTER_TEST')) return;

    final now = DateTime.now();
    final titles = subjectTitles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toSet();

    final bookIds = <String>{};
    for (final chapter in paragraphChapters) {
      final bookId = StudyTextbookCatalog.bookIdFromChapter(chapter);
      if (bookId != null && StudyTextbookCatalog.sources.containsKey(bookId)) {
        bookIds.add(bookId);
      }
    }
    for (final title in titles) {
      bookIds.addAll(bookIdsForSubject(title));
    }

    for (final bookId in bookIds) {
      if (_isCoolingDown(_retryBooksAfter[bookId], now)) continue;
      if (!_scheduledBooks.add(bookId)) continue;
      _pdfQueue.add(() async {
        try {
          await _textbooks.ensureLocal(bookId);
          _retryBooksAfter.remove(bookId);
        } catch (_) {
          _scheduledBooks.remove(bookId);
          _retryBooksAfter[bookId] = DateTime.now().add(_retryDelay);
          rethrow;
        }
      });
    }

    for (final title in titles) {
      final paths = ReshebaService.jsPathsFor(title);
      if (paths.isEmpty) continue;
      final key = paths.join('|');
      if (_isCoolingDown(_retryGdzAfter[key], now)) continue;
      if (!_scheduledGdz.add(key)) continue;
      _gdzQueue.add(() async {
        try {
          final book = await _resheba.loadBook(title);
          // Не скачиваем тысячи картинок сразу. Две стартовые фотографии дают
          // мгновенное открытие первых разделов, а соседние номера дальше
          // подкачиваются самим ReshebaService автоматически.
          await _resheba.prefetchPreviewPhotos(
            title,
            book,
            limit: 2,
          );
          _retryGdzAfter.remove(key);
        } catch (_) {
          _scheduledGdz.remove(key);
          _retryGdzAfter[key] = DateTime.now().add(_retryDelay);
          rethrow;
        }
      });
    }
  }

  static bool _isCoolingDown(DateTime? retryAfter, DateTime now) =>
      retryAfter != null && now.isBefore(retryAfter);

  /// Возвращает официальные учебники, относящиеся к названию предмета.
  /// Пунктуация частей/хрестоматий не важна: «Русская литература» получает
  /// основной учебник и обе хрестоматии, а «История (часть 1)» — только ч. 1.
  static List<String> bookIdsForSubject(String subjectTitle) {
    final title = _normalizeTitle(subjectTitle);
    if (title.isEmpty) return const [];

    final result = <String>[];
    for (final source in StudyTextbookCatalog.sources.values) {
      final sourceTitle = _normalizeTitle(source.title);
      final sameFamily = sourceTitle == title ||
          sourceTitle.startsWith('$title ') ||
          title.startsWith('$sourceTitle ');
      if (sameFamily) result.add(source.bookId);
    }
    return result;
  }

  static String _normalizeTitle(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('ў', 'у')
      .replaceAll(RegExp(r'[·()–—\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _AsyncWorkQueue {
  final int maxConcurrent;
  final Queue<Future<void> Function()> _pending =
      Queue<Future<void> Function()>();
  int _running = 0;

  _AsyncWorkQueue(this.maxConcurrent)
      : assert(maxConcurrent > 0, 'maxConcurrent must be positive');

  void add(Future<void> Function() job) {
    _pending.add(job);
    _pump();
  }

  void _pump() {
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeFirst();
      _running++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    try {
      await job();
    } catch (_) {
      // Фоновая подготовка best-effort: пользовательский экран сам покажет
      // ошибку и предложит повтор, если конкретный материал всё ещё недоступен.
    } finally {
      _running--;
      _pump();
    }
  }
}

final studyAutoCacheServiceProvider = Provider<StudyAutoCacheService>((ref) {
  return StudyAutoCacheService(ref.read(studyTextbookServiceProvider));
});
