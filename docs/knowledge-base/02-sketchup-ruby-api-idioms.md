# 02. SketchUp Ruby API — идиомы и подводные камни

## Namespace-изоляция — абсолютное правило

Все extensions живут в одном глобальном Ruby-пространстве. Если два extension создают класс `Utils` в корне — второй затрёт первый, и работать будет плохо обоим. Экстеншн должен весь свой код завернуть в уникальный namespace-модуль.

```ruby
# root.rb (единственный unencrypted файл в RBZ)
module NN                          # NN = сокращение разработчика/компании
  module FabKit                  # название экстеншна
    # здесь только объявление SketchupExtension
    PLUGIN_ROOT = File.dirname(__FILE__)
    EXTENSION = SketchupExtension.new("NN FabKit", "nn_fabkit/main")
    EXTENSION.creator = "NN"
    EXTENSION.version = "0.1.0"
    EXTENSION.copyright = "2026"
    EXTENSION.description = "AI-assisted metal fabrication for SketchUp"
    Sketchup.register_extension(EXTENSION, true)
  end
end
```

Никогда не писать `class Utils`, `class ProfileGenerator` в глобальном скоупе. Всегда `NN::FabKit::ProfileGenerator`.

## `Sketchup.require` вместо `require`

Внутри вашего extension все модули подключайте через `Sketchup.require`, без указания расширения:

```ruby
# main.rb
Sketchup.require "nn_fabkit/generator"
Sketchup.require "nn_fabkit/catalog"
Sketchup.require "nn_fabkit/ui/dialog"
```

Причина: Extension Warehouse шифрует `.rb` → `.rbe`. Обычный Ruby `require "file.rb"` не найдёт зашифрованный. `Sketchup.require` прозрачно ищет `.rbe`, `.rb`, `.rbs`. Писать без расширения.

НЕ использовать `require_relative` внутри extension — ломается при шифровании.

## `start_operation` / `commit_operation` — всегда

Любое изменение модели (добавление геометрии, установка атрибутов, изменение материала, что угодно) должно быть внутри operation-обёртки. Это требование Extension Warehouse с 2026 года.

Шаблон:

```ruby
model = Sketchup.active_model
model.start_operation("Понятное пользователю название", true)  # disable_ui
begin
  # вся работа
  model.commit_operation
rescue StandardError => e
  model.abort_operation
  puts "[NN::FabKit] operation failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  raise
end
```

Второй аргумент `disable_ui = true` отключает перерисовку UI во время операции. Критично для производительности при массовых правках.

Третий-четвёртый аргументы — `transparent` и `next_transparent` — для nested operations. В 99% случаев не нужны.

## Единицы — всегда явно

```ruby
# ПРАВИЛЬНО
face.pushpull(1000.mm)
point = Geom::Point3d.new(100.mm, 50.mm, 0)
bbox_width_mm = bounds.width.to_mm

# НЕПРАВИЛЬНО
face.pushpull(1000)                  # это 1000 дюймов = 25.4 м
point = Geom::Point3d.new(100, 50, 0) # это 100 дюймов
bbox_width = bounds.width             # Length, выглядит как число, но с единицами
```

На входе всегда добавляй суффикс единиц. На выходе всегда явно конвертируй в ожидаемые единицы.

## Глобальные переменные — нельзя

Extension Warehouse отклоняет extensions с `$variables`. Исключение — работа с уже существующими глобалами SketchUp (`$dc_observers` из Dynamic Components, см. 03).

Использовать:
- `@instance_variables` внутри классов
- `CONSTANTS` в namespace-модуле
- `Module.module_function` для helpers

## Observers — не забывать удалять

Добавленный observer живёт пока его держит референс. Если extension перезагружается (dev-режим) или пользователь меняет модель — висячие observers продолжают срабатывать и иногда падают.

```ruby
module NN::FabKit
  class ProfileObserver < Sketchup::EntityObserver
    # ...
  end

  @@observers = {}

  def self.attach_observer(entity)
    obs = ProfileObserver.new
    entity.add_observer(obs)
    @@observers[entity.persistent_id] = obs
  end

  def self.detach_all
    @@observers.each do |pid, obs|
      entity = Sketchup.active_model.find_entity_by_persistent_id(pid)
      entity&.remove_observer(obs)
    end
    @@observers.clear
  end
end
```

При `AppObserver#onCloseModel` — отсоединять всех observers от модели.

## Dev-loop: `file_loaded?` и безопасная перезагрузка

Регистрация меню, тулбаров, observers выполняется ОДИН раз при загрузке extension. В production так и происходит. Но в dev, когда ты перегружаешь `.rb` через Alex Schreyer's "Extension Loader" или через `load "main.rb"` в Ruby Console — код выполнится повторно и меню задвоится.

Защита:

```ruby
unless file_loaded?(__FILE__)
  UI.menu("Extensions").add_item("NN FabKit → Открыть") { ... }
  file_loaded(__FILE__)
end
```

`file_loaded?` / `file_loaded` — встроенные helper-методы SketchUp для именно этого.

## Puts и debug

Засорять Ruby Console `puts`-ами в production нельзя — пользователь не поймёт, откуда идут сообщения, и жалуется на мусор. В extension переключатель:

```ruby
module NN::FabKit
  DEBUG = false   # или true в dev

  def self.log(msg)
    puts "[NN::FabKit] #{msg}" if DEBUG
  end
end

NN::FabKit.log("Вставлен профиль #{params[:typesize]}")
```

## Гемы — копировать код, не ставить

SketchUp содержит полноценный Ruby runtime, но установка гемов через `gem install` внутри SU — плохая идея: замораживает UI, у некоторых гемов сломанная компиляция native extensions, конфликт версий между разными extensions.

Правила:
- Нужна библиотека — вручную копируешь её `.rb` файлы в свою папку, заворачиваешь под свой namespace (если лицензия позволяет).
- Проверяешь, не входит ли нужное в Ruby stdlib SketchUp: `JSON`, `CSV`, `FileUtils`, `Base64`, `StringIO`, `Date`, `Time`, `Set` (есть, но как `Sketchup::Set` с 2018 из-за конфликта), `URI`, `Net::HTTP` — доступны.
- OpenSSL / native dependencies — не пытаться.

## `$LOAD_PATH` — не трогать

Изменение `$LOAD_PATH` в extension может сломать загрузку других extensions. Если нужно требовать файл из своей папки — используйте полный путь:

```ruby
Sketchup.require File.join(__dir__, "generator", "profile")
```

## Потоки и UI

SketchUp Ruby API **не thread-safe**. Любой вызов API из не-main потока — потенциальный крэш SketchUp (без сообщения). Все UI-операции, все обращения к `Sketchup.active_model` — только из main thread.

Для фоновых задач: `UI.start_timer` + продвижение работы маленькими порциями, чекая время.

```ruby
class NN::FabKit::Worker
  def initialize(tasks)
    @tasks = tasks
    @timer_id = UI.start_timer(0.05, true) { tick }
  end

  def tick
    return stop if @tasks.empty?
    task = @tasks.shift
    task.call
  end

  def stop
    UI.stop_timer(@timer_id)
  end
end
```

## Кодировки и русские строки

SketchUp 2021+ работает в UTF-8 по умолчанию на всех платформах. Русские строки в константах, именах компонентов, атрибутах — корректно. При чтении файлов — явно указывать encoding:

```ruby
File.open(path, "r:UTF-8") { |f| f.read }
File.open(path, "w:UTF-8") { |f| f.write(text) }
```

Пути с русскими папками (как у заказчика: `C:\Users\Заурядный\Desktop\Металл\`) — работают, но при конкатенации следить, чтобы все куски были UTF-8.

## Работа с файлами

```ruby
# Путь плагина (работает и в зашифрованном виде)
plugin_root = File.dirname(__FILE__)

# Пользовательские настройки — в AppData/Application Support
if Sketchup.platform == :platform_win
  user_data = File.join(ENV["APPDATA"], "NN FabKit")
else
  user_data = File.join(Dir.home, "Library", "Application Support", "NN FabKit")
end
FileUtils.mkdir_p(user_data)

# Каталог сортамента — рядом с плагином (read-only)
catalog_dir = File.join(plugin_root, "catalog")
```

## Поиск компонента по имени/атрибуту — не по индексу

Позиции в `model.entities` и `model.definitions` нестабильны между сохранениями. Искать нужно по `persistent_id`, `guid`, имени или атрибуту.

```ruby
# Плохо
tube_def = model.definitions[3]              # может быть чем угодно

# Хорошо
tube_def = model.definitions.find do |d|
  d.get_attribute("nn_fabkit", "profile_type") == "rect_tube" &&
  d.get_attribute("nn_fabkit", "typesize")     == "40x20x2"
end
```

## Bounding box и ориентация

Ось `Z` в SketchUp — «вверх». Но внутри компонента это не обязательно. Компонент имеет свою локальную систему координат (видна в Component Axes), и именно относительно неё считаются длина/ширина/толщина для OCL.

Правило для наших компонентов: **длина профиля = ось X** (красная), **поперечные габариты = Y (зелёная) и Z (синяя)**. Это совпадает с нормальной практикой OCL для dimensional material.

Для листа: **длина = X, ширина = Y, толщина = Z**.

## Undo-операции при записи атрибутов

Установка атрибутов — тоже изменение модели, тоже требует `start_operation`. Это не очевидно.

```ruby
# Плохо — не записывается в undo stack, пользователь не сможет откатить
instance.set_attribute("nn_fabkit", "typesize", "40x20x2")

# Хорошо
model.start_operation("Задать типоразмер", true)
instance.set_attribute("nn_fabkit", "typesize", "40x20x2")
model.commit_operation
```

## Очистка — `model.definitions.purge_unused`

Файлы заказчика часто содержат мусор (неиспользуемые definitions, материалы, слои, стили). Один вызов:

```ruby
model.definitions.purge_unused
model.materials.purge_unused
model.layers.purge_unused
model.styles.purge_unused
```

Наш плагин делает это опционально (с подтверждением пользователя), чтобы не удалять то, что пользователь считает «почти нужным».
