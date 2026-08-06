// Схемы инструментов (function calling) для Hermes и Насти.

import 'agent_loop.dart';

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

/// Инструменты Hermes Agent (полный набор).
final List<ToolDefinition> hermesAgentTools = [
  webSearchTool,
  getWebpageTool,
  searchKnowledgeTool,
  readNoteTool,
  createNoteTool,
  writeFileTool,
  readFileTool,
  listDirTool,
  makePdfTool,
  currencyTool,
  setTaskTool,
  listTasksTool,
  markTaskDoneTool,
];

/// Инструменты Насти (компаньон: база знаний + веб + задачи).
final List<ToolDefinition> nastyaAgentTools = [
  searchKnowledgeTool,
  readNoteTool,
  createNoteTool,
  webSearchTool,
  getWebpageTool,
  setTaskTool,
  listTasksTool,
  markTaskDoneTool,
  currencyTool,
];
