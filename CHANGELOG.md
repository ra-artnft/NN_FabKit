# Changelog

Формат — по [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Версии монорепо независимы от версии плагина; версия плагина живёт в `plugin-sketchup/src/nn_fabkit/version.rb`.

## [v0.0.7] — 2026-04-24

### Fixed
- Плагин v0.3.1: **`NoMethodError: undefined method 'add_loop' for #<Deleted Entity>`** при создании профильной трубы. Inner loop стенки строился через `entities.add_line` по сегментам, но каждая такая линия в плоскости уже существующей outer face расщепляет её — outer становится Deleted Entity к моменту вызова `add_loop`. Возврат к стандартной SketchUp-идиоме: `add_face(inner_pts) → erase!` поверх outer автоматически образует inner loop (отверстие). Плюс fallback по `entities.grep(Sketchup::Face).max_by(&:area)` если outer всё-таки не выживает.

## [v0.0.6] — 2026-04-24

### Fixed
- **Сборка `.rbz` под Windows ломала установку в SketchUp.** Rakefile использовал `[System.IO.Compression.ZipFile]::CreateFromDirectory` через PowerShell — под .NET Framework 4.x он пишет нативные `\` в именах файлов архива, что нарушает PKZIP App Note (требует `/`) и SketchUp Extension Manager молча отвергает такой `.rbz` (диалога с ошибкой нет, просто ничего не происходит). Detected на SU 2025 Windows 2026-04-24 при попытке поставить `nn_fabkit-0.3.0.rbz`. Rakefile теперь упаковывает архив через Python `zipfile` (гарантированно `/`); fallback на `zip(1)` для Unix; явный fail с инструкцией если Python отсутствует. На Linux/macOS поведение не меняется.

## [v0.0.5] — 2026-04-24

### Added
- Плагин v0.3.0: первый параметрический генератор металл-ветки `NN::MetalFab::ProfileGenerator::RectTube` — LOD-1 геометрия профильной трубы (rounded rect сечение со скруглёнными углами и реальной стенкой, Follow Me экструзия по +Z, бюджет ≤60 faces / ≤100 edges, 8 сегментов на радиус).
- Команда меню `Extensions → NN FabKit → MetalFab → Создать «Профильная труба»…` — выбор типоразмера / марки стали / длины из каталога ГОСТ 30245-2003, создаёт definition с метаданными `nn_metalfab` (ADR-005) и DC-атрибутами для Component Options.
- Структура `plugin-sketchup/src/nn_fabkit/metalfab/` под ветку `NN::MetalFab` — модули `catalog`, `attr_dict`, `dc_attrs`, `profile_generator/rect_tube`, `commands/create_rect_tube`. Каталог `catalogs/gost-30245-rect-tube.json` — копия канонического `docs/knowledge-base/gost-30245-rect-tube.json`, доставляется в `.rbz`.
- Радиус гиба считается по формуле R = 1.5 × t для t ≤ 6 мм и R = 2 × t для t > 6 мм (06-sortament-ontology, ADR-014). Каталог переопределяет формулу фактическими значениями ГОСТ.

### Implementation notes
- DC-атрибуты на этой итерации помечены `_access = "VIEW"` (readonly) — встроенный DC-движок умеет менять только scale, не топологию (ADR-002). Регенерация при изменении параметров — следующий sprint (DC-EntityObserver, блок 5.5 spec-01).
- Имена материалов — наша конвенция `«Труба <typesize> <grade>»` (ADR-016, **без** OCL-словаря `lairdubois_opencutlist_*`).

## [v0.0.4] — 2026-04-23

### Added
- `docs/specs/spec-01-dc-rework-for-iges.md` — продуктовая спецификация на этап 1, MetalFab: доработка существующих DC заказчика «Профильная труба» и «Лист» с LOD-0 (box) на LOD-1 (с радиусами и стенкой) + метаданные `nn_metalfab`. Цель — пригодность к собственному IGES-конвертёру (ADR-017). Содержит: scope, критерии приёмки, блоки работы, тест-план на корпусе, открытые вопросы к заказчику.
- Аналитический pass по 4 моделям корпуса (без артефакта в репо — наблюдения интегрированы в spec-01 §2 «Контекст из корпуса» и в открытые вопросы §8).

### Changed
- Привязка к ADR в CLAUDE.md, memory и Notion обновлена: учтены ADR-014 (LOD-0/1/2 + бюджет геометрии), ADR-016 (OCL — только референс, не пишем `lairdubois_opencutlist_*` на компоненты, supersedes ADR-003), ADR-017 (собственный IGES-конвертёр в MVP, без SolidWorks-посредника, supersedes ADR-009). Pipeline продукта переформулирован соответственно. ADR-009 и ADR-003 помечены как superseded в навигационных табличках.

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
