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
    expect(types, contains(LocalStudySectionType.overview));
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

  test('устный предмет превращается в конспект без списка упражнений', () {
    const biology = '''
Клетка является основной структурной и функциональной единицей живого.
Клеточная мембрана отделяет содержимое клетки от внешней среды и регулирует обмен веществ.
Цитоплазма представляет собой внутреннюю среду клетки, где расположены органоиды.
Главная особенность ядра состоит в хранении наследственной информации.
Таким образом, согласованная работа частей клетки поддерживает её жизнедеятельность.
1.1. Перечислите органоиды клетки и подпишите рисунок.
''';

    final result = LocalStudyContent.build(biology, analysis: 'science');
    final types = result.sections.map((section) => section.type).toSet();
    expect(types, contains(LocalStudySectionType.overview));
    expect(types, contains(LocalStudySectionType.terms));
    expect(types, isNot(contains(LocalStudySectionType.tasks)));
  });
}
