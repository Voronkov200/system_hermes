import 'package:flutter_test/flutter_test.dart';
import 'package:system_hermes/services/study/study_textbook_catalog.dart';

void main() {
  group('StudyTextbookCatalog', () {
    test('stores and hides the bundled book marker', () {
      final stored = StudyTextbookCatalog.chapterWithBook(
        'Глава 1. Степени',
        '894',
      );

      expect(stored, '[hermes-book:894] Глава 1. Степени');
      expect(StudyTextbookCatalog.bookIdFromChapter(stored), '894');
      expect(
        StudyTextbookCatalog.visibleChapter(stored),
        'Глава 1. Степени',
      );
    });

    test('calculates printed and PDF page ranges', () {
      final range = StudyTextbookCatalog.rangeFor(
        chapter: '[hermes-book:894] Глава 1',
        pages: 'с. 4',
        siblings: const [
          (chapter: '[hermes-book:894] Глава 1', pages: 'с. 4'),
          (chapter: '[hermes-book:894] Глава 1', pages: 'с. 9'),
          (chapter: '[hermes-book:900] Глава 1', pages: 'с. 5'),
        ],
      );

      expect(range, isNotNull);
      expect(range!.printedStart, 4);
      expect(range.printedEnd, 8);
      expect(range.pdfStart, 8);
      expect(range.pdfEnd, 12);
    });

    test('does not invent a source for a manual paragraph', () {
      final range = StudyTextbookCatalog.rangeFor(
        chapter: 'Моя глава',
        pages: 'с. 10',
        siblings: const [],
      );

      expect(range, isNull);
    });

    test('all configured sources are direct HTTPS PDFs', () {
      expect(StudyTextbookCatalog.sources.length, 20);
      expect(
        StudyTextbookCatalog.sources.keys.toSet(),
        {
          '888', '894', '897', '899', '900', '902', '904', '914', '915',
          '920', '921', '923', '938', '986', '1015', '1155', '1176',
          '1202', '1207', '1208',
        },
      );
      for (final source in StudyTextbookCatalog.sources.values) {
        expect(source.pdfUri.scheme, 'https');
        expect(source.pdfUri.path.toLowerCase(), endsWith('.pdf'));
        expect(source.pageOffset, greaterThanOrEqualTo(0));
      }
    });
  });
}
