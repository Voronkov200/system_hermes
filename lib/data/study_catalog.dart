// Каталог предметов 11 класса (белорусская школьная программа).
//
// Каждый предмет — с реальным учебным пособием для 11 класса,
// используемым в школах Беларуси. При первом запуске модуля «Учёба»
// предметы из этого каталога создаются автоматически, дальше к ним
// прикрепляются PDF-учебники и разбираются на параграфы.

/// Встроенный предмет каталога «Учёба».
class StudyCatalogItem {
  final String title;
  final String subtitle;
  final String icon; // ключ иконки (маппинг в UI)
  final String kind; // subject | guide
  final String category; // «Гуманитарные» | «Точные науки» | «Языки» | ...
  /// Синонимы названия (для матчинга по имени PDF), напр. белорусские.
  final List<String> aliases;

  const StudyCatalogItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.kind = 'subject',
    required this.category,
    this.aliases = const [],
  });
}

/// Встроенные предметы 11 класса (Беларусь).
const List<StudyCatalogItem> studyCatalog = [
  StudyCatalogItem(
    title: 'История Беларуси',
    subtitle: 'А. В. Косович, В. С. Кошелев и др.',
    icon: 'history',
    category: 'Гуманитарные',
    aliases: ['гісторыя беларусі'],
  ),
  StudyCatalogItem(
    title: 'Всемирная история',
    subtitle: 'Новейшее время. 1918 — начало XXI в.',
    icon: 'world',
    category: 'Гуманитарные',
    aliases: ['сусветная гісторыя'],
  ),
  StudyCatalogItem(
    title: 'Обществоведение',
    subtitle: 'О. И. Чуприс и др.',
    icon: 'society',
    category: 'Гуманитарные',
    aliases: ['грамадазнаўства'],
  ),
  StudyCatalogItem(
    title: 'Беларуская мова',
    subtitle: 'Г. М. Валочка, Л. С. Васюковіч и др.',
    icon: 'lang_bel',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Беларуская літаратура',
    subtitle: 'З. П. Мельнікава, Г. М. Трафімава',
    icon: 'lit_bel',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Русский язык',
    subtitle: 'В. Л. Леонович и др.',
    icon: 'lang_ru',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Русская литература',
    subtitle: 'Т. В. Сенькевич и др.',
    icon: 'lit_ru',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Английский язык',
    subtitle: 'Н. В. Юхнель, Н. В. Демченко и др.',
    icon: 'lang_en',
    category: 'Языки',
    aliases: ['англійская мова'],
  ),
  StudyCatalogItem(
    title: 'Алгебра',
    subtitle: 'И. Г. Арефьева, О. Н. Пирютко',
    icon: 'algebra',
    category: 'Точные науки',
  ),
  StudyCatalogItem(
    title: 'Геометрия',
    subtitle: 'Л. А. Латотин, Б. Д. Чеботаревский, И. В. Горбунова',
    icon: 'geometry',
    category: 'Точные науки',
    aliases: ['геаметрыя'],
  ),
  StudyCatalogItem(
    title: 'Физика',
    subtitle: 'Е. В. Громыко, В. В. Зборовская и др.',
    icon: 'physics',
    category: 'Точные науки',
    aliases: ['фізіка'],
  ),
  StudyCatalogItem(
    title: 'Химия',
    subtitle: 'Т. А. Колевич и др.',
    icon: 'chemistry',
    category: 'Точные науки',
    aliases: ['хімія'],
  ),
  StudyCatalogItem(
    title: 'Биология',
    subtitle: 'М. Л. Дашков, А. Г. Перснякевич, А. М. Головач',
    icon: 'biology',
    category: 'Точные науки',
    aliases: ['біялогія'],
  ),
  StudyCatalogItem(
    title: 'География',
    subtitle: 'А. Н. Витченко, Е. А. Антипова',
    icon: 'geo',
    category: 'Гуманитарные',
    aliases: ['геаграфія'],
  ),
  StudyCatalogItem(
    title: 'Информатика',
    subtitle: 'В. М. Котов, А. И. Лапо, Ю. А. Быкадоров',
    icon: 'informatics',
    category: 'Точные науки',
    aliases: ['інфарматыка'],
  ),
  StudyCatalogItem(
    title: 'Астрономия',
    subtitle: 'И. В. Галузо, В. А. Голубев, А. А. Шимбалев',
    icon: 'astronomy',
    category: 'Точные науки',
    aliases: ['астраномія'],
  ),
];
