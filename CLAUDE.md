# NN FabKit — заметки для Claude Code

Этот файл — карта проекта для будущих сессий. Не дублирует README, Notion и базу знаний — только то, что нужно для быстрой ориентации.

## Что это за проект

Экосистема для проектирования металлоконструкций и корпусной мебели поверх SketchUp Pro 2021+.
Заказчик-0 формулирует задачу словами → Claude через MCP-мост генерит точные 3D-компоненты с реальной геометрией → на выходе ТЗ в LayOut, cut-list, NC-программы.

**Pipeline продукта** (формулировка заказчика-0, 2026-04-23):
1. `skp_dump.rb` извлекает структурированные данные из реальных моделей заказчика-0 → `model.dump.json`.
2. Корпус ([`corpus/examples/`](corpus/)) собирается из дампов + `notes.md` с tacit knowledge (ADR-015).
3. Claude через Project Knowledge / MCP видит корпус как контекст — квази-обучение.
4. По текстовому запросу заказчика Claude генерирует **типовые модели по образцу**, повторяя стиль и паттерны корпуса.
5. Параллельно: дорабатываем существующие DC заказчика (Профильная труба, Лист — см. [08-reference-components-analysis](docs/knowledge-base/08-reference-components-analysis.md)) так, чтобы они проходили путь до **собственного IGES-конвертёра** ([ADR-017](docs/knowledge-base/09-architecture-decisions.md) — заказчик отказался от SolidWorks-посредника, ADR-009 superseded). Доработка значит: переход с LOD-0 (монолитный box, как у заказчика сейчас) на LOD-1 (реальные радиусы + стенка) и LOD-2 (с отверстиями для NC) — см. [ADR-014](docs/knowledge-base/09-architecture-decisions.md); плюс метаданные в `nn_metalfab` (тип, ГОСТ, типоразмер, марка, толщина, радиус) для извлечения BREP-структуры конвертёром. Сам IGES-райтер живёт в `app-desktop`/standalone, не в плагине.

**Архитектура зонтика** (ADR-013):
- **`NN FabKit`** (эта папка) — зонтик / оболочка всего продукта. Общее ядро: MCP-мост, DC-интеграция, OCL-разметка по именам, LayOut-генератор, движок параметрического генератора. Namespace `NN::FabKit`.
- **`MetalFab`** — предметная ветка металлоконструкций (труба, лист, уголок, швеллер; NC: IGES/DXF). **Приоритет сейчас.** Namespace `NN::MetalFab`, attribute dictionary `nn_metalfab` (ADR-005).
- **`MebelFab`** — предметная ветка корпусной мебели (ЛДСП, фанера, кромка, метизы; раскрой через OCL Cutting Diagrams). Получит свой sub-INDEX в Notion позже, когда заказчик даст вводные. Namespace `NN::MebelFab` (будущий).

Текущее состояние: **v0.0.1**, в репо только скелет SketchUp-плагина с одним пунктом меню «О плагине…». Вся продуктовая функциональность — в следующих ТЗ.

## Источники истины (в этом порядке)

1. **Notion sub-INDEX `🔧 NN_FabKit`** — `https://www.notion.so/34a879eb1d5f812a9c8ac8b8c664a4a4` — entry-point для проекта, статус этапов, чек-листы.
2. **Notion `📐 SketchUp — продукт (металл + мебель)`** — `https://www.notion.so/349879eb1d5f81f8b3c6c867443b6ee5` — TL;DR, roadmap, открытые вопросы к заказчику, контекст colour-hack.
3. **Notion `📐 SketchUp — архитектура и ADR`** — `https://www.notion.so/349879eb1d5f813cba19ff9ad50c9988` — все 13 ADR с альтернативами и последствиями.
4. **`docs/knowledge-base/`** — read-only справочники по SketchUp/LayOut Ruby API, DC, OCL, онтология сортамента, JSON-каталоги ГОСТ. Не редактируется из задач разработки плагина — обновляется отдельно.
5. **`docs/knowledge-base/09-architecture-decisions.md`** — локальная копия ADR (тот же контент, что в Notion).

При старте сессии: если вопрос про статус/roadmap/решения → Notion. Если про API SketchUp/LayOut/OCL/идиомы → `docs/knowledge-base/`.

## Структура монорепо

```
NN_FabKit/
├── plugin-sketchup/      # Ruby-плагин SketchUp (скелет, v0.1.0) — единственная часть с реальным кодом
├── app-desktop/
│   └── nc-export/        # Python standalone: IGES writer для CNC (v0.1.0, ADR-017)
├── mcp-corpus/           # заглушка — будущий MCP-сервер (Python, stdio)
├── corpus/               # заглушка — корпус реальных заказов (см. ADR-015)
├── docs/knowledge-base/  # read-only база знаний (10 MD + JSON-каталоги + skp_dump.rb)
├── README.md             # общий обзор + сборка
├── CHANGELOG.md          # Keep a Changelog
└── *.skp_dump.json       # пробные дампы из knowledge-base/tools/skp_dump.rb
```

## Навигация: что где править

| Запрос пользователя | Файл(ы) |
|---|---|
| Меню плагина (пункты, обработчики) | [plugin-sketchup/src/nn_fabkit/ui/menu.rb](plugin-sketchup/src/nn_fabkit/ui/menu.rb) |
| Регистрация плагина / проверка версии SU | [plugin-sketchup/src/nn_fabkit.rb](plugin-sketchup/src/nn_fabkit.rb) |
| Точка входа после активации (загрузка модулей) | [plugin-sketchup/src/nn_fabkit/main.rb](plugin-sketchup/src/nn_fabkit/main.rb) |
| Версия плагина | [plugin-sketchup/src/nn_fabkit/version.rb](plugin-sketchup/src/nn_fabkit/version.rb) |
| Сборка `.rbz` | [plugin-sketchup/Rakefile](plugin-sketchup/Rakefile) |
| Дампер модели → JSON (внутри плагина) | [plugin-sketchup/src/nn_fabkit/skp_dump.rb](plugin-sketchup/src/nn_fabkit/skp_dump.rb) |
| Дампер модели → JSON (канонический исходник) | [docs/knowledge-base/tools/skp_dump.rb](docs/knowledge-base/tools/skp_dump.rb) |
| **MetalFab — generator профильной трубы (LOD-1)** | [plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube.rb](plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube.rb) |
| MetalFab — UI-команда создания DC «Профильная труба» | [plugin-sketchup/src/nn_fabkit/metalfab/commands/create_rect_tube.rb](plugin-sketchup/src/nn_fabkit/metalfab/commands/create_rect_tube.rb) |
| MetalFab — writer метаданных `nn_metalfab` (ADR-005) | [plugin-sketchup/src/nn_fabkit/metalfab/attr_dict.rb](plugin-sketchup/src/nn_fabkit/metalfab/attr_dict.rb) |
| MetalFab — установка `dynamic_attributes` для DC-UX | [plugin-sketchup/src/nn_fabkit/metalfab/dc_attrs.rb](plugin-sketchup/src/nn_fabkit/metalfab/dc_attrs.rb) |
| MetalFab — загрузчик JSON-каталогов сортамента | [plugin-sketchup/src/nn_fabkit/metalfab/catalog.rb](plugin-sketchup/src/nn_fabkit/metalfab/catalog.rb) |
| MetalFab — каталог трубы (копия в плагине) | [plugin-sketchup/src/nn_fabkit/metalfab/catalogs/gost-30245-rect-tube.json](plugin-sketchup/src/nn_fabkit/metalfab/catalogs/gost-30245-rect-tube.json) |
| MetalFab — IGES wireframe-экспорт (Type 110 + 100) | [plugin-sketchup/src/nn_fabkit/metalfab/iges_exporter/wireframe.rb](plugin-sketchup/src/nn_fabkit/metalfab/iges_exporter/wireframe.rb) |
| MetalFab — UI-команда экспорта в IGES | [plugin-sketchup/src/nn_fabkit/metalfab/commands/export_iges.rb](plugin-sketchup/src/nn_fabkit/metalfab/commands/export_iges.rb) |
| **nc-export (standalone) — обзор и Quickstart** | [app-desktop/nc-export/README.md](app-desktop/nc-export/README.md) |
| nc-export — IGES core writer (S/G/D/P/T) | [app-desktop/nc-export/src/nn_fabkit_nc_export/iges/document.py](app-desktop/nc-export/src/nn_fabkit_nc_export/iges/document.py) |
| nc-export — IGES entities (Type 110, 100, 122) | [app-desktop/nc-export/src/nn_fabkit_nc_export/iges/entities.py](app-desktop/nc-export/src/nn_fabkit_nc_export/iges/entities.py) |
| nc-export — IGES low-level форматирование (80-col, Hollerith, fnum) | [app-desktop/nc-export/src/nn_fabkit_nc_export/iges/format.py](app-desktop/nc-export/src/nn_fabkit_nc_export/iges/format.py) |
| nc-export — генератор прямоугольной трубы (surface-модель) | [app-desktop/nc-export/src/nn_fabkit_nc_export/tube/rect_tube.py](app-desktop/nc-export/src/nn_fabkit_nc_export/tube/rect_tube.py) |
| nc-export — CLI (hello-surface, rect-tube) | [app-desktop/nc-export/src/nn_fabkit_nc_export/cli.py](app-desktop/nc-export/src/nn_fabkit_nc_export/cli.py) |
| nc-export — образцы .igs для проверки в CAM | [app-desktop/nc-export/examples/](app-desktop/nc-export/examples/) |
| Удалённое обновление плагина (manifest URL → .rbz) | [plugin-sketchup/src/nn_fabkit/updater.rb](plugin-sketchup/src/nn_fabkit/updater.rb) |
| UI-команды updater'а (Проверить / Сменить URL) | [plugin-sketchup/src/nn_fabkit/commands/check_update.rb](plugin-sketchup/src/nn_fabkit/commands/check_update.rb) |
| **MCP-мост Ruby (TCP сервер в SU)** | [plugin-sketchup/src/nn_fabkit/mcp/server.rb](plugin-sketchup/src/nn_fabkit/mcp/server.rb) |
| MCP — JSON-RPC dispatch | [plugin-sketchup/src/nn_fabkit/mcp/jsonrpc.rb](plugin-sketchup/src/nn_fabkit/mcp/jsonrpc.rb) |
| MCP — handlers (eval_ruby / get_scene_info / dump_model) | [plugin-sketchup/src/nn_fabkit/mcp/handlers.rb](plugin-sketchup/src/nn_fabkit/mcp/handlers.rb) |
| MCP — UI команды (Start/Stop/Status) | [plugin-sketchup/src/nn_fabkit/commands/mcp_control.rb](plugin-sketchup/src/nn_fabkit/commands/mcp_control.rb) |
| **MCP-мост Python (FastMCP)** | [mcp-bridge/](mcp-bridge/) |
| MCP — Python server | [mcp-bridge/src/nn_fabkit_mcp/server.py](mcp-bridge/src/nn_fabkit_mcp/server.py) |
| MCP — TCP transport | [mcp-bridge/src/nn_fabkit_mcp/transport.py](mcp-bridge/src/nn_fabkit_mcp/transport.py) |
| MCP — install workflow | [mcp-bridge/README.md](mcp-bridge/README.md) |
| Сортамент: профильная труба | [docs/knowledge-base/gost-30245-rect-tube.json](docs/knowledge-base/gost-30245-rect-tube.json) |
| Сортамент: лист г/к | [docs/knowledge-base/gost-19903-hot-sheet.json](docs/knowledge-base/gost-19903-hot-sheet.json) |
| Сортамент: марки стали | [docs/knowledge-base/steel-grades.json](docs/knowledge-base/steel-grades.json) |
| Архитектурные решения (ADR) | [docs/knowledge-base/09-architecture-decisions.md](docs/knowledge-base/09-architecture-decisions.md) |
| Корпус примеров (структура, статус, правила) | [corpus/README.md](corpus/README.md) |
| Шаблон `notes.md` для нового примера | [docs/knowledge-base/templates/example-notes.template.md](docs/knowledge-base/templates/example-notes.template.md) |
| Продуктовые спецификации (specs) | [docs/specs/](docs/specs/) |
| spec-01: доработка DC под собственный IGES-конвертёр | [docs/specs/spec-01-dc-rework-for-iges.md](docs/specs/spec-01-dc-rework-for-iges.md) |
| spec-02: MCP-мост Claude ⇄ SketchUp (TCP + Python FastMCP) | [docs/specs/spec-02-mcp-bridge.md](docs/specs/spec-02-mcp-bridge.md) |
| spec-03: UI-редизайн плагина (HtmlDialog Inspector) | [docs/specs/spec-03-plugin-ui-redesign.md](docs/specs/spec-03-plugin-ui-redesign.md) |
| История изменений | [CHANGELOG.md](CHANGELOG.md), [docs/knowledge-base/CHANGELOG.md](docs/knowledge-base/CHANGELOG.md) |

**По мере роста плагина дополнять**: новые UI-диалоги, генераторы профилей, экспортёры — каждый получает строку в этой таблице.

## Карта базы знаний

| Файл | Когда читать |
|---|---|
| [00-README](docs/knowledge-base/00-README.md) | старт, доменный словарь |
| [01-sketchup-ruby-api-core](docs/knowledge-base/01-sketchup-ruby-api-core.md) | пишем Ruby-код плагина |
| [02-sketchup-ruby-api-idioms](docs/knowledge-base/02-sketchup-ruby-api-idioms.md) | code review, namespace, observers, encoding |
| [03-dynamic-components-deep-dive](docs/knowledge-base/03-dynamic-components-deep-dive.md) | работа с DC заказчика |
| [04-layout-ruby-api](docs/knowledge-base/04-layout-ruby-api.md) | генерация ТЗ в LayOut |
| [05-opencutlist-integration](docs/knowledge-base/05-opencutlist-integration.md) | интеграция через имена материалов (без GPLv3-кода) |
| [06-sortament-ontology](docs/knowledge-base/06-sortament-ontology.md) | JSON-схема каталога, правило R=1.5t |
| [07-ruby-for-sketchup](docs/knowledge-base/07-ruby-for-sketchup.md) | особенности Ruby-среды внутри SU |
| [08-reference-components-analysis](docs/knowledge-base/08-reference-components-analysis.md) | что нашли в `Профильная_труба.skp` и `Лист.skp` |
| [09-architecture-decisions](docs/knowledge-base/09-architecture-decisions.md) | все ADR полностью |

## Доменный словарь (минимум)

| Термин | Значение |
|---|---|
| **Заказчик-0** | мебельщик + металлист, Россия. Использует SketchUp Pro 2025, LayOut, OpenCutList. |
| **DC** | Dynamic Component — родной механизм параметризации SU. UX-поверхность нашего плагина (ADR-002). |
| **OCL** | OpenCutList (GPLv3). Интеграция только через имя материала, код не импортируем (ADR-003). |
| **Сортамент** | Каталог металлопроката с параметрами. JSON в `docs/knowledge-base/*.json` (ADR-004). |
| **`nn_metalfab`** | `attribute_dictionary` для метаданных металл-компонентов параллельно DC (ADR-005). Для мебельных компонентов — `nn_mebelfab` (когда появятся). Общий namespace оболочки — `NN::FabKit`. |
| **NC-экспортёр** | DXF для листа, IGES для объёмных (через SolidWorks-посредника заказчика на этапе MVP — ADR-009). |
| **Colour-hack** | Цвет материала у заказчика = маркер уникальности типа проката. ⏸ Пока **не актуально** — сначала обучаем Claude на остальной онтологии, к colour-hack возвращаемся позже. ADR-012 описывает план, но в работу не берём. |

## Конвенции кода (плагин)

- Namespace: `NN::FabKit`. Глобальный скоуп не трогаем.
- В `src/` **только** `Sketchup.require` (не `require` / `require_relative` — они не находят `.rbe`, ломают Extension Warehouse-публикацию).
- Файлы UTF-8 без BOM, LF, магический `# encoding: UTF-8` в каждом `.rb` внутри `src/`.
- Отступ 2 пробела, двойные кавычки, `snake_case` для методов/файлов, `PascalCase` для модулей.
- Тексты UI — по-русски (ADR-007). Идентификаторы, ключи JSON, имена attribute dictionary — английский snake_case.
- Все модификации модели — внутри `model.start_operation` / `commit_operation` (одна undo-запись на действие).
- Префикс логов в Ruby Console: `[NN::FabKit]`.

## Сборка и установка плагина

```bash
cd plugin-sketchup
rake build      # → build/nn_fabkit-<version>.rbz
rake install    # копирует src/ в Plugins самой свежей SU (с подтверждением)
rake clean      # удалить build/
```

Установка пользователю — `Extensions → Extension Manager → Install Extension`, выбрать `.rbz` из `build/`.

## Окружение разработчика (Windows)

См. также `~/.claude/CLAUDE.md` — там общие правила (UTF-8, SSH через PowerShell из-за кириллического `$HOME`, Notion-конвенции). Краткое:

- Платформа: Windows 11, Git bash. `$HOME` = `/c/Users/Заурядный` (Cyrillic).
- Файлы под Windows-путями с кириллицей — пишем через Write/Edit (UTF-8 без BOM); через `Out-File` обязательно `-Encoding utf8`.
- Дампы из SU-плагина пишутся через `IO.write(path, json, mode: "wb")` или с явным `encoding: "UTF-8"` — иначе SU на Windows подсунет CP1251.

## Память

В `~/.claude/projects/.../memory/` живут проектные memory-файлы (NN_FabKit-specific). Индекс — в `MEMORY.md` той же папки. Глобальные конвенции (Notion, SSH, encoding) — в `~/.claude/CLAUDE.md`, не дублируем сюда.

## Что точно НЕ нужно делать

- Не редактировать `docs/knowledge-base/` из задач разработки плагина/приложения. Обновление базы знаний — отдельная процедура с записью в `docs/knowledge-base/CHANGELOG.md`.
- Не импортировать код OpenCutList (GPLv3). Интеграция только через канонические имена материалов (ADR-003).
- Не путать namespaces: `NN::FabKit` — общая оболочка, `NN::MetalFab` — металл-ветка, `NN::MebelFab` — мебельная (будущая). Сейчас в коде только общая оболочка, потому что металл-генераторы ещё не написаны.
- Не реализовывать colour-hack (ADR-012) на этом этапе — отложен до момента, когда базовая онтология обучена.
- Не пересматривать существующие ADR — оформляем новый ADR со ссылкой на предшественника.
- Не лезть в DC-формулы для топологии — формулы умеют только масштабировать (ADR-002).
- Не коммитить `corpus/examples/` в git. Внутри `model.dump.json` поле `model.path` содержит ФИО клиентов (Yandex.Disk paths). Папка целиком в `.gitignore`. Если корпус нужно опубликовать — отдельная процедура с обезличиванием и ревью.
- Не цитировать **ADR-009** и **ADR-003** как актуальные — они superseded:
  - **ADR-017** supersedes ADR-009 — собственный IGES-конвертёр в MVP (на минимальном подмножестве IGES 5.3: line/arc/cylinder/plane), плюс DXF для листа. SolidWorks-посредник убран.
  - **ADR-016** supersedes ADR-003 — OCL только референс. Наш плагин **не пишет** OCL-словарь `lairdubois_opencutlist_*` на материалы, даже несмотря на то, что у заказчика в production-моделях он повсеместно. Свой раскрой строим без оглядки на OCL.
- Не оптимизировать под «красивую визуализацию» в ущерб бюджету геометрии. ADR-014 фиксирует лимиты faces/edges на типовую деталь и три уровня детализации (LOD-0 монолит → LOD-1 с радиусами → LOD-2 с отверстиями для NC).
