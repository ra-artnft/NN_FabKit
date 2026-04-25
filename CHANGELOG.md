# Changelog

Формат — по [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Версии монорепо независимы от версии плагина; версия плагина живёт в `plugin-sketchup/src/nn_fabkit/version.rb`.

## [v0.0.13] — 2026-04-24

### Added
- Плагин v0.5.0: **MCP-мост Claude ⇄ SketchUp** (Sprint A spec-02). Ruby сторона — `NN::FabKit::Mcp::Server` (TCP 127.0.0.1:9876, JSON-RPC 2.0, line-delimited, connection-per-request, `UI.start_timer` polling без Thread.new). MVP tools: `eval_ruby` (universal escape hatch с захватом stdout), `get_scene_info` (быстрый снапшот с selection brief), `dump_model` (полный SkpDump через MCP).
- Меню `Extensions → NN FabKit → MCP сервер → Запустить / Остановить / Статус`. Запуск явный с предупреждением про мощь `eval_ruby`. По умолчанию сервер не активен — открытие порта только по явному действию пользователя.
- `mcp-bridge/` — отдельный Python пакет `nn-fabkit-mcp` (FastMCP framework). Tools зеркалят Ruby-сторону. Установка: `pip install -e mcp-bridge/` + `claude mcp add nn-fabkit -- python -m nn_fabkit_mcp`. README с полным install-workflow.
- В `Extensions → NN FabKit → О плагине…` добавлен индикатор статуса MCP-сервера.

### Implementation notes
- Архитектурный pivot — **ADR-018 supersedes ADR-001**: вместо форка `mhyrr/sketchup-mcp` (license=null, форкать нельзя) — собственная реализация, опираясь на публично описанные паттерны (TCP+JSON-RPC+timer polling — общеизвестные идиомы). Код mhyrr НЕ копировался.
- Папка `mcp-corpus/` оставлена под свою роль (MCP к корпусу примеров, ADR-015), `mcp-bridge/` — новая папка под мост к работающему SketchUp процессу. В Claude Code оба сервера могут работать одновременно.
- Предупреждение безопасности: после запуска MCP сервера любой процесс на 127.0.0.1 может выполнять `eval_ruby` в SU. Bind строго на loopback, никаких external соединений.

## [v0.0.12] — 2026-04-24

### Added
- `docs/specs/spec-02-mcp-bridge.md` — спецификация MCP-моста SketchUp ⇄ Claude. Архитектура: TCP сервер в плагине (`NN::FabKit::Mcp::Server`, 127.0.0.1:9876, line-delimited JSON-RPC 2.0, `UI.start_timer` polling) + Python пакет `nn_fabkit_mcp` (FastMCP framework). MVP tools: `eval_ruby`, `get_scene_info`, `dump_model` плюс высокоуровневые. Цель — ускорить итерации разработки на порядок (3 минуты install цикл → 5 секунд eval_ruby).
- `docs/specs/spec-03-plugin-ui-redesign.md` — спецификация UI редизайна. Замена inputbox-driven workflow на постоянную боковую панель «NN FabKit Inspector» через `UI::HtmlDialog`. Vanilla JS + минимальный CSS (без React/build step). Sortament browser + Selection inspector + Toolbar. Default scope — UI/UX (A); visual brand (логотип, иконки, цветовая схема — B) — отдельный sprint при подтверждении заказчиком.
- **ADR-018 добавлен в `docs/knowledge-base/09-architecture-decisions.md`** — MCP-мост собственной реализации, supersedes ADR-001. Причина: `mhyrr/sketchup-mcp` (на которое ссылался ADR-001) не имеет LICENSE — по умолчанию all-rights-reserved, форкать нельзя. Используем только публично описанные паттерны (TCP+JSON-RPC+timer polling — общеизвестные идиомы), код не копируем.

### Changed
- ADR-001 помечен как `superseded ADR-018` в `memory/reference_adr_map.md` и в Notion ADR-странице.

## [v0.0.11] — 2026-04-24

### Added
- Репозиторий опубликован на GitHub: https://github.com/ra-artnft/NN_FabKit (public).
- `update.json` в корне репо — manifest для Updater'а. Формат `{ latest_version, rbz_url, release_notes }`. Раздаётся через `https://raw.githubusercontent.com/ra-artnft/NN_FabKit/master/update.json`.
- GitHub Release `v0.4.1` с прикреплённым `nn_fabkit-0.4.1.rbz` — официальный канал распространения.
- Плагин v0.4.1: `Updater::DEFAULT_MANIFEST_URL` теперь указывает на raw GitHub URL — `Проверить обновления…` работает без первоначальной ручной настройки. `Сменить URL обновлений…` остаётся для приватных каналов / форков.
- Команда `CheckUpdate.ensure_manifest_url` упрощена — не спрашивает URL при первом запуске (default уже валиден), пользователь сразу видит результат проверки.

## [v0.0.10] — 2026-04-24

### Added
- Плагин v0.4.0: **IGES wireframe-экспорт одной трубы** (`Extensions → NN FabKit → MetalFab → Экспорт «Профильная труба» в IGES…`). Минимальное подмножество IGES 5.3 — Type 110 (Line) + Type 100 (Circular Arc), ASCII fixed 80-col format со всеми пятью секциями (S/G/D/P/T). Выгружает endcap-контуры на z=0 и z=length (outer + inner) плюс 4 силуэтных вертикальных линии с каждого контура. Файл читается любым IGES viewer'ом — даёт визуальный контроль геометрии. Это первый шаг к полному собственному IGES-конвертёру (ADR-017); полный surface-model BREP (Type 120/122/144) — отдельный sprint в `app-desktop/`.
- Плагин v0.4.0: **удалённое обновление плагина** (`NN FabKit → Проверить обновления…` + `Сменить URL обновлений…`). Manifest формат — JSON `{ latest_version, rbz_url, release_notes }` по любому URL (заказчик выбирает хостинг). URL хранится в `Sketchup.read_default("NN_FabKit", "update_manifest_url")` между сессиями. Первый запуск спрашивает URL; дальше — точечная проверка по запросу. Скачка через `Net::HTTP` (https + редиректы), установка через `Sketchup.install_from_archive`. Рестарт SU всё ещё нужен после установки (поведение Extension Manager, см. `feedback_sketchup_install_restart.md`).
- В `nn_metalfab` теперь записывается `length_mm` — нужно IGES-экспортёру (раньше падал в bounds.depth с конверсией единиц, что плохо после Make Unique / cut).

### Implementation notes
- Структура `metalfab/iges_exporter/wireframe.rb` (~280 строк) — полный IGES writer без зависимостей: hollerith strings, fixed 80-col padding, sequence numbering, P→D pointer back, G section с 25 параметрами. Открыто к расширению (Type 120 surface of revolution для углов трубы — следующий шаг к surface model).
- `nn_fabkit/updater.rb` — Net::HTTP (stdlib) + JSON.parse. Manifest URL заглушка `https://example.invalid/...`, заказчик задаёт свой при первом запуске (любой статический хостинг — GitHub Releases, S3, собственный сервер).

## [v0.0.9] — 2026-04-24

### Changed
- Каталог `gost-30245-rect-tube.json` расширен с 28 до **62 типоразмеров** на основе реального прайса ООО «Юг-Сталь» (Краснодар) — основного поставщика заказчика-0. Schema bump 1.0 → 1.1: добавлены поля `derived.supplier_stock_lengths_mm` (фактический длины проката) и `_mass_note` (для аномалий и теоретических значений). Сохранены крупные типоразмеры (`80×80×4`…`180×180×6`) по ГОСТ как «не у поставщика, теоретические». Подробности в `docs/knowledge-base/CHANGELOG.md`.
- Копия каталога в плагине синхронизирована, плагин v0.3.2 → v0.3.3. Меню «Создать «Профильная труба»…» теперь предлагает 62 опции.
- Откат демо-сборки рамки перегородки (`build_partition_frame.rb`, sprint A) — компоновка transformations была преждевременной, возвращены к чистому генератору `RectTube`. Git revert `3b91446`, история сохранена.

## [v0.0.8] — 2026-04-24

### Changed
- Плагин v0.3.2: визуально упрощённая геометрия профильной трубы. Дуговые рёбра внешнего и внутреннего контура помечаются как `soft + smooth` после построения — 8 сегментов на угол перестают рисоваться отдельными линиями, профиль выглядит как одна гладкая дуга. После Follow Me все вертикальные рёбра, не лежащие на 4 «угловых» прямых (X=±hw, Y=±hh), также помечаются soft+smooth — боковая поверхность трубы рендерится как один цилиндр-сегмент, не как 32-гранник. Геометрия не меняется (NC-конвертёр по-прежнему получает 8 точек на радиус + аналитический outer_radius_mm в `nn_metalfab`); меняется только rendering.
- Плагин v0.3.2: `ext.check if ext.respond_to?(:check)` в loader сразу после `register_extension` — попытка форсировать загрузку main.rb в той же сессии после Install. Не всегда помогает (Extension Manager не пересканирует Plugins folder в runtime), но удешевляет сценарий «поставил → сразу хочу пользоваться» для случаев, когда SU всё-таки готов resync. В большинстве случаев рестарт SU остаётся обязательным.

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
