import 'study_content_quality.dart';

enum LocalStudySectionType {
  overview,
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
/// телефоне. Он только группирует дословные фрагменты источника и ничего не
/// дописывает «от себя».
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

    final flat = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    final sections = <LocalStudySection>[];
    final opening = _boundedExcerpt(flat, 0, 1400);
    if (opening.isNotEmpty) {
      sections.add(
        LocalStudySection(
          type: LocalStudySectionType.overview,
          title: analysis == 'literature'
              ? 'Начало произведения или раздела'
              : 'О чём начинается параграф',
          items: [opening],
        ),
      );
    }

    final rules = _markerWindows(
      flat,
      RegExp(
        r'(?:^|\s)(?:Определение|Теорема|Правило|Свойств(?:о|а)|Вывод)',
        caseSensitive: false,
      ),
      maxItems: 60,
      maxChars: 900,
    );
    if (rules.isNotEmpty) {
      sections.add(
        LocalStudySection(
          type: LocalStudySectionType.rules,
          title: analysis == 'languages'
              ? 'Правила из учебника'
              : 'Определения, правила и свойства',
          items: rules,
        ),
      );
    }

    final examples = _markerWindows(
      flat,
      RegExp(
        r'(?:^|\s)(?:Пример(?:\s+\d+)?|Решение)\s*[.:]',
        caseSensitive: false,
      ),
      maxItems: 80,
      maxChars: 1100,
    );
    if (examples.isNotEmpty) {
      sections.add(
        LocalStudySection(
          type: LocalStudySectionType.examples,
          title: 'Примеры и решения из учебника',
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
      final key = excerpt
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .substring(0, excerpt.length < 120 ? excerpt.length : 120);
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
