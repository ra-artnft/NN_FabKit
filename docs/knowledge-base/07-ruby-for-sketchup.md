# 07. Ruby-среда внутри SketchUp

## Версии Ruby

| SketchUp | Ruby |
|---|---|
| 2014 | 2.0 |
| 2017 | 2.2 |
| 2019 | 2.5 |
| 2021 | 2.7 |
| 2023 | 2.7 |
| 2025 | 3.2 |
| 2026 | 3.2 |

Наш MVP ориентируем на SketchUp **2021 как минимум** (Ruby 2.7). Это отсекает совсем старые версии, но оставляет практически всех активных пользователей.

Следствия для кода:
- `case/in` (pattern matching) — только Ruby 3.0+, **не использовать**
- endless method `def x = ...` — 3.0+, **не использовать**
- keyword arguments и `**kwargs` — ок
- `&.` (safe navigation) — ок с 2.3+
- `Array#sum`, `Enumerable#tally` — ок с 2.4+
- Литералы Hash с `**` — ок

Нормальный target — Ruby 2.7 синтаксис. Если отладить и запустить в 3.2 — работает «как 2.7», просто быстрее.

## Что доступно из stdlib

Работает из коробки:
- `JSON` (parse/generate, pretty_generate)
- `CSV`
- `FileUtils`
- `Base64`, `Digest::SHA256`, `Digest::MD5`
- `StringIO`
- `Set` — но с SU 2018 перенесли в `Sketchup::Set` во избежание конфликта с Ruby stdlib
- `Date`, `Time`, `DateTime`
- `URI`, `CGI` — для URL-encoding (нужен для парсинга DC-опций)
- `Net::HTTP`, `Net::HTTPS` — для HTTP-запросов
- `OpenSSL` — работает, но с ограничениями
- `Zlib`
- `WEBrick` (до 3.0) / отдельный gem — для встроенного HTTP-сервера (TCP-server для нашего MCP-моста удобнее на `TCPServer` из `socket`)
- `socket` — **критично для MCP-моста**

Не работает или работает плохо:
- Bundler — вообще нет
- `gem install` внутри — замораживает SU, нестабильно, не делать
- Native extensions — только вручную пред-собранные `.so`/`.bundle`/`.dll`
- Rails, ActiveRecord, Sinatra и прочий web-стек — не для SU

Правило: если нужна функциональность вне stdlib — копируем pure-Ruby код в свою папку, заворачиваем под свой namespace, никаких `gem` команд.

## Пути и платформы

`Sketchup.platform` возвращает `:platform_win` или `:platform_osx`. (`platform_linux` теоретически тоже бывает для wine-сборок, но это исключение).

Путь к установке плагина:

```ruby
# Windows
# C:\Users\{user}\AppData\Roaming\SketchUp\SketchUp 20XX\SketchUp\Plugins\

# macOS
# ~/Library/Application Support/SketchUp 20XX/SketchUp/Plugins/

plugins_dir = Sketchup.find_support_file("Plugins")
```

Пользовательские данные (наши настройки, кэш, каталоги):

```ruby
def self.user_data_dir
  base = if Sketchup.platform == :platform_win
           ENV["APPDATA"]
         else
           File.join(Dir.home, "Library", "Application Support")
         end
  dir = File.join(base, "NN FabKit")
  FileUtils.mkdir_p(dir)
  dir
end
```

## Кодировка

Внутри SketchUp Ruby по умолчанию работает в UTF-8 на всех платформах с SU 2021+. Но:

- **Чтение файлов** — указывать явно: `File.read(path, mode: "r:UTF-8")`
- **Запись файлов** — `File.open(path, "w:UTF-8")` или `File.write(path, content, mode: "w:UTF-8")`
- **Пути с русскими именами** (как у заказчика `C:\Users\Заурядный\Desktop\Металл\`) — работают, но при **конкатенации** путей следить, чтобы все операнды были UTF-8. Windows API выдаёт имена в cp1251 в некоторых местах — принудительный `.force_encoding("UTF-8")` после получения от ENV, чтобы избежать глюков.

```ruby
# Защита от cp1251-сюрпризов
def self.safe_utf8(str)
  return nil if str.nil?
  s = str.dup
  s.force_encoding("UTF-8") unless s.encoding == Encoding::UTF_8
  s.valid_encoding? ? s : s.encode("UTF-8", invalid: :replace, undef: :replace)
end
```

## Глобальные переменные, которые **можно** использовать

Общее правило: свои `$global` — нельзя. Но есть готовые от SketchUp и extensions, которые мы будем использовать:

- `$dc_observers` — глобал, создаваемый встроенным extension Dynamic Components. См. 03-dynamic-components-deep-dive.
- `$SU_LOAD_PATH` — альтернатива `$LOAD_PATH`, используется SketchUp для поиска encrypted-файлов через `Sketchup.require`. Читать можно, писать — нежелательно.

Больше ничего не трогаем.

## Потоки и таймеры

API SketchUp — не thread-safe. Использовать Ruby `Thread.new { ... }` для работы с моделью — **гарантированный крэш без сообщения**. Обходной путь — `UI.start_timer`:

```ruby
# Фоновая задача, выполняемая кусочками
class NN::FabKit::BackgroundJob
  def initialize(items)
    @items = items
    @index = 0
    @timer = UI.start_timer(0.05, true) { tick }
  end

  def tick
    return finish if @index >= @items.length
    process_one(@items[@index])
    @index += 1
  end

  def process_one(item)
    # работа с одним item
  end

  def finish
    UI.stop_timer(@timer)
  end
end
```

Для параллельной работы с сетью (не с моделью) — обычный `Thread` допустим, но результат обработки надо возвращать в main thread через timer-ping-pong.

## Undo-разделение

Каждое `start_operation` / `commit_operation` создаёт один undo step. Но **в течение операции** SketchUp кэширует изменения. Если делать внутри operation несколько тысяч мелких правок — кэш распухает, UI замерзает после commit.

Правило: длинные операции (тысячи правок) разбивать на несколько операций по N правок каждая (N = 500–1000).

## Defensive coding — обязательный минимум

Внутри extension ошибки легко глотаются SketchUp'ом и превращаются в «просто ничего не произошло». Поэтому:

```ruby
# Обёртка для всех пользовательских действий
def self.safe(label = nil)
  yield
rescue StandardError => e
  puts "[NN::FabKit] #{label || 'operation'} failed:"
  puts "  #{e.class}: #{e.message}"
  puts e.backtrace.first(6).map { |l| "  #{l}" }.join("\n")
  UI.messagebox("Ошибка: #{e.message}\nПодробности в Ruby Console.", MB_OK)
end

# Использование
UI.menu("Extensions").add_item("NN: Вставить профиль") do
  NN::FabKit.safe("insert_profile") { NN::FabKit::UI.open_picker }
end
```

## Отладка

Развивайтесь с включённой Ruby Console (`Window → Ruby Console`). Все `puts` внутри extension в prod — под флагом `DEBUG`. В Console полезно:

```ruby
# Быстрая проверка API
Sketchup.active_model.entities.grep(Sketchup::ComponentInstance).first.inspect

# Поиск метода
Sketchup::ComponentInstance.instance_methods(false).sort

# Смотреть constant-tree нашего extension
NN::FabKit.constants.sort
NN::FabKit::Generator.constants.sort

# Перезагрузить файл в dev
load File.join(NN::FabKit::PLUGIN_ROOT, "generator.rb")
```

Для сложной отладки — `AS On-Demand Ruby / Extension Loader` (Alex Schreyer) или `Extension Sources` (ThomThom). Стандартный workflow — разработка из папки с исходниками, без каждый-раз-сборки `.rbz`.

## Encoding URL-ов и русские атрибуты

Ключи и значения в OCL-материалах и атрибутах компонентов могут содержать русские символы. Для API это норма (UTF-8 in, UTF-8 out), но при передаче через JavaScript в HtmlDialog — нужно правильное JSON-экранирование (`JSON.generate` делает это автоматически).

```ruby
# В Ruby
data = { name: "Труба 40x20x2 Ст3сп" }
dialog.execute_script("window.receiveData(#{JSON.generate(data)});")
```

```javascript
// В JS
window.receiveData = (data) => {
  console.log(data.name);           // "Труба 40x20x2 Ст3сп"
};
```

## Тестирование

Встроенного runner'а тестов нет. Варианты:
- Mini::Test или RSpec вне SketchUp, запущенные против pure-Ruby модулей (то, что не вызывает `Sketchup::*`).
- **TestUp2** — специализированный SketchUp-runner от Trimble для API-тестов.

Для MVP достаточно TestUp для критической логики (параметрический генератор, JSON-каталог, OCL-атрибуты), без интеграционных тестов через UI.

Ссылка: [github.com/SketchUp/testup-2](https://github.com/SketchUp/testup-2)

## RuboCop-SketchUp

Trimble поддерживает [rubocop-sketchup](https://github.com/SketchUp/rubocop-sketchup) — набор правил линтера именно для SketchUp-extensions. Extension Warehouse review team прогоняет им ваш код перед публикацией. Использовать в CI — освобождает от мелких ошибок.

```yaml
# .rubocop.yml
require: rubocop-sketchup

AllCops:
  TargetRubyVersion: 2.7
  SketchUp:
    SourcePath: src
    TargetSketchUpVersion: 2021
```
