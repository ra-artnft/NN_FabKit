# 03. Dynamic Components — подробный разбор

## Что это

Dynamic Components (DC) — встроенный в SketchUp Pro механизм параметризации компонентов. Пользователь задаёт атрибуты с формулами в окне **Component Attributes** (Window → Component Attributes), а конечный пользователь меняет значения через **Component Options** (Window → Component Options, или правый клик → Dynamic Components → Component Options). Формулы автоматически пересчитываются, и геометрия перестраивается.

Важно, что DC — это не отдельный API, а extension, распространяемый вместе с SketchUp. Его реализация живёт в глобальных объектах (`$dc_observers`), и взаимодействовать с ним можно только через недокументированные хуки.

## Архитектура хранения

DC-атрибуты — это обычные `AttributeDictionary` с именем `dynamic_attributes`. Они лежат в двух местах:

- **На ComponentDefinition** — определения параметров, их мета-свойства, формулы.
- **На ComponentInstance** — конкретные значения для этого экземпляра.

Третье место — служебный словарь с **пустым именем `""`** на инстансе:

```json
{
  "": {
    "_last_lenx": 0.9842519685039371,
    "_last_leny": 0.984251968503937,
    "_last_lenz": 39.37007874015748
  }
}
```

Это кэш последних применённых значений `LenX/LenY/LenZ` в дюймах (внутренние единицы). DC использует его, чтобы детектить, нужно ли перерисовывать. При ручных манипуляциях (например, изменение геометрии внутри definition) кэш рассинхронизируется — это источник типичных багов «DC не перерисовывается». Наш плагин должен уметь валидировать и чинить.

## Имена атрибутов — два подхода

### Встроенные (reserved)

Зарезервированы SketchUp'ом, интерпретируются движком DC автоматически. Имена всегда в нижнем регистре:

| Атрибут | Смысл |
|---|---|
| `x`, `y`, `z` | Позиция компонента в родительских координатах |
| `lenx`, `leny`, `lenz` | Размеры по локальным осям (аналог Scale tool) |
| `rotx`, `roty`, `rotz` | Поворот вокруг локальных осей, в градусах |
| `copies` | Количество копий, создаваемых движком |
| `copy` | Индекс текущей копии (для формул) |
| `hidden` | 1 = скрыт, 0 = видим |
| `name` | Имя, отображаемое в Component Options |
| `summary` | Краткое описание для Component Options |
| `description` | Длинное описание |
| `itemcode` | Код товара для спецификации |
| `material` | Имя материала |
| `onclick` | Формула, выполняемая по клику на компонент Interact-tool-ом |
| `dialog_scale_tool` | Видимость Scale-рукояток |

### Пользовательские

Любое имя, которое разработчик DC добавил через Attribute Editor. В ваших файлах у `Профильная труба` это `square`, `rectangle`, `scaletool`, `sizerectangley`. Строго говоря, `square` и `rectangle` — это служебные пользовательские атрибуты, через которые реализуется выбор типоразмера.

## Мета-атрибуты (префикс `_`)

Каждый пользовательский или встроенный атрибут имеет набор мета-полей с префиксом `_{name}_`:

| Мета-поле | Назначение |
|---|---|
| `_{name}_label` | Внутренний «кодовый» label (обычно = `{Name}` с капитализацией) |
| `_{name}_formlabel` | **Человеческая подпись** в Component Options (например, «Глубина», «Ширина») |
| `_{name}_formula` | Формула DC, пересчитывающая значение |
| `_{name}_access` | Тип контрола в UI: `NONE` (скрытый), `TEXTBOX` (свободный ввод), `LIST` (dropdown), `BUTTON` (action) |
| `_{name}_options` | Для `LIST` — список пар ключ/значение в URL-encoded формате |
| `_{name}_units` | Единицы: `DEFAULT`, `INCHES`, `FEET`, `MILLIMETERS`, `CENTIMETERS`, `METERS`, `DEGREES`, `FLOAT`, `INTEGER`, `STRING`, `BOOLEAN` |
| `_{name}_formulaunits` | Единицы вычисляемого значения формулы (может отличаться от `_units`) |
| `_{name}_error` | Последнее сообщение об ошибке в формуле |

Префикс `_inst_{name}_...` — мета-атрибут копируется на каждый инстанс при создании (для атрибутов, которые должны различаться у разных инстансов, например `rotx`, `roty`, `rotz`). В definition такие атрибуты хранятся как `_inst_{name}_*`, в instance — как `_{name}_*`.

## Синтаксис формул

Формулы DC — это упрощённый DSL, похожий на Excel, но не идентичный.

### Арифметика

```
=lenx * 2
=width + margin
=(h - 2 * t) / 2
```

### Условия

```
=IF(width > 100, "large", "small")
=IF(AND(a > 0, b > 0), sqrt(a*a + b*b), 0)
=CHOOSE(type, "тонкий", "средний", "толстый")     # type = 1..3
```

### Ссылки на атрибуты

Внутри компонента — по имени: `lenx`. На родителя — `parent!name`. На дочерний компонент по имени: `child!lenx` (child — имя инстанса внутри). На материал — `material`.

Ссылка с итерацией копий: `copy * (spacing + lenx)` — используется в предустановленном паттерне «копии с шагом».

### Встроенные функции

Математика: `ABS`, `INT`, `ROUND`, `FLOOR`, `CEILING`, `SQRT`, `POWER`, `LN`, `LOG10`, `EXP`, `PI()`, `SIN`, `COS`, `TAN`, `ASIN`, `ACOS`, `ATAN`, `ATAN2`, `DEGREES`, `RADIANS`, `MIN`, `MAX`, `SUM`, `PRODUCT`, `AVERAGE`, `MEDIAN`, `MOD`, `RANDBETWEEN`.

Логика/выбор: `IF`, `AND`, `OR`, `NOT`, `CHOOSE`, `LIST` (проверка принадлежности множеству), `RANGE` (проверка диапазона), `LIMIT` (clamp).

Строки: `CONCATENATE`, `LEN`, `LEFT`, `RIGHT`, `MID`, `UPPER`, `LOWER`, `FIND`.

Агрегации по иерархии: `CURRENT("attr")`, `SUM` с ссылкой по иерархии.

### LIST options — URL-encoded

`_{name}_options` хранится в формате `&displayValue1=internalValue1&displayValue2=internalValue2&...` с URL-encoding для русских символов. Пример из `Профильная труба`:

```
&10=0.39370078740157477&15=0.5905511811023622&20=0.7874015748031495&25=0.984251968503937&
```

Здесь displayValue — это то, что видит пользователь в dropdown (в мм), internalValue — значение, которое записывается в атрибут (в дюймах; 25 мм = 0.9842 дюйма). Это причина, почему формулы содержат `/10` — пользовательский DC хранил значения в сантиметрах, отсюда конверсия.

Русские символы кодируются через `%uXXXX` (legacy JavaScript escape) или `%XX` (URL-encoded UTF-8):

```
&180%20%u0433%u0440%u0430%u0434=180%20%u0433%u0440%u0430%u0434.&
```

Это `180 град=180 град.` URL-encoded.

## Единицы — запутанно

DC внутри хранит значения для длин всегда в **дюймах**, вне зависимости от units документа. `_lengthunits: "CENTIMETERS"` на definition — это предпочтение отображения, не хранения. Формула `square/10` в `Профильная труба` работает потому, что значение `square = "25"` (строка) конвертируется движком в Length через `_square_units: STRING` → interpretation → 25 * unit. Делить на 10 → сантиметры → автоконверсия в дюймы.

Вывод: при **программном чтении** значений `lenx/leny/lenz` на инстансе всегда считать их дюймами и явно конвертировать:

```ruby
lenx_mm = instance.get_attribute("dynamic_attributes", "lenx").to_f * 25.4
```

А при **программной записи** значений — также записывать в дюймах:

```ruby
new_length_mm = 1500
instance.set_attribute("dynamic_attributes", "lenz", new_length_mm / 25.4)
```

## Принудительная перерисовка

Это самая важная часть взаимодействия с DC из наших extensions. После записи атрибута движок DC **не перерисовывает** компонент автоматически — нужен явный триггер.

Недокументированное, но стабильно работающее со всех SU 2015+ (до 2026 включительно):

```ruby
$dc_observers.get_latest_class.redraw_with_undo(instance)
```

`$dc_observers` — глобальная переменная, которую DC-extension создаёт при загрузке. `get_latest_class` возвращает актуальный класс DC-engine (в разных SU именовался по-разному, этот хелпер абстрагирует). `redraw_with_undo` перерисовывает инстанс, записывая шаг в undo-стек.

Альтернатива — `redraw` без undo. Пакетная перерисовка для коллекции:

```ruby
dc_class = $dc_observers.get_latest_class
model.start_operation("Пересчитать DC", true)
instances.each { |i| dc_class.redraw_with_undo(i) }
model.commit_operation
```

Безопасная обёртка (на случай, если DC-extension отключен):

```ruby
def self.redraw_dc(instance)
  return unless defined?($dc_observers) && $dc_observers
  klass = $dc_observers.get_latest_class
  klass.redraw_with_undo(instance) if klass.respond_to?(:redraw_with_undo)
end
```

## Ограничения, которые нам мешают

### 1. Формулы не умеют перерисовать геометрию

DC применяет к inside-геометрии компонента **Scale-transformation**. Это означает: исходный box 10×10×10 становится 25×25×1000 через матрицу `[2.5, 2.5, 100]`, но сами edges и faces — те же, что были. Угол прямой (без радиуса), стенки нет.

Добавить радиус гиба через формулу **невозможно** — формула не меняет топологию, только пропорции.

### 2. Списки (`_options`) ограничены одним уровнем

Нельзя задать «если square = 25, то список толщин = [1.5, 2, 2.5]; если square = 40, то [2, 2.5, 3]». Только плоский список.

### 3. Редактор DC — Pro-only

Бесплатная SketchUp Make/Free не позволяет **редактировать** DC, только использовать готовые. Но наш плагин пишет атрибуты через Ruby API — это работает даже в бесплатной версии.

### 4. Нет event-API для изменения значений

DC не шлёт Ruby-событие «пользователь поменял lenz». Надо вешать `EntityObserver#onChangeEntity` на инстанс и самим проверять, что изменилось.

## Наша интеграция с DC

Стратегия, кратко: **DC сохраняем как UX для пользователя, но геометрию рисуем сами**.

1. **Сохраняем внешний вид DC**. Структура `dynamic_attributes`, имена `lenx/leny/lenz`, `square`, `rectangle`, контекстное меню — всё остаётся знакомым. Заказчику не нужно переучиваться.

2. **Расширяем список опций**. Полный сортамент ГОСТ вместо обрезанного. Правильное соответствие типоразмера → толщина стенки → радиус загиба (см. 06-sortament-ontology).

3. **Перехватываем изменения**. `EntityObserver#onChangeEntity` на инстансе + таймер дебаунса (чтобы не перерисовывать 60 раз в секунду во время drag).

4. **Перерисовываем геометрию сами**. Очищаем `definition.entities`, генерим правильное сечение с радиусами, экструдируем `followme`. Это физически настоящая труба, а не box-pretender.

5. **Дополняем свои метаданные**. Словарь `nn_fabkit` на definition И на instance:

   ```
   nn_fabkit:
     profile_type: "rect_tube"
     gost: "30245-2003"
     typesize: "40x20x2"
     width_mm: 40
     height_mm: 20
     wall_mm: 2
     outer_radius_mm: 3
     steel_grade: "Ст3сп"
     mass_per_m_kg: 1.74
     surface_m2: 0.12
     nc_ready: true
   ```

6. **Согласованность с OCL**. На создаваемые компоненты ставим материал с правильным именем (см. 05-opencutlist-integration) — тогда OCL видит группировку.

7. **Обработка кэша**. При открытии проекта проверяем `_last_lenx` vs текущие значения. Если рассогласование — перестраиваем тихо.

## Пример программного изменения DC-атрибута и пересборки

```ruby
module NN::FabKit
  module DC
    DICT = "dynamic_attributes".freeze

    def self.set_length(instance, length_mm)
      model = instance.model
      model.start_operation("Задать длину", true)
      begin
        instance.set_attribute(DICT, "lenz", length_mm / 25.4)   # inch!
        instance.set_attribute("", "_last_lenz", length_mm / 25.4) # обновляем кэш
        redraw(instance)
        # после redraw — наша пересборка геометрии по обновлённому typesize
        NN::FabKit::Generator.rebuild(instance)
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        raise
      end
    end

    def self.redraw(instance)
      return unless defined?($dc_observers) && $dc_observers
      klass = $dc_observers.get_latest_class
      klass.redraw_with_undo(instance) if klass.respond_to?(:redraw_with_undo)
    end
  end
end
```

## Парсинг URL-encoded списков

Для чтения/записи `_square_options` и подобных — нужен decoder:

```ruby
require "cgi"

def self.parse_dc_options(encoded)
  # Формат: "&displayKey1=value1&displayKey2=value2&..."
  result = []
  encoded.to_s.split("&").each do |pair|
    next if pair.empty?
    key, val = pair.split("=", 2)
    # DC использует %uXXXX для unicode — костыль-декодер
    key = key.gsub(/%u([0-9A-F]{4})/i) { [$1.to_i(16)].pack("U") }
    key = CGI.unescape(key)
    result << [key, val]
  end
  result
end

def self.encode_dc_options(pairs)
  # pairs = [["10", "0.3937..."], ["20", "0.7874..."], ...]
  "&" + pairs.map { |k, v| "#{CGI.escape(k.to_s)}=#{v}" }.join("&") + "&"
end
```

## Список встроенных атрибутов — ссылка

Полная таблица с описаниями:
[help.sketchup.com/en/sketchup/dynamic-component-predefined-attributes](https://help.sketchup.com/en/sketchup/dynamic-component-predefined-attributes)
