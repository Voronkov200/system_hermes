// Каталог механик "Жизни": действия, достижения, квесты.
// Механики перенесены из Telegram-игры «Богатая жизнь» и адаптированы
// под реальные задачи Тима (социализация, физформа, финансы, фриланс).

/// Действие, которое Тим может выполнить в реальной жизни.
class LifeActionDef {
  final String id;
  final String name;
  final String icon; // имя Material-иконки
  final String description;
  final double energyDelta; // изменение энергии
  final double moodDelta; // изменение настроения
  final double disciplineDelta; // изменение дисциплины
  final int xp; // награда опытом
  final Duration cooldown; // перезарядка действия

  const LifeActionDef({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    this.energyDelta = 0,
    this.moodDelta = 0,
    this.disciplineDelta = 0,
    this.xp = 0,
    this.cooldown = const Duration(minutes: 30),
  });
}

/// Достижение (личная веха).
class LifeAchievementDef {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int xp;

  const LifeAchievementDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.xp = 0,
  });
}

/// Квест из цепочки "Сосед-старожил".
class LifeQuestDef {
  final int index; // порядковый номер (1-based)
  final String name;
  final String description;
  final String icon;
  final int xp;

  const LifeQuestDef({
    required this.index,
    required this.name,
    required this.description,
    required this.icon,
    this.xp = 0,
  });
}

/// Каталог всех механик.
class LifeCatalog {
  LifeCatalog._();

  // ------------------------------------------------------------- действия

  static const List<LifeActionDef> actions = [
    LifeActionDef(
      id: 'walk',
      name: 'Прогулка',
      icon: 'directions_walk',
      description: 'Выйти на улицу, пройтись',
      moodDelta: 15,
      disciplineDelta: 5,
      energyDelta: -5,
      xp: 10,
      cooldown: Duration(hours: 2),
    ),
    LifeActionDef(
      id: 'store',
      name: 'Поход в магазин',
      icon: 'storefront',
      description: 'Самостоятельно сходить в магазин',
      moodDelta: 10,
      disciplineDelta: 10,
      energyDelta: -8,
      xp: 15,
      cooldown: Duration(hours: 3),
    ),
    LifeActionDef(
      id: 'atm',
      name: 'Банкомат',
      icon: 'account_balance',
      description: 'Снять деньги с банкомата',
      moodDelta: 5,
      disciplineDelta: 10,
      xp: 15,
      cooldown: Duration(days: 1),
    ),
    LifeActionDef(
      id: 'workout',
      name: 'Тренировка',
      icon: 'fitness_center',
      description: 'Отжимания или зарядка (10-15 раз)',
      moodDelta: 5,
      disciplineDelta: 12,
      energyDelta: -10,
      xp: 12,
      cooldown: Duration(hours: 4),
    ),
    LifeActionDef(
      id: 'study',
      name: 'Учёба',
      icon: 'school',
      description: 'Python, английский, LLM Handbook',
      moodDelta: -3,
      disciplineDelta: 12,
      energyDelta: -8,
      xp: 15,
      cooldown: Duration(hours: 3),
    ),
    LifeActionDef(
      id: 'freelance',
      name: 'Фриланс-заказ',
      icon: 'work',
      description: 'Работа над заказом: Kwork, FL.ru',
      moodDelta: 5,
      disciplineDelta: 10,
      energyDelta: -12,
      xp: 25,
      cooldown: Duration(hours: 6),
    ),
    LifeActionDef(
      id: 'clean',
      name: 'Уборка',
      icon: 'cleaning_services',
      description: 'Навести порядок в комнате',
      moodDelta: 8,
      disciplineDelta: 8,
      energyDelta: -8,
      xp: 10,
      cooldown: Duration(hours: 4),
    ),
    LifeActionDef(
      id: 'meditation',
      name: 'Тишина',
      icon: 'self_improvement',
      description: 'Минута без экранов, дыхание',
      moodDelta: 10,
      disciplineDelta: 8,
      xp: 8,
      cooldown: Duration(hours: 2),
    ),
    LifeActionDef(
      id: 'read',
      name: 'Книга',
      icon: 'menu_book',
      description: 'Чтение: Атомные привычки и др.',
      moodDelta: 6,
      disciplineDelta: 10,
      energyDelta: -3,
      xp: 12,
      cooldown: Duration(hours: 3),
    ),
    LifeActionDef(
      id: 'social',
      name: 'Общение',
      icon: 'forum',
      description: 'Написать/поговорить с человеком',
      moodDelta: 15,
      energyDelta: -4,
      xp: 8,
      cooldown: Duration(hours: 3),
    ),
  ];

  static LifeActionDef? actionById(String id) {
    for (final a in actions) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ---------------------------------------------------------- достижения

  static const List<LifeAchievementDef> achievements = [
    LifeAchievementDef(
      id: 'first_action',
      name: 'Первый шаг',
      description: 'Выполнить первое действие',
      icon: 'flag',
      xp: 20,
    ),
    LifeAchievementDef(
      id: 'social_3',
      name: 'Выход в мир',
      description: '3 самостоятельных выхода из дома',
      icon: 'door_front_door',
      xp: 30,
    ),
    LifeAchievementDef(
      id: 'workout_3',
      name: 'Форма',
      description: '3 тренировки за неделю',
      icon: 'fitness_center',
      xp: 40,
    ),
    LifeAchievementDef(
      id: 'study_3',
      name: 'Ученик',
      description: '3 дня учёбы подряд',
      icon: 'school',
      xp: 40,
    ),
    LifeAchievementDef(
      id: 'first_freelance',
      name: 'Заработок',
      description: 'Первый оплаченный заказ',
      icon: 'payments',
      xp: 100,
    ),
    LifeAchievementDef(
      id: 'xp_500',
      name: 'Новичок системы',
      description: 'Накопить 500 XP',
      icon: 'bolt',
      xp: 50,
    ),
    LifeAchievementDef(
      id: 'xp_2000',
      name: 'Опытный игрок',
      description: 'Накопить 2000 XP',
      icon: 'local_fire_department',
      xp: 100,
    ),
    LifeAchievementDef(
      id: 'level_5',
      name: 'Уровень 5',
      description: 'Достичь 5 уровня',
      icon: 'military_tech',
      xp: 60,
    ),
    LifeAchievementDef(
      id: 'days_7',
      name: 'Неделя в системе',
      description: 'Прожить в системе 7 дней',
      icon: 'calendar_month',
      xp: 50,
    ),
    LifeAchievementDef(
      id: 'days_30',
      name: 'Месяц в системе',
      description: 'Прожить в системе 30 дней',
      icon: 'calendar_today',
      xp: 150,
    ),
    LifeAchievementDef(
      id: 'clean_7',
      name: 'Стабильность',
      description: '7 дней без срывов протокола',
      icon: 'verified',
      xp: 60,
    ),
    LifeAchievementDef(
      id: 'first_deposit',
      name: 'Вкладчик',
      description: 'Первые 50 BYN на «Топливе разработки»',
      icon: 'savings',
      xp: 80,
    ),
    LifeAchievementDef(
      id: 'first_usd',
      name: 'Твердая валюта',
      description: 'Первые 10 USD в «Твердых активах»',
      icon: 'currency_exchange',
      xp: 100,
    ),
  ];

  static LifeAchievementDef? achievementById(String id) {
    for (final a in achievements) {
      if (a.id == id) return a;
    }
    return null;
  }

  // -------------------------------------------------------------- квесты

  static const List<LifeQuestDef> quests = [
    LifeQuestDef(
      index: 1,
      name: 'Правило номер один',
      description: 'Деньги. Выполни любое действие в «Жизни»',
      icon: 'flag',
      xp: 20,
    ),
    LifeQuestDef(
      index: 2,
      name: 'Прогулка',
      description: 'Соверши первую прогулку',
      icon: 'directions_walk',
      xp: 25,
    ),
    LifeQuestDef(
      index: 3,
      name: 'Учёба',
      description: 'Проведи первое занятие (Python/английский)',
      icon: 'school',
      xp: 30,
    ),
    LifeQuestDef(
      index: 4,
      name: 'Тренировка',
      description: 'Первая тренировка (отжимания ×10)',
      icon: 'fitness_center',
      xp: 30,
    ),
    LifeQuestDef(
      index: 5,
      name: 'Магазин',
      description: 'Самостоятельный поход в магазин',
      icon: 'storefront',
      xp: 40,
    ),
    LifeQuestDef(
      index: 6,
      name: 'Банкомат',
      description: 'Снять деньги с банкомата',
      icon: 'account_balance',
      xp: 40,
    ),
    LifeQuestDef(
      index: 7,
      name: 'Банковская карта',
      description: 'Накопи 50 BYN на «Топливе разработки»',
      icon: 'credit_card',
      xp: 50,
    ),
    LifeQuestDef(
      index: 8,
      name: 'Первые доллары',
      description: 'Накопи 10 USD в «Твердых активах»',
      icon: 'currency_exchange',
      xp: 60,
    ),
    LifeQuestDef(
      index: 9,
      name: 'Фриланс',
      description: 'Оформи первый заказ на фрилансе',
      icon: 'work',
      xp: 100,
    ),
    LifeQuestDef(
      index: 10,
      name: 'Неделя стабильности',
      description: '7 дней без срывов протокола',
      icon: 'verified',
      xp: 80,
    ),
    LifeQuestDef(
      index: 11,
      name: 'Месяц в системе',
      description: 'Прожить в системе 30 дней',
      icon: 'calendar_month',
      xp: 150,
    ),
  ];

  /// Расчёт уровня по XP (каждый уровень дороже предыдущего).
  static int levelForXp(int xp) {
    var level = 1;
    var need = 100;
    var rest = xp;
    while (rest >= need) {
      rest -= need;
      level++;
      need += 100;
    }
    return level;
  }

  /// Прогресс внутри текущего уровня: сколько XP до следующего.
  static ({int level, int xpInLevel, int xpForNext}) levelProgress(int xp) {
    var level = 1;
    var need = 100;
    var rest = xp;
    while (rest >= need) {
      rest -= need;
      level++;
      need += 100;
    }
    return (level: level, xpInLevel: rest, xpForNext: need);
  }
}
