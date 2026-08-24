import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings_service.dart';

/// Lightweight local learning record. Stored in SharedPreferences so the
/// learning state survives bundled-book updates and does not depend on the
/// generated Hive adapters for the content model.
class StudyLearningRecord {
  final String paragraphId;
  final double mastery;
  final int attempts;
  final int correct;
  final int streak;
  final DateTime? lastReviewedAt;
  final DateTime? nextReviewAt;
  final List<String> weakTopics;

  const StudyLearningRecord({
    required this.paragraphId,
    this.mastery = 0,
    this.attempts = 0,
    this.correct = 0,
    this.streak = 0,
    this.lastReviewedAt,
    this.nextReviewAt,
    this.weakTopics = const [],
  });

  StudyLearningRecord copyWith({
    double? mastery,
    int? attempts,
    int? correct,
    int? streak,
    DateTime? lastReviewedAt,
    DateTime? nextReviewAt,
    List<String>? weakTopics,
  }) => StudyLearningRecord(
        paragraphId: paragraphId,
        mastery: mastery ?? this.mastery,
        attempts: attempts ?? this.attempts,
        correct: correct ?? this.correct,
        streak: streak ?? this.streak,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
        weakTopics: weakTopics ?? this.weakTopics,
      );

  Map<String, dynamic> toJson() => {
        'paragraphId': paragraphId,
        'mastery': mastery,
        'attempts': attempts,
        'correct': correct,
        'streak': streak,
        'lastReviewedAt': lastReviewedAt?.toIso8601String(),
        'nextReviewAt': nextReviewAt?.toIso8601String(),
        'weakTopics': weakTopics,
      };

  factory StudyLearningRecord.fromJson(Map<String, dynamic> json) =>
      StudyLearningRecord(
        paragraphId: json['paragraphId'] as String? ?? '',
        mastery: (json['mastery'] as num?)?.toDouble() ?? 0,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        correct: (json['correct'] as num?)?.toInt() ?? 0,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        lastReviewedAt: DateTime.tryParse(json['lastReviewedAt'] as String? ?? ''),
        nextReviewAt: DateTime.tryParse(json['nextReviewAt'] as String? ?? ''),
        weakTopics: (json['weakTopics'] as List? ?? const [])
            .whereType<String>()
            .take(20)
            .toList(),
      );
}

/// Local mastery engine for the Study module.
///
/// It deliberately does not mark a paragraph as mastered merely because the
/// user opened it or pressed "learned". Mastery changes only after a check.
class StudyLearningService {
  static const _storageKey = 'study_learning_v1';

  final Ref ref;

  StudyLearningService(this.ref);

  Future<Map<String, StudyLearningRecord>> _read() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) {
        final map = value is Map
            ? Map<String, dynamic>.from(value)
            : <String, dynamic>{};
        return MapEntry(key.toString(), StudyLearningRecord.fromJson(map));
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, StudyLearningRecord> records) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final data = <String, dynamic>{
      for (final entry in records.entries) entry.key: entry.value.toJson(),
    };
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  Future<StudyLearningRecord> get(String paragraphId) async {
    final records = await _read();
    return records[paragraphId] ??
        StudyLearningRecord(paragraphId: paragraphId);
  }

  Future<List<StudyLearningRecord>> due({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final records = await _read();
    return records.values
        .where((r) => r.nextReviewAt == null || !r.nextReviewAt!.isAfter(at))
        .toList()
      ..sort((a, b) => (a.nextReviewAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(b.nextReviewAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
  }

  /// Record one answer. Correct answers increase mastery; incorrect answers
  /// lower it slightly and schedule a near-term retry.
  Future<StudyLearningRecord> recordAnswer({
    required String paragraphId,
    required bool correct,
    List<String> weakTopics = const [],
  }) async {
    final records = await _read();
    final old = records[paragraphId] ??
        StudyLearningRecord(paragraphId: paragraphId);
    final attempts = old.attempts + 1;
    final correctCount = old.correct + (correct ? 1 : 0);
    final streak = correct ? old.streak + 1 : 0;

    // Bayesian-ish bounded update: early answers matter more, but mastery
    // never jumps directly to 100% after a single lucky answer.
    final target = correct ? 1.0 : 0.0;
    final alpha = correct ? 0.20 : 0.28;
    final mastery = (old.mastery + (target - old.mastery) * alpha)
        .clamp(0.0, 1.0)
        .toDouble();

    final intervalDays = correct
        ? _intervalFor(mastery, streak)
        : 0.08; // about 2 hours
    final now = DateTime.now();
    final updated = old.copyWith(
      mastery: mastery,
      attempts: attempts,
      correct: correctCount,
      streak: streak,
      lastReviewedAt: now,
      nextReviewAt: now.add(Duration(minutes: (intervalDays * 1440).round())),
      weakTopics: _mergeWeakTopics(old.weakTopics, weakTopics, correct),
    );
    records[paragraphId] = updated;
    await _write(records);
    return updated;
  }

  double _intervalFor(double mastery, int streak) {
    if (mastery < 0.35) return 0.25;
    if (mastery < 0.55) return 1;
    if (mastery < 0.75) return 3;
    if (mastery < 0.90) return 7;
    if (streak < 4) return 14;
    return 30;
  }

  List<String> _mergeWeakTopics(
    List<String> existing,
    List<String> incoming,
    bool correct,
  ) {
    final result = [...existing];
    for (final topic in incoming) {
      final clean = topic.trim();
      if (clean.isEmpty) continue;
      result.remove(clean);
      if (!correct) result.insert(0, clean);
    }
    return result.take(20).toList();
  }

  Future<void> clear(String paragraphId) async {
    final records = await _read();
    records.remove(paragraphId);
    await _write(records);
  }

  Future<void> clearAll() => _write({});
}

final studyLearningProvider = Provider<StudyLearningService>(
  StudyLearningService.new,
);
