# 04. LayOut Ruby API — чертежи и ТЗ

## Где живёт API

LayOut Ruby API включён в SketchUp. Это значит, работать с `.layout` можно из любого SketchUp-extension **без установки LayOut вообще** — достаточно, чтобы у пользователя была SketchUp Pro. Namespace — `Layout::` (двоеточие имеет значение, не путать с `Sketchup::Layer`).

Ключевое следствие: наш плагин живёт **в SketchUp**, но генерирует `.layout` документы напрямую. LayOut нужен пользователю только для итогового просмотра/печати/экспорта.

## Координатная система

Отличается от SketchUp:
- 2D, единицы — **дюймы**
- Origin — левый верхний угол страницы
- X растёт вправо, Y растёт **вниз**
- Используется `Geom::Point2d` и `Geom::Bounds2d`

Связка с SketchUp-моделью — через `Layout::SketchUpModel`, который хранит ссылку на `.skp`-файл и в нём можно переключать сцены. Координаты внутри SketchUp-модели остаются 3D (в дюймах, как обычно).

## Точка входа

```ruby
# Создать пустой документ (одна страница, один слой)
doc = Layout::Document.new

# Создать из шаблона (.layout-файла с настроенной рамкой, штампом и т.д.)
doc = Layout::Document.new(File.join(__dir__, "templates", "gost_a3.layout"))

# Открыть существующий
doc = Layout::Document.open("C:/projects/project1/tz.layout")

# Сохранить
doc.save("C:/projects/project1/tz.layout")
doc.save(Layout::Document::VERSION_CURRENT)
```

## Структура документа

```
Layout::Document
├── Layout::Pages     (Pages collection — упорядоченные страницы)
│   └── Layout::Page  (отдельная страница)
│       └── nonshared_entities  (Entities для этой страницы)
├── Layout::Layers    (Layers collection)
│   └── Layout::Layer
│       ├── shared = true/false
│       └── locked = true/false
└── shared_entities   (Entities на всех shared-слоях документа)
```

**Правило:** на каждой странице должен быть хотя бы один разблокированный видимый слой. API этого требует (методы `locked=`, `set_layer_visibility`, `remove` откажутся нарушать правило).

**Shared layer** — слой, видимый на всех страницах (туда идут рамка, штамп, автотексты). **Non-shared layer** — слой конкретной страницы (туда идут виды модели, размеры).

## Основные сущности

`Layout::Entity` — родительский класс всего, что можно разместить на странице:

| Класс | Назначение |
|---|---|
| `Rectangle` | Прямоугольники — рамки, блоки |
| `Ellipse` | Эллипсы, круги |
| `Path` | Произвольные контуры, линии |
| `FormattedText` | Текст с форматированием |
| `Label` | Текстовая метка с лидером |
| `Table` | Таблицы (спецификация) |
| `SketchUpModel` | Вставленный .skp с выбранной сценой и масштабом |
| `Image` | Растровое изображение |
| `LinearDimension` | Линейный размер |
| `AngularDimension` | Угловой размер |
| `ReferenceEntity` | Ссылка на внешний файл (старое API; не использовать) |
| `Group` | Группировка |

Все они наследуют `attribute_dictionary`, `locked`, `bounds`, `style`, `move_to_layer`, `transform!` и прочие.

## Добавление entity

```ruby
doc = Layout::Document.new
layer = doc.layers.first
page = doc.pages.first

# Прямоугольник 1×1 дюйм в точке (1, 1)
rect = Layout::Rectangle.new(Geom::Bounds2d.new(1.0, 1.0, 2.0, 2.0))
doc.add_entity(rect, layer, page)

# Если слой shared — page опускается
shared_layer = doc.layers.find { |l| l.shared? }
title = Layout::FormattedText.new("Проект", Geom::Point2d.new(0.5, 0.5),
                                   Layout::FormattedText::ANCHOR_TYPE_TOP_LEFT)
doc.add_entity(title, shared_layer)
```

## Вставка SketchUp-модели

`Layout::SketchUpModel` — это то, что превращает чертёж из картинки в живую ссылку на `.skp`. При обновлении `.skp` (в SketchUp) модель в `.layout` обновляется.

```ruby
# Загружаем .skp (только файл, не активная модель SketchUp)
skp_path = "C:/projects/project1/model.skp"
bounds = Geom::Bounds2d.new(3.0, 3.0, 10.0, 8.0)   # размер окна на странице
su_model = Layout::SketchUpModel.new(skp_path, bounds)
doc.add_entity(su_model, layer, page)

# Переключить сцену
scenes = su_model.scenes                            # список сцен из .skp
su_model.current_scene = 2                          # индекс сцены

# Масштаб
su_model.scale = 0.1                                # 1:10
# или авто по bounds
su_model.preserve_scale_on_resize = false

# Стиль отображения (рендер-режим)
su_model.render_mode = Layout::SketchUpModel::RASTER_RENDER
# альтернативы: VECTOR_RENDER, HYBRID_RENDER
```

Особенность: из `Layout::SketchUpModel` **нельзя программно** манипулировать entity внутри .skp через LayOut API. Только считывать координаты для ConnectionPoints (см. ниже). Если нужно менять модель — это делать в SketchUp, `.layout` обновится.

## Размеры

```ruby
# Соединить LinearDimension с двумя точками на объекте
rect = Layout::Rectangle.new(Geom::Bounds2d.new(3, 3, 7, 5))
doc.add_entity(rect, layer, page)

start_cp = Layout::ConnectionPoint.new(rect, Geom::Point2d.new(3, 3))
end_cp   = Layout::ConnectionPoint.new(rect, Geom::Point2d.new(7, 3))

dim = Layout::LinearDimension.new(
  Geom::Point2d.new(3, 2.5),     # начало extension line
  Geom::Point2d.new(7, 2.5),     # конец extension line
  0.5                             # высота текста
)
dim.connect(start_cp, end_cp)
doc.add_entity(dim, layer, page)
```

Для связи с SketchUp-моделью — ConnectionPoint принимает `Geom::Point3d` в координатах модели:

```ruby
pt_3d = Geom::Point3d.new(0, 0, 0)
cp = Layout::ConnectionPoint.new(su_model, pt_3d)
```

Размеры автоматически обновляются при изменении модели (если `auto_scale = true`).

## Таблицы (спецификация)

`Layout::Table` — двумерная сетка ячеек.

```ruby
bounds = Geom::Bounds2d.new(8, 5, 13, 9)
table = Layout::Table.new(bounds, 5, 3)                # 5 строк, 3 столбца

# Заголовок
["№", "Наименование", "Кол-во"].each_with_index do |h, col|
  text = Layout::FormattedText.new(h, Geom::Point2d.new(0, 0),
                                    Layout::FormattedText::ANCHOR_TYPE_CENTER_CENTER)
  table[0, col].data = text
end

# Данные
parts.each_with_index do |part, row|
  table[row + 1, 0].data = Layout::FormattedText.new((row + 1).to_s,
                             Geom::Point2d.new(0, 0),
                             Layout::FormattedText::ANCHOR_TYPE_CENTER_CENTER)
  table[row + 1, 1].data = Layout::FormattedText.new(part[:name], ...)
  table[row + 1, 2].data = Layout::FormattedText.new(part[:qty].to_s, ...)
end

doc.add_entity(table, layer, page)
```

Форматирование таблицы (границы, шрифты, цвета ячеек) — через style properties, см. `Layout::Style`.

## AutoText — заполнение штампа

AutoText-поля — placeholder'ы, которые LayOut подставляет автоматически: имя файла, дата, пользовательские поля. Определяются на уровне документа, ссылаются из `FormattedText`.

```ruby
doc.auto_text_definitions.each do |autotext|
  puts "#{autotext.tag}: #{autotext.name} (#{autotext.type})"
end

# Добавить пользовательский AutoText
custom = doc.auto_text_definitions.add("Project Title", Layout::AutoTextDefinition::TYPE_CUSTOM_TEXT)
custom.custom_text = "Проект «Металлоконструкция X»"

# Использовать в тексте
text = Layout::FormattedText.new("<Project Title>",
                                  Geom::Point2d.new(1, 1),
                                  Layout::FormattedText::ANCHOR_TYPE_TOP_LEFT)
```

В штампе ГОСТ полезны:
- `<File>` — имя файла
- `<CurrentDate>` — текущая дата
- `<ModifiedDate>` — дата последней модификации
- `<PageName>` — имя страницы
- `<PageNumber>` / `<PageCount>`
- Пользовательские: `<Designer>`, `<Project>`, `<Revision>`, `<Material>`

## Export

```ruby
# PDF — все страницы
doc.export("C:/out/tz.pdf")

# PDF — диапазон + настройки качества
opts = {
  start_page: 1,
  end_page: 3,
  compress_images: true,
  compress_quality: 0.75
}
doc.export("C:/out/tz.pdf", opts)

# Отдельные страницы (LayOut 2024+)
opts = { page_range: "1,3-5", compress_images: true }
doc.export("C:/out/tz.pdf", opts)

# PNG/JPG — серия файлов (по странице)
doc.export("C:/out/tz.png")
doc.export("C:/out/tz.jpg", { dpi: 300 })

# DWG/DXF — экспорт в CAD
doc.export("C:/out/tz.dwg")
doc.export("C:/out/tz.dxf")
```

DWG/DXF-экспорт из LayOut — это **ключевая возможность для нашего NC-модуля**. Если нужно получить плоский чертёж листа для раскроечного станка, цепочка:
1. В SketchUp — модель листа
2. В LayOut — страница с видом листа в плане (сцена сверху)
3. `doc.export("part.dxf")` → DXF с реальной геометрией

## Паттерн генерации ТЗ — черновик

Не конечная архитектура, каркас для обсуждения:

```ruby
module NN::FabKit::TechTask
  TEMPLATE = File.join(__dir__, "templates", "gost_a3_frame.layout")

  def self.generate(model, parts_list, output_path)
    doc = Layout::Document.new(TEMPLATE)
    fill_titleblock(doc, model)
    add_overview_page(doc, model)
    add_parts_pages(doc, model, parts_list)
    add_specification_table(doc, parts_list)
    doc.save(output_path)
    doc.export(output_path.sub(/\.layout$/, ".pdf"))
    output_path
  end

  def self.fill_titleblock(doc, model)
    project_name = model.get_attribute("nn_fabkit", "project_name") || "Без имени"
    designer = model.get_attribute("nn_fabkit", "designer") || ENV["USERNAME"]

    set_autotext(doc, "Project", project_name)
    set_autotext(doc, "Designer", designer)
    set_autotext(doc, "Revision", model.get_attribute("nn_fabkit", "revision") || "1")
  end

  def self.set_autotext(doc, name, value)
    at = doc.auto_text_definitions.find { |a| a.name == name }
    at&.custom_text = value
  end

  # ... далее: add_overview_page, add_parts_pages, add_specification_table
end
```

## Ограничения, которые мы учтём

- Нельзя **выделять** entity в SketchUp-модели изнутри LayOut API — только координаты.
- Нельзя программно **добавлять сцены** в .skp через LayOut API. Сцены создаются в SketchUp.
- Нельзя **экспортировать в IGES** — только DWG/DXF/PDF/раст.
- `ConnectionPoint` на 3D-точке модели — требует, чтобы точка была на существующей геометрии (не в пустоте).
- Render-режим `VECTOR_RENDER` — красивее, медленнее, нестабильнее для сложных моделей. `HYBRID_RENDER` — компромисс.

## Источники

- [ruby.sketchup.com/Layout.html](https://ruby.sketchup.com/Layout.html) — root namespace
- [ruby.sketchup.com/file.LayOut.html](https://ruby.sketchup.com/file.LayOut.html) — обзор
- [ruby.sketchup.com/Layout/Document.html](https://ruby.sketchup.com/Layout/Document.html)
- Классы: `Layout::Page`, `Layout::Layer`, `Layout::Rectangle`, `Layout::Table`, `Layout::LinearDimension`, `Layout::FormattedText`, `Layout::SketchUpModel`, `Layout::AutoTextDefinition`, `Layout::ConnectionPoint`
- Сэмпл: `RubyExampleCreateLayOut` в [SketchUp/sketchup-ruby-api-tutorials](https://github.com/SketchUp/sketchup-ruby-api-tutorials)
