import 'package:flutter_test/flutter_test.dart';
import 'package:system_hermes/services/study/local_study_content.dart';

void main() {
  const source = '''
§ 1. Степень с рациональным показателем.
Определение. Степенью числа a с рациональным показателем называется
корень соответствующей степени.
Свойство. При умножении степеней показатели складываются.
Пример 1. Найдите значение выражения.
Решение. Применим определение степени и получим ответ 3.
1.1. Найдите значение выражения: а) 4; б) 9.
1.2. Упростите выражение x.
Почему показатели складываются?
''';

  test('локально выделяет только фрагменты исходного учебника', () {
    final result = LocalStudyContent.build(source, analysis: 'exact');
    final types = result.sections.map((section) => section.type).toSet();
    final extracted =
        result.sections.expand((section) => section.items).join('\n');

    expect(types, contains(LocalStudySectionType.rules));
    expect(types, contains(LocalStudySectionType.examples));
    expect(types, contains(LocalStudySectionType.tasks));
    expect(types, contains(LocalStudySectionType.questions));
    expect(extracted, contains('Определение'));
    expect(extracted, contains('1.1.'));
    expect(extracted, contains('Почему показатели складываются?'));
    expect(result.sourceText, contains('Решение. Применим определение'));
  });

  test('не создаёт разбор при отсутствии текста', () {
    final result = LocalStudyContent.build('   ');
    expect(result.isEmpty, isTrue);
    expect(result.sections, isEmpty);
  });
}
