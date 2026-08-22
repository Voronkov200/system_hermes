// Схемы инструментов (function calling) для Hermes.

import 'tool_definition.dart';

const ToolDefinition webSearchTool = ToolDefinition(
  name: 'web_search',
  description:
      'Поиск информации в интернете. Возвращает заголовки, ссылки и краткие '
      'сниппеты по запросу. Используй, когда нужно свежие данные, новости, '
      'факты, примеры кода или ответы, которых нет в базе знаний.',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Поисковый запрос'},
    },
    'required': ['query'],
  },
);

const ToolDefinition getWebpageTool = ToolDefinition(
  name: 'get_webpage',
  description:
      'Загрузка веб-страницы по URL и извлечение читаемого текста. '
      'Используй после web_search, чтобы прочитать полную статью.',
  parameters: {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'Полный URL страницы'},
    },
    'required': ['url'],
  },
);

const ToolDefinition writeFileTool = ToolDefinition(
  name: 'write_file',
  description:
      'Создание или перезапись файла на телефоне (код, текст, документация, '
      'конфиги, проекты). Вложенные папки создаются автоматически. '
      'Файлы лежат в SystemHermes/ (или в каталоге приложения, если нет '
      'доступа ко всем файлам).',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Путь: папка/имя.расширение'},
      'content': {'type': 'string', 'description': 'Полное содержимое файла'},
    },
    'required': ['path', 'content'],
  },
);

const ToolDefinition readFileTool = ToolDefinition(
  name: 'read_file',
  description: 'Чтение файла, созданного в SystemHermes/ или каталоге приложения.',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Путь к файлу'},
    },
    'required': ['path'],
  },
);

const ToolDefinition listDirTool = ToolDefinition(
  name: 'list_dir',
  description: 'Список файлов и папок в SystemHermes/ или каталоге приложения.',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Папка (пусто = корень)'},
    },
    'required': [],
  },
);

const ToolDefinition makePdfTool = ToolDefinition(
  name: 'make_pdf',
  description:
      'Сборка текста в PDF-документ прямо на телефоне (поддерживает '
      'русский). Используй для документации, отчётов, сводок, конспектов.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Заголовок документа'},
      'text': {'type': 'string', 'description': 'Текст документа'},
      'path': {
        'type': 'string',
        'description': 'Необязательный путь, по умолчанию docs/<title>.pdf',
      },
    },
    'required': ['title', 'text'],
  },
);

const ToolDefinition searchKnowledgeTool = ToolDefinition(
  name: 'search_knowledge',
  description:
      'Поиск по базе знаний владельца (Obsidian Vault): заметки по названию '
      'и содержимому. Используй прежде интернет-поиска для личных тем.',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Поисковый запрос'},
    },
    'required': ['query'],
  },
);

const ToolDefinition readNoteTool = ToolDefinition(
  name: 'read_obsidian_note',
  description: 'Чтение полного содержимого заметки из Obsidian Vault по названию.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Название заметки'},
    },
    'required': ['title'],
  },
);

const ToolDefinition createNoteTool = ToolDefinition(
  name: 'create_obsidian_note',
  description: 'Создание новой заметки в Obsidian Vault.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
      'content': {'type': 'string'},
    },
    'required': ['title', 'content'],
  },
);

const ToolDefinition currencyTool = ToolDefinition(
  name: 'get_currency_rates',
  description: 'Официальные курсы валют Нацбанка РБ (USD, EUR в BYN).',
  parameters: {'type': 'object', 'properties': {}},
);

const ToolDefinition setTaskTool = ToolDefinition(
  name: 'set_task',
  description:
      'Поставить задачу для владельца. Используй для составления планов, '
      'дедлайнов, шагов к целям. Задача сохранится и её можно отмечать.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Краткое название задачи'},
      'description': {
        'type': 'string',
        'description': 'Подробности, срок, критерии выполнения',
      },
    },
    'required': ['title'],
  },
);

const ToolDefinition listTasksTool = ToolDefinition(
  name: 'list_tasks',
  description: 'Список текущих и выполненных задач владельца.',
  parameters: {'type': 'object', 'properties': {}},
);

const ToolDefinition markTaskDoneTool = ToolDefinition(
  name: 'mark_task_done',
  description: 'Отметить задачу выполненной.',
  parameters: {
    'type': 'object',
    'properties': {
      'task_id': {'type': 'string', 'description': 'id задачи'},
    },
    'required': ['task_id'],
  },
);

const ToolDefinition journalAddTool = ToolDefinition(
  name: 'journal_add',
  description:
      'Добавить запись в журнал изменений (табличку всех действий). '
      'Используй, когда пользователь сделал что-то важное, надиктовал мысль '
      'или попросил записать результат. Позже это можно будет найти и '
      'просмотреть.',
  parameters: {
    'type': 'object',
    'properties': {
      'type': {
        'type': 'string',
        'description': 'voice | file | pdf | task | note | study | system',
      },
      'title': {'type': 'string', 'description': 'Краткое название'},
      'text': {'type': 'string', 'description': 'Содержание записи'},
    },
    'required': ['type', 'title'],
  },
);

const ToolDefinition makeStudyPdfTool = ToolDefinition(
  name: 'make_study_pdf',
  description:
      'Составить конспект по параграфу/теме учебника в PDF: '
      'предмет → параграф → суть → определения → формулы/правила → '
      'важные моменты → вопросы для проверки. Сохраняется в '
      'SystemHermes/study/конспекты/.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Название (предмет, параграф)'},
      'text': {'type': 'string', 'description': 'Текст конспекта по шаблону'},
    },
    'required': ['title', 'text'],
  },
);

const ToolDefinition readPdfTool = ToolDefinition(
  name: 'read_pdf',
  description:
      'Извлечь текст из PDF-файла на телефоне (учебники). Папка study/ '
      'содержит учебники и конспекты. pages: номер страницы, диапазон '
      '"12-15" или пусто (первые страницы).',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Путь к PDF'},
      'pages': {
        'type': 'string',
        'description': 'Страницы: "12", "12-15" (необязательно)',
      },
    },
    'required': ['path'],
  },
);

const ToolDefinition getGithubCommitsTool = ToolDefinition(
  name: 'get_github_commits',
  description:
      'Коммиты владельца в GitHub-репозитории за период (цифровой след '
      'дисциплины). Нужны настройки GitHub owner/repo.',
  parameters: {
    'type': 'object',
    'properties': {
      'owner': {'type': 'string', 'description': 'Владелец репозитория'},
      'repo': {'type': 'string', 'description': 'Репозиторий'},
      'since': {'type': 'string', 'description': 'Дата с (YYYY-MM-DD)'},
    },
    'required': ['owner', 'repo', 'since'],
  },
);

const ToolDefinition getHealthDataTool = ToolDefinition(
  name: 'get_health_data',
  description: 'Количество шагов за сегодня через Health Connect.',
  parameters: {
    'type': 'object',
    'properties': {},
    'required': [],
  },
);

const ToolDefinition requestPhotoVerificationTool = ToolDefinition(
  name: 'request_photo_verification',
  description:
      'Попросить владельца прислать фото, подтверждающее выполненное дело '
      '(цифровой след).',
  parameters: {
    'type': 'object',
    'properties': {
      'task_id': {'type': 'string', 'description': 'ID задачи (необязательно)'},
      'description': {'type': 'string', 'description': 'Что подтвердить'},
    },
    'required': ['description'],
  },
);

const ToolDefinition updateProtocolStatusTool = ToolDefinition(
  name: 'update_dopamine_protocol_status',
  description: 'Отметить выполненную тренировку в протоколе.',
  parameters: {
    'type': 'object',
    'properties': {
      'habit_id': {
        'type': 'string',
        'description': 'ID тренировки: workout_squat или workout_pushups',
      },
      'status': {'type': 'string', 'description': 'Только "done"'},
    },
    'required': ['habit_id', 'status'],
  },
);

/// Инструменты Hermes Agent (полный набор).
final List<ToolDefinition> hermesAgentTools = [
  webSearchTool,
  getWebpageTool,
  searchKnowledgeTool,
  readNoteTool,
  createNoteTool,
  readPdfTool,
  writeFileTool,
  readFileTool,
  listDirTool,
  makePdfTool,
  makeStudyPdfTool,
  currencyTool,
  setTaskTool,
  listTasksTool,
  markTaskDoneTool,
  journalAddTool,
  getGithubCommitsTool,
  getHealthDataTool,
  requestPhotoVerificationTool,
  updateProtocolStatusTool,
];
