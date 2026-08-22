import 'package:flutter_test/flutter_test.dart';
import 'package:system_hermes/services/study/study_content_quality.dart';

void main() {
  group('StudyContentQuality', () {
    test('blocks analysis without a real source', () {
      final missing = StudyContentQuality.inspect('');
      final short = StudyContentQuality.inspect('Параграф: логарифмы');

      expect(missing.quality, StudySourceQuality.missing);
      expect(short.quality, StudySourceQuality.tooShort);
      expect(missing.canAnalyze, isFalse);
      expect(short.canAnalyze, isFalse);
    });

    test('marks a readable textbook fragment as ready', () {
      final source = List.generate(
        20,
        (i) => 'Страница ${i + 1}. Определение и подробное объяснение '
            'математического свойства с подтверждённым примером.',
      ).join('\n');

      final report = StudyContentQuality.inspect(source);

      expect(report.quality, StudySourceQuality.ready);
      expect(report.canAnalyze, isTrue);
    });

    test('keeps noisy OCR analyzable but reports a warning', () {
      final source = List.generate(
        80,
        (i) => i.isEven ? 'a' : 'Описание свойства степени номер $i.',
      ).join('\n');

      final report = StudyContentQuality.inspect(source);

      expect(report.quality, StudySourceQuality.noisy);
      expect(report.canAnalyze, isTrue);
    });

    test('removes control symbols and duplicate publisher footer', () {
      final source = '${List.filled(20, 'Содержательный текст учебника.').join(' ')}'
          '\n\u0014\nПравообладатель Народная асвета\nКонец параграфа.';

      final cleaned = StudyContentQuality.prepareForAnalysis(source);

      expect(cleaned, isNot(contains('\u0014')));
      expect(cleaned, isNot(contains('Правообладатель Народная асвета')));
      expect(cleaned, contains('Конец параграфа'));
    });

    test('stable identity ignores case and repeated spaces', () {
      final first = StudyContentQuality.paragraphIdentity(
        subjectId: 'algebra',
        title: '§ 1.  Степень',
      );
      final second = StudyContentQuality.paragraphIdentity(
        subjectId: 'algebra',
        title: '§ 1. степень',
      );

      expect(first, second);
    });
  });
}
