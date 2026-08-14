/// Deterministic router for the Study Skill.
///
/// The LLM may explain a request, but the app decides which study workflow
/// is active. This prevents prompt wording from accidentally switching a
/// learning session into a destructive or answer-only workflow.
enum StudySkill {
  explain,
  learn,
  practice,
  review,
  solve,
  gdzCheck,
  exam,
}

class StudySkillRequest {
  final StudySkill skill;
  final String query;
  final bool allowGdz;

  const StudySkillRequest({
    required this.skill,
    required this.query,
    this.allowGdz = false,
  });
}

class StudySkillRouter {
  const StudySkillRouter();

  StudySkillRequest route(String query) {
    final q = query.trim().toLowerCase();
    if (_containsAny(q, const [
      'гдз',
      'готовый ответ',
      'проверь мой ответ',
      'сверь ответ',
    ])) {
      return StudySkillRequest(
        skill: StudySkill.gdzCheck,
        query: query,
        allowGdz: true,
      );
    }
    if (_containsAny(q, const [
      'экзамен',
      'цт',
      'цэ',
      'контрольная',
      'пробник',
    ])) {
      return StudySkillRequest(skill: StudySkill.exam, query: query);
    }
    if (_containsAny(q, const [
      'реши',
      'решение',
      'задачу',
      'упражнение',
      'пример',
    ])) {
      return StudySkillRequest(skill: StudySkill.solve, query: query);
    }
    if (_containsAny(q, const [
      'повтори',
      'повторение',
      'ошибки',
      'что я не знаю',
      'слабые места',
    ])) {
      return StudySkillRequest(skill: StudySkill.review, query: query);
    }
    if (_containsAny(q, const [
      'потренируй',
      'тест',
      'проверь меня',
      'вопросы',
    ])) {
      return StudySkillRequest(skill: StudySkill.practice, query: query);
    }
    if (_containsAny(q, const [
      'научи',
      'выучи',
      'изучи',
      'изучить',
      'запомнить',
    ])) {
      return StudySkillRequest(skill: StudySkill.learn, query: query);
    }
    return StudySkillRequest(skill: StudySkill.explain, query: query);
  }

  bool _containsAny(String text, List<String> values) =>
      values.any(text.contains);
}
