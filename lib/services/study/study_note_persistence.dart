import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StudyNoteTextData {
  final String ownExample;
  final String conclusion;
  final String teacherNotes;
  final String unclear;
  final List<String> errors;

  const StudyNoteTextData({
    this.ownExample = '',
    this.conclusion = '',
    this.teacherNotes = '',
    this.unclear = '',
    this.errors = const [],
  });

  Map<String, dynamic> toJson() => {
        'ownExample': ownExample,
        'conclusion': conclusion,
        'teacherNotes': teacherNotes,
        'unclear': unclear,
        'errors': errors,
      };

  static StudyNoteTextData fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return StudyNoteTextData(
      ownExample: json['ownExample'] as String? ?? '',
      conclusion: json['conclusion'] as String? ?? '',
      teacherNotes: json['teacherNotes'] as String? ?? '',
      unclear: json['unclear'] as String? ?? '',
      errors: rawErrors is List
          ? rawErrors.whereType<String>().toList(growable: false)
          : const [],
    );
  }
}

class StudyReviewData {
  final DateTime? startedAt;
  final int completedStages;

  const StudyReviewData({
    this.startedAt,
    this.completedStages = 0,
  });

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt?.toIso8601String(),
        'completedStages': completedStages,
      };

  static StudyReviewData fromJson(Map<String, dynamic> json) {
    final rawDate = json['startedAt'] as String?;
    return StudyReviewData(
      startedAt: rawDate == null ? null : DateTime.tryParse(rawDate),
      completedStages: (json['completedStages'] as num?)?.toInt() ?? 0,
    );
  }
}

class StudyNotePersistence {
  StudyNotePersistence._();

  static const reviewIntervals = <Duration>[
    Duration(minutes: 15),
    Duration(days: 1),
    Duration(days: 4),
    Duration(days: 7),
    Duration(days: 30),
  ];

  static String _textKey(String paragraphId) => 'study_note_text_v1_$paragraphId';
  static String _reviewKey(String paragraphId) => 'study_note_review_v1_$paragraphId';

  static StudyNoteTextData readText(
    SharedPreferences prefs,
    String paragraphId,
  ) {
    final raw = prefs.getString(_textKey(paragraphId));
    if (raw == null || raw.isEmpty) return const StudyNoteTextData();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StudyNoteTextData.fromJson(decoded);
      }
      if (decoded is Map) {
        return StudyNoteTextData.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return const StudyNoteTextData();
  }

  static Future<void> writeText(
    SharedPreferences prefs,
    String paragraphId,
    StudyNoteTextData data,
  ) {
    return prefs.setString(_textKey(paragraphId), jsonEncode(data.toJson()));
  }

  static StudyReviewData readReview(
    SharedPreferences prefs,
    String paragraphId,
  ) {
    final raw = prefs.getString(_reviewKey(paragraphId));
    if (raw == null || raw.isEmpty) return const StudyReviewData();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StudyReviewData.fromJson(decoded);
      }
      if (decoded is Map) {
        return StudyReviewData.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return const StudyReviewData();
  }

  static Future<void> writeReview(
    SharedPreferences prefs,
    String paragraphId,
    StudyReviewData data,
  ) {
    return prefs.setString(_reviewKey(paragraphId), jsonEncode(data.toJson()));
  }

  static DateTime? nextReviewAt(StudyReviewData data) {
    final start = data.startedAt;
    if (start == null || data.completedStages >= reviewIntervals.length) {
      return null;
    }
    return start.add(reviewIntervals[data.completedStages]);
  }

  static String stageLabel(int index) {
    return switch (index) {
      0 => 'Через 10–15 минут',
      1 => 'На следующий день',
      2 => 'Через 3–4 дня',
      3 => 'Через неделю',
      _ => 'Через месяц',
    };
  }
}
