import 'package:flutter_test/flutter_test.dart';
import 'package:system_hermes/data/study_catalog.dart';
import 'package:system_hermes/services/study/local_study_content.dart';
import 'package:system_hermes/services/study/study_note_template.dart';

void main() {
  const empty = LocalStudyBreakdown(sourceText: '', sections: []);

  test('every bundled subject gets a concrete notebook template', () {
    for (final item in studyCatalog) {
      final template = StudyNoteTemplateEngine.build(
        subjectTitle: item.title,
        sourceText: '',
        local: empty,
      );
      expect(template.subjectLabel, isNot('Универсальный конспект'));
      expect(template.sections.length, greaterThanOrEqualTo(6));
      expect(template.memoryChain, isNotEmpty);
      expect(template.selfCheck, isNotEmpty);
    }
  });

  test('algebra keeps formula OCR explicitly secondary', () {
    final template = StudyNoteTemplateEngine.build(
      subjectTitle: 'Алгебра',
      sourceText: '',
      local: empty,
    );
    final formula = template.sections.firstWhere(
      (section) => section.title == 'Формулы',
    );
    expect(formula.emptyHint, contains('оригинальной странице'));
    expect(template.memoryChain, contains('ОДЗ'));
  });

  test('history uses cause-event-result memory chain', () {
    final template = StudyNoteTemplateEngine.build(
      subjectTitle: 'История (часть 1)',
      sourceText: 'Причиной события стали перемены. В 1945 году период завершился.',
      local: empty,
    );
    expect(template.memoryChain, 'причина → событие → результат → последствия');
    expect(
      template.sections.firstWhere((s) => s.title == 'Причины').items,
      isNotEmpty,
    );
  });
}
