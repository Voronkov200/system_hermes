import 'package:flutter_test/flutter_test.dart';
import 'package:system_hermes/services/study/resheba_service.dart';

void main() {
  group('ReshebaService', () {
    test('maps supported 11 class subjects to exact catalog scripts', () {
      expect(
        ReshebaService.jsPathFor('Алгебра'),
        'algebra-11-klass',
      );
      expect(
        ReshebaService.jsPathFor('Биология'),
        'biologija-11',
      );
      expect(ReshebaService.jsPathFor('Астрономия'), isNull);
    });

    test('parses chapters and ranges without renumbering', () {
      const source = '''
        var GDZ = {
          mixedFormats: true,
          maxPhotos: 1,
          tree: [{
            folder: "GDZ/11-alg-2021",
            childrens: [{
              text: "Глава 1",
              folder: "glava-1",
              numbers: "1-3, 7"
            }]
          }]
        };
      ''';

      final book = ReshebaService.parseBook(source);

      expect(book.root, 'GDZ/11-alg-2021');
      expect(book.sections.single.text, 'Глава 1');
      expect(book.sections.single.numbers, [1, 2, 3, 7]);
      expect(
        ReshebaService.solutionUrl(book, book.sections.single, 2),
        'https://resheba.top/GDZ/11-alg-2021/glava-1/2.png',
      );
    });

    test('rejects an empty solution catalog', () {
      const source = '''
        var GDZ = {tree: [{folder: "", childrens: []}]};
      ''';

      expect(
        () => ReshebaService.parseBook(source),
        throwsFormatException,
      );
    });
  });
}
