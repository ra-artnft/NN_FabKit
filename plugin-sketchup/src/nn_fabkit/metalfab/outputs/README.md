# MetalFab × Outputs — файлы выдачи (production)

> Зонтик для всех output-форматов металл-ветки. Намерение — у пользователя должно быть ОДНО место, куда он бьёт запросом «по IGES …» / «по DXF …», и это сразу маппится на конкретный файл/папку.

## Текущие форматы выдачи

| Формат | Назначение | Где код | Статус |
|---|---|---|---|
| **IGES (wireframe)** | Type 110 (line) + Type 100 (arc) — простой обмен 2D/wireframe для CAM. Embedded в плагин. | [../iges_exporter/wireframe.rb](../iges_exporter/wireframe.rb), UI-команда [../commands/export_iges.rb](../commands/export_iges.rb) | ✅ есть (LOD-1 wireframe) |
| **IGES (surface, NC)** | Полноценная поверхность для laser tube cutter — эллиптические дуги на скруглениях, surface-модель. **Standalone Python**, не плагин (ADR-017). | [`../../../../../app-desktop/nc-export/`](../../../../../app-desktop/nc-export/) — `nn_fabkit_nc_export` package | ✅ есть (rect_tube hollow mitre 45°) |
| **DXF (лист)** | Раскрой листа г/к (ГОСТ 19903), плазма / лазер. Будущее — для `Лист.skp` компонентов. | [dxf/](dxf/) — пока stub | 🔜 TODO (нет требований заказчика) |

## Эвристика «по запросу пользователя»

| Запрос | Куда | Что делать |
|---|---|---|
| «по IGES wireframe / в плагине / в SketchUp» | [../iges_exporter/](../iges_exporter/) | LOD-1 wireframe Type 110 + 100, через UI-команду |
| «по IGES surface / для CAM / для laser» | [`app-desktop/nc-export/`](../../../../../app-desktop/nc-export/) | Surface-модель из Python, не плагин |
| «по DXF / лист / плазма» | [dxf/](dxf/) | Stub, пока нет реализации — TODO определить с заказчиком |

## Когда сюда добавлять код

Новый output-формат для металла (STEP, IFC, BVBS для арматуры, CSV cut-list для другого CAM, etc.) — добавлять как подпапку рядом с `dxf/`, обновлять таблицу выше, обновлять верхнеуровневую навигацию в [CLAUDE.md](../../../../../CLAUDE.md) («Подсистемы — адресация корректировок»).

**НЕ путать с LayOut**: LayOut — это **чертёж для человека** (PDF/печать), Outputs — это **машинные файлы для production** (CNC, плазма, лазер).
