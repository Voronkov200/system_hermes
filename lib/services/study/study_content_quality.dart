/// Проверка качества текста, извлечённого из учебника.
///
/// Модуль намеренно не пытается «восстановить» повреждённые формулы:
/// исправление OCR без изображения страницы способно изменить условие задачи.
enum StudySourceQuality { missing, tooShort, noisy, ready }

class StudySourceReport {
  final StudySourceQuality quality;
  final int characterCount;
  final int letterCount;
  final double isolatedLineRatio;
  final int controlCharacterCount;

  const StudySourceReport({
    required this.quality,
    required this.characterCount,
    required this.letterCount,
    required this.isolatedLineRatio,
    required this.controlCharacterCount,
  });

  bool get canAnalyze =>
      quality == StudySourceQuality.ready ||
      quality == StudySourceQuality.noisy;

  String get label {
    switch (quality) {
      case StudySourceQuality.missing:
        return 'Текст источника отсутствует';
      case StudySourceQuality.tooShort:
        return 'Недостаточно текста для надёжного разбора';
      case StudySourceQuality.noisy:
        return 'Текст извлечён, но формулы требуют сверки с PDF';
      case StudySourceQuality.ready:
        return 'Текст учебника готов к разбору';
    }
  }
}

class StudyContentQuality {
  static final RegExp _letters = RegExp(
    r'[A-Za-zА-Яа-яЁёІіЎў]',
  );
  static final RegExp _controlCharacters = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );
  static final RegExp _copyrightFooter = RegExp(
    r'^\s*Правообладатель\s+Народная\s+асвета\s*$',
    caseSensitive: false,
  );

  static StudySourceReport inspect(String source) {
    final text = source.trim();
    if (text.isEmpty) {
      return const StudySourceReport(
        quality: StudySourceQuality.missing,
        characterCount: 0,
        letterCount: 0,
        isolatedLineRatio: 0,
        controlCharacterCount: 0,
      );
    }

    final letterCount = _letters.allMatches(text).length;
    final controls = _controlCharacters.allMatches(text).length;
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final isolated = lines.where((line) => line.length <= 2).length;
    final isolatedRatio = lines.isEmpty ? 0.0 : isolated / lines.length;

    final StudySourceQuality quality;
    if (text.length < 250 || letterCount < 100) {
      quality = StudySourceQuality.tooShort;
    } else if (controls > 0 || isolatedRatio > 0.28) {
      quality = StudySourceQuality.noisy;
    } else {
      quality = StudySourceQuality.ready;
    }

    return StudySourceReport(
      quality: quality,
      characterCount: text.length,
      letterCount: letterCount,
      isolatedLineRatio: isolatedRatio,
      controlCharacterCount: controls,
    );
  }

  /// Готовит источник для локального отображения: убирает управляющие
  /// символы и повторяющиеся издательские колонтитулы, но не исправляет
  /// формулы и номера заданий.
  static String prepareForAnalysis(
    String source, {
    int maxChars = 48000,
  }) {
    var cleaned = source
        .replaceAll(_controlCharacters, ' ')
        .split('\n')
        .where((line) => !_copyrightFooter.hasMatch(line))
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (cleaned.length <= maxChars) return cleaned;

    // Сохраняем и начало, и конец: вопросы и упражнения часто находятся в
    // конце параграфа, поэтому обычное обрезание только хвоста недопустимо.
    final headLength = (maxChars * 0.72).round();
    final tailLength = maxChars - headLength;
    cleaned = '${cleaned.substring(0, headLength)}\n\n'
        '[ФРАГМЕНТ ИСТОЧНИКА ПРОПУЩЕН ИЗ-ЗА ОГРАНИЧЕНИЯ ДЛИНЫ]\n\n'
        '${cleaned.substring(cleaned.length - tailLength)}';
    return cleaned;
  }

  static String preview(String source, {int maxChars = 12000}) {
    final cleaned = source.replaceAll(_controlCharacters, ' ').trim();
    if (cleaned.length <= maxChars) return cleaned;
    return '${cleaned.substring(0, maxChars)}\n\n…Источник сокращён в интерфейсе.';
  }

  static String paragraphIdentity({
    required String subjectId,
    required String title,
  }) {
    final normalizedTitle = title
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$subjectId::$normalizedTitle';
  }
}
