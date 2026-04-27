# Changelog

Формат — по [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Версии монорепо независимы от версии плагина; версия плагина живёт в `plugin-sketchup/src/nn_fabkit/version.rb`.

## [v0.0.36] — 2026-04-27

### Fixed (updater UI: длинные release notes ломали кнопку OK)

- **Плагин 0.12.0 → 0.12.1** — feedback пользователя: «из-за большого полотна текста ознакомительного и отсутствия скроллинга я кнопку OK не вижу».
- Корень: `UI.messagebox` в [check_update.rb](plugin-sketchup/src/nn_fabkit/commands/check_update.rb) показывал `release_notes` из `update.json` целиком. Windows MessageBox не имеет скролла — при overflow YES/NO кнопки уходят за низ экрана, обновление подтвердить невозможно.
- Fix: `summarize_notes` truncate'ит notes до **6 строк / 400 символов**, добавляет «…» и **ссылку на полный changelog** ([github.com/ra-artnft/NN_FabKit/releases](https://github.com/ra-artnft/NN_FabKit/releases)). Кнопки YES/NO видны всегда. Применено и для manual check (`Extensions → NN FabKit → Проверить обновления…`), и для background popup при запуске SU.

### Modified
- `plugin-sketchup/src/nn_fabkit/commands/check_update.rb` — `build_update_prompt`, `summarize_notes`, константы `NOTES_MAX_LINES`, `NOTES_MAX_CHARS`, `RELEASES_URL`.

## [v0.0.35] — 2026-04-27

### Fixed (FabKit CAD: остаточные геометрические баги)

- **Плагин 0.11.12 → 0.12.0** — добиты три остаточных бага из v0.11.x roadmap.

#### (1) Joint angle через joint-to-far vectors (тупой L и Y-joint configurations)
- **Был**: `acos(axis_a.dot(axis_b).abs)` использовал local +Z axes труб, игнорируя `end_axis_sign`. Это давало правильный mitre **только** когда обе трубы ориентированы так, что local +Z указывает «away from joint» (классическая конфигурация L-corner с обеими end_axis=+1). В других конфигурациях формула ломалась:
  - **Y-joint, обе end_axis=−1** (origin каждой трубы = joint, +Z указывает к far): для θ=60° между трубами правильный mitre = (180−60)/2 = 60°, но `axis_a.dot(axis_b) = cos(60°) = 0.5` → acute = 60° → mitre **30°**. Wrong.
  - **Mixed end_axis** (одна +1, другая −1): тоже даёт wrong результат.
  - Также `angle_between_deg` в UI label всегда показывался как acute (≤ 90°), даже для тупого θ=120° — путаница в preview text.
- **Стало**: `theta_deg` считается из joint-to-far vectors `v_a = far_a − end_a_at_joint` и `v_b = far_b − end_b_at_joint`. `dot(v_a, v_b)` даёт правильный joint angle [0..180°] независимо от end_axis sign convention'ов. Формула `mitre = (180 − θ)/2`. Корректно для всего диапазона:
  - θ=60° (острый Y/K) → mitre 60°
  - θ=90° (perpendicular L) → mitre 45°
  - θ=120° (тупой L) → mitre 30°
  - θ=180° (collinear butt) → mitre 0° (perpendicular cut)
- Preview/status text теперь показывают честный joint angle: «Mitre 30.0° (joint 120.0° между трубами)».

#### (2) Skew axes detection
- **Был**: если оси двух труб не пересекались в одной точке (skew distance > 0), `Geom.closest_points` возвращал две разные точки; `compute_trim` для каждой трубы trim'ил endpoint до её собственной closest_point. Endpoints труб НЕ совпадали — между ними оставался видимый зазор размером со skew distance. Tilt direction'ы тоже выбирались независимо → визуальный artifact на стыке.
- **Стало**: после `Geom.closest_points` явная проверка `skew_dist > 1mm` (`SKEW_TOLERANCE_MM`). При превышении — `find_joint` возвращает nil с `@last_error_reason = :skew_axes`. `analyze_selection` показывает messagebox с указанием размера skew и инструкцией: «Подвинь одну из труб так, чтобы её ось пересеклась с осью другой». Геометрически невозможно сделать чистый mitre на skew axes — лучше явный отказ, чем silent gap.

#### (3) Параллельные трубы
- **Был**: при `dot=±1` (axes parallel/anti-parallel) `mitre_angle` вычислялся как 0° или 90°, апплай давал degenerate cut.
- **Стало**: `theta_deg < 1°` детектируется как `:parallel` → messagebox «Mitre joint геометрически не определён».

### Changed (snap markers всегда видны)

- **Плагин 0.11.12 → 0.12.0** — feedback: «эти инпойнты, куда ориентироваться при магничивании, должны показываться сразу же, всегда».
- До v0.12.0 snap markers в 8 углах bbox каждой трубы были `Sketchup::ConstructionPoint` (`add_cpoint`). Visible **только** при `View → Construction Geometry` ON (model-level toggle). Если выкл — snap inference работало, но markers были невидимые → непонятно, к чему magnetism цепляется.
- **Стало**: 8 углов × 3 коротких edges (X+Y+Z кресты по 1.5mm half-length) = 24 edges на трубу, на отдельном Tag/Layer `FabKit::SnapMarkers` с magenta color. Edges рендерятся всегда независимо от `View → Construction Geometry`. Их endpoints дают тот же Endpoint snap inference. Layer создаётся один раз при первом build трубы; пользователь может скрыть его в Tags panel если визуально мешает (snap продолжит работать пока Tag visible).

### Modified
- `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb` — `find_joint` (joint-to-far theta calculation, skew detection, parallel guard); `analyze_selection` (case по `@last_error_reason` с разными UI messages); добавлена `SKEW_TOLERANCE_MM` constant.
- `plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube.rb` — `add_bbox_snap_points` → `add_bbox_snap_markers` (edges-based, dedicated Layer); добавлены `ensure_snap_marker_layer`, `SNAP_MARKER_LAYER`, `SNAP_MARKER_HALF_MM`, `SNAP_MARKER_COLOR`.

### Added (LayOut integration: cut-list template)

- Первая интеграция с LayOut Ruby API. LayOut SDK живёт **внутри SketchUp process** (`Layout::Document`, `Layout::Page`, `Layout::Rectangle`, `Layout::FormattedText`, `Layout::SketchUpModel`, …) — отдельный extension под LayOut НЕ нужен (LayOut на Windows не имеет Extension Manager). Все handlers через тот же MCP/TCP сервер плагина.
- Новый namespace `NN::MetalFab::LayoutGen` (имя `Layout` зарезервировано LayOut SDK) в [plugin-sketchup/src/nn_fabkit/metalfab/layout/template_cut_list.rb](plugin-sketchup/src/nn_fabkit/metalfab/layout/template_cut_list.rb).
- Метод `TemplateCutList.generate(output_path:, meta:)` создаёт A4 portrait .layout с:
  - **Title block** в правом верхнем углу — проект, заказчик, дата, масштаб; реквизиты пока хардкод-default'ы, перекрываются опциональным `meta` хэшем.
  - **3D viewport** на активную SketchUp-модель через `Layout::SketchUpModel`. Перед save: `view.zoom_extents` + `model.save` чтобы embedded-view взял свежую camera (Layout читает .skp с диска, не in-memory).
  - **Cut-list table** внизу — группировка `rect_tube` инстансов из активной сцены по `nn_metalfab.typesize`, колонки № / Типоразмер / ГОСТ / Сталь / Кол-во / Σ Длина / Σ Масса + строка ИТОГО.
- Документ в **миллиметрах** (`Layout::Document::DECIMAL_MILLIMETERS`, precision 0.1mm).
- `TemplateCutList.export_pdf(layout_path:, pdf_path:)` — обёртка над `Layout::Document#export`.
- 2 новых MCP handlers в [plugin-sketchup/src/nn_fabkit/mcp/handlers.rb](plugin-sketchup/src/nn_fabkit/mcp/handlers.rb):
  - `layout_create_template(path, meta?)` — генерация .layout
  - `layout_export_pdf(layout_path, pdf_path)` — PDF export
- Соответствующие Python wrappers в [mcp-bridge/src/nn_fabkit_mcp/server.py](mcp-bridge/src/nn_fabkit_mcp/server.py).
- Loose end: `Layout::FormattedText.new("")` бросает `ArgumentError: empty string` — добавлен guard в `add_text_center`.
- Loose end: file lock — если .layout открыт в LayOut, save fails с `Errno::EACCES`. Текущая семантика — propagate ошибку наверх (handler raise → MCP error).

### Подсистемная навигация (CLAUDE.md)

- Новый раздел [«Подсистемы — адресация корректировок»](CLAUDE.md) — матрица 2×2 `{MetalFab, MebelFab} × {SketchUp, LayOut}` + общее ядро (FabKit umbrella) + standalone NC.
- Эвристика выбора подсистемы по запросу: «труба / mitre / IGES» → MetalFab × SketchUp; «чертёж металла / cut-list» → MetalFab × LayOut; «шкаф / ЛДСП» → MebelFab × SketchUp; и т.д.
- Stub-папки с README под будущий код:
  - [plugin-sketchup/src/nn_fabkit/metalfab/layout/](plugin-sketchup/src/nn_fabkit/metalfab/layout/) — теперь **не stub**, есть первый template (`template_cut_list.rb`)
  - [plugin-sketchup/src/nn_fabkit/mebelfab/](plugin-sketchup/src/nn_fabkit/mebelfab/) — stub (skp/ + layout/ под мебельную ветку, ждём вводных от заказчика)

### Deferred (TODO следующих версий)
- **Asymmetric mitre** (разные сечения труб). Bisecting plane та же, но external contours не совпадают edge-to-edge. Решение — отдельный cope joint mode (v0.13+).
- **T-joint butt** (perpendicular cut на brace). См. roadmap §10.
- **T-joint notch** (envelope cope rect-on-rect).
- **X-cross 4-tube symmetric**.
- **Round tube mitre + fishmouth cope**.
- **LayOut: параметризация title block** через UI dialog или `nn_metalfab.project_*` attrs (сейчас reverse path — реквизиты в `meta` хэше handler'а).
- **LayOut: scenes binding** (выбор `Layout::SketchUpModel#current_scene` по индексу — текущая логика берёт default view модели после `zoom_extents`).
- **LayOut: assembly drawings** — отдельный template с многостраничным views (front/top/side), отдельная задача от cut-list.

## [v0.0.34] — 2026-04-27

### Fixed (transformation drift + shared definition)
- **Плагин 0.11.11 → 0.11.12** — feedback: «соседняя труба удлиняется» после apply cut. Две root причины обнаружены через MCP диагностику.
- **(1) Transformation drift**: в `apply_to_one_tube` shift transformation.origin для `end_axis=-1` делался через `Geom::Transformation.axes(origin, x_axis, y_axis, z_axis)` с пере-вычислением осей из `old_transformation`. Это accumulated FP errors в orthonormal basis на каждый apply — после ~5 операций tubes начинали «крутиться» (zaxis (0, 0.0067, 1) вместо (0, 0, 1)) и origin'ы drift'или (0, -7, -13) вместо (0, 0, 10). **Fix**: `Geom::Transformation.translation(delta) * old_transformation`. Pure translation сохраняет rotation TOOH. Verified MCP: zaxis до и после apply совпадают на 8 знаков после запятой.
- **(2) Shared definition**: если две trubы имели общий definition (создано через SU Move+Ctrl, или Make Unique button cancel'нута), apply mitre на ОДНОЙ trubе модифицировал shared definition → ОБА instance меняются. Это и было «соседняя удлиняется». **Fix**: `apply_to_one_tube` auto-выполняет `tube.make_unique` если `definition.instances.length > 1`. Страховка независимая от Make Unique button.

### Modified
- `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb` — `apply_to_one_tube` (auto make_unique + translation × old_t).

## [v0.0.33] — 2026-04-27

### Fixed (Cut tilt direction restoration on opposite end)
- **Плагин 0.11.10 → 0.11.11** — feedback: при apply mitre на втором конце трубы (когда первый уже cut) первый cut «flip'ался» в обратную сторону. Причина: `rebuild_with_cut` делает `RectTube.build` (clear+rebuild perpendicular tube), потом восстанавливает cut на opposite end. Но direction (tilt_dir_local) cut'а **не сохранялся** в attribute_dictionary — restoration использовал hardcoded default `(0, 1, 0)`, что часто не совпадало с оригинальным direction → видимый flip первого cut'а.
- В [attr_dict.rb](plugin-sketchup/src/nn_fabkit/metalfab/attr_dict.rb) `read_rect_tube_params` читает 4 новых поля `cut_z0_tilt_x/y, cut_zL_tilt_x/y` (default `(0, 1)` для backward compat с v0.11.10 definitions).
- В [rect_tube_mitre.rb](plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube_mitre.rb) `rebuild_with_cut` теперь:
  - Читает `existing_z0_tilt`, `existing_zL_tilt` из params до clear
  - Restoration на opposite end использует saved tilt (не default)
  - В конце записывает `cut_z*_tilt_x/y` для **обоих** ends (текущего apply + сохранённого opposite)
- Verified через MCP: frame из 4 труб → последовательный apply 4 corners по часовой стрелке. После каждого corner проверяется state всех 4 труб: `zL_tilt_y` остаётся постоянным от corner до corner, никаких flip'ов.

### Added (MCP-сервер auto-start при загрузке плагина)
- **Плагин 0.11.10 → 0.11.11** — feedback: MCP сервер сам должен стартовать после launch SketchUp без manual click в menu.
- В [main.rb](plugin-sketchup/src/nn_fabkit/main.rb) после `Toolbar.register!` добавлен `UI.start_timer(2.0, false) { Mcp.start }` — 2s grace period после plugin load чтобы SU успел инициализироваться, потом MCP server starts.
- Если порт 9876 занят (другой SU instance) — log error, SU не падает. Manual control остаётся через menu Extensions → NN FabKit → MCP сервер → Запустить/Остановить.

### Modified
- `plugin-sketchup/src/nn_fabkit/metalfab/attr_dict.rb` — `read_rect_tube_params` возвращает `cut_z*_tilt_x/y`.
- `plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube_mitre.rb` — `rebuild_with_cut` сохраняет/restore'ит tilts.
- `plugin-sketchup/src/nn_fabkit/main.rb` — MCP auto-start на plugin load.

## [v0.0.32] — 2026-04-27

### Fixed (FabKit CAD: tilt direction для произвольных end_axis)
- **Плагин 0.11.9 → 0.11.10** — на frame из 4 труб 1-2 cuts работали, 3-4 cuts «отходили» — user компенсировал ручным rotate трубы. Корень: v0.11.2 simple `compute_tilt_dir` использовал `tube_axis_world(other)` без учёта end_axis_other — direction правильная только при joint at z=length end of OTHER tube. Для z=0 end (что бывает в 4-tube frame с разными orientation'ами труб) — wrong sign.
- В [fabkit_cad_tool.rb:286](plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb#L286) `compute_tilt_dir` переписан через explicit geometric vector `end_data_other.point − far_endpoint(other)` — это direction «away from body of other tube» = toward outer corner L. Long side mitre всегда extends в outer corner direction. Не зависит от end_axis sign — работает для всех 4 corner типов в frame.
- В `find_joint` исправлены вызовы — передаётся `end_data` of OTHER tube (не self), как ожидает функция: `tilt_a = compute_tilt_dir(tube_a, tube_b, best[:end_b])`.

### Added (Make Unique button при detection same-definition)
- При активации FabKit CAD с 2 selected трубами одной definition (копии) теперь показывается `MB_OKCANCEL` диалог: «Сделать Make Unique для более поздней (created позднее)?». ОК → автоматически делается unique у трубы с большим `persistent_id` (created позднее), FabKit CAD продолжает работу с двумя независимыми definitions. Cancel → отмена tool.
- Раньше: `messagebox` с OK единственной опцией «Сделай Make Unique вручную» — пользователь вынужден закрыть tool, в outliner делать make_unique, заново активировать tool.

### Modified
- `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb` — `compute_tilt_dir` переписан, `find_joint` calls обновлены, `analyze_selection` same_definition branch с Make Unique логикой.

## [v0.0.31] — 2026-04-27

### Added (snap к bbox-углам компонента)
- **Плагин 0.11.8 → 0.11.9** — по feedback'у пользователя: «при стыковке труб snap липнет к geometry внутри (rounded corner vertices), а нужно к краям bbox компонента».
- В [rect_tube.rb](plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube.rb) `RectTube.build` после extrude добавляется новый шаг `add_bbox_snap_points(entities, w, h, length)` — создаёт 8 ConstructionPoint в углах bounding box (4 на z=0 + 4 на z=length). SU snap inference cursor подхватывает их как Endpoint targets с высоким priority.
- Визуально: cpoints — крошечные «+» symbols, едва заметны. Можно скрыть глобально через `View → Construction Geometry` если мешают.
- Это решает classical SU issue с rounded geometry: 8 segments на corner radius создают vertices где нет физических углов компонента, и snap прилипает не туда. ConstructionPoint в bbox corner — explicit hint для SU snap.

### Modified
- `plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube.rb` — wire `add_bbox_snap_points` в `build`, новый helper в конце модуля.

## [v0.0.30] — 2026-04-27

### Added (FabKit CAD: single cut на axis intersection)

- **Плагин 0.11.7 → 0.11.8** — по feedback'у пользователя «у нас два места реза, а должен быть один по центру между ними». Joint_point теперь вычисляется как **пересечение осей труб** через `Geom.closest_points` (не midpoint endpoints, который off-axis от обеих).
- В [fabkit_cad_tool.rb:226-258](plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb#L226-L258):
  - `find_joint` теперь использует `Geom.closest_points(line_a, line_b)` для нахождения axis intersection (или для skew axes — пары closest points, midpoint которых)
  - Добавлен helper `compute_trim(tube, end_data, target_world)` — возвращает new_length_mm + опциональный new_origin_world (для end_axis=-1 case)
- В `apply_to_one_tube`: перед `rebuild_with_cut` применяется trim — обновляется transformation.origin (если joint at z=0) и `params[:length_mm]` устанавливается в trim_data[:new_length_mm].
- В `draw_cut_plane`: rect рисуется в trimmed endpoint position. На perpendicular L-corner с пересекающимися axes обе rect совпадают в одной плоскости → visually выглядит как ОДИН cut.
- Обоснование: в v0.11.2 baseline preview показывал 2 cyan rect — каждый на endpoint своей трубы. Endpoints не совпадают если трубы overlap'ятся в corner → 2 разных места реза. После моего fix'а оба рисуются на bisecting plane (axis intersection) → совпадают.

### Implication для length_mm

После apply mitre joint, length_mm каждой трубы обновляется до distance от far endpoint до axis intersection. Inspector / cut-list покажут эту новую длину — это правильное число для NC.

### Modified
- `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb` — `find_joint`, `compute_trim` (новый), `draw_preview` & `draw_cut_plane` (signature с endpoint_world), `apply_cut` & `apply_to_one_tube` (новый параметр `trim_data`).
- `compute_tilt_dir` НЕ менялся — оставлен как в v0.11.2 baseline.

## [v0.0.29] — 2026-04-27

### Reverted (FabKit CAD: откат к v0.11.2 — selection-based 2-tube auto, до моих 'улучшений')

- **Плагин 0.11.6 → 0.11.7** — FabKit CAD откачен к v0.11.2 (commit 815fbb8) — selection-based 2-tube auto-mitre, **начальная версия** этого UX до моих refinement'ов v0.11.3..v0.11.5. Пользователь идентифицировал v0.11.2 как working baseline.
- v0.11.6 (vertex pick из v0.11.0) и предложенный v0.11.1 (face pick) не подошли — нужен selection-based 2-tube workflow.
- Восстановленные файлы из v0.11.2:
  - `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb`
  - `plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube_mitre.rb`
- Удалены изменения v0.11.3 (tilt direction sign fix, который сломал результат), v0.11.4 (compute_tilt_dir переписан через far-joint vector), v0.11.5 (trim mode).
- Не затронуто: Inspector, toolbar, auto-update, knowledge-base.

### Known issue в v0.11.2 (из original memory)
- Тонкие protrusions на L-corner — overlap труб не убирается полностью на endpoint-cut'е. Это known issue, но user accepts as baseline.

## [v0.0.28] — 2026-04-27

### Reverted (FabKit CAD: откат к v0.11.0 manual mode)

- **Плагин 0.11.5 → 0.11.6** — FabKit CAD откачен к initial v0.11.0 reализации (interactive vertex pick + drag-protractor, 1-tube manual mode). Selection-based 2-tube auto-mitre из v0.11.2..v0.11.5 удалён по решению пользователя — за 4 итерации redesign'а (v0.11.2 → v0.11.5) визуально корректный L-corner mitre так и не получен, хотя математика cuts (биссектрисная плоскость, совпадение vertices) была верифицирована через MCP.
- Восстановленные файлы из v0.11.0 (commit e51daa5):
  - `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb` — state machine `:waiting_for_apex` (vertex pick) → `:waiting_for_angle` (drag protractor / VCB).
  - `plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube_mitre.rb` — `rebuild_with_cut` без trim mode и без cap rebuild.
- Не затронуто:
  - Inspector (tabs, supplier chip, subgroup filters) — сохранён.
  - Toolbar 3-buttons (Inspector / Создать трубу / FabKit CAD) — сохранён, кнопка теперь активирует v0.11.0-style tool.
  - Auto-update popup при старте — сохранён.
  - Knowledge-base `12-tube-joints-geometry.md` — сохранён как reference для будущих работ.
- Memory feedback "НЕ делать vertex pick UX" из сессии после v0.11.2 → отозван (был вынужденный ответ на specific bug, не fundamental design preference).

### Modified
- `plugin-sketchup/src/nn_fabkit/version.rb` — bump 0.11.5 → 0.11.6
- `update.json` — pointer на v0.11.6 release
- `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb` — restored from v0.11.0
- `plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube_mitre.rb` — restored from v0.11.0

## [v0.0.27] — 2026-04-26

### Added (FabKit CAD: trim mode)

- **Плагин 0.11.4 → 0.11.5** — новый режим резки на bisecting plane через axis intersection.
- **Проблема, которую решает**: vertex displacement v0.11.x резал на endpoint трубы (z=0 или z=length). Если концы труб overlap'ятся в L-corner (реальная привычка проектирования у заказчика-0), cut на endpoint оставляет лишний кусок над corner — direction tilt_dir правильный (v0.11.4), но cut просто не там.
- **Решение**: в [fabkit_cad_tool.rb](plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb) добавлен `@trim_mode` (default ON). Через `Geom.closest_points` находится точка пересечения axes труб; каждая труба укорачивается / удлиняется до своей closest point на её axis (`compute_trim`); затем применяется mitre на новый endpoint. Endpoint cuts оказываются точно на bisecting plane joint'а.
- **Реализация trim**:
  - end_axis=+1 (joint at z=length): меняется `length_mm` через `RectTube.build`, transformation.origin не двигается.
  - end_axis=-1 (joint at z=0): сдвигается transformation.origin до axis-intersection точки + меняется `length_mm`.
- **UX**:
  - Клавиша **T** в preview переключает trim ON/OFF (`onKeyDown`, VK_T=84).
  - Status bar показывает `[ТРИМ ВКЛ]` / `[ТРИМ ВЫКЛ]`.
  - Preview label возле joint point: `Mitre 45.0° (joint 90.0°)  ТРИМ ВКЛ (T)`.
  - Cyan cut plane preview рендерится в РЕАЛЬНОЙ позиции реза (на trimmed endpoint при trim ON) — пользователь видит exactly где будет cut до apply.
- **Implication для production**: при trim ON `length_mm` детали обновляется (= distance от far endpoint до axis intersection). Это правильное число для NC и cut-list — деталь с такой длиной + cut angle даёт точную обрабатываемую заготовку. Inspector подхватит новую длину автоматически.
- `compute_tilt_dir` (v0.11.4 fix через `far - joint`) остался без изменений — он correct для обоих trim modes.

### Modified
- `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb` — `@trim_mode`, `onKeyDown`, `compute_trim`, `find_joint`, `set_status_text`, `draw_preview`, `draw_cut_plane` (новая signature с `endpoint_world`), `apply_cut`, `apply_to_one_tube` (новый параметр `trim_data`).

## [v0.0.26] — 2026-04-26

### Fixed (FabKit CAD: zigzag mitre на L-corner)

- **Плагин 0.11.3 → 0.11.4** — `compute_tilt_dir` в [fabkit_cad_tool.rb](plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb) переписан через explicit geometric vector `far_endpoint(other) - joint_endpoint(other)` вместо прежней комбинации `tube_axis_world + end_axis_sign`. На user setup (две перпендикулярные трубы L-corner) v0.11.3 давал «zigzag» — long side mitre оказывалась на ВНУТРЕННЕЙ стороне угла вместо внешней.
- Причина: sign-fix `axis_world.reverse` на end_axis_other == +1 был корректен на бумаге, но взаимодействие с `Vector3d#transform(transformation.inverse)` и конкретной orientation труб у заказчика-0 давало reversed result. Геометрический подход через два endpoint'а исключает эту хрупкость — направление от joint к far end равно направлению body other tube в world coords без посредников.
- Логика `apply_mitre` (`dz = sign × (pos · tilt_dir) × tan(angle)`) не менялась — она correct и достаточна, нужно было только надёжно вычислять `tilt_dir`.

### Modified
- `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb` — `compute_tilt_dir`.

## [v0.0.25] — 2026-04-26

### Added (FabKit CAD interactive mitre tool)
- **Плагин 0.10.3 → 0.11.0** — третья кнопка toolbar'а «FabKit CAD» (иконка: rect tube cross-section + диагональный orange cut line с угловым indicator'ом). Активирует кастомный `Sketchup::Tool` для interactive mitre cutting:
  - **State 1 (waiting_for_apex)**: пользователь кликает вершину rect_tube DC. Tool ищет parent ComponentInstance с `nn_metalfab.profile_type=="rect_tube"`, определяет ближайший конец (z=0 или z=length) по distance.
  - **State 2 (waiting_for_angle)**: live protractor нарисован в plane perpendicular оси трубы, реальный 3D arc. Mouse move → live angle update. VCB (Value Control Box) активирован — user может набрать число + Enter (как в SU Rotate / Move tool'ах).
  - **Apply**: `RectTubeMitre.rebuild_with_cut` — vertex displacement через `Entities#transform_by_vectors`. Atomic per-vertex смещение, нет артефактов open holes.
- Новый module `NN::MetalFab::ProfileGenerator::RectTubeMitre`. Стратегия: построить perpendicular tube, потом сдвинуть вершины cut-конца по `dz = sign × y × tan(angle)`. SU автоматически деформирует connected faces (sides → trapezoids, endcap → tilted plane).
- `attr_dict.rb` расширен: `cut_z0_angle_deg` / `cut_zL_angle_deg` (default 0.0 = perpendicular). `read_rect_tube_params(entity)` возвращает все params включая cut state (для nc-export integration).

### Added (product vision)
- **`docs/PRODUCT_VISION.md`** — формализация конечной цели продукта:
  - 3 выхода: laser tube IGES (CypTube) + wood saw DXF (OCL-naming) + docs (LayOut).
  - One-click cut-list как ключевая UX-фича (группировка идентичных деталей).
  - Принципы: точная BREP-геометрия, метаданные на каждой детали, локальный offline pipeline.
  - Roadmap-таблица с этапами (0..7).

### New files
- `plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube_mitre.rb`
- `plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb`
- `plugin-sketchup/src/nn_fabkit/ui/icons/fabkit-cad-{16,24}.png`
- `docs/PRODUCT_VISION.md`

### Modified
- `plugin-sketchup/src/nn_fabkit/main.rb` — `Sketchup.require` для нового generator + tool.
- `plugin-sketchup/src/nn_fabkit/metalfab/attr_dict.rb` — cut fields + read_rect_tube_params helper.
- `plugin-sketchup/src/nn_fabkit/ui/toolbar.rb` — третья кнопка `build_fabkit_cad_command`.
- `plugin-sketchup/src/nn_fabkit/ui/menu.rb` — пункт «MetalFab → FabKit CAD…» fallback.

## [v0.0.24] — 2026-04-26

### Added (auto-update popup при старте)
- **Плагин 0.9.0 → 0.10.0** — при старте SketchUp плагин через `UI.start_timer(3.0)` проверяет manifest и, если доступна новая версия — показывает popup «Обновление NN FabKit доступно: vX.Y.Z. Обновить сейчас?» с YES/NO.
  - YES → existing install flow (download + `Sketchup.install_from_archive` + restart message).
  - NO → сохраняет в Sketchup prefs (`dismissed_update_version`), не показывает popup для этой же версии повторно. Для будущих версий popup снова появится.
- Сетевые ошибки и offline-старт глотает тихо (puts в Ruby Console), не блокирует загрузку SU.
- Helper-методы в `Commands::CheckUpdate`: `background_check_on_startup`, `run_background_check`, `show_update_prompt`, `install_and_notify`, `dismissed?`, `dismiss!`.

### Fixed (toolbar dock)
- v0.9.0 toolbar `NN FabKit` не докался в верхнюю workspace area — даже после ручного drag'а к toolbar bar и попытки выбора через `View → Toolbars` checkbox он оставался floating'ом. Причина — SVG-иконка в SU 2025 рендерилась, но drag-to-dock мог ломаться (плюс `set_validation_proc` подозревали в interference). Решение:
  - Заменили SVG на PNG (16×16 + 24×24, генерируем через PIL'ом supersampled 4× и downsampled с Lanczos для anti-aliasing).
  - Убрали `cmd.set_validation_proc` (косметика подсветки кнопки — не критично).
- Теперь стандартное SU dock-поведение работает как у других плагинов (OCL и т.п.).

### New files
- `plugin-sketchup/src/nn_fabkit/ui/icons/inspector-16.png`
- `plugin-sketchup/src/nn_fabkit/ui/icons/inspector-24.png`

### Modified
- `plugin-sketchup/src/nn_fabkit/main.rb` — вызов `CheckUpdate.background_check_on_startup` после `Toolbar.register!`.
- `plugin-sketchup/src/nn_fabkit/ui/toolbar.rb` — PNG icons, удалён `set_validation_proc`.
- `plugin-sketchup/src/nn_fabkit/commands/check_update.rb` — фоновая проверка + dismissed-версия в prefs.

## [v0.0.23] — 2026-04-26

### Added (UI::Toolbar button)
- **Плагин 0.8.0 → 0.9.0** — toolbar «NN FabKit» с одной кнопкой-иконкой Inspector в верхней workspace area SU (рядом с другими плагинами, как OCL по референсу заказчика-0).
- Клик по кнопке → `Inspector.show` (открывает или brings to front).
- Native X в заголовке Inspector закрывает только диалог; toolbar-кнопка остаётся стационарно — `UI::Toolbar` и `UI::HtmlDialog` независимы.
- Auto-show при первой загрузке после установки (`TB_NEVER_SHOWN → tb.show`); при последующих сессиях `tb.restore` уважает выбор пользователя. Чтобы убрать toolbar — `View → Toolbars → NN FabKit` (uncheck).
- Validation proc подсвечивает кнопку (MF_CHECKED) пока Inspector visible — visual press-state.
- Иконка 24×24 SVG: профиль трубы (outer rounded rect + inner cavity), `stroke="#1a1a1a"` для светлой темы SU; в SU dark mode рендерится через инверсию colorize.

### New files
- `plugin-sketchup/src/nn_fabkit/ui/icons/inspector.svg`
- `plugin-sketchup/src/nn_fabkit/ui/toolbar.rb`

### Modified
- `plugin-sketchup/src/nn_fabkit/main.rb` — `Sketchup.require "nn_fabkit/ui/toolbar"` + `Toolbar.register!` в `unless file_loaded?` блоке.

## [v0.0.22] — 2026-04-26

### Added (Inspector tabs + supplier + subgroups)
- **Плагин 0.7.0 → 0.8.0** — структурная перестройка Inspector'а под фидбек заказчика-0:
  - **Top-level tabs Metal FAB / Дерево FAB** на месте бывшей плоской секции «MetalFab — сортамент трубы». «Дерево FAB» — пилотная заглушка для мебельной ветки (ЛДСП, фанера, кромка, метизы; будущее).
  - **Supplier chip** под top tabs — отображает имя поставщика и город из `supplier`-поля JSON-каталога. Сейчас показывает «ООО «Юг-Сталь» · Краснодар» (была ошибочная подпись «ГОСТ 30245-2003» — это название стандарта, не поставщика).
  - **Subgroup-фильтры** Все (62) / Квадратные (30) / Прямоугольные (32) — chip-кнопки над списком, разделение по `params.width_mm == params.height_mm`. Поиск работает поверх выбранной подгруппы.
- Bootstrap-payload теперь использует `state.catalog.supplier` (это поле уже было в JSON, но не выводилось в UI).

### Notes
- ГОСТ 30245-2003 в каталоге — не имя поставщика, а нормативный стандарт (теоретический. supplier convention для радиусов = Юг-Сталь 1.5×t, см. v0.0.18).

## [v0.0.21] — 2026-04-26

### Added (Inspector Sprint B)
- **Плагин 0.6.0 → 0.7.0** — форма «Создать «Профильная труба»» прямо в Inspector'е (HtmlDialog). Поля: длина (input number, default 1000), марка стали (select из catalog grades, default Ст3сп), primary button «Создать». Disabled state до выбора типоразмера; динамический hint меняется на «Будет создан компонент «Труба X»». После клика — async flow: JS → Ruby `nn_create_rect_tube(typesize, grade, length)` → возврат `{ok, name}` → JS hint «Создано: …».
- `CreateRectTube.create_with_params(typesize, grade, length_mm)` — выделена из `call` для программного входа (Inspector / MCP / тесты). Возвращает Hash `{ok:, name:, typesize:, ..., error:}`.
- Helper `Inspector.js_json(payload)` — инкапсулирует U+2028/U+2029 escape (вместо копипасты).
- Dark theme styles для всех новых form-элементов.

### Fixed
- **`check_update.rb` syntax error** — лишний `end` на (старой) строке 78 закрывал `module CheckUpdate` слишком рано, `change_url` оказывался вне модуля. SU 2024 / Ruby 2.7 видимо проглатывал без эффекта; SU 2025 / Ruby 3.2 строже — кидает SyntaxError при загрузке плагина → каскад «Some Extensions Failed to Load». Pre-existing baggage из v0.4.1 (commit 17e9a08), пользователь не мог получить Inspector до этого fix.
- **`ext.version`** теперь берётся из `NN::FabKit::VERSION` (был хардкод `"0.1.0"` с момента создания плагина). Extension Manager теперь показывает реальную версию.

### Auto-update infrastructure
- Опубликован GitHub release **v0.7.0** с артефактом `nn_fabkit-0.7.0.rbz`. `update.json` на master ветке указывает на новую версию.
- Добавлен `.github/workflows/release.yml` — на push tag `v*` собирает .rbz через Python zipfile (из `plugin-sketchup/src/`) и публикует release с артефактом. Будущие версии можно публиковать одним `git tag vX.Y.Z && git push --tags`.

## [v0.0.20] — 2026-04-26

### Added (proper hollow mitre 45° + hole prototype)
- **`app-desktop/nc-export` 0.4.1 → 0.5.0** — два новых generator'а в `tube/rect_tube.py`:
  - **`rect_tube_with_hole_y_plus`** — hollow rounded tube + сквозное круглое отверстие через +Y стенку (Type 120 SoR + 2 Type 102 composite circles из 4 NURBS arcs degree 2 + post-факт mutation `inner_boundaries` для outer/inner +Y Type 144). 199 entities. CLI: `rect-tube-hole-y-plus --hole-x --hole-z --hole-radius`.
  - **`rect_tube_hollow_mitre_xl_45`** — proper mitre 45° на +X конце с эллиптическими углами. 4 outer/inner trapezoid planes + 4 outer/inner cylinder corners cut by mitre plane (boundary с elliptic arc Type 126 rational quadratic, weight √2/2 для 90° conic) + perpendicular endcap на x=0 + annular rounded-rect endcap в наклонной плоскости x=L+z. 186 entities. CLI: `rect-tube-hollow-mitre-45`.
- Helper `_nurbs_arc_90_3pts` — generic 90° rational quadratic Bezier из 3 explicit 3D ctrl points (для эллиптических arc'ов).
- Helper `_build_trimmed_cylinder_corner_mitre_xl` — четверть-цилиндр обрезан mitre-плоскостью на +X конце, boundary loop = axial + elliptic arc + axial + circular arc.
- Helper `_emit_outer_shell_mitre_xl` / `_emit_inner_shell_mitre_xl` / `_emit_mitre_annular_endcap`.
- Параметр `blank_outer` к `_emit_annular_endcap` (default True для backward compat). Mitre case передаёт False.
- Новые examples: `rect-tube-hole-y-plus_40x20x1.5_L600_h200_z0_r4__v0.4.1-prototype.igs`, `rect-tube-hollow-mitre-45_40x20x1.5_L600__v0.4.1-proper.igs`, `rect-tube-mitre-45_40x20_L600__v0.4.1-prototype.igs`.

### Verified in CypTube
- **Hole**: голубой контур по внутреннему периметру отверстия + зелёный по внешнему. Заказчик подтвердил визуально (отверстие на стороне 20-мм, центр в x=200).
- **Hollow mitre 45°**: full зелёный outer rounded-rect outline + голубой inner rounded-rect cut path на наклонной endcap. Зелёные direction-arrow фрагменты на углах радиусов сохраняются — то же поведение в SolidWorks-reference IGS, признано нормальным CypTube renderer artifact (в memory зафиксировано).

### Tests
- 38 → 44 тестов (6 новых для hollow mitre): entity counts, valid IGES serialization, file write, body extends correctly до x=L+hh / x=L-hh, elliptic arcs use weight √2/2, invalid inputs raise.

## [v0.0.19] — 2026-04-26

### Added
- **`app-desktop/nc-export` 0.4.0 → 0.4.1**: per-instance `iges_status` override в Entity. Document.py использует override если задан, иначе per-type default. Это позволяет blank-нуть конкретные entity instances вместо всего type'а.
- Outer Type 142 + Composite Curve endcap'ов теперь **blanked** (`01010500`). Inner Type 142 endcap'а (cavity hole) остаётся visible — голубой подсвет в CypTube как cut path работает.
- Новый baseline в `examples/`: **`rect-tube_40x20x1.5_L600__v0.4.1-hollow.igs`** — труба 40×20×1.5 R=2.25 длиной 600 мм (по факту часто используемая заказчиком). 184 entities.
- Все остальные `examples/*.igs` пере-сгенерированы под v0.4.1.

### Verified
- Outer endcap rounded-rect больше не подсвечивается зелёным как самостоятельный cut path, ходя feature recognition сохранилось (visible Type 144 use blanked Type 142 как outer_boundary — logical reference работает независимо от blank-флага). Inner endcap (cavity hole) — голубой как требуется.

## [v0.0.18] — 2026-04-26

### Added (LOD-2 hollow tube)
- **`app-desktop/nc-export` 0.3.0 → 0.4.0** — LOD-2 полая труба со стенкой. Структура: outer shell (4 plane + 4 cylinder corner) + inner shell (4 plane + 4 cylinder corner) + 2 annular endcap (Type 144 с inner_boundaries для отверстия от стенки). 184 entities на одну деталь, файл ~52 КБ.
- CLI флаг `--hollow` активирует LOD-2.
- Helpers в `tube/rect_tube.py`: `_emit_outer_shell`, `_emit_inner_shell`, `_emit_annular_endcap`, `_make_rounded_rect_boundary`, `_make_plain_rect_boundary`.

### Verified in CypTube
- `examples/rect-tube_60x10x1.5_L992_R2.25__v0.4.0-mimic-reference.igs` — наш hollow точно соответствует reference от заказчика (`60X10X992 21 шт.IGS`). CypTube показывает `Rect 10 × 60 R2.25 X 992`, голубым выделен inner endcap (cut path), визуализация без лишних диагональных линий.

### Changed (status flags)
- В D-section IGES для каждого entity type теперь выставляется правильный Status field per IGES 5.3 §2.2.4.4 (по конвенции SolidWorks/reference): subord entities (Type 100, 102, 110, 120, 126, 128) — **blanked** (не рендерятся в CAM viewport), top-level (Type 142, 144) — visible. Это устранило лишние iso-curves поверхностей в CypTube — теперь визуализация совпадает с reference.

### Changed — критическое исправление JSON-каталога
- **`gost-30245-rect-tube.json` v1.2 → v1.3**: ОТКАТ радиусов с ГОСТ 30245-2003 nominal (R=2.0×t) обратно на supplier convention (R=1.5×t для t≤6, R=2.0×t для t>6). Утренняя миграция v1.1→v1.2 была ошибкой: ГОСТ 30245 nominal — это «теоретический максимум», supplier (Юг-Сталь и др. электросварные тонкостенные по 8639/8645 «по соглашению») реально производит по 1.5×t.
- Подтверждение supplier-формулы двумя реальными замерами заказчика:
  - 60×10×1.5 → R=2.25 (1.5×1.5) — из reference IGES SolidWorks.
  - 40×20×2 → R=3.0 (1.5×2) — фактический замер заказчика, прислан в ходе тестирования.
- `06-sortament-ontology.md` — формула R=f(t) переписана под supplier convention. ГОСТ 30245 помечен как «теоретический максимум, supplier не производит».
- В nc-export функция `_gost_30245_radius` переименована в `_supplier_default_radius` с правильной формулой.

### Implementation notes
- Supplier convention (1.5×t для t≤6) — это нижняя граница допуска ГОСТ 30245-2003 (1.6t–2.4t) и эквивалент правила «по соглашению» в ГОСТ 8639-82 / 8645-68. Для feature recognition в CypTube критично использовать **фактический** радиус поставщика, а не nominal стандарта — иначе cut paths не совпадут с реальной геометрией трубы.
- Inner cylinder normals в LOD-2 идут радиально outward от axis (та же ориентация что outer cylinder). По convention хотелось бы inward (в сторону cavity), но Type 120 IGES такой ориентации не позволяет без дополнительного transformation matrix. CypTube корректно интерпретирует через annular endpcap trim — feature recognition работает.

### Known cosmetic issues
- 40×20×2 hollow в CypTube: outer endcap rounded-rect подсвечен зелёным как дополнительный cut path. Причина — наш BREP имеет дублирующиеся boundary edges (один в endcap, другой в adjacent side face), у SolidWorks reference эти edges shared. Косметика, не влияет на feature recognition.

## [v0.0.17] — 2026-04-26

### Added
- **`app-desktop/nc-export` 0.2.0 → 0.3.0** — LOD-1 со скруглёнными углами профиля. Главный milestone: **CypTube делает feature recognition нашего IGES** — для трубы 60×10×1.5 R=2.25 L=992 показывает в title `Rect 10 × 60 R2.25 X 992`, идентично reference-файлу заказчика.
- Новые entity-классы в `iges/entities.py`: `SurfaceOfRevolution` (Type 120) и `NurbsCurve` (Type 126).
- Helpers в `tube/rect_tube.py`:
  - `_nurbs_arc_90` — 90° arc как Type 126 NURBS degree 2 (3 ctrl points с весами [1, √2/2, 1]) — работает в произвольной плоскости (не только параллельной XT-YT как Type 100).
  - `_build_trimmed_cylinder_corner` — четверть-цилиндр на углу профиля (10 entities: axis line + generatrix + 2 axial edges + 2 NURBS arcs + composite + Type 120 + COS + Type 144).
  - `_build_rounded_endcap` — endcap с rounded-rectangle boundary (12 entities: 4 lines + 4 NURBS arcs + composite + Type 128 plane + COS + Type 144).
- CLI: `--radius R` (явный радиус) или auto по ГОСТ 30245-2003. `--no-radius` оставлен для legacy mode.
- 38 тестов (было 35) — добавлены тесты для default rounded mode (96 entities, 10 Type 144, 4 Type 120, 16 Type 126), explicit radius, no-radius back-compat.

### Verified in CypTube
- `examples/rect-tube_60x10x1.5_L992_R2.25__v0.3.0-mimic-ref.igs` (96 entities, 26 КБ) — полностью повторяет reference structure SolidWorks. Title в CypTube: `Rect 10 × 60 R2.25 X 992` ✓ (точно как в reference от заказчика).
- `examples/rect-tube_40x20x2_L600__v0.3.0-rounded.igs` (96 entities) — стандартная труба с auto-radius по ГОСТ (R=4.0).
- `examples/rect-tube_40x20x2_L600__v0.3.0-noradius.igs` (48 entities) — back-compat с v0.2.0.

### Implementation notes
- **Распознавание профиля как `Rect WxH RR`** требует BREP с правильно ориентированными boundary loops (CCW от outer normal) и Type 144 trim над Type 128 (плоские грани) и Type 120 (цилиндры).
- **Type 100 (Circular Arc) не подошёл** для arcs трубных скруглений — стандарт требует «arc lies in plane parallel to XT-YT», а наши arcs в плоскостях параллельных YZ. Решение — Type 126 NURBS degree 2 (универсальная замена для arcs в произвольной ориентации, что и делает SolidWorks).
- **Размеры в title CypTube** — это **внутренний просвет** трубы (для reference 60×10 → показывает 10×60). У нашего LOD-1 (без полости) CypTube тоже показывает 10×60, потому что вычисляет от boundary trimmed surface, не зная о стенке. Корректность размеров inner cavity подтвердится после LOD-2.

### Known limitations
- **Полая структура (LOD-2) не реализована** — труба моделируется как сплошное тело со скруглениями. Reference SolidWorks — полая (есть outer surface + inner surface + annular endcap). Следующий шаг: 4 inner plane + 4 inner cylinder + endcaps с inner_boundaries в Type 144.

## [v0.0.16] — 2026-04-26

### Added
- `docs/knowledge-base/11-gost-profile-tubes-radii.md` (~733 строки) — справочник по российским ГОСТам на профильные трубы (30245-2003, 30245-2012, 8645-68, 8639-82, 13663-86, 32931-2015) с фокусом на радиусах скругления. Сравнительная таблица типоразмеров, формулы R=f(t), допуски, практика поставщиков, рекомендации для генератора.
- В `gost-30245-rect-tube.json` добавлен **`supplier`-блок** с метаданными ООО «Юг-Сталь» (Краснодар, прайс 2026-04). В каждой записи `items[].derived` появилось поле `price_per_m_rub` (placeholder под цены, пока null).

### Changed
- **`gost-30245-rect-tube.json` v1.1 → v1.2**: пересчитан `outer_radius_mm` для всех 62 типоразмеров с формулы `R = 1.5×t` на номинал ГОСТ 30245-2003 п. 3.5: `R = 2.0×t` (t ≤ 6 мм), `R = 2.5×t` (6 < t ≤ 10 мм), `R = 3.0×t` (t > 10 мм). Старая формула давала занижение радиуса на ~33% и ломала feature recognition в CypTube для t ≥ 2 мм. Sync'нуто в копию плагина `plugin-sketchup/.../catalogs/`.
- `06-sortament-ontology.md` — раздел «Правила выбора радиуса гиба» обновлён под ГОСТ 30245-2003 (формула R=2t/2.5t/3t, допуск 1.6t–2.4t для t≤6, упоминание о тонкостенных по 8639/8645).
- **`app-desktop/nc-export` 0.1.0 → 0.2.0**: BREP-структура с Type 144 trim wrapper. Каждая грань теперь = 8 entities (4 Line + Composite Curve + NURBS Surface + Curve on Parametric Surface + Trimmed Surface). Box LOD-1 = 48 entities (вместо 12 на Type 122). Type 122 Tabulated Cylinder выкинут — CypTube/Friendess его не поддерживает (в reference-файле заказчика 0 instances), правильное представление плоской грани — Type 128 NURBS degree 1×1 поверх Type 144 trim.
- nc-export ось трубы переориентирована с Z на **X** — конвенция Friendess (X=axial, Y=ширина, Z=высота).
- Имена `examples/*.igs` теперь включают версию writer'а (`...__v0.2.0-brep.igs`) — чтобы в title CypTube было видно какая версия открыта.

### Added (entities)
- `iges/entities.py`: новые классы `NurbsSurface` (Type 128 degree 1×1, 2×2 control points), `CompositeCurve` (Type 102), `CurveOnParametricSurface` (Type 142), `TrimmedSurface` (Type 144).
- 35 тестов (было 34) — добавлен `test_rect_tube_box_trimmed_surface_references_nurbs`, обновлены counts (8/48 entities вместо 1/6).

### Implementation notes
- **CypTube делает feature recognition по BREP**: для reference 60×10×992 в title окна показывает `Rect 10 × 60 R2.25 X 992` — то есть автоматически распознаёт тип профиля, размеры (это **внутренний** просвет полой трубы, не внешний габарит), радиус скругления и длину. Без скруглений и без полой структуры (LOD-2) этого не получить.
- **Reference 60×10×1.5 R=2.25** соответствует формуле `R = 1.5×t` (тонкостенная, 8639/8645 «по соглашению»), не ГОСТ 30245. Тонкостенные позиции в JSON формально переведены на ГОСТ 30245 для единообразия — требует подтверждения замером штангенциркулем фактических партий Юг-Сталь.
- `examples/*.IGS` (uppercase, reference от заказчика) добавлены в `.gitignore` — G-section может содержать пути с именами клиентов.

### Known limitations (нерешённое)
- Скругления углов профиля ещё не реализованы (Type 100 directrix + Type 120 Surface of Revolution) — следующий шаг.
- Полая труба LOD-2 (4 inner side faces + endcaps с отверстием от стенки через `inner_boundaries` в Type 144) — следующий шаг после скруглений. Без неё CypTube не показывает корректный «внутренний» размер трубы.

## [v0.0.15] — 2026-04-25

### Added
- **`app-desktop/nc-export/`** — новый Python standalone-проект v0.1.0 (ADR-017): собственный IGES-конвертёр для CNC. Stdlib-only, Python 3.10+, нулевые runtime-зависимости.
- IGES core writer (`iges/document.py`, `iges/entities.py`, `iges/format.py`): корректный 80-col fixed-format, S/G/D/P/T-секции, sequence numbering, топ-сорт по cross-references, CRLF line endings, ASCII без BOM. Hollerith-строки, форматирование чисел без экспонент, back-pointers в P-секции.
- Поддержанные entities: Type 110 (Line), Type 100 (Circular Arc), Type 122 (Tabulated Cylinder).
- Шаг 1 — `nn-fabkit-nc-export hello-surface --width W --length L`: одна Type 122 поверхность W×L (smoke-тест совместимости с CAM, 2 entities).
- Шаг 2 — `nn-fabkit-nc-export rect-tube --width W --height H --wall t --length L --no-radius`: closed box LOD-1 без скруглений (4 боковых грани + 2 endcaps, surface-модель из 12 entities).
- 34 unit-теста (pytest) на низкоуровневое форматирование, структурную валидность IGES (80-col, T-section счётчики), геометрию обоих CLI-команд.
- `app-desktop/nc-export/examples/` — образцы `.igs` для тестирования в Tube Pro / Lantek / FreeCAD: `hello-surface_w40_l600.igs`, `rect-tube-box_40x20x2_L600.igs`.

### Implementation notes
- Координатная система: ось трубы — Z, профиль в XY (выровнено с `plugin-sketchup` ProfileGenerator). Единицы — мм (G-section unit flag = 2). Минимальная пользовательская точность — 0.001 мм. Approx max coord — 13000 мм (13 м реалистичный потолок длины трубы для NC).
- Все 6 граней box'а представлены через Type 122 (включая endcaps) — единообразный writer, минимум кода. Type 128 / Type 144 подключим на следующих шагах (скругления Type 100 как directrix, endcaps с inner+outer trimming для отверстия от стенки).
- Ориентация Type 122 directrix-ов выбрана так, чтобы нормали смотрели наружу (cross-product `dC/dt × generatrix_vector`). Не критично для visual model, но валидно для NC feature recognition.
- Решение по языку standalone (намечалось как ADR-019): **Python**. Обоснование — research [10-iges-for-tube-nc.md](docs/knowledge-base/10-iges-for-tube-nc.md): pythonocc-core слишком тяжёл (~200 МБ бандл), Rust добавляет 3-4 недели против 1-2 на Python. Для DXF-writer'а в будущем — `ezdxf` готовая библиотека.
- TCP/JSON приёмник от Ruby-плагина — следующий шаг (после подтверждения совместимости surface-модели с реальным CAM на стороне заказчика/разработчика).

### Known limitations
- Не BREP, не Type 144 — surface-модель без сшивки граней. Tube Pro (Friendess) и аналоги, по research, лучше работают с surface-моделями чем с Type 186 BREP, но это требует эмпирической проверки.
- Скругления углов профиля (LOD-1 → LOD-2) ещё не поддержаны — `--no-radius` единственный режим.
- Endcaps без отверстия от стенки — труба моделируется как «коробка», не как «полая труба».

## [v0.0.14] — 2026-04-25

### Added
- Плагин v0.6.0: **Inspector — постоянная боковая панель плагина** (Sprint A spec-03). `UI::HtmlDialog` с тремя секциями: header (бренд + версия), MetalFab — сортамент трубы (62 типоразмера, поиск по подстроке, лайв-фильтр), Selection (заглушка под Sprint C). Vanilla JS + минимальный CSS, без сборки и без runtime-зависимостей. Тёмная тема через `prefers-color-scheme`. Позиция и размер сохраняются между сессиями (`preferences_key = "NN_FabKit_Inspector"`).
- Меню `Extensions → NN FabKit → Открыть Inspector` — точка входа.
- Каталог трубы передаётся в JS через `execute_script` на колбэке `nn_inspector_ready` (JSON инлайнится как JS-литерал, U+2028/U+2029 эскейпятся вручную).

### Implementation notes
- `nn_fabkit/ui/inspector.rb` (~110 строк) — singleton-контроллер, переиспользует один HtmlDialog. `reset!` нужен для hot-reload в Ruby Console.
- HTML/CSS/JS живут в `nn_fabkit/ui/html/inspector.{html,css,js}`. Frontend stack — `system-ui` шрифт-стек, без custom fonts; палитра industrial-нейтральная (scope-A spec-03, без брендинга).
- Sprint B/C добавят: кнопка «Создать», SelectionObserver и редактор параметров. Visual brand (B-scope spec-03) — отдельный sprint при подтверждении заказчиком.

## [v0.0.13] — 2026-04-24

### Added
- Плагин v0.5.0: **MCP-мост Claude ⇄ SketchUp** (Sprint A spec-02). Ruby сторона — `NN::FabKit::Mcp::Server` (TCP 127.0.0.1:9876, JSON-RPC 2.0, line-delimited, connection-per-request, `UI.start_timer` polling без Thread.new). MVP tools: `eval_ruby` (universal escape hatch с захватом stdout), `get_scene_info` (быстрый снапшот с selection brief), `dump_model` (полный SkpDump через MCP).
- Меню `Extensions → NN FabKit → MCP сервер → Запустить / Остановить / Статус`. Запуск явный с предупреждением про мощь `eval_ruby`. По умолчанию сервер не активен — открытие порта только по явному действию пользователя.
- `mcp-bridge/` — отдельный Python пакет `nn-fabkit-mcp` (FastMCP framework). Tools зеркалят Ruby-сторону. Установка: `pip install -e mcp-bridge/` + `claude mcp add nn-fabkit -- python -m nn_fabkit_mcp`. README с полным install-workflow.
- В `Extensions → NN FabKit → О плагине…` добавлен индикатор статуса MCP-сервера.

### Implementation notes
- Архитектурный pivot — **ADR-018 supersedes ADR-001**: вместо форка `mhyrr/sketchup-mcp` (license=null, форкать нельзя) — собственная реализация, опираясь на публично описанные паттерны (TCP+JSON-RPC+timer polling — общеизвестные идиомы). Код mhyrr НЕ копировался.
- Папка `mcp-corpus/` оставлена под свою роль (MCP к корпусу примеров, ADR-015), `mcp-bridge/` — новая папка под мост к работающему SketchUp процессу. В Claude Code оба сервера могут работать одновременно.
- Предупреждение безопасности: после запуска MCP сервера любой процесс на 127.0.0.1 может выполнять `eval_ruby` в SU. Bind строго на loopback, никаких external соединений.

## [v0.0.12] — 2026-04-24

### Added
- `docs/specs/spec-02-mcp-bridge.md` — спецификация MCP-моста SketchUp ⇄ Claude. Архитектура: TCP сервер в плагине (`NN::FabKit::Mcp::Server`, 127.0.0.1:9876, line-delimited JSON-RPC 2.0, `UI.start_timer` polling) + Python пакет `nn_fabkit_mcp` (FastMCP framework). MVP tools: `eval_ruby`, `get_scene_info`, `dump_model` плюс высокоуровневые. Цель — ускорить итерации разработки на порядок (3 минуты install цикл → 5 секунд eval_ruby).
- `docs/specs/spec-03-plugin-ui-redesign.md` — спецификация UI редизайна. Замена inputbox-driven workflow на постоянную боковую панель «NN FabKit Inspector» через `UI::HtmlDialog`. Vanilla JS + минимальный CSS (без React/build step). Sortament browser + Selection inspector + Toolbar. Default scope — UI/UX (A); visual brand (логотип, иконки, цветовая схема — B) — отдельный sprint при подтверждении заказчиком.
- **ADR-018 добавлен в `docs/knowledge-base/09-architecture-decisions.md`** — MCP-мост собственной реализации, supersedes ADR-001. Причина: `mhyrr/sketchup-mcp` (на которое ссылался ADR-001) не имеет LICENSE — по умолчанию all-rights-reserved, форкать нельзя. Используем только публично описанные паттерны (TCP+JSON-RPC+timer polling — общеизвестные идиомы), код не копируем.

### Changed
- ADR-001 помечен как `superseded ADR-018` в `memory/reference_adr_map.md` и в Notion ADR-странице.

## [v0.0.11] — 2026-04-24

### Added
- Репозиторий опубликован на GitHub: https://github.com/ra-artnft/NN_FabKit (public).
- `update.json` в корне репо — manifest для Updater'а. Формат `{ latest_version, rbz_url, release_notes }`. Раздаётся через `https://raw.githubusercontent.com/ra-artnft/NN_FabKit/master/update.json`.
- GitHub Release `v0.4.1` с прикреплённым `nn_fabkit-0.4.1.rbz` — официальный канал распространения.
- Плагин v0.4.1: `Updater::DEFAULT_MANIFEST_URL` теперь указывает на raw GitHub URL — `Проверить обновления…` работает без первоначальной ручной настройки. `Сменить URL обновлений…` остаётся для приватных каналов / форков.
- Команда `CheckUpdate.ensure_manifest_url` упрощена — не спрашивает URL при первом запуске (default уже валиден), пользователь сразу видит результат проверки.

## [v0.0.10] — 2026-04-24

### Added
- Плагин v0.4.0: **IGES wireframe-экспорт одной трубы** (`Extensions → NN FabKit → MetalFab → Экспорт «Профильная труба» в IGES…`). Минимальное подмножество IGES 5.3 — Type 110 (Line) + Type 100 (Circular Arc), ASCII fixed 80-col format со всеми пятью секциями (S/G/D/P/T). Выгружает endcap-контуры на z=0 и z=length (outer + inner) плюс 4 силуэтных вертикальных линии с каждого контура. Файл читается любым IGES viewer'ом — даёт визуальный контроль геометрии. Это первый шаг к полному собственному IGES-конвертёру (ADR-017); полный surface-model BREP (Type 120/122/144) — отдельный sprint в `app-desktop/`.
- Плагин v0.4.0: **удалённое обновление плагина** (`NN FabKit → Проверить обновления…` + `Сменить URL обновлений…`). Manifest формат — JSON `{ latest_version, rbz_url, release_notes }` по любому URL (заказчик выбирает хостинг). URL хранится в `Sketchup.read_default("NN_FabKit", "update_manifest_url")` между сессиями. Первый запуск спрашивает URL; дальше — точечная проверка по запросу. Скачка через `Net::HTTP` (https + редиректы), установка через `Sketchup.install_from_archive`. Рестарт SU всё ещё нужен после установки (поведение Extension Manager, см. `feedback_sketchup_install_restart.md`).
- В `nn_metalfab` теперь записывается `length_mm` — нужно IGES-экспортёру (раньше падал в bounds.depth с конверсией единиц, что плохо после Make Unique / cut).

### Implementation notes
- Структура `metalfab/iges_exporter/wireframe.rb` (~280 строк) — полный IGES writer без зависимостей: hollerith strings, fixed 80-col padding, sequence numbering, P→D pointer back, G section с 25 параметрами. Открыто к расширению (Type 120 surface of revolution для углов трубы — следующий шаг к surface model).
- `nn_fabkit/updater.rb` — Net::HTTP (stdlib) + JSON.parse. Manifest URL заглушка `https://example.invalid/...`, заказчик задаёт свой при первом запуске (любой статический хостинг — GitHub Releases, S3, собственный сервер).

## [v0.0.9] — 2026-04-24

### Changed
- Каталог `gost-30245-rect-tube.json` расширен с 28 до **62 типоразмеров** на основе реального прайса ООО «Юг-Сталь» (Краснодар) — основного поставщика заказчика-0. Schema bump 1.0 → 1.1: добавлены поля `derived.supplier_stock_lengths_mm` (фактический длины проката) и `_mass_note` (для аномалий и теоретических значений). Сохранены крупные типоразмеры (`80×80×4`…`180×180×6`) по ГОСТ как «не у поставщика, теоретические». Подробности в `docs/knowledge-base/CHANGELOG.md`.
- Копия каталога в плагине синхронизирована, плагин v0.3.2 → v0.3.3. Меню «Создать «Профильная труба»…» теперь предлагает 62 опции.
- Откат демо-сборки рамки перегородки (`build_partition_frame.rb`, sprint A) — компоновка transformations была преждевременной, возвращены к чистому генератору `RectTube`. Git revert `3b91446`, история сохранена.

## [v0.0.8] — 2026-04-24

### Changed
- Плагин v0.3.2: визуально упрощённая геометрия профильной трубы. Дуговые рёбра внешнего и внутреннего контура помечаются как `soft + smooth` после построения — 8 сегментов на угол перестают рисоваться отдельными линиями, профиль выглядит как одна гладкая дуга. После Follow Me все вертикальные рёбра, не лежащие на 4 «угловых» прямых (X=±hw, Y=±hh), также помечаются soft+smooth — боковая поверхность трубы рендерится как один цилиндр-сегмент, не как 32-гранник. Геометрия не меняется (NC-конвертёр по-прежнему получает 8 точек на радиус + аналитический outer_radius_mm в `nn_metalfab`); меняется только rendering.
- Плагин v0.3.2: `ext.check if ext.respond_to?(:check)` в loader сразу после `register_extension` — попытка форсировать загрузку main.rb в той же сессии после Install. Не всегда помогает (Extension Manager не пересканирует Plugins folder в runtime), но удешевляет сценарий «поставил → сразу хочу пользоваться» для случаев, когда SU всё-таки готов resync. В большинстве случаев рестарт SU остаётся обязательным.

## [v0.0.7] — 2026-04-24

### Fixed
- Плагин v0.3.1: **`NoMethodError: undefined method 'add_loop' for #<Deleted Entity>`** при создании профильной трубы. Inner loop стенки строился через `entities.add_line` по сегментам, но каждая такая линия в плоскости уже существующей outer face расщепляет её — outer становится Deleted Entity к моменту вызова `add_loop`. Возврат к стандартной SketchUp-идиоме: `add_face(inner_pts) → erase!` поверх outer автоматически образует inner loop (отверстие). Плюс fallback по `entities.grep(Sketchup::Face).max_by(&:area)` если outer всё-таки не выживает.

## [v0.0.6] — 2026-04-24

### Fixed
- **Сборка `.rbz` под Windows ломала установку в SketchUp.** Rakefile использовал `[System.IO.Compression.ZipFile]::CreateFromDirectory` через PowerShell — под .NET Framework 4.x он пишет нативные `\` в именах файлов архива, что нарушает PKZIP App Note (требует `/`) и SketchUp Extension Manager молча отвергает такой `.rbz` (диалога с ошибкой нет, просто ничего не происходит). Detected на SU 2025 Windows 2026-04-24 при попытке поставить `nn_fabkit-0.3.0.rbz`. Rakefile теперь упаковывает архив через Python `zipfile` (гарантированно `/`); fallback на `zip(1)` для Unix; явный fail с инструкцией если Python отсутствует. На Linux/macOS поведение не меняется.

## [v0.0.5] — 2026-04-24

### Added
- Плагин v0.3.0: первый параметрический генератор металл-ветки `NN::MetalFab::ProfileGenerator::RectTube` — LOD-1 геометрия профильной трубы (rounded rect сечение со скруглёнными углами и реальной стенкой, Follow Me экструзия по +Z, бюджет ≤60 faces / ≤100 edges, 8 сегментов на радиус).
- Команда меню `Extensions → NN FabKit → MetalFab → Создать «Профильная труба»…` — выбор типоразмера / марки стали / длины из каталога ГОСТ 30245-2003, создаёт definition с метаданными `nn_metalfab` (ADR-005) и DC-атрибутами для Component Options.
- Структура `plugin-sketchup/src/nn_fabkit/metalfab/` под ветку `NN::MetalFab` — модули `catalog`, `attr_dict`, `dc_attrs`, `profile_generator/rect_tube`, `commands/create_rect_tube`. Каталог `catalogs/gost-30245-rect-tube.json` — копия канонического `docs/knowledge-base/gost-30245-rect-tube.json`, доставляется в `.rbz`.
- Радиус гиба считается по формуле R = 1.5 × t для t ≤ 6 мм и R = 2 × t для t > 6 мм (06-sortament-ontology, ADR-014). Каталог переопределяет формулу фактическими значениями ГОСТ.

### Implementation notes
- DC-атрибуты на этой итерации помечены `_access = "VIEW"` (readonly) — встроенный DC-движок умеет менять только scale, не топологию (ADR-002). Регенерация при изменении параметров — следующий sprint (DC-EntityObserver, блок 5.5 spec-01).
- Имена материалов — наша конвенция `«Труба <typesize> <grade>»` (ADR-016, **без** OCL-словаря `lairdubois_opencutlist_*`).

## [v0.0.4] — 2026-04-23

### Added
- `docs/specs/spec-01-dc-rework-for-iges.md` — продуктовая спецификация на этап 1, MetalFab: доработка существующих DC заказчика «Профильная труба» и «Лист» с LOD-0 (box) на LOD-1 (с радиусами и стенкой) + метаданные `nn_metalfab`. Цель — пригодность к собственному IGES-конвертёру (ADR-017). Содержит: scope, критерии приёмки, блоки работы, тест-план на корпусе, открытые вопросы к заказчику.
- Аналитический pass по 4 моделям корпуса (без артефакта в репо — наблюдения интегрированы в spec-01 §2 «Контекст из корпуса» и в открытые вопросы §8).

### Changed
- Привязка к ADR в CLAUDE.md, memory и Notion обновлена: учтены ADR-014 (LOD-0/1/2 + бюджет геометрии), ADR-016 (OCL — только референс, не пишем `lairdubois_opencutlist_*` на компоненты, supersedes ADR-003), ADR-017 (собственный IGES-конвертёр в MVP, без SolidWorks-посредника, supersedes ADR-009). Pipeline продукта переформулирован соответственно. ADR-009 и ADR-003 помечены как superseded в навигационных табличках.

## [v0.0.3] — 2026-04-23

### Added
- Первое наполнение корпуса: `corpus/examples/01..04` — четыре реальных проекта заказчика-0, дампы прогнаны через плагин v0.2.0. `notes.md` — заглушки с TODO, ждут ответов от заказчика.
- `corpus/README.md` — структура папки примера, статус наполнения, правила приватности, процесс пополнения.
- В CLAUDE.md и memory `project_overview.md` зафиксирована Pipeline-формулировка продукта от заказчика-0 (corpus → квази-обучение → генерация типовых моделей по образцу + параллельная доработка существующих DC под IGES-экспорт через SolidWorks-посредника).

### Changed
- `.gitignore` исключил `corpus/examples/`, `*.skp`, `*.dump.json`, `*.skp_dump.json` — внутри дампов в `model.path` лежат ФИО клиентов.

## [v0.0.2] — 2026-04-23

### Added
- `CLAUDE.md` в корне — карта проекта для будущих сессий: источники истины (Notion + kb), навигационная таблица, доменный словарь, конвенции кода плагина.
- Плагин v0.2.0: команда `Extensions → NN FabKit → Dump в JSON…` — обёртка над `NN::FabKit::SkpDump`, синхронизированной копией `docs/knowledge-base/tools/skp_dump.rb` (без автозапуска при загрузке).

### Changed
- В `plugin-sketchup/README.md` обновлены разделы «Текущая функциональность», «Структура», «Следующие шаги».

## [v0.0.1] — 2026-04-22

### Added
- Инициализация монорепо, git-репозиторий на уровне корня.
- Скелет плагина `plugin-sketchup/` v0.1.0: меню `Extensions → NN FabKit → О плагине…`, messagebox с версией плагина и SketchUp.
- Rakefile с тасками `build`, `clean`, `install` (без gem-зависимостей).
- Заглушки `app-desktop/`, `mcp-corpus/`, `corpus/` с README, описывающими будущую роль и ADR-контекст.
- Корневой `README.md`, `CHANGELOG.md`, `.gitignore`.
