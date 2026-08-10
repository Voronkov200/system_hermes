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

  const StudyCatalogItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.kind = 'subject',
    required this.category,
  });
}

/// Встроенные предметы 11 класса (Беларусь).
const List<StudyCatalogItem> studyCatalog = [
  StudyCatalogItem(
    title: 'История Беларуси',
    subtitle: '1917 г. — начало XXI в. · учебное пособие, 11 класс',
    icon: 'history',
    category: 'Гуманитарные',
  ),
  StudyCatalogItem(
    title: 'Всемирная история',
    subtitle: 'Новейшее время. 1918 — начало XXI в. · 11 класс',
    icon: 'world',
    category: 'Гуманитарные',
  ),
  StudyCatalogItem(
    title: 'Обществоведение',
    subtitle: 'Учебное пособие, 11 класс',
    icon: 'society',
    category: 'Гуманитарные',
  ),
  StudyCatalogItem(
    title: 'Беларуская мова',
    subtitle: 'Вучэбны дапаможнік, 11 клас',
    icon: 'lang_bel',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Беларуская літаратура',
    subtitle: 'Вучэбны дапаможнік, 11 клас',
    icon: 'lit_bel',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Русский язык',
    subtitle: 'Учебное пособие, 11 класс',
    icon: 'lang_ru',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Русская литература',
    subtitle: 'Учебное пособие, 11 класс',
    icon: 'lit_ru',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Английский язык',
    subtitle: 'Учебное пособие, 11 класс',
    icon: 'lang_en',
    category: 'Языки',
  ),
  StudyCatalogItem(
    title: 'Алгебра',
    subtitle: 'Алгебра, 11 класс',
    icon: 'algebra',
    category: 'Точные науки',
  ),
  StudyCatalogItem(
    title: 'Геометрия',
    subtitle: 'Геометрия, 11 класс',
    icon: 'geometry',
    category: 'Точные науки',
  ),
  StudyCatalogItem(
    title: 'Физика',
    subtitle: 'Физика, 11 класс',
    icon: 'physics',
    category: 'Точные науки',
  ),
  StudyCatalogItem(
    title: 'Химия',
    subtitle: 'Химия, 11 класс',
    icon: 'chemistry',
    category: 'Точные науки',
  ),
  StudyCatalogItem(
    title: 'Биология',
    subtitle: 'Биология, 11 класс',
    icon: 'biology',
    category: 'Точные науки',
  ),
  StudyCatalogItem(
    title: 'География',
    subtitle: 'География, 11 класс',
    icon: 'geo',
    category: 'Гуманитарные',
  ),
  StudyCatalogItem(
    title: 'Информатика',
    subtitle: 'Информатика, 11 класс',
    icon: 'informatics',
    category: 'Точные науки',
  ),
  StudyCatalogItem(
    title: 'Астрономия',
    subtitle: 'Астрономия, 11 класс',
    icon: 'astronomy',
    category: 'Точные науки',
  ),
];
