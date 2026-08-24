// Автоматическая фоновая подготовка учебников и ГДЗ для «Учёбы».
//
// Основные PDF 11 класса ставятся в очередь независимо от того, успела ли
// локальная миграция создать предметы/параграфы. Сборники и хрестоматии в
// автопредзагрузку не входят. После сетевой ошибки загрузка повторяется сама.

import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'resheba_service.dart';
import 'study_textbook_catalog.dart';
import 'study_textbook_service.dart';

class StudyAutoCacheService {
  static const _retryDelay = Duration(minutes: 3);

  /// 15 предметов пользователя = 17 физических PDF: история и английский
  /// состоят из двух частей. Хрестоматии/сборники сюда намеренно не входят.
  static const Set<String> primaryBookIds = <String>{
    '888', // Астрономия
    '894', // Алгебра
    '897', // География
    '899', // Химия
    '900', // Физика
    '902', // Геометрия
    '904', // Беларуская літаратура
    '914', // Русский язык
    '915', // Русская литература
    '920', // Беларуская мова
    '921', // Биология
    '923', // Информатика
    '938', // Обществоведение
    '986', // Английский язык, часть 1
    '1015', // Английский язык, часть 2
    '1155', // История, часть 1
    '1176', // История, часть 2
  };

  final StudyTextbookService _textbooks;
  final ReshebaService _resheba;
  final _pdfQueue = _AsyncWorkQueue(2);
  final _gdzQueue = _AsyncWorkQueue(3);
  final Set<String> _scheduledBooks = <String>{};
  final Set<String> _scheduledGdz = <String>{};
  final Map<String, DateTime> _retryBooksAfter = <String, DateTime>{};
  final Map<String, DateTime> _retryGdzAfter = <String, DateTime>{};
  final Map<String, Timer> _bookRetryTimers = <String, Timer>{};
  final Map<String, Timer> _gdzRetryTimers = <String, Timer>{};

  StudyAutoCacheService(this._textbooks, [ReshebaService? resheba])
      : _resheba = resheba ?? ReshebaService();

  /// Запускает фоновую подготовку учебников и ГДЗ.
  ///
  /// Важное отличие от старой схемы: все основные учебники ставятся в очередь
  /// сразу. Поэтому неполная миграция Hive больше не может оставить часть PDF
  /// вообще без попытки загрузки.
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

    // Основные 17 PDF всегда имеют приоритет и не зависят от состояния базы.
    final bookIds = <String>{...primaryBookIds};

    // Явные маркеры старых/импортированных параграфов учитываем только если
    // это основной учебник, а не исключённый сборник/хрестоматия.
    for (final chapter in paragraphChapters) {
      final bookId = StudyTextbookCatalog.bookIdFromChapter(chapter);
      if (bookId != null && primaryBookIds.contains(bookId)) {
        bookIds.add(bookId);
      }
    }
    for (final title in titles) {
      bookIds.addAll(bookIdsForSubject(title));
    }

    for (final bookId in bookIds) {
      if (_isCoolingDown(_retryBooksAfter[bookId], now)) continue;
      _scheduleBook(bookId);
    }

    for (final title in titles) {
      final paths = ReshebaService.jsPathsFor(title);
      if (paths.isEmpty) continue;
      final key = paths.join('|');
      if (_isCoolingDown(_retryGdzAfter[key], now)) continue;
      _scheduleGdz(title, key);
    }
  }

  void _scheduleBook(String bookId) {
    if (!primaryBookIds.contains(bookId)) return;
    if (!_scheduledBooks.add(bookId)) return;

    _pdfQueue.add(() async {
      try {
        await _textbooks.ensureLocal(bookId);
        _retryBooksAfter.remove(bookId);
        _bookRetryTimers.remove(bookId)?.cancel();
      } catch (_) {
        _scheduledBooks.remove(bookId);
        _scheduleBookRetry(bookId);
        rethrow;
      }
    });
  }

  void _scheduleBookRetry(String bookId) {
    final retryAt = DateTime.now().add(_retryDelay);
    _retryBooksAfter[bookId] = retryAt;
    _bookRetryTimers.remove(bookId)?.cancel();
    _bookRetryTimers[bookId] = Timer(_retryDelay, () {
      _bookRetryTimers.remove(bookId);
      _retryBooksAfter.remove(bookId);
      _scheduleBook(bookId);
    });
  }

  void _scheduleGdz(String title, String key) {
    if (!_scheduledGdz.add(key)) return;

    _gdzQueue.add(() async {
      try {
        final book = await _resheba.loadBook(title);
        // Не скачиваем тысячи картинок сразу. Две стартовые фотографии дают
        // быстрый первый вход, соседние номера подкачиваются при просмотре.
        await _resheba.prefetchPreviewPhotos(title, book, limit: 2);
        _retryGdzAfter.remove(key);
        _gdzRetryTimers.remove(key)?.cancel();
      } catch (_) {
        _scheduledGdz.remove(key);
        _scheduleGdzRetry(title, key);
        rethrow;
      }
    });
  }

  void _scheduleGdzRetry(String title, String key) {
    _retryGdzAfter[key] = DateTime.now().add(_retryDelay);
    _gdzRetryTimers.remove(key)?.cancel();
    _gdzRetryTimers[key] = Timer(_retryDelay, () {
      _gdzRetryTimers.remove(key);
      _retryGdzAfter.remove(key);
      _scheduleGdz(title, key);
    });
  }

  static bool _isCoolingDown(DateTime? retryAfter, DateTime now) =>
      retryAfter != null && now.isBefore(retryAfter);

  /// Возвращает только основные учебники, относящиеся к названию предмета.
  /// Хрестоматии и сборники намеренно исключены из автопредзагрузки.
  static List<String> bookIdsForSubject(String subjectTitle) {
    final title = _normalizeTitle(subjectTitle);
    if (title.isEmpty) return const [];

    final result = <String>[];
    for (final source in StudyTextbookCatalog.sources.values) {
      if (!primaryBookIds.contains(source.bookId)) continue;
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

  void dispose() {
    for (final timer in _bookRetryTimers.values) {
      timer.cancel();
    }
    for (final timer in _gdzRetryTimers.values) {
      timer.cancel();
    }
    _bookRetryTimers.clear();
    _gdzRetryTimers.clear();
  }
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
      // Фоновая подготовка best-effort: конкретный экран всё равно покажет
      // ошибку, а сервис сам поставит повторную попытку в очередь.
    } finally {
      _running--;
      _pump();
    }
  }
}

final studyAutoCacheServiceProvider = Provider<StudyAutoCacheService>((ref) {
  final service = StudyAutoCacheService(ref.read(studyTextbookServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});