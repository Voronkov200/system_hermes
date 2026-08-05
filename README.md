# System: Hermes

Цифровая ОС жизни — Flutter-приложение для Android, объединяющее геймификацию
в стиле RPG, финансовый контроль, интеграцию с Obsidian и автономного
AI-агента Hermes.

## Модули

| Модуль | Что делает |
|---|---|
| **Obsidian Sync Engine** | Выбор Vault-папки, чтение/создание/редактирование `.md`, файловый watcher в реальном времени |
| **Центральный Банк Тима** | Пенсия 450 BYN (настраиваемая дата), автораспределение: 50 BYN → «Топливо разработки», 400 BYN → «Твердые активы» (USD/EUR), конвертация по курсу API Нацбанка РБ, история операций, анимация «дождя из монет» |
| **Майнинг & PC Builder** | Сборка ПК из комплектующих (CPU/GPU/RAM/Storage), установка ОС и драйверов через симуляцию терминала, хешрейт и очки прогресса |
| **Протокол Дофаминовой Стабильности** | Стрики без срывов, тренировки 20×приседаний и 20×отжиманий, штрафы (25 BYN + блок фермы на 24 ч) и бонусы (+10% хешрейта за каждую тренировку) |
| **Hermes Agent** | Чат-контроллер с Tool Calling: `create_obsidian_note`, `read_obsidian_note`, `get_github_commits`, `get_health_data`, `request_photo_verification`, `update_dopamine_protocol_status` |
| **Настройки** | Тема, день пенсии, валюта активов, папка Vault, URL/ключ Hermes, GitHub-репозиторий, сброс данных |

## Стек

- **Flutter / Dart** (state: Riverpod, routing: go_router)
- **Hive CE** (быстрая локальная БД, адаптеры написаны вручную — build_runner не нужен)
- **API Нацбанка РБ** `https://www.nbrb.by/api/exrates/rates?periodicity=0`
- **GitHub Actions** для сборки APK в облаке
- **Health Connect** (опционально, для верификации шагов)

## Как собрать APK (GitHub Actions)

1. Создай репозиторий на GitHub и запуши проект (файл `.github/workflows/main.yml` уже готов).
2. Открой вкладку **Actions** → запусти workflow `Flutter Build APK` (автозапуск при каждом push в `main`).
3. Скачай APK из артефактов сборки (`release-apk`).

Workflow генерирует Android-платформу (`flutter create`), патчит
`AndroidManifest.xml` (разрешения `INTERNET`, `MANAGE_EXTERNAL_STORAGE`,
Health Connect) и `minSdk 28`.

### Почему в репозитории нет папки `android/`

Чтобы не тащить бинарные файлы gradle-wrapper.jar. Папка генерируется
автоматически при сборке, а конфигурация (манифест, minSdk, имя приложения)
применяется скриптом `tool/patch_android.sh`.

## Локальный запуск (по желанию)

```bash
flutter create --platforms android --org com.hermes --project-name system_hermes .
flutter pub get
bash tool/patch_android.sh   # Windows: git-bash или WSL
flutter run
```

> Примечание: на слабом ПК (Celeron, 4 ГБ RAM) локальная сборка APK будет
> очень медленной — для этого и предусмотрена сборка в облаке.

## Настройка Hermes Agent (сервер)

В разделе «Настройки → Hermes Agent» укажи URL своего сервера и API-ключ.
Ожидаемый формат ответа сервера:

```json
{
  "reply": "текст ответа",
  "tool_calls": [
    { "name": "create_obsidian_note", "arguments": { "title": "План дня", "content": "...", "tags": [] } }
  ]
}
```

Без сервера работает **офлайн-режим**: встроенный отклик с той же
демонстрацией Tool Calling («создай заметку …», «курс валют», «коммиты»,
«статус системы», «фото»).

## Структура проекта

```
lib/
├── main.dart                 # точка входа: Hive + SharedPreferences
├── app.dart                  # корневой виджет (темы, роутер)
├── router.dart               # go_router
├── core/                     # тема, константы, утилиты
├── data/
│   ├── models.dart           # модели (Account, Transaction, MiningFarm, …)
│   └── adapters.dart         # ручные Hive-адаптеры
├── services/                 # бизнес-логика (Riverpod Notifier'ы)
└── features/                 # экраны по модулям
```

## Возможные проблемы при сборке

- **flutter_health_connect** — старый плагин; если сборка упадёт на нём,
  убери его из `pubspec.yaml` (сервис `health_service.dart` корректно
  вернёт «недоступно», приложение продолжит работать).
- **file_picker на Android 11+** — для доступа к произвольным папкам
  требуется `MANAGE_EXTERNAL_STORAGE` (добавляется скриптом патча). На
  некоторых прошивках нужно вручную выдать разрешение в настройках системы.
