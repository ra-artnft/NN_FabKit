# nn-fabkit-mcp

MCP bridge from Claude (Code, Desktop, любой MCP-клиент) к работающему SketchUp с установленным плагином [NN FabKit](https://github.com/ra-artnft/NN_FabKit) v0.5.0+.

## Архитектура

```
Claude  ──stdin/stdout──► nn-fabkit-mcp (Python, FastMCP)
                                │
                                │ TCP 127.0.0.1:9876, JSON-RPC 2.0
                                ▼
                          NN::FabKit::Mcp::Server (Ruby, в SketchUp)
                                │
                                ▼
                          Sketchup.active_model + наш плагин
```

Полный план — `docs/specs/spec-02-mcp-bridge.md` в корне репо.

## Tools (MVP)

- **`eval_ruby(code)`** — выполнить произвольный Ruby в SketchUp. Покрывает 90% сценариев. Возвращает `{value, stdout}`.
- **`get_scene_info()`** — быстрый снапшот модели (title, counts, bounds, selection brief).
- **`dump_model(path?)`** — полный JSON-дамп модели через `NN::FabKit::SkpDump`.

## Установка

### 1. Плагин в SketchUp

Скачать `nn_fabkit-0.5.0.rbz` (или новее) с [Releases](https://github.com/ra-artnft/NN_FabKit/releases), поставить через `Extensions → Extension Manager → Install Extension`. Перезапустить SketchUp.

### 2. Python пакет

Из корня этого подкаталога:

```bash
pip install -e .
```

Или (рекомендуется) через [uv](https://github.com/astral-sh/uv):

```bash
uv pip install -e .
```

### 3. Регистрация в Claude Code

```bash
claude mcp add nn-fabkit -- python -m nn_fabkit_mcp
```

Проверить:

```bash
claude mcp list
# nn-fabkit  python -m nn_fabkit_mcp
```

После — перезапустить Claude Code, чтобы он подхватил MCP server.

### 4. В SketchUp — запустить TCP-сервер

`Extensions → NN FabKit → MCP сервер → Запустить…`

Появится предупреждение про мощь `eval_ruby` (любой процесс на машине может исполнять Ruby в SU, пока сервер активен). Подтвердить.

## Проверка

В Claude Code:

```
> use the eval_ruby tool to compute Sketchup.active_model.title
```

Claude должен вызвать `eval_ruby("Sketchup.active_model.title")` и получить имя текущей модели.

```
> use get_scene_info to tell me how many definitions are in the model
```

## Разработка / смена транспорта

Если порт 9876 занят — меняется в `transport.py` (constructor `TcpClient(port=...)`) на Python стороне и в `server.rb` (`DEFAULT_PORT`) на Ruby стороне.

## Лицензия

MIT.
