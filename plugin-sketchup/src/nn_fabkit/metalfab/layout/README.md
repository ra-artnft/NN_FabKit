# MetalFab × LayOut — заглушка под будущий код

> Подсистема: **MetalFab × LayOut**
> Namespace: `NN::MetalFab::LayoutGen` (имя `Layout` зарезервировано LayOut SDK — корневой `::Layout::Document`, `::Layout::Page`, etc., поэтому используем `LayoutGen`).
> Источник истины: [docs/specs/](../../../../../docs/specs/) (TODO `spec-04-metalfab-layout-templates.md`)

Здесь будет жить весь код, который **MetalFab-ветка** генерирует **в LayOut**:

- A3 cut-list table (типоразмер | количество | длина | масса) — читает `nn_metalfab` attrs со всех `rect_tube` инстансов в активной SU-сцене.
- Title block с шапкой проекта (логотип, название, дата, scale).
- Viewport на 3D-вид через `Layout::SketchUpModel`.
- IGES preview / DXF preview (если на чертеже нужны NC-выкладки рядом с моделью).
- Export to PDF.

**Текущее состояние**: первый template — [template_cut_list.rb](template_cut_list.rb) — A4 portrait, mm units, title block + 3D viewport + cut-list для `rect_tube` инстансов из активной SU-сцены. Реквизиты title block пока хардкод (см. `default_meta`), параметризуем когда заказчик даст шаблон. MCP handlers `layout_create_template` и `layout_export_pdf` живут в [../../mcp/handlers.rb](../../mcp/handlers.rb).

**Когда сюда добавлять код**: запрос пользователя «в MetalFab в LayOut …» / «сделай чертёж рамы / cut-list» / «титульный блок металл-проекта».
