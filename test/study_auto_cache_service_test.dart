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

    test('excludes collections from automatic preload', () {
      expect(
        StudyAutoCacheService.bookIdsForSubject('Русская литература'),
        ['915'],
      );
      expect(
        StudyAutoCacheService.bookIdsForSubject('Беларуская літаратура'),
        ['904'],
      );
    });

    test('primary preload contains all 17 physical textbooks', () {
      expect(StudyAutoCacheService.primaryBookIds.length, 17);
      expect(StudyAutoCacheService.primaryBookIds, containsAll(<String>{
        '986',
        '1015',
        '1155',
        '1176',
      }));
      expect(
        StudyAutoCacheService.primaryBookIds.intersection(<String>{
          '1202',
          '1207',
          '1208',
        }),
        isEmpty,
      );
    });
  });
}