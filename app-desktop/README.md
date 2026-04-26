# app-desktop

Standalone-приложения NN FabKit. Не плагин SketchUp — отдельные процессы.

## Подпроекты

| Папка | Что | Статус |
|---|---|---|
| [nc-export/](nc-export/) | Python: IGES/DXF writer для CNC | ✅ v0.1.0 — IGES surface-модель |
| (планируется) `dialog/` | UI диалога с Claude (Electron/Tauri/PySide?) | ⏸ |
| (планируется) `layout-tz/` | Генератор ТЗ в LayOut | ⏸ |

См. [ADR-013](../docs/knowledge-base/09-architecture-decisions.md) (зонтичная архитектура) и [ADR-017](../docs/knowledge-base/09-architecture-decisions.md) (собственный IGES-конвертёр в MVP).
