# spec-02 — MCP-мост NN FabKit ⇄ Claude (TCP + Python MCP)

**Статус:** черновик 2026-04-24, в очереди на этап 1 (после spec-01).
**Привязка к ADR:** ADR-001 (нужен пересмотр — см. §1).
**Применимо к:** общая оболочка `NN::FabKit` (мост безразличен к ветке — обслуживает и металл, и будущую мебель).

---

## 1. Контекст и пересмотр ADR-001

ADR-001 называет `mhyrr/sketchup-mcp` базой TCP-моста под лицензией MIT. **Это неверно по факту 2026-04-24:**

- Repo: https://github.com/mhyrr/sketchup-mcp (227★, 42 forks, last update 2025-03-14).
- API ответ `gh api repos/mhyrr/sketchup-mcp` показывает `license: null`. В корне репо нет файла `LICENSE`.
- По умолчанию это **«All rights reserved»** — нельзя форкать, нельзя копировать код в свой плагин.

**Решение:** пишем собственный минимум, опираясь на публично описанную архитектуру (TCP + JSON-RPC + Python MCP — это идиома, не защищённый IP). Идеи из README mhyrr используем как референс паттернов; код не копируем.

**ADR-018 (новый, supersedes ADR-001):** TCP-мост + MCP — собственная реализация в `NN::FabKit::McpServer` (Ruby) + `nn_fabkit_mcp` (Python пакет). Минимальный набор tools, рост по необходимости.

## 2. Цель

Дать Claude (Code, Desktop, любой MCP-клиент) прямой доступ к работающему SketchUp:
- Читать состояние модели в реальном времени (без необходимости пользователю руками гонять Dump в JSON).
- Вызывать наши команды программно (`CreateRectTube`, `ExportIges`, `SkpDump`) с конкретными параметрами.
- Выполнять произвольный Ruby в SU для отладки и итеративной разработки.

**Главный выигрыш:** время от «изменил код плагина» до «увидел результат в SketchUp» падает с ~3 минут (rebuild → uninstall → close → install → close → open → клик через меню) до ~5 секунд (`eval_ruby` через MCP). При разработке это ускоряет на порядок.

## 3. Архитектура

```
┌────────────────────┐    JSON-RPC 2.0    ┌─────────────────────┐
│  Claude (MCP       │◄───── stdin ──────►│  nn_fabkit_mcp      │
│  client: Code,     │       stdout       │  (Python)           │
│  Desktop, …)       │                    │  FastMCP server     │
└────────────────────┘                    └──────────┬──────────┘
                                                     │
                                                     │ TCP 127.0.0.1:9876
                                                     │ JSON-RPC 2.0 (line-delimited)
                                                     │ one request → one connection
                                                     ▼
                                          ┌─────────────────────┐
                                          │  NN::FabKit::       │
                                          │  McpServer (Ruby)   │
                                          │  inside SketchUp    │
                                          └──────────┬──────────┘
                                                     │
                                                     ▼
                                          ┌─────────────────────┐
                                          │  Sketchup.active_   │
                                          │  model + наш plugin │
                                          └─────────────────────┘
```

**Ключевые ограничения SketchUp Ruby (учтены):**
- Нельзя `Thread.new` для UI работы → используем `UI.start_timer(0.1, true)` для polling `IO.select` на TCP socket.
- Все изменения модели — внутри `start_operation` / `commit_operation` (одна undo-запись на одну MCP-команду).
- TCPServer слушает только `127.0.0.1` — никаких внешних соединений, security baseline.

## 4. Scope MVP

**Входит:**
- `NN::FabKit::McpServer` — TCP server в плагине, line-delimited JSON-RPC 2.0.
- Меню `NN FabKit → MCP сервер → Запустить / Остановить` — явный контроль (не запускаем порт автоматически на каждом старте SU).
- Status indicator — пункт меню «MCP сервер: запущен на 127.0.0.1:9876 [✓]» / «не запущен [×]».
- `nn_fabkit_mcp` — Python пакет с MCP server, FastMCP framework.
- Минимальный набор tools (см. §5).
- Конфиг для Claude Code: `claude mcp add` инструкция.
- README с install/usage.

**Не входит:**
- Авторизация / TLS (только localhost loopback — этого достаточно для разработки).
- Перевод высокоуровневых SU API (component management, materials, layers) — пока через `eval_ruby`, потом нарастаем по необходимости.
- WebSocket / persistent connection — connection-per-request даёт простоту и устойчивость.
- Mac/Linux build (только Windows на старте, потом расширяем).

## 5. Tools MVP

Минимально-достаточный набор. Tools 1–3 — то с чего начнём.

| # | Tool | Inputs | Output | Назначение |
|---|---|---|---|---|
| 1 | `eval_ruby` | `code: str`, `timeout_s: int = 10` | `{ result: any, stdout: str, stderr: str }` | Universal escape hatch. Любой Ruby код выполняется в контексте плагина. Покрывает 90% use cases. |
| 2 | `get_scene_info` | — | `{ title, path, units, definitions_count, instances_count, materials_count, selection_count, bounds_mm }` | Быстрый снапшот состояния модели — для контекста перед действием. |
| 3 | `dump_model` | `path: str?` | `{ saved_to: str, size_kb: float }` | Обёртка над `NN::FabKit::SkpDump.run` — полный JSON-дамп для подробного анализа. |
| 4 | `create_rect_tube` | `typesize: str`, `length_mm: int`, `grade: str?` | `{ definition_name: str, instance_persistent_id: int }` | Высокоуровневая обёртка над `CreateRectTube` без UI диалогов. |
| 5 | `export_iges_wireframe` | `definition_name: str`, `output_path: str` | `{ path, entity_count, line_count, arc_count }` | Headless IGES экспорт. |
| 6 | `find_definitions` | `name_pattern: str?`, `with_attribute: str?` | `[{ name, instance_count, profile_type, typesize, ... }]` | Найти трубы / компоненты по имени или metadata. |

После MVP — добавляем по запросам: `transform_instance`, `set_material`, `delete_definition`, `list_materials`, и т.д.

## 6. JSON-RPC протокол

Line-delimited JSON-RPC 2.0 (одно сообщение = одна строка, terminated by `\n`).

**Запрос:**
```json
{"jsonrpc": "2.0", "id": 1, "method": "eval_ruby", "params": {"code": "Sketchup.active_model.title"}}
```

**Ответ (успех):**
```json
{"jsonrpc": "2.0", "id": 1, "result": {"value": "MyModel.skp", "stdout": "", "stderr": ""}}
```

**Ответ (ошибка):**
```json
{"jsonrpc": "2.0", "id": 1, "error": {"code": -32603, "message": "NameError: undefined local variable", "data": {"backtrace": ["...", "..."]}}}
```

Стандартные коды ошибок JSON-RPC: `-32700` parse error, `-32600` invalid request, `-32601` method not found, `-32602` invalid params, `-32603` internal error.

## 7. Безопасность

- Bind строго на `127.0.0.1`, не `0.0.0.0` (никаких внешних соединений).
- `eval_ruby` — мощно и опасно. В UI меню при первом запуске сервера показать messagebox: «MCP сервер запущен на 127.0.0.1:9876. Любой процесс на этом компьютере может выполнять произвольный Ruby в SketchUp. Не запускай если не доверяешь окружению.».
- Сервер запускается явно из меню, не автоматически. На рестарте SU сервер по умолчанию не активен.
- Persistent setting: `Sketchup.read_default("NN_FabKit", "mcp_autostart", false)` — пользователь может включить, на свой риск.

## 8. Структура реализации

### Ruby side (внутри плагина)

```
plugin-sketchup/src/nn_fabkit/
├── mcp/
│   ├── server.rb           # NN::FabKit::Mcp::Server — TCPServer + UI.start_timer + dispatch
│   ├── handlers.rb         # NN::FabKit::Mcp::Handlers — реализация tools (eval_ruby, get_scene_info, …)
│   └── jsonrpc.rb          # парсинг и сборка JSON-RPC 2.0 сообщений
├── commands/
│   └── mcp_control.rb      # UI: запустить/остановить/статус
└── ui/
    └── menu.rb             # + submenu "MCP сервер"
```

### Python side (отдельный пакет)

```
mcp-corpus/                 # ← переименовать в mcp-bridge или поменять смысл (см. §11)
├── pyproject.toml          # project name = nn-fabkit-mcp, deps: fastmcp, mcp
├── README.md               # install + claude mcp add инструкция
├── src/
│   └── nn_fabkit_mcp/
│       ├── __init__.py
│       ├── __main__.py     # entry point: python -m nn_fabkit_mcp
│       ├── server.py       # FastMCP server + tool definitions
│       ├── transport.py    # TCP client к Ruby (с retry/timeout)
│       └── tools/
│           ├── eval_ruby.py
│           ├── get_scene_info.py
│           └── …
└── tests/
    └── test_protocol.py    # smoke с mock TCP server
```

### Claude Code config

```bash
# Пользователь делает один раз:
claude mcp add nn-fabkit -- python -m nn_fabkit_mcp

# Или через JSON в settings.json:
{
  "mcpServers": {
    "nn-fabkit": {
      "command": "python",
      "args": ["-m", "nn_fabkit_mcp"]
    }
  }
}
```

## 9. План реализации (sprints)

**Sprint A** (мин. жизнеспособный):
- [ ] `Mcp::Server` Ruby + `UI.start_timer` polling.
- [ ] Один tool: `eval_ruby`.
- [ ] Меню Запустить/Остановить + статус.
- [ ] Python `nn_fabkit_mcp` с одним tool `eval_ruby` пробрасывающимся в TCP.
- [ ] Smoke-тест: `claude mcp add` + проверить, что Claude может вызвать `eval_ruby("1+1")` и получить `2`.

После Sprint A — у нас рабочий мост, и я могу заниматься следующими спринтами (UI redesign, IGES surface model, ВГП-труба) **с прямым тестированием через MCP**.

**Sprint B:**
- [ ] Tools 2-3: `get_scene_info`, `dump_model`.
- [ ] Stderr capture + backtrace в error response.
- [ ] Timeout handling.

**Sprint C:**
- [ ] Tools 4-6 (high-level: create_rect_tube, export_iges, find_definitions).
- [ ] PyPI публикация `nn-fabkit-mcp` для удобной установки.
- [ ] Документация usage с примерами.

## 10. Тест-план

Sprint A приёмка:
- T1: Запуск SU → Запустить MCP → в Ruby Console сообщение «Listening on 127.0.0.1:9876».
- T2: `python -m nn_fabkit_mcp` → подключается, `eval_ruby("Sketchup.version")` → возвращает `"25.0.575"`.
- T3: `eval_ruby("Sketchup.active_model.entities.add_line(ORIGIN, [1.m, 0, 0])")` → в SU появляется линия 1м, в undo-ленте «MCP: eval_ruby».
- T4: `eval_ruby("raise 'boom'")` → возвращается JSON-RPC error с backtrace, SU не падает.
- T5: Закрыть SU при работающем сервере → следующий запуск SU → MCP не активен.

## 11. Что делать с `mcp-corpus/`

В монорепо есть пустая папка `mcp-corpus/` — она задумывалась как MCP-сервер для корпуса примеров (ADR-015). Эта роль остаётся, но MCP-мост к самому SketchUp — другая роль.

**Решение:** разделить:
- `mcp-corpus/` остаётся под MCP-сервер для корпуса (читает `corpus/examples/` и отдаёт Claude).
- `mcp-bridge/` (новая папка) — MCP-мост к работающему SketchUp процессу.

Оба сервера могут быть зарегистрированы в Claude Code одновременно (`nn-fabkit-corpus` + `nn-fabkit-bridge`).

## 12. Открытые вопросы

1. **Encoding на Windows.** Ruby `client.gets` под Windows может прийти CRLF или CP1251 если что-то посередине. Тест через `force_encoding('UTF-8')` после `gets`.
2. **Длинные ответы.** `eval_ruby("Sketchup.active_model.definitions.map(&:name)")` на модели peregorodka вернёт 285 имён, плюс metadata — может быть >64 KB. TCP socket нормально это глотает (line-delimited, длина определяется по `\n`), но MCP framework Python должен принять. FastMCP должен справиться, проверить лимиты.
3. **Stdout capture для `eval_ruby`.** В чистом Ruby `puts` пишет в `$stdout`. Перехватить — `StringIO`-substitution: `$stdout = StringIO.new; eval(...); captured = $stdout.string; $stdout = STDOUT`. Поточно-безопасно? В нашем случае single-thread main, так что да.
4. **Файловые `requires` для Python пакета.** FastMCP framework — pin версию или follow tip? Решение в начале реализации.

## 13. Зависимости

- Этот spec **не блокирован** ничем — можно стартовать параллельно spec-01.
- Этот spec **разблокирует** все следующие: spec-03 (UI redesign), spec-04 (IGES surface model), spec-05 (мебельная ветка). После Sprint A любая разработка ускоряется.
- На верхнем уровне продукта — это инфраструктурный шаг, после которого Claude становится частью workflow заказчика-0 в SU (а не только разработческим инструментом).
