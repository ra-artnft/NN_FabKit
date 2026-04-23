# 01. SketchUp Ruby API — ядро

## Точка входа

```ruby
model = Sketchup.active_model       # текущая модель в активном окне SketchUp
entities = model.entities           # корневой Entities-контейнер
selection = model.selection         # текущий выбор
definitions = model.definitions     # библиотека ComponentDefinition
materials = model.materials         # палитра материалов
layers = model.layers               # слои (в 2020+ — теги)
styles = model.styles
pages = model.pages                 # scenes
rendering_options = model.rendering_options
shadow_info = model.shadow_info
options = model.options             # UnitsOptions, PrintOptions, и т.д.
```

`Sketchup::Model` — единственный объект, через который делается всё значимое.

## Иерархия Entity

```
Sketchup::Entity
├── Sketchup::Drawingelement
│   ├── Sketchup::Edge
│   ├── Sketchup::Face
│   ├── Sketchup::Group
│   ├── Sketchup::ComponentInstance
│   ├── Sketchup::Image
│   ├── Sketchup::ConstructionLine
│   ├── Sketchup::ConstructionPoint
│   ├── Sketchup::SectionPlane
│   └── Sketchup::Text
├── Sketchup::ComponentDefinition
├── Sketchup::Layer
├── Sketchup::LayerFolder           # SU 2021+
├── Sketchup::Material
├── Sketchup::Page
└── Sketchup::Style
```

Все `Drawingelement` живут внутри `Sketchup::Entities`-контейнера. Entities-контейнеры бывают трёх мест: у `Model`, у `ComponentDefinition`, у `Group` (через `group.entities`).

## Геометрия — минимум для продукта

### Edge и Face

```ruby
# Создание
edge = entities.add_line(pt1, pt2)                     # → Edge или nil
edges = entities.add_edges(pt1, pt2, pt3, pt4)         # → [Edge, ...]
face = entities.add_face(pt1, pt2, pt3, pt4)           # → Face
arc_edges = entities.add_arc(center, xaxis, normal, radius, start_angle, end_angle)
circle_edges = entities.add_circle(center, normal, radius, num_segments = 24)

# Экструзия (ключевой метод для труб/листов)
face.pushpull(distance, copy = false)                  # distance in inches!

# Follow Me (протяжка сечения вдоль пути — незаменимо для профилей)
face.followme([edge1, edge2, ...])
# или
face.followme(path_edge)
```

### Геометрические типы

```ruby
p  = Geom::Point3d.new(100.mm, 50.mm, 0)
v  = Geom::Vector3d.new(1, 0, 0)
t  = Geom::Transformation.new(p)                       # только сдвиг
t  = Geom::Transformation.rotation(center, axis, angle_rad)
t  = Geom::Transformation.scaling(2.0)                 # равномерный
t  = Geom::Transformation.scaling(sx, sy, sz)
bb = entities.bounds                                   # Geom::BoundingBox
```

Transformation комбинируется умножением: `t_total = t_translate * t_rotate * t_scale`.

### Единицы — правило №1

SketchUp внутри всё хранит в **дюймах**. Пользовательские mm/cm/m — только слой отображения.

```ruby
# НА ВХОДЕ — всегда конверсия
face.pushpull(1000.mm)              # ← правильно, 1.mm даёт Length в inch
face.pushpull(1000)                 # ← НЕПРАВИЛЬНО, это 1000 дюймов = 25.4 метра

# НА ВЫХОДЕ — читаем как Length, конвертируем явно
height = bounds.height               # Length (субкласс Float)
mm_value = height.to_mm              # → Float в миллиметрах
```

`Length` — это `Float` с методами `.mm`, `.cm`, `.m`, `.feet`, `.inch`, `.to_mm`, `.to_cm`, `.to_s` (локализованная строка), `.to_l` (парсинг строки в Length).

## Компоненты

### ComponentDefinition — описание

```ruby
# Создание пустой
defn = definitions.add("Труба 40x20x2")
defn.description = "Профильная труба ГОСТ 30245-2003"

# Создание/заполнение геометрии
entities = defn.entities
face = entities.add_face(...)
face.pushpull(1000.mm)

# Загрузка из .skp файла
defn = definitions.load("C:/path/to/component.skp")

# Получение по GUID или имени
defn = definitions["Имя"]
defn = definitions.find { |d| d.guid == some_guid }

# Работа с атрибутами
defn.set_attribute("nn_fabkit", "gost", "30245-2003")
defn.get_attribute("nn_fabkit", "gost")              # → "30245-2003"
defn.attribute_dictionaries                            # → AttributeDictionaries
defn.attribute_dictionary("dynamic_attributes")        # → AttributeDictionary

# Все существующие инстансы
defn.instances                                         # → [ComponentInstance, ...]
defn.count_used_instances                              # → Integer (O(1))
```

### ComponentInstance — размещение

```ruby
# Добавление инстанса в entities
transformation = Geom::Transformation.new(Geom::Point3d.new(0, 0, 0))
instance = entities.add_instance(defn, transformation)

# Атрибуты инстанса (DC кладёт значения сюда, метаданные definition-scope — на defn)
instance.set_attribute("nn_fabkit", "steel_grade", "Ст3сп")

# Перемещение, поворот, скейлинг
instance.transform!(translation_transform)
instance.transformation = new_transform                # полная замена

# Definition, из которой создан
instance.definition                                     # → ComponentDefinition
```

### Group — как компонент без переиспользования

`Group` внутри тоже имеет `ComponentDefinition` (начиная с SU 2015), доступный через `group.definition`. Но «приватную», не попадающую в `model.definitions` до `make_unique` / explicit save.

## AttributeDictionaries — метаданные

```ruby
# Запись
entity.set_attribute(dict_name, key, value)
# value может быть: String, Integer, Float, Boolean, Length, Time,
# Geom::Point3d, Geom::Vector3d, Sketchup::Color, Array (только с этими же типами)

# Чтение
entity.get_attribute(dict_name, key, default = nil)

# Итерация по всем словарям
entity.attribute_dictionaries.each do |dict|
  puts "Dictionary: #{dict.name}"
  dict.each_pair { |k, v| puts "  #{k} = #{v.inspect}" }
end

# Удаление
entity.delete_attribute(dict_name)                      # весь словарь
entity.delete_attribute(dict_name, key)                 # один ключ
```

Зарезервированные имена словарей: `dynamic_attributes` (DC), `SU_DefinitionSet`, `SU_InstanceSet`, `GSU_ContributorsInfo`, и дикционарии, начинающиеся с префикса `lairdubois_opencutlist_`. Наш словарь — `nn_fabkit`, трогать чужие не должны.

## Операции — undo и производительность

**Любое изменение модели оборачиваем в operation**. Это:
- одна запись в Undo-стеке (пользователь откатывает одним нажатием)
- отсрочка дорогих пересчётов (геометрия пересчитывается в commit, не на каждом edit)
- Extension Warehouse отклонит extension, не использующий operation wrappers

```ruby
model.start_operation("Создать трубу 40x20x2", true)    # disable_ui=true
begin
  defn = definitions.add("Труба 40x20x2")
  # ... наполнение геометрии ...
  entities.add_instance(defn, transformation)
  model.commit_operation
rescue => e
  model.abort_operation
  raise
end
```

Второй аргумент `true` отключает UI-обновления в течение операции — ускоряет в разы для массовых правок.

## Observers — реактивность

```ruby
class MyObserver < Sketchup::EntityObserver
  def onChangeEntity(entity)
    # вызывается при изменении атрибутов, свойств entity
  end
  def onEraseEntity(entity)
    # вызывается при удалении
  end
end

observer = MyObserver.new
instance.add_observer(observer)
```

Полезные observer-классы:
- `Sketchup::AppObserver` — открытие/закрытие модели
- `Sketchup::ModelObserver` — транзакции, pre/post save, pre/post commit
- `Sketchup::EntitiesObserver` — добавление/удаление entity в контейнере
- `Sketchup::EntityObserver` — изменение конкретной entity
- `Sketchup::SelectionObserver` — изменения выделения
- `Sketchup::MaterialsObserver` — изменения в палитре материалов
- `Sketchup::ToolsObserver` — смена инструмента
- `Sketchup::FrameChangeObserver` — для анимаций

## UI

```ruby
# Простые диалоги
UI.messagebox("Текст", MB_OK)
UI.inputbox(["Длина, мм:"], ["1000"], "Параметры трубы")
UI.savepanel("Сохранить", Dir.home, "default.ext")
UI.openpanel("Открыть", Dir.home, "*.skp|*.skp||")

# Богатый диалог с HTML/JS (наш основной UI в MVP)
dialog = UI::HtmlDialog.new(
  dialog_title: "Генератор профиля",
  preferences_key: "nn_fabkit.profile_gen",          # запоминает положение/размер
  scrollable: true,
  resizable: true,
  width: 420,
  height: 640,
  style: UI::HtmlDialog::STYLE_DIALOG
)
dialog.set_file(File.join(__dir__, "ui", "profile_gen.html"))

# Двусторонняя связь JS ↔ Ruby
dialog.add_action_callback("on_generate") do |ctx, payload_json|
  params = JSON.parse(payload_json)
  ProfileGenerator.generate(params)
end

# В HTML/JS:
#   sketchup.on_generate(JSON.stringify({width: 40, height: 20, wall: 2}));

dialog.show
```

## Меню и тулбары

```ruby
# Разовая регистрация при загрузке extension
unless file_loaded?(__FILE__)
  menu = UI.menu("Extensions").add_submenu("NN FabKit")
  menu.add_item("Вставить профиль") { NnFabKit::UI.open_profile_picker }
  menu.add_separator
  menu.add_item("Экспорт в IGES") { NnFabKit::Export.iges }

  toolbar = UI::Toolbar.new("NN FabKit")
  cmd = UI::Command.new("Профиль") { NnFabKit::UI.open_profile_picker }
  cmd.small_icon = File.join(__dir__, "icons", "profile_s.png")
  cmd.large_icon = File.join(__dir__, "icons", "profile_l.png")
  cmd.tooltip = "Вставить профиль из сортамента"
  cmd.status_bar_text = "Выбрать типоразмер и вставить в модель"
  toolbar.add_item(cmd)
  toolbar.show

  file_loaded(__FILE__)
end
```

## Export

Нативные форматы (Pro):

```ruby
model.export("C:/out/model.dwg")
model.export("C:/out/model.dxf")
model.export("C:/out/model.dae")                       # COLLADA
model.export("C:/out/model.stl")
model.export("C:/out/model.obj")
model.export("C:/out/model.fbx")
# с опциями
options = { triangulated_faces: true, edges: false, export_meshes: true }
model.export("C:/out/model.dae", options)
```

**IGES нативно не поддерживается** — см. 09-architecture-decisions и модуль NC-экспортёра.

## ImageRep — скриншоты для feedback-loop

`Sketchup::ImageRep` (SU 2018+) позволяет получить пиксельный буфер текущего вида модели без сохранения на диск, что полезно для обратной связи Claude. SU 2026 расширил возможности работы с ImageRep.

```ruby
view = model.active_view
image_rep = view.write_image(
  filename: nil,                  # не пишем на диск
  width: 1024,
  height: 768,
  antialias: true,
  compression: 0.9
)
# image_rep.save_file("C:/tmp/preview.png")            # опционально
# image_rep.data                                        # raw bytes
```

В нашей архитектуре это основной канал возврата картинки Claude для итераций диалога.

## Persistent IDs

С SU 2017 у entity есть `persistent_id` — стабильный через save/load. Используем вместо объектных ссылок, когда нужно запомнить сущность между сеансами.

```ruby
pid = face.persistent_id                                # → Integer
face_again = model.find_entity_by_persistent_id(pid)    # → Face или nil
```

## Что ещё пригодится (ссылки)

- [ruby.sketchup.com](https://ruby.sketchup.com) — полная документация
- [github.com/SketchUp/sketchup-ruby-api-tutorials](https://github.com/SketchUp/sketchup-ruby-api-tutorials) — официальные примеры
- [github.com/SketchUp/ruby-api-docs](https://github.com/SketchUp/ruby-api-docs) — исходники документации
