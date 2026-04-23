# NN FabKit

Экосистема для проектирования металлоконструкций и мебели поверх SketchUp Pro 2021+. Цель — параметрические компоненты (трубы, листы, уголки), автоматическое оформление ТЗ в LayOut, экспорт в NC-форматы.

## Состояние

В репозитории сейчас только **скелет плагина** — минимальный жизнеспособный SketchUp-экстеншн с меню «Extensions → NN FabKit → О плагине…». Вся продуктовая функциональность (параметрические генераторы, ТЗ в LayOut, NC-экспорт, корпус примеров) — в отдельных следующих ТЗ.

## Компоненты (план)

Монорепо рассчитан на три компонента:

| Папка | Роль | Стек | Статус |
|---|---|---|---|
| `plugin-sketchup/` | Плагин SketchUp: чтение/запись модели, DC-перерисовка, ImageRep, TCP-сервер | Ruby 2.7 (стандартная среда SketchUp) | скелет |
| `app-desktop/` | Standalone-приложение: UI диалога с Claude, NC-конвертёр, генератор ТЗ в LayOut | — (стек выбирается) | заглушка |
| `mcp-corpus/` | MCP-сервер для корпуса примеров | Python, stdio | заглушка |
| `corpus/` | Корпус реальных/учебных заказов | данные | заглушка |

Решение о гибридном форм-факторе «плагин + standalone» — [ADR-013](docs/knowledge-base/09-architecture-decisions.md). Протокол корпуса примеров — [ADR-015](docs/knowledge-base/09-architecture-decisions.md).

## Структура

```
NN_FabKit/
├── plugin-sketchup/      # Ruby-плагин SketchUp (скелет)
├── app-desktop/          # заглушка — будущий standalone
├── mcp-corpus/           # заглушка — будущий MCP-сервер
├── corpus/               # заглушка — будущий корпус примеров
├── docs/
│   └── knowledge-base/   # read-only: API-справочники, ADR, онтология сортамента
├── README.md
├── CHANGELOG.md
└── .gitignore
```

База знаний в `docs/knowledge-base/` — обязательный контекст для работы над любым компонентом. Не редактируется из задач разработки плагина/приложения; обновляется отдельно.

## Сборка плагина

```powershell
cd plugin-sketchup
rake build
# результат: plugin-sketchup/build/nn_fabkit-0.1.0.rbz
```

Установка в SketchUp — через Extensions → Extension Manager → Install Extension, выбрать полученный `.rbz`.

## Дальше

Закрыто:
- Команда «Dump в JSON» — `Extensions → NN FabKit → Dump в JSON…` в плагине v0.2.0 оборачивает `docs/knowledge-base/tools/skp_dump.rb`.

Следующее:
- Форк `mhyrr/sketchup-mcp` как база TCP-моста ([ADR-001](docs/knowledge-base/09-architecture-decisions.md)).
- Параметрический генератор профилей в namespace `NN::MetalFab` ([ADR-002](docs/knowledge-base/09-architecture-decisions.md)).
- Attribute dictionary `nn_metalfab` для металл-компонентов ([ADR-005](docs/knowledge-base/09-architecture-decisions.md)).
