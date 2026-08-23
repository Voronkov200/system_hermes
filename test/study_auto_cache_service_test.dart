import 'package:flutter_test/flutter_test.dart';
import 'package:system_hermes/services/study/study_auto_cache_service.dart';

void main() {
  group('StudyAutoCacheService.bookIdsForSubject', () {
    test('maps a single textbook subject', () {
      expect(StudyAutoCacheService.bookIdsForSubject('Алгебра'), ['894']);
      expect(StudyAutoCacheService.bookIdsForSubject('Астрономия'), ['888']);
    });

    test('keeps explicit textbook parts precise', () {
      expect(
        StudyAutoCacheService.bookIdsForSubject('История (часть 1)'),
        ['1155'],
      );
      expect(
        StudyAutoCacheService.bookIdsForSubject('Английский язык (часть 2)'),
        ['1015'],
      );
    });

    test('warms the whole family for a base subject', () {
      expect(
        StudyAutoCacheService.bookIdsForSubject('Русская литература').toSet(),
        {'915', '1207', '1208'},
      );
      expect(
        StudyAutoCacheService.bookIdsForSubject('Беларуская літаратура').toSet(),
        {'904', '1202'},
      );
    });
  });
}
