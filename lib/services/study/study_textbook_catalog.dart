// Официальные PDF-источники учебников 11 класса и привязка параграфов.
//
// В Hive не добавляется новое поле: id книги хранится служебным маркером в
// начале `StudyParagraph.chapter`. Это сохраняет совместимость со старыми
// данными. В интерфейсе маркер всегда скрывается.

class StudyTextbookSource {
  final String bookId;
  final String title;
  final Uri pdfUri;

  /// Разница между напечатанным номером страницы и номером страницы PDF.
  final int pageOffset;

  const StudyTextbookSource({
    required this.bookId,
    required this.title,
    required this.pdfUri,
    required this.pageOffset,
  });
}

class StudyTextbookPageRange {
  final StudyTextbookSource source;
  final int printedStart;
  final int printedEnd;

  const StudyTextbookPageRange({
    required this.source,
    required this.printedStart,
    required this.printedEnd,
  });

  int get pdfStart => printedStart + source.pageOffset;
  int get pdfEnd => printedEnd + source.pageOffset;

  String get printedLabel => printedStart == printedEnd
      ? 'Страница $printedStart'
      : 'Страницы $printedStart–$printedEnd';
}

class StudyTextbookCatalog {
  static const _marker = '[hermes-book:';

  // Прямые PDF-ссылки взяты из каталога электронных учебников 11 класса:
  // https://mgask.org/ru/14/lib-11
  static final Map<String, StudyTextbookSource> sources = {
    '888': _source(
      '888',
      'Астрономия',
      'https://e-padruchnik.adu.by/books/astronomiya/Astronomiya_Galuzo_11_rus_2021.pdf',
      4,
    ),
    '894': _source(
      '894',
      'Алгебра',
      'https://e-padruchnik.adu.by/books/matematika/Algebra_11k_Arefieva_rus_2020.pdf',
      4,
    ),
    '897': _source(
      '897',
      'География',
      'https://e-padruchnik.adu.by/books/geografija/Geografija_Vitchenko_11kl_rus_2021.pdf',
      6,
    ),
    '899': _source(
      '899',
      'Химия',
      'https://e-padruchnik.adu.by/books/himija/Himiya_11kl_Michko_rus_2021.pdf',
      3,
    ),
    '900': _source(
      '900',
      'Физика',
      'https://e-padruchnik.adu.by/books/fizika/Fizika_11kl_Zhilko_rus_2021.pdf',
      4,
    ),
    '902': _source(
      '902',
      'Геометрия',
      'https://e-padruchnik.adu.by/books/matematika/Geometriya_11kl_Latotin_rus_2020.pdf',
      0,
    ),
    '904': _source(
      '904',
      'Беларуская літаратура',
      'https://e-padruchnik.adu.by/books/belaruskaja-litaratura/bel_lit_11kl_Melnikava_bel_rus_2021.pdf',
      1,
    ),
    '914': _source(
      '914',
      'Русский язык',
      'https://e-padruchnik.adu.by/books/russkij-jazyk/Rus_yaz_11kl_Dolbik_bel_rus_2021.pdf',
      5,
    ),
    '915': _source(
      '915',
      'Русская литература',
      'https://e-padruchnik.adu.by/books/russkaya-literatura/rus_lit_11k_Senkevich_rus_bel_2021.pdf',
      1,
    ),
    '920': _source(
      '920',
      'Беларуская мова',
      'https://e-padruchnik.adu.by/books/belaruskaja-mova/Bel_mova_11kl_Valochka_rus_bel_2021.pdf',
      5,
    ),
    '921': _source(
      '921',
      'Биология',
      'https://e-padruchnik.adu.by/books/biologija/Biologiya_11k_Dashkov_rus_2021.pdf',
      2,
    ),
    '923': _source(
      '923',
      'Информатика',
      'https://e-padruchnik.adu.by/books/informatika/Informatika_11kl_Kotov_rus_2021.pdf',
      1,
    ),
    '938': _source(
      '938',
      'Обществоведение',
      'https://e-padruchnik.adu.by/books/obschestvovedenie/Obschestvovedenie_11kl_Chupris_rus_2021.pdf',
      5,
    ),
    '986': _source(
      '986',
      'Английский язык · часть 1',
      'https://e-padruchnik.adu.by/books/english/angliski_Demchenko_11kl_bel_rus_ch1_2022.pdf',
      5,
    ),
    '1015': _source(
      '1015',
      'Английский язык · часть 2',
      'https://e-padruchnik.adu.by/books/english/angliski_Demchenko_11kl_bel_rus_ch2_2022.pdf',
      5,
    ),
    '1155': _source(
      '1155',
      'История · часть 1',
      'https://e-padruchnik.adu.by/books/istorija/Ist.Bel_v_kontekste_Vs_Ist_Kohanovski_11kl_ch1_rus_2025.pdf',
      5,
    ),
    '1176': _source(
      '1176',
      'История · часть 2',
      'https://e-padruchnik.adu.by/books/istorija/Ist.Bel_v_kontekste_Vs_Ist_Kohanovski_11kl_ch2_rus_2025.pdf',
      5,
    ),
    '1202': _source(
      '1202',
      'Беларуская літаратура · хрэстаматыя',
      'https://adu.by/images/2025/07/Hrestomatii/Hrestamatya_Belaruskaa_litaratura._11_klas.pdf',
      0,
    ),
    '1207': _source(
      '1207',
      'Русская литература · хрестоматия · часть 1',
      'https://adu.by/images/2025/08/hrestomatiya-rus-lit-11kl-ch1.pdf',
      0,
    ),
    '1208': _source(
      '1208',
      'Русская литература · хрестоматия · часть 2',
      'https://adu.by/images/2025/12/24/Hrestomatiya_po_russkoj_literature_dlya_11_chast_2.pdf',
      0,
    ),
  };

  static const Map<String, String> _defaultBookBySubject = {
    'астрономия': '888',
    'алгебра': '894',
    'география': '897',
    'химия': '899',
    'физика': '900',
    'геометрия': '902',
    'беларуская літаратура': '904',
    'русский язык': '914',
    'русская литература': '915',
    'беларуская мова': '920',
    'биология': '921',
    'информатика': '923',
    'обществоведение': '938',
    'английский язык часть 1': '986',
    'английский язык часть 2': '1015',
    'история часть 1': '1155',
    'история часть 2': '1176',
  };

  static StudyTextbookSource _source(
    String id,
    String title,
    String url,
    int offset,
  ) =>
      StudyTextbookSource(
        bookId: id,
        title: title,
        pdfUri: Uri.parse(url),
        pageOffset: offset,
      );

  static String? bookIdFromChapter(String chapter) {
    final match = RegExp(r'^\[hermes-book:(\d+)\]\s*')
        .firstMatch(chapter.trimLeft());
    return match?.group(1);
  }

  static String visibleChapter(String chapter) => chapter
      .trimLeft()
      .replaceFirst(RegExp(r'^\[hermes-book:\d+\]\s*'), '')
      .trim();

  static String chapterWithBook(String chapter, String? bookId) {
    final visible = visibleChapter(chapter);
    if (bookId == null || bookId.trim().isEmpty) return visible;
    return '$_marker${bookId.trim()}]${visible.isEmpty ? '' : ' $visible'}';
  }

  static int? printedPageFrom(String pages) {
    final match = RegExp(r'\d+').firstMatch(pages);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static String _normalizeSubject(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('ў', 'у')
      .replaceAll(RegExp(r'[·()–—\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Резервная привязка для старых локальных записей, у которых миграция ещё
  /// не успела добавить `[hermes-book:*]`. Явный маркер всегда важнее.
  static String? bookIdForSubject(String? subjectTitle) {
    if (subjectTitle == null) return null;
    final normalized = _normalizeSubject(subjectTitle);
    return _defaultBookBySubject[normalized];
  }

  /// Вычисляет диапазон параграфа: от его первой страницы до страницы перед
  /// следующим параграфом этой же книги. Если следующей страницы нет,
  /// показывается хотя бы первая страница.
  ///
  /// `subjectTitle` используется только как страховка для старых записей без
  /// служебного bookId. Для вручную созданного неизвестного предмета источник
  /// не придумывается.
  static StudyTextbookPageRange? rangeFor({
    required String chapter,
    required String pages,
    required Iterable<({String chapter, String pages})> siblings,
    String? subjectTitle,
  }) {
    final explicitBookId = bookIdFromChapter(chapter);
    final bookId = explicitBookId ?? bookIdForSubject(subjectTitle);
    final source = bookId == null ? null : sources[bookId];
    final start = printedPageFrom(pages);
    if (source == null || start == null || start < 1) return null;

    int? nextStart;
    for (final sibling in siblings) {
      final siblingBookId = bookIdFromChapter(sibling.chapter);
      if (explicitBookId != null) {
        if (siblingBookId != bookId) continue;
      } else if (siblingBookId != null && siblingBookId != bookId) {
        continue;
      }
      final candidate = printedPageFrom(sibling.pages);
      if (candidate == null || candidate <= start) continue;
      if (nextStart == null || candidate < nextStart) nextStart = candidate;
    }
    final end = nextStart == null ? start : nextStart - 1;
    return StudyTextbookPageRange(
      source: source,
      printedStart: start,
      printedEnd: end < start ? start : end,
    );
  }
}
