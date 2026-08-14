/// Deterministic router for the Study skill.
///
/// The LLM can choose a mode, but the mode itself is constrained to this
/// finite set. This keeps study behaviour stable and testable.
enum StudySkillMode { explain, learn, practice, review, solve, gdzCheck, exam }

class StudySkillRequest {
  final StudySkillMode mode;
  final String? subject;
  final String? paragraphId;
  final String topic;

  const StudySkillRequest({
    required this.mode,
    this.subject,
    this.paragraphId,
    this.topic = '',
  });
}

class StudySkillRouter {
  const StudySkillRouter();

  StudySkillRequest route({
    required String message,
    String? subject,
    String? paragraphId,
  }) {
    final text = message.trim().toLowerCase();
    final mode = _modeFor(text);
    return StudySkillRequest(
      mode: mode,
      subject: subject,
      paragraphId: paragraphId,
      topic: message.trim(),
    );
  }

  String systemContext(StudySkillRequest request) {
    final mode = switch (request.mode) {
      StudySkillMode.explain => 'ОБЪЯСНЕНИЕ',
      StudySkillMode.learn => 'ОБУЧЕНИЕ',
      StudySkillMode.practice => 'ПРАКТИКА',
      StudySkillMode.review => 'ПОВТОРЕНИЕ',
      StudySkillMode.solve => 'РЕШЕНИЕ',
      StudySkillMode.gdzCheck => 'ПРОВЕРКА ПО ГДЗ',
      StudySkillMode.exam => 'ЭКЗАМЕН',
    };

    return '''SKILL: STUDY / $mode

Правила:
- Используй локальный учебник как основной источник, если он доступен.
- Не выдумывай параграфы, страницы, задания или ответы.
- В режиме practice/exam сначала дай пользователю возможность ответить самому.
- В режиме solve показывай ход решения и только затем итог.
- В режиме gdzCheck используй ГДЗ только для сверки и явно отделяй источник от собственного объяснения.
- После ошибки назови конкретную слабую тему и предложи повторную попытку.
- Не помечай тему освоенной только из-за открытия страницы или нажатия кнопки.
- Для устойчивого освоения используй локальный mastery-прогресс StudyLearningService.
- Ответы и объяснения — на русском, если пользователь не попросил другой язык.''';
  }

  StudySkillMode _modeFor(String text) {
    if (_hasAny(text, ['гдз', 'решеб', 'сверь ответ', 'проверь по ответу'])) {
      return StudySkillMode.gdzCheck;
    }
    if (_hasAny(text, ['экзамен', 'экзаменац', 'контрольная', 'тест'])) {
      return StudySkillMode.exam;
    }
    if (_hasAny(text, ['реши', 'решение', 'решить задачу', 'задач'])) {
      return StudySkillMode.solve;
    }
    if (_hasAny(text, ['повтори', 'повторить', 'повторение', 'что я забыл'])) {
      return StudySkillMode.review;
    }
    if (_hasAny(text, ['потренируй', 'практика', 'проверь меня', 'дай задания'])) {
      return StudySkillMode.practice;
    }
    if (_hasAny(text, ['научи', 'изучи со мной', 'выучи', 'учить'])) {
      return StudySkillMode.learn;
    }
    return StudySkillMode.explain;
  }

  bool _hasAny(String text, List<String> needles) =>
      needles.any(text.contains);
}

const studySkillRouter = StudySkillRouter();
