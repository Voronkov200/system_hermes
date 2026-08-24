import 'local_study_content.dart';

class StudyNoteSection {
  final String title;
  final String marker;
  final List<String> items;
  final String emptyHint;

  const StudyNoteSection({
    required this.title,
    required this.marker,
    required this.items,
    required this.emptyHint,
  });
}

class StudyNoteTemplate {
  final String subjectLabel;
  final String memoryChain;
  final List<StudyNoteSection> sections;
  final List<String> methodSteps;
  final List<String> selfCheck;

  const StudyNoteTemplate({
    required this.subjectLabel,
    required this.memoryChain,
    required this.sections,
    required this.methodSteps,
    required this.selfCheck,
  });
}

class _FieldSpec {
  final String title;
  final String marker;
  final List<LocalStudySectionType> sources;
  final String? keywords;
  final String emptyHint;
  final int maxItems;

  const _FieldSpec(
    this.title,
    this.marker, {
    this.sources = const [],
    this.keywords,
    this.emptyHint = 'Дополнить после объяснения учителя.',
    this.maxItems = 4,
  });
}

class _TemplateSpec {
  final String label;
  final String memoryChain;
  final List<_FieldSpec> fields;
  final List<String> methodSteps;
  final List<String> selfCheck;

  const _TemplateSpec({
    required this.label,
    required this.memoryChain,
    required this.fields,
    this.methodSteps = const [],
    this.selfCheck = const [],
  });
}

/// Предметный конструктор конспектов. Он ничего не придумывает о теме:
/// фактические пункты выбираются из локально извлечённого текста учебника.
/// Статическими остаются только учебные алгоритмы и вопросы самопроверки.
class StudyNoteTemplateEngine {
  StudyNoteTemplateEngine._();

  static StudyNoteTemplate build({
    required String subjectTitle,
    required String sourceText,
    required LocalStudyBreakdown local,
  }) {
    final spec = _specFor(subjectTitle);
    final sentences = _sentences(sourceText);
    final byType = <LocalStudySectionType, List<String>>{};
    for (final section in local.sections) {
      byType.putIfAbsent(section.type, () => <String>[]).addAll(section.items);
    }

    final sections = <StudyNoteSection>[];
    for (final field in spec.fields) {
      final items = <String>[];
      for (final type in field.sources) {
        items.addAll(byType[type] ?? const <String>[]);
      }
      if (field.keywords != null) {
        final re = RegExp(field.keywords!, caseSensitive: false);
        items.addAll(sentences.where(re.hasMatch));
      }
      sections.add(
        StudyNoteSection(
          title: field.title,
          marker: field.marker,
          items: _unique(items, field.maxItems),
          emptyHint: field.emptyHint,
        ),
      );
    }

    final sourceQuestions = byType[LocalStudySectionType.questions] ?? const [];
    final questions = _unique(
      <String>[...sourceQuestions, ...spec.selfCheck],
      6,
    );

    return StudyNoteTemplate(
      subjectLabel: spec.label,
      memoryChain: spec.memoryChain,
      sections: sections,
      methodSteps: spec.methodSteps,
      selfCheck: questions,
    );
  }

  static _TemplateSpec _specFor(String title) {
    final t = title.toLowerCase().replaceAll('ё', 'е').replaceAll('ў', 'у');
    if (t.contains('беларус') && t.contains('мов')) return _belarusian;
    if (t.contains('русск') && t.contains('язык')) return _russian;
    if (t.contains('английск')) return _english;
    if (t.contains('беларус') && t.contains('літарат') ||
        t.contains('беларус') && t.contains('литератур')) {
      return _belLiterature;
    }
    if (t.contains('русск') && t.contains('литератур')) return _rusLiterature;
    if (t.contains('истори')) return _history;
    if (t.contains('обществ')) return _society;
    if (t.contains('географ')) return _geography;
    if (t.contains('алгебр')) return _algebra;
    if (t.contains('геометр')) return _geometry;
    if (t.contains('физик')) return _physics;
    if (t.contains('хими')) return _chemistry;
    if (t.contains('биолог')) return _biology;
    if (t.contains('информат')) return _informatics;
    if (t.contains('астроном')) return _astronomy;
    return _general;
  }

  static List<String> _sentences(String source) {
    final flat = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return const [];
    final result = <String>[];
    for (final match in RegExp(r'[^.!?]+(?:[.!?]+|$)').allMatches(flat)) {
      final text = match.group(0)?.trim() ?? '';
      if (text.length < 35 || text.length > 420) continue;
      final letters = RegExp(r'[A-Za-zА-Яа-яЁёІіЎў]').allMatches(text).length;
      if (letters < text.length * .45) continue;
      result.add(text);
      if (result.length >= 160) break;
    }
    return result;
  }

  static List<String> _unique(Iterable<String> values, int maxItems) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.length < 18) continue;
      final key = clean.toLowerCase();
      if (!seen.add(key)) continue;
      result.add(clean);
      if (result.length >= maxItems) break;
    }
    return result;
  }

  static const _general = _TemplateSpec(
    label: 'Универсальный конспект',
    memoryChain: 'смысл → понятия → правило → пример → вывод',
    fields: [
      _FieldSpec('Основная мысль', '!', sources: [LocalStudySectionType.overview]),
      _FieldSpec('Ключевые понятия', 'П', sources: [LocalStudySectionType.terms]),
      _FieldSpec('Правила, формулы или даты', 'Ф', sources: [LocalStudySectionType.rules], keywords: r'\b(?:1[0-9]{3}|20[0-9]{2})\b'),
      _FieldSpec('Причины и следствия', '→', keywords: r'причин|следств|поэтому|в результате|привел|обуслов'),
      _FieldSpec('Пример', '•', sources: [LocalStudySectionType.examples]),
      _FieldSpec('Что нужно запомнить', '!', sources: [LocalStudySectionType.keyPoints]),
    ],
    selfCheck: ['Объясни тему без учебника.', 'Приведи собственный пример.', 'Свяжи новую тему с предыдущей.'],
  );

  static const _belarusian = _TemplateSpec(
    label: 'Беларуская мова',
    memoryChain: 'правіла → прыкметы → выключэнні → свой прыклад',
    fields: [
      _FieldSpec('Азначэнне / определение', 'П', sources: [LocalStudySectionType.terms]),
      _FieldSpec('Правіла', 'П', sources: [LocalStudySectionType.rules]),
      _FieldSpec('Прыкметы', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Выключэнні', '!', keywords: r'выключ|исключ|запомн'),
      _FieldSpec('Прыклады з падручніка', '•', sources: [LocalStudySectionType.examples]),
      _FieldSpec('Тыповыя памылкі', 'О', keywords: r'памыл|ошиб|няправ|неправ'),
      _FieldSpec('Міні-заданне', 'ПВ', sources: [LocalStudySectionType.tasks]),
    ],
    selfCheck: ['Сфармулюй правіла сваімі словамі.', 'Прыдумай тры ўласныя прыклады.', 'Правер, ці ёсць выключэнні.'],
  );

  static const _russian = _TemplateSpec(
    label: 'Русский язык',
    memoryChain: 'явление → признаки → правило → исключение → объяснение',
    fields: [
      _FieldSpec('Главное правило', 'П', sources: [LocalStudySectionType.rules]),
      _FieldSpec('На какие вопросы отвечает / признаки', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Как определить', '→', keywords: r'определ|признак|следует|нужно|необходимо'),
      _FieldSpec('Схема', 'П', sources: [LocalStudySectionType.rules], emptyHint: 'Запиши краткую схему конструкции своими обозначениями.'),
      _FieldSpec('Примеры', '•', sources: [LocalStudySectionType.examples]),
      _FieldSpec('Исключения', '!', keywords: r'исключ|запомн|особый случай'),
      _FieldSpec('Ошибки на экзамене', 'О', keywords: r'ошиб|неверн|следует различать'),
    ],
    methodSteps: ['Определи языковое явление.', 'Назови его признаки.', 'Найди зависимые слова или части предложения.', 'Примени правило.', 'Проверь исключения.', 'Объясни ответ.'],
    selfCheck: ['Объясни правило своими словами.', 'Придумай собственный пример.', 'Объясни расстановку знаков или написание.'],
  );

  static const _english = _TemplateSpec(
    label: 'English',
    memoryChain: 'vocabulary → grammar → phrase → own sentence → correction',
    fields: [
      _FieldSpec('Key vocabulary', 'П', keywords: r'\b[A-Za-z]{3,}\b', maxItems: 8, emptyHint: 'Добавь 10–15 ключевых слов темы.'),
      _FieldSpec('Grammar', 'П', sources: [LocalStudySectionType.rules]),
      _FieldSpec('Examples', '•', sources: [LocalStudySectionType.examples]),
      _FieldSpec('Useful phrases', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Practice', 'ПВ', sources: [LocalStudySectionType.tasks]),
      _FieldSpec('Mistakes', 'О', keywords: r'mistake|error|remember|неправ|ошиб'),
    ],
    methodSteps: ['Повтори 10–15 слов.', 'Составь 5 собственных предложений.', 'Перескажи тему вслух.', 'Раз в неделю напиши текст 80–120 слов.', 'Запиши и исправь ошибки.'],
    selfCheck: ['Назови ключевые слова без подсказки.', 'Составь вопрос, отрицание и утверждение.', 'Скажи 2–3 собственных предложения.'],
  );

  static const _belLiterature = _TemplateSpec(
    label: 'Беларуская літаратура',
    memoryChain: 'аўтар → кантэкст → герой → учынак → ідэя',
    fields: [
      _FieldSpec('Аўтар, назва, жанр', 'П', sources: [LocalStudySectionType.overview]),
      _FieldSpec('Гістарычны і культурны кантэкст', 'Д', keywords: r'эпох|стагод|год|гістор|истор|культур'),
      _FieldSpec('Тэма і ідэя', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Праблематыка', '?', keywords: r'праблем|проблем|канфлікт|конфликт'),
      _FieldSpec('Сюжэт і кампазіцыя', '→', keywords: r'сюж|кампаз|композ|падзе|событ'),
      _FieldSpec('Героі і ўчынкі', 'П', keywords: r'геро|персонаж|вобраз|образ|учын|поступ'),
      _FieldSpec('Мастацкія сродкі / цытаты', '!', keywords: r'метафор|эпитет|параўнан|сравнен|цытат|цитат'),
    ],
    selfCheck: ['Перакажы сюжэт праз 5–7 падзей.', 'Што аўтар хацеў сказаць?', 'Назаві тры важныя доказы з тэксту.'],
  );

  static const _rusLiterature = _TemplateSpec(
    label: 'Русская литература',
    memoryChain: 'эпоха → конфликт → герой → выбор → последствия → идея',
    fields: [
      _FieldSpec('Автор и эпоха', 'Д', keywords: r'автор|писател|поэт|эпох|век|год'),
      _FieldSpec('Направление и жанр', 'П', keywords: r'жанр|направлен|романтиз|реализм|модерн'),
      _FieldSpec('История создания', 'Д', keywords: r'создан|написан|опублик|замыс'),
      _FieldSpec('Тема и идея', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Основной конфликт', '→', keywords: r'конфликт|противореч|борьб'),
      _FieldSpec('Сюжет и система образов', 'П', keywords: r'сюжет|геро|персонаж|образ|событ'),
      _FieldSpec('Проблемы и средства выразительности', '?', keywords: r'проблем|метафор|эпитет|сравнен|символ'),
      _FieldSpec('Цитаты / доказательства', '!', keywords: r'цитат|говорит|слова героя'),
    ],
    selfCheck: ['Расскажи произведение за 1 минуту.', 'Объясни выбор главного героя.', 'Сформулируй идею автора в 2–3 предложениях.'],
  );

  static const _history = _TemplateSpec(
    label: 'История Беларуси в контексте всемирной истории',
    memoryChain: 'причина → событие → результат → последствия',
    fields: [
      _FieldSpec('Период и годы', 'Д', keywords: r'\b(?:1[0-9]{3}|20[0-9]{2})\b|период|век'),
      _FieldSpec('Главные события', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Причины', '→', keywords: r'причин|обуслов|предпосыл|вследствие'),
      _FieldSpec('Участники и персоналии', 'П', keywords: r'правител|деятел|политик|командир|княз|корол|президент'),
      _FieldSpec('Ход событий', '→', sources: [LocalStudySectionType.overview]),
      _FieldSpec('Итоги и последствия', '!', keywords: r'итог|последств|в результате|привел|завершил'),
      _FieldSpec('Историческое значение', '!', keywords: r'значени|важн|повлиял|роль'),
      _FieldSpec('Термины и даты', 'Д', sources: [LocalStudySectionType.terms], keywords: r'\b(?:1[0-9]{3}|20[0-9]{2})\b'),
    ],
    selfCheck: ['Назови причину, событие, результат и последствия.', 'Назови ключевые даты без учебника.', 'Объясни роль одной исторической личности.'],
  );

  static const _society = _TemplateSpec(
    label: 'Обществоведение',
    memoryChain: 'понятие → признаки → виды → функции → жизненный пример',
    fields: [
      _FieldSpec('Понятие и определение простыми словами', 'П', sources: [LocalStudySectionType.terms]),
      _FieldSpec('Основные признаки', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Виды', 'П', keywords: r'виды|различают|выделяют|классифиц'),
      _FieldSpec('Функции', '→', keywords: r'функц|назначени|роль'),
      _FieldSpec('Пример из жизни', '•', sources: [LocalStudySectionType.examples], emptyHint: 'Добавь собственный бытовой пример.'),
      _FieldSpec('Связь с другими понятиями', '→', keywords: r'связан|взаимосвяз|зависит|отличается'),
      _FieldSpec('Права, обязанности, причины и последствия', '!', keywords: r'право|обязан|ответствен|причин|последств'),
    ],
    selfCheck: ['Объясни понятие без термина из учебника.', 'Чем оно отличается от похожего понятия?', 'Приведи реальный пример.'],
  );

  static const _geography = _TemplateSpec(
    label: 'География',
    memoryChain: 'положение → ресурсы → население → хозяйство → проблемы',
    fields: [
      _FieldSpec('Географическое положение', '→', keywords: r'положен|располож|гранич|сосед|территор'),
      _FieldSpec('Природные ресурсы', 'П', keywords: r'ресурс|полезн.*ископ|сырь|водн|земель'),
      _FieldSpec('Население', 'П', keywords: r'населен|демограф|городск|миграц'),
      _FieldSpec('Хозяйство и промышленность', '!', keywords: r'хозяйств|промышлен|производств|эконом'),
      _FieldSpec('Сельское хозяйство и транспорт', '→', keywords: r'сельск|аграр|транспорт|дорог|порт'),
      _FieldSpec('Проблемы', '?', keywords: r'проблем|загряз|дефицит|угроз'),
      _FieldSpec('Связи с другими странами', '→', keywords: r'экспорт|импорт|торгов|сотруднич|связ'),
    ],
    selfCheck: ['Покажи объект на карте.', 'Объясни связь ресурсов и хозяйства.', 'Назови главную проблему региона.'],
  );

  static const _algebra = _TemplateSpec(
    label: 'Алгебра',
    memoryChain: 'понятие → формула → ОДЗ → алгоритм → проверка',
    fields: [
      _FieldSpec('Основное понятие', 'П', sources: [LocalStudySectionType.terms]),
      _FieldSpec('Формулы', 'Ф', sources: [LocalStudySectionType.rules], emptyHint: 'Формулу смотри на оригинальной странице: повреждённый OCR не используется.'),
      _FieldSpec('Область допустимых значений', '!', keywords: r'допустим|одз|область определ|огранич'),
      _FieldSpec('Алгоритм / свойства', '→', sources: [LocalStudySectionType.rules]),
      _FieldSpec('Пример из учебника', '•', sources: [LocalStudySectionType.examples]),
      _FieldSpec('Типичные ошибки', 'О', keywords: r'ошиб|нельзя|неверн|следует помнить'),
      _FieldSpec('Задание для тренировки', 'ПВ', sources: [LocalStudySectionType.tasks]),
    ],
    methodSteps: ['Запиши, что дано.', 'Определи тип задачи.', 'Выбери формулу или метод.', 'Проверь ОДЗ.', 'Выполни преобразования по шагам.', 'Проверь результат.', 'Запиши ответ.'],
    selfCheck: ['Назови формулу и условие её применения.', 'Объясни каждый шаг решения.', 'Проверь ОДЗ и ответ.'],
  );

  static const _geometry = _TemplateSpec(
    label: 'Геометрия',
    memoryChain: 'чертёж → дано → теорема → доказательство → ответ',
    fields: [
      _FieldSpec('Определения', 'П', sources: [LocalStudySectionType.terms]),
      _FieldSpec('Теоремы', 'П', sources: [LocalStudySectionType.rules]),
      _FieldSpec('Условие и заключение', '→', keywords: r'если|то |теорем|следует'),
      _FieldSpec('Чертёж', 'Ф', emptyHint: 'Используй оригинальную страницу или сделай собственный рисунок.'),
      _FieldSpec('Доказательство', '→', keywords: r'доказ|поскольку|следовательно|получаем'),
      _FieldSpec('Формулы', 'Ф', sources: [LocalStudySectionType.rules], emptyHint: 'Формулы сверяй с PNG оригинальной страницы.'),
      _FieldSpec('Пример / задача', '•', sources: [LocalStudySectionType.examples, LocalStudySectionType.tasks]),
    ],
    methodSteps: ['Сделай рисунок.', 'Запиши дано и найти.', 'Отметь известные углы и стороны.', 'Найди связанные фигуры.', 'Выбери теорему или формулу.', 'Выполни доказательство.', 'Запиши ответ.'],
    selfCheck: ['Сформулируй теорему: если …, то …', 'Объясни доказательство без учебника.', 'Покажи на рисунке, где применяется теорема.'],
  );

  static const _physics = _TemplateSpec(
    label: 'Физика',
    memoryChain: 'явление → закон → величины → формула → применение',
    fields: [
      _FieldSpec('Физическое явление и определение', 'П', sources: [LocalStudySectionType.terms, LocalStudySectionType.overview]),
      _FieldSpec('Основной закон', 'П', sources: [LocalStudySectionType.rules]),
      _FieldSpec('Формула', 'Ф', sources: [LocalStudySectionType.rules], emptyHint: 'Формулу смотри на оригинальной PNG-странице.'),
      _FieldSpec('Величины и единицы измерения', 'Ф', keywords: r'измеря|единиц|ньютон|джоул|ватт|вольт|ампер|метр|секунд|килограмм'),
      _FieldSpec('График или схема', '→', emptyHint: 'Смотри рисунок/график на оригинальной странице.'),
      _FieldSpec('Пример и применение', '•', sources: [LocalStudySectionType.examples], keywords: r'примен|использ|пример'),
    ],
    methodSteps: ['Запиши данные в СИ.', 'Сделай рисунок или схему.', 'Выбери закон.', 'Запиши формулу.', 'Вырази неизвестную величину.', 'Подставь числа.', 'Укажи единицу измерения.', 'Проверь реалистичность ответа.'],
    selfCheck: ['Сформулируй закон.', 'Что означает каждая величина?', 'В каких единицах она измеряется?', 'Где закон применяется?'],
  );

  static const _chemistry = _TemplateSpec(
    label: 'Химия',
    memoryChain: 'вещество → свойство → реакция → продукт → применение',
    fields: [
      _FieldSpec('Основные понятия', 'П', sources: [LocalStudySectionType.terms]),
      _FieldSpec('Свойства вещества', '!', keywords: r'свойств|характерн|реагиру|окисл|восстанов'),
      _FieldSpec('Получение', '→', keywords: r'получа|образу|синтез'),
      _FieldSpec('Химические реакции', 'Ф', sources: [LocalStudySectionType.rules], keywords: r'реакц|уравнен'),
      _FieldSpec('Условия и признаки реакций', '!', keywords: r'услов|температур|катализ|осад|газ|окраск'),
      _FieldSpec('Применение', '•', keywords: r'примен|использ'),
      _FieldSpec('Опасность / экологическое значение', '?', keywords: r'опас|токс|эколог|загряз|вред'),
    ],
    methodSteps: ['Запиши уравнение.', 'Определи тип реакции.', 'Укажи условия.', 'Объясни, что изменяется.', 'Назови признак реакции.', 'Свяжи реакцию с практическим значением.'],
    selfCheck: ['Объясни цепочку вещество → свойство → реакция → продукт.', 'Назови условия реакции.', 'Реши три уравнения и одну задачу.'],
  );

  static const _biology = _TemplateSpec(
    label: 'Биология',
    memoryChain: 'условия → процесс → результат → значение',
    fields: [
      _FieldSpec('Объект и определение', 'П', sources: [LocalStudySectionType.terms, LocalStudySectionType.overview]),
      _FieldSpec('Строение', 'П', keywords: r'строен|состоит|части|органел|структур'),
      _FieldSpec('Функции', '→', keywords: r'функц|выполня|обеспеч'),
      _FieldSpec('Процессы', '→', keywords: r'процесс|этап|происход|образу'),
      _FieldSpec('Связи', '→', keywords: r'связан|взаимодейств|зависит'),
      _FieldSpec('Примеры', '•', sources: [LocalStudySectionType.examples], keywords: r'например|пример'),
      _FieldSpec('Значение', '!', keywords: r'значени|роль|необходим|важн'),
    ],
    selfCheck: ['Где происходит процесс?', 'Что для него необходимо?', 'Какие этапы он включает?', 'Что образуется и зачем это нужно организму?'],
  );

  static const _informatics = _TemplateSpec(
    label: 'Информатика',
    memoryChain: 'задача → данные → алгоритм → программа → тест → исправление',
    fields: [
      _FieldSpec('Понятие и назначение', 'П', sources: [LocalStudySectionType.terms, LocalStudySectionType.overview]),
      _FieldSpec('Основные элементы', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Алгоритм работы', '→', sources: [LocalStudySectionType.rules]),
      _FieldSpec('Пример', '•', sources: [LocalStudySectionType.examples]),
      _FieldSpec('Практическая задача', 'ПВ', sources: [LocalStudySectionType.tasks]),
      _FieldSpec('Типичные ошибки', 'О', keywords: r'ошиб|неверн|исключен|синтакс'),
    ],
    methodSteps: ['Определи входные данные.', 'Определи выходные данные.', 'Опиши алгоритм словами.', 'Запиши псевдокод.', 'Реализуй программу.', 'Проверь тестом.', 'Запиши ошибку и исправление.'],
    selfCheck: ['Объясни алгоритм без кода.', 'Какие входные и выходные данные?', 'Реши маленькую задачу без копирования примера.'],
  );

  static const _astronomy = _TemplateSpec(
    label: 'Астрономия',
    memoryChain: 'наблюдение → объяснение → закон → практическое значение',
    fields: [
      _FieldSpec('Объект или явление и определение', 'П', sources: [LocalStudySectionType.terms, LocalStudySectionType.overview]),
      _FieldSpec('Основные характеристики', '!', sources: [LocalStudySectionType.keyPoints]),
      _FieldSpec('Размеры и расстояния', 'Ф', keywords: r'расстояни|размер|радиус|диаметр|километр|парсек|светов'),
      _FieldSpec('Движение', '→', keywords: r'движ|вращ|орбит|период|скорост'),
      _FieldSpec('Состав', 'П', keywords: r'состав|состоит|атмосфер|веществ'),
      _FieldSpec('Наблюдение', '•', keywords: r'наблюд|телескоп|видим|яркост'),
      _FieldSpec('Значение и интересный факт', '!', keywords: r'значени|интерес|особенност|важн'),
    ],
    selfCheck: ['Нарисуй схему расположения объектов.', 'Объясни наблюдаемое явление.', 'Свяжи наблюдение с законом.'],
  );
}
