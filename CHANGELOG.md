# Changelog

Формат — по [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Версии монорепо независимы от версии плагина; версия плагина живёт в `plugin-sketchup/src/nn_fabkit/version.rb`.

## [v0.0.3] — 2026-04-23

### Added
- Первое наполнение корпуса: `corpus/examples/01..04` — четыре реальных проекта заказчика-0, дампы прогнаны через плагин v0.2.0. `notes.md` — заглушки с TODO, ждут ответов от заказчика.
- `corpus/README.md` — структура папки примера, статус наполнения, правила приватности, процесс пополнения.
- В CLAUDE.md и memory `project_overview.md` зафиксирована Pipeline-формулировка продукта от заказчика-0 (corpus → квази-обучение → генерация типовых моделей по образцу + параллельная доработка существующих DC под IGES-экспорт через SolidWorks-посредника).

### Changed
- `.gitignore` исключил `corpus/examples/`, `*.skp`, `*.dump.json`, `*.skp_dump.json` — внутри дампов в `model.path` лежат ФИО клиентов.

## [v0.0.2] — 2026-04-23

### Added
- `CLAUDE.md` в корне — карта проекта для будущих сессий: источники истины (Notion + kb), навигационная таблица, доменный словарь, конвенции кода плагина.
- Плагин v0.2.0: команда `Extensions → NN FabKit → Dump в JSON…` — обёртка над `NN::FabKit::SkpDump`, синхронизированной копией `docs/knowledge-base/tools/skp_dump.rb` (без автозапуска при загрузке).

### Changed
- В `plugin-sketchup/README.md` обновлены разделы «Текущая функциональность», «Структура», «Следующие шаги».

## [v0.0.1] — 2026-04-22

### Added
- Инициализация монорепо, git-репозиторий на уровне корня.
- Скелет плагина `plugin-sketchup/` v0.1.0: меню `Extensions → NN FabKit → О плагине…`, messagebox с версией плагина и SketchUp.
- Rakefile с тасками `build`, `clean`, `install` (без gem-зависимостей).
- Заглушки `app-desktop/`, `mcp-corpus/`, `corpus/` с README, описывающими будущую роль и ADR-контекст.
- Корневой `README.md`, `CHANGELOG.md`, `.gitignore`.
