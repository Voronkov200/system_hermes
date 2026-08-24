import 'study_content_quality.dart';

enum LocalStudySectionType {
  overview,
  keyPoints,
  terms,
  rules,
  examples,
  tasks,
  questions,
}

class LocalStudySection {
  final LocalStudySectionType type;
  final String title;
  final List<String> items;

  const LocalStudySection({
    required this.type,
    required this.title,
    required this.items,
  });
}

class LocalStudyBreakdown {
  final String sourceText;
  final List<LocalStudySection> sections;

  const LocalStudyBreakdown({
    required this.sourceText,
    required this.sections,
  });

  bool get isEmpty => sourceText.trim().isEmpty;
}

/// Детерминированный разбор учебного текста, который выполняется целиком на
/// телефоне. Он выбирает и группирует дословные предложения источника и
/// ничего не дописывает «от себя».
class LocalStudyContent {
  LocalStudyContent._();

  static LocalStudyBreakdown build(
    String source, {
    String analysis = 'humanities',
  }) {
    final cleaned = StudyContentQuality.prepareForAnalysis(
      source,
      maxChars: 180000,
    );
    if (cleaned.isEmpty) {
      return const LocalStudyBreakdown(sourceText: '', sections: []);
    }

    final flat = _normalize(cleaned);
    final sections = <LocalStudySection>[];
    final sentences = _sentences(flat);

    final summary = _summary(sentences, analysis: analysis);
    if (summary.isNotEmpty) {
      sections.add(
        LocalStudySection(
          type: LocalStudySectionType.overview,
          title: analysis == 'literature'
              ? 'Кратко о разделе или произведении'
              : 'Краткий конспект',
          items: summary,
        ),
      );
    }

    final keyPoints = _keyPoints(sentences, excluding: summary);
    if (keyPoints.isNotEmpty) {
      sections.add(
        LocalStudySection(
          type: LocalStudySectionType.keyPoints,
          title: 'Главные мысли',
          items: keyPoints,
        ),
      );
    }

    final terms = _matchingSentences(
      sentences,
      RegExp(
        r'(?:\s—\s|\s-\s)?(?:это|называется|называют|понимают|'
        r'представляет собой|определяется как|обозначает)',
        caseSensitive: false,
      ),
      maxItems: 10,
    );
    if (terms.isNotEmpty) {
      sections.add(
        LocalStudySection(
          type: LocalStudySectionType.terms,
          title: 'Термины и определения',
          items: terms,
        ),
      );
    }

    final rules = _markerWindows(
      flat,
      RegExp(
        r'(?:^|\s)(?:Определение|Теорема|Правило|Свойств(?:о|а)|Вывод)',
        caseSensitive: false,
      ),
      maxItems: 12,
      maxChars: 560,
    );
    rules.addAll(
      _matchingSentences(
        sentences,
        RegExp(
          r'(?:следует|необходимо|нужно|должен|должна|закон|формул|'
          r'если .{0,100} то|запрещается)',
          caseSensitive: false,
        ),
        maxItems: 12,
      ),
    );
    final uniqueRules = _unique(rules, maxItems: 12);
    if (uniqueRules.isNotEmpty) {
      sections.add(
        LocalStudySection(
          type: LocalStudySectionType.rules,
          title: analysis == 'languages'
              ? 'Правила из учебника'
              : analysis == 'science'
                  ? 'Правила, законы и формулы'
                  : 'Правила и выводы',
          items: uniqueRules,
        ),
      );
    }

    // Для языков и точных предметов упражнения полезны. В конспектах
    // истории, биологии и других устных предметов они только создают шум.
    final practiceMode = analysis == 'languages' || analysis == 'exact';
    if (practiceMode) {
      final examples = _markerWindows(
        flat,
        RegExp(
          r'(?:^|\s)(?:Пример(?:\s+\d+)?|Решение)\s*[.:]',
          caseSensitive: false,
        ),
        maxItems: 12,
        maxChars: 700,
      );
      if (examples.isNotEmpty) {
        sections.add(
          LocalStudySection(
            type: LocalStudySectionType.examples,
            title: 'Примеры из учебника',
            items: examples,
          ),
        );
      }

      final tasks = _taskWindows(flat);
      if (tasks.isNotEmpty) {
        sections.add(
          LocalStudySection(
            type: LocalStudySectionType.tasks,
            title: analysis == 'languages'
                ? 'Упражнения'
                : 'Задания параграфа',
            items: tasks,
          ),
        );
      }
    }

    final questions = _questions(flat);
    if (questions.isNotEmpty) {
      sections.add(
        LocalStudySection(
          type: LocalStudySectionType.questions,
          title: 'Вопросы из текста',
          items: questions,
        ),
      );
    }

    return LocalStudyBreakdown(sourceText: cleaned, sections: sections);
  }

  static String _normalize(String source) {
    const letters = r'A-Za-zА-Яа-яЁёІіЎў';
    final joinedWords = source.replaceAllMapped(
      RegExp('([$letters])-\\s*\\n\\s*([$letters])'),
      (match) => '${match.group(1)}${match.group(2)}',
    );
    return joinedWords.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _sentences(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final match in RegExp(r'[^.!?]+(?:[.!?]+|$)').allMatches(text)) {
      final sentence = match.group(0)?.trim() ?? '';
      if (!_isUsefulSentence(sentence)) continue;
      final key = sentence.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (seen.add(key)) result.add(sentence);
    }
    return result;
  }

  static bool _isUsefulSentence(String sentence) {
    if (sentence.length < 42 || sentence.length > 420) return false;
    if (RegExp(r'^\d{1,3}(?:\.\d{1,3})?\.\s').hasMatch(sentence)) {
      return false;
    }
    if (RegExp(r'^(?:Пример|Решение|Упражнение|Задание)\b',
            caseSensitive: false)
        .hasMatch(sentence)) {
      return false;
    }
    final letters = RegExp(r'[A-Za-zА-Яа-яЁёІіЎў]').allMatches(sentence).length;
    return letters / sentence.length >= .52;
  }

  static List<String> _summary(
    List<String> sentences, {
    required String analysis,
  }) {
    final result = <String>[];
    for (final sentence in sentences.take(45)) {
      if (sentence.endsWith('?')) continue;
      if (RegExp(r'^(?:Определение|Правило|Теорема|Свойство)\b',
              caseSensitive: false)
          .hasMatch(sentence)) {
        continue;
      }
      result.add(sentence);
      if (result.length == (analysis == 'literature' ? 4 : 5)) break;
    }
    return result;
  }

  static List<String> _keyPoints(
    List<String> sentences, {
    required List<String> excluding,
  }) {
    final excluded = excluding
        .map((item) => item.toLowerCase().replaceAll(RegExp(r'\s+'), ' '))
        .toSet();
    final weighted = <({String text, int score, int order})>[];
    for (var i = 0; i < sentences.length && i < 100; i++) {
      final sentence = sentences[i];
      final key = sentence.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (excluded.contains(key) || sentence.endsWith('?')) continue;
      var score = 0;
      if (RegExp(
        r'\b(?:главн|важн|причин|следств|поэтому|таким образом|'
        r'характерн|особенност|в результате|в отличие|включает|'
        r'состоит|зависит|влияет)\w*',
        caseSensitive: false,
      ).hasMatch(sentence)) {
        score += 4;
      }
      if (RegExp(r'\b(?:1[0-9]{3}|20[0-9]{2})\b').hasMatch(sentence)) {
        score += 2;
      }
      if (sentence.length >= 80 && sentence.length <= 260) score += 2;
      score += (100 - i) ~/ 30;
      weighted.add((text: sentence, score: score, order: i));
    }
    weighted.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score == 0 ? a.order.compareTo(b.order) : score;
    });
    final selected = weighted.take(5).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return selected.map((item) => item.text).toList();
  }

  static List<String> _matchingSentences(
    List<String> sentences,
    RegExp marker, {
    required int maxItems,
  }) {
    return _unique(
      sentences.where(marker.hasMatch),
      maxItems: maxItems,
    );
  }

  static List<String> _unique(
    Iterable<String> values, {
    required int maxItems,
  }) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final clean = value.trim();
      if (clean.length < 24) continue;
      final normalized = clean.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final key = normalized.substring(
        0,
        normalized.length < 150 ? normalized.length : 150,
      );
      if (seen.add(key)) result.add(clean);
      if (result.length >= maxItems) break;
    }
    return result;
  }

  static List<String> _markerWindows(
    String text,
    RegExp marker, {
    required int maxItems,
    required int maxChars,
  }) {
    final matches = marker.allMatches(text).toList();
    final result = <String>[];
    final seen = <String>{};
    for (var i = 0; i < matches.length && result.length < maxItems; i++) {
      final start = matches[i].start;
      final next = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final end = next < start + maxChars ? next : start + maxChars;
      final excerpt = _boundedExcerpt(text, start, end - start);
      if (excerpt.length < 24) continue;
      final normalized =
          excerpt.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final key = normalized.substring(
        0,
        normalized.length < 120 ? normalized.length : 120,
      );
      if (seen.add(key)) result.add(excerpt);
    }
    return result;
  }

  static List<String> _taskWindows(String text) {
    final marker = RegExp(r'(?:^|\s)(\d{1,2}\.\d{1,3}\.)\s+');
    final matches = marker.allMatches(text).toList();
    final result = <String>[];
    final seenNumbers = <String>{};
    for (var i = 0; i < matches.length; i++) {
      final number = matches[i].group(1);
      if (number == null || !seenNumbers.add(number)) continue;
      final start = matches[i].start;
      final next = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final end = next < start + 850 ? next : start + 850;
      final excerpt = _boundedExcerpt(text, start, end - start);
      if (excerpt.length >= 20) result.add(excerpt);
      if (result.length >= 20) break;
    }
    return result;
  }

  static List<String> _questions(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final match in RegExp(r'[^.!?]{20,360}\?').allMatches(text)) {
      var question = match.group(0)?.trim() ?? '';
      final lastBoundary = question.lastIndexOf(RegExp(r'[.:;]'));
      if (lastBoundary >= 0 && lastBoundary + 1 < question.length) {
        question = question.substring(lastBoundary + 1).trim();
      }
      if (question.length < 18) continue;
      final key = question.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (seen.add(key)) result.add(question);
      if (result.length >= 12) break;
    }
    return result;
  }

  static String _boundedExcerpt(String text, int start, int maxChars) {
    if (text.isEmpty || start >= text.length || maxChars <= 0) return '';
    final safeStart = start < 0 ? 0 : start;
    var end = safeStart + maxChars;
    if (end > text.length) end = text.length;
    var excerpt = text.substring(safeStart, end).trim();
    if (end < text.length) {
      final boundary = excerpt.lastIndexOf(RegExp(r'[.!?]'));
      if (boundary > excerpt.length ~/ 2) {
        excerpt = excerpt.substring(0, boundary + 1).trim();
      } else {
        excerpt = '$excerpt…';
      }
    }
    return excerpt;
  }
}
