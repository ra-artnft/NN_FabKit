# NN FabKit — плагин SketchUp

Плагин для SketchUp Pro 2021+. Часть экосистемы NN FabKit (см. корневой [README.md](../README.md) и [ADR-013](../docs/knowledge-base/09-architecture-decisions.md)).

## Требования

- SketchUp Pro 2021, 2022, 2023, 2024 на Windows или macOS.
- Для сборки `.rbz` — Ruby 2.7+ и `rake` (в переменной окружения PATH).

## Установка

**Способ 1: через Extension Manager (рекомендуется).**

1. Собрать `.rbz`:
   ```powershell
   cd plugin-sketchup
   rake build
   ```
2. В SketchUp: `Extensions → Extension Manager → Install Extension`.
3. Выбрать собранный `plugin-sketchup/build/nn_fabkit-<version>.rbz`.
4. Перезапустить SketchUp.

**Способ 2: ручное копирование** (для разработки).

Скопировать содержимое `src/` в Plugins-папку SketchUp:
- Windows: `%APPDATA%\SketchUp\SketchUp <год>\SketchUp\Plugins\`
- macOS: `~/Library/Application Support/SketchUp <год>/SketchUp/Plugins/`

Либо запустить (копирует в самую свежую найденную установку с подтверждением):
```
rake install
```

## Текущая функциональность

- `Extensions → NN FabKit → Dump в JSON…` — выгружает текущую модель в JSON-файл рядом с `.skp` (или на Рабочий стол, если модель не сохранена). Используется для пополнения корпуса примеров (см. [ADR-015](../docs/knowledge-base/09-architecture-decisions.md)). Реализация — `src/nn_fabkit/skp_dump.rb`, синхронизированная копия канонического `docs/knowledge-base/tools/skp_dump.rb`.
- `Extensions → NN FabKit → О плагине…` — messagebox с версией плагина и SketchUp.

## Следующие шаги

- Параметрический генератор профилей ([ADR-002](../docs/knowledge-base/09-architecture-decisions.md)) — namespace `NN::MetalFab`.
- Attribute dictionary `nn_metalfab` для металл-компонентов ([ADR-005](../docs/knowledge-base/09-architecture-decisions.md)).
- Форк `mhyrr/sketchup-mcp` как база TCP-моста ([ADR-001](../docs/knowledge-base/09-architecture-decisions.md)).

## Сборка

```powershell
rake build       # → build/nn_fabkit-<version>.rbz
rake clean       # удалить build/
rake install     # скопировать src/ в Plugins SketchUp (с подтверждением)
rake             # = rake build
```

## Структура

```
plugin-sketchup/
├── Rakefile                        # обычный Ruby: require, FileUtils — можно
├── README.md
├── .gitignore                      # build/, *.rbz
└── src/                            # ← содержимое идёт в .rbz
    ├── nn_fabkit.rb                # loader: register_extension, проверка версии
    └── nn_fabkit/
        ├── main.rb                 # точка входа после активации: регистрация меню
        ├── version.rb              # NN::FabKit::VERSION
        ├── skp_dump.rb             # NN::FabKit::SkpDump — выгрузка модели в JSON
        └── ui/
            └── menu.rb             # NN::FabKit::UI::Menu.register!
```

## Правила кода

- Namespace всего Ruby-кода — `NN::FabKit`. Глобальный скоуп не трогаем.
- В `src/` только `Sketchup.require`, без `require` / `require_relative` (они не находят зашифрованные `.rbe` и ломают Extension Warehouse-публикацию). См. [idioms](../docs/knowledge-base/02-sketchup-ruby-api-idioms.md).
- Файлы — UTF-8 без BOM, перевод строк LF, магический комментарий `# encoding: UTF-8` в каждом `.rb` внутри `src/`.
- Отступ — 2 пробела, двойные кавычки, `snake_case` для методов и файлов, `PascalCase` для модулей/классов.
- Имя attribute dictionary для будущих метаданных — `nn_fabkit` ([ADR-005](../docs/knowledge-base/09-architecture-decisions.md)).
