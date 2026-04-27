# encoding: UTF-8

module NN
  module MetalFab
    module LayoutGen
      # Генератор A4 portrait LayOut-документа с cut-list для металлоконструкций.
      #
      # Что попадает на лист:
      # - Title block в правом верхнем углу: проект, заказчик, дата, масштаб
      # - 4 viewport'а (2×2 grid): Изометрия, Сверху, Спереди, Сбоку (справа).
      #   Изометрия — основной «объёмный» вид (по ГОСТ — прямоугольная изометрия,
      #   eye на (+X, −Y, +Z) от центра bbox, ParallelProjection).
      #   3 ортогональных вида (Top/Front/Right) — стандартные SU-направления,
      #   тоже ParallelProjection, чтобы расстояния на чертеже отражали реальные.
      # - Cut-list table внизу: группировка по типоразмеру (`nn_metalfab.typesize`),
      #   с колонками № / Типоразмер / ГОСТ / Сталь / Кол-во / Σ Длина / Σ Масса +
      #   строка ИТОГО.
      #
      # Для viewport'ов нужны **scenes** в .skp с правильными cameras. При первом
      # вызове `ensure_fabkit_scenes` создаёт 4 страницы (FabKit::Iso/Top/Front/
      # Right) с auto-fit камерами по bounds модели. При повторных вызовах
      # переиспользует существующие.
      #
      # Реквизиты title block — пока хардкод-default'ы в `default_meta`, опционально
      # перекрываются `meta` хэшем.
      #
      # Workflow:
      #   1. Если активная SU-модель не сохранена — нет viewport'ов (placeholder).
      #   2. ensure_fabkit_scenes — создать недостающие FabKit-сцены с cameras.
      #   3. model.save — Layout::SketchUpModel читает .skp с диска, не in-memory.
      #   4. Генерируем .layout, опционально сразу export PDF.
      #   5. Если файл открыт в LayOut — `Errno::EACCES` (close first).
      module TemplateCutList
        PAGE_W_MM = 210
        PAGE_H_MM = 297
        MARGIN_MM = 10

        TITLE_BLOCK = { x: 100, y: 10, w: 100, h: 40, label_w: 22 }.freeze
        HEADER_BLOCK = { x: 100, y: 5, w: 100, h: 5 }.freeze

        # 2×2 viewport grid в области (10, 60) .. (200, 200) = 190 × 140 мм.
        # Каждая ячейка: viewport 92.5 × 60 + label 5mm сверху + dim-area 7mm снизу.
        # Зазоры между ячейками 3mm.
        VIEWPORT_AREA_X = 10
        VIEWPORT_AREA_Y = 55
        VP_W = 92.5
        VP_H = 60
        VP_LABEL_H = 5
        VP_GAP_X = 5
        VP_GAP_Y = 3
        DIM_AREA_H = 7   # 7mm под viewport под размерную линию (line + tick + label)
        DIM_TICK_HALF_MM = 1.5
        DIM_LINE_W_MM = 0.05  # тонкий rectangle = размерная линия

        # 4 viewport'а: Изометрия (основная), Сверху, Спереди, Сбоку.
        # Раскладка:
        #   [ Изометрия ] [ Сверху    ]
        #   [ Спереди   ] [ Сбоку     ]
        #
        # standard_view: значение из Layout::SketchUpModel constants (TOP_VIEW,
        # FRONT_VIEW, RIGHT_VIEW). Для них Layout сам рисует ortho-проекцию,
        # не зависит от scenes. Для :iso стандартный ISO_VIEW Layout-а даёт
        # фронт-правый-сверху iso — подходит.
        VIEWPORTS = [
          { key: :iso,   label: "Изометрия",      col: 0, row: 0, std_view: :iso   },
          { key: :top,   label: "Сверху",         col: 1, row: 0, std_view: :top   },
          { key: :front, label: "Спереди",        col: 0, row: 1, std_view: :front },
          { key: :right, label: "Сбоку (справа)", col: 1, row: 1, std_view: :right }
        ].freeze

        # Колонки cut-list:
        #   Длина — длина ОДНОЙ детали (после mitre/trim). Дает прозрачную
        #     спецификацию: «4 шт по 1350 мм», а не только Σ.
        #   Кол-во × Длина = Σ Длина.
        #   Группировка: typesize × length_per_piece (с округлением до 1мм).
        CUT_LIST = {
          x: 10, y: 215, header_h: 8, row_h: 6,
          cols: [
            ["№",           8],
            ["Типоразмер", 28],
            ["ГОСТ",       28],
            ["Сталь",      18],
            ["Длина, мм",  22],
            ["Кол-во, шт", 18],
            ["Σ Длина, мм",30],
            ["Σ Масса, кг",38]
          ].freeze
        }.freeze

        module_function

        # Главный entry point.
        #
        # output_path — куда сохранить .layout
        # meta        — Hash с реквизитами title block (см. default_meta).
        # pdf_path    — опционально, тут же экспортнуть PDF в указанный путь.
        #
        # Возвращает Hash со статистикой и путями.
        def generate(output_path:, meta: nil, pdf_path: nil)
          model = ::Sketchup.active_model
          raise "Нет активной SketchUp-модели" unless model

          meta = default_meta.merge(meta || {})

          # Save .skp чтобы Layout::SketchUpModel взял свежее состояние модели.
          if model.path && !model.path.empty?
            model.save
          end

          doc = build_document(model, meta)

          File.delete(output_path) if File.exist?(output_path)
          doc.save(output_path)

          rows_count, totals = collect_cut_list(model)
          stats = {
            "saved_to"        => output_path,
            "size_kb"         => (File.size(output_path) / 1024.0).round(2),
            "cut_list_groups" => rows_count,
            "total_count"     => totals[:count],
            "total_length_mm" => totals[:length_mm].round(0),
            "total_mass_kg"   => totals[:mass_kg].round(2)
          }

          if pdf_path
            pdf_stats = export_pdf(layout_path: output_path, pdf_path: pdf_path)
            stats["pdf_path"] = pdf_stats["pdf_path"]
            stats["pdf_size_kb"] = pdf_stats["size_kb"]
          end

          stats
        end

        # Экспорт уже существующего .layout в PDF.
        def export_pdf(layout_path:, pdf_path:)
          raise "LayOut-файл не найден: #{layout_path}" unless File.exist?(layout_path)
          File.delete(pdf_path) if File.exist?(pdf_path)
          doc = ::Layout::Document.open(layout_path)
          doc.export(pdf_path)
          {
            "pdf_path" => pdf_path,
            "size_kb"  => (File.size(pdf_path) / 1024.0).round(2)
          }
        end

        # ----- Standard views + scale fitting -----

        # Layout::SketchUpModel constants — встроенные ortho/iso views Layout-а.
        # Их Layout сам отрисует правильно, не нужны .skp scenes.
        STD_VIEW_MAP = {
          top:   ::Layout::SketchUpModel::TOP_VIEW,
          front: ::Layout::SketchUpModel::FRONT_VIEW,
          right: ::Layout::SketchUpModel::RIGHT_VIEW,
          iso:   ::Layout::SketchUpModel::ISO_VIEW
        }.freeze

        # Подсчёт "model dimensions visible in this view" (в model units, обычно
        # дюймы) для auto-fit scale.
        def model_visible_dims(view_key, bounds)
          case view_key
          when :top   then [bounds.width,  bounds.height]   # XY plane
          when :front then [bounds.width,  bounds.depth]    # XZ plane (looking along Y)
          when :right then [bounds.height, bounds.depth]    # YZ plane (looking along X)
          when :iso
            # Iso isometric: видимая диагональ ~ диагональ bbox * cos(30°)
            diag = Math.sqrt(bounds.width**2 + bounds.height**2 + bounds.depth**2)
            [diag * 0.85, diag * 0.85]
          else raise "unknown view key: #{view_key}"
          end
        end

        # Compute scale factor (model_unit / paper_unit) для auto-fit модели
        # в viewport (vp_w_mm × vp_h_mm). Минимум из 2 ratio (чтобы fit обе оси),
        # с запасом 5% по краям.
        def fit_scale(view_key, bounds, vp_w_mm, vp_h_mm)
          mw, mh = model_visible_dims(view_key, bounds)
          # Layout scale = paper / model. Меньше = модель более «зум-аутом».
          scale_w = (vp_w_mm.mm * 0.95) / mw
          scale_h = (vp_h_mm.mm * 0.95) / mh
          [scale_w, scale_h].min
        end

        # ----- Document build -----

        def default_meta
          {
            "project"   => "Проект NN FabKit",
            "customer"  => "—",
            "date"      => Time.now.strftime("%Y-%m-%d"),
            "scale"     => "1:10",
            "header"    => "NN FabKit — MetalFab"
          }
        end

        def build_document(model, meta)
          doc = ::Layout::Document.new
          pi = doc.page_info
          pi.width = PAGE_W_MM.mm
          pi.height = PAGE_H_MM.mm
          pi.left_margin = MARGIN_MM.mm
          pi.right_margin = MARGIN_MM.mm
          pi.top_margin = MARGIN_MM.mm
          pi.bottom_margin = MARGIN_MM.mm
          doc.units = ::Layout::Document::DECIMAL_MILLIMETERS
          doc.precision = 0.1

          page = doc.pages.first
          layer = doc.layers.first

          draw_title_block(doc, page, layer, meta)
          draw_viewports(doc, page, layer, model)
          draw_cut_list(doc, page, layer, model)
          doc
        end

        def draw_title_block(doc, page, layer, meta)
          tb = TITLE_BLOCK
          add_rect(doc, page, layer, tb[:x], tb[:y], tb[:w], tb[:h])
          3.times do |i|
            add_rect(doc, page, layer, tb[:x], tb[:y] + (i + 1) * 10, tb[:w], 0.001)
          end
          add_rect(doc, page, layer, tb[:x] + tb[:label_w], tb[:y], 0.001, tb[:h])

          rows = [
            ["Проект",   meta["project"]],
            ["Заказчик", meta["customer"]],
            ["Дата",     meta["date"]],
            ["Масштаб",  meta["scale"]]
          ]
          value_w = tb[:w] - tb[:label_w]
          rows.each_with_index do |(label, value), i|
            add_text_center(doc, page, layer,
                            tb[:x] + 1, tb[:y] + i * 10, tb[:label_w] - 1, 10, label)
            add_text_center(doc, page, layer,
                            tb[:x] + tb[:label_w] + 1, tb[:y] + i * 10, value_w - 1, 10, value)
          end

          hb = HEADER_BLOCK
          add_rect(doc, page, layer, hb[:x], hb[:y], hb[:w], hb[:h])
          add_text_center(doc, page, layer, hb[:x], hb[:y], hb[:w], hb[:h], meta["header"])
        end

        def draw_viewports(doc, page, layer, model)
          path = model.path
          if path.nil? || path.empty?
            add_rect(doc, page, layer, VIEWPORT_AREA_X, VIEWPORT_AREA_Y, 190, 140)
            add_text_center(doc, page, layer, VIEWPORT_AREA_X, VIEWPORT_AREA_Y, 190, 140,
                            "[Сохрани .skp файл сначала — viewports требуют saved model]")
            return
          end

          bounds = model.bounds
          ab = axis_bbox_mm(model)
          piece = piece_dims_mm(model)  # размер одной детали (труба сечение + длина)

          VIEWPORTS.each do |vp|
            row_pitch = VP_LABEL_H + VP_H + DIM_AREA_H + VP_GAP_Y
            x = VIEWPORT_AREA_X + vp[:col] * (VP_W + VP_GAP_X)
            y = VIEWPORT_AREA_Y + vp[:row] * row_pitch + VP_LABEL_H
            label_y = y - VP_LABEL_H

            # Label НАД viewport (с размерами конструкции и сечением детали)
            label = augment_label(vp, ab, piece)
            add_text_center(doc, page, layer, x, label_y, VP_W, VP_LABEL_H, label)
            # Border вокруг viewport
            add_rect(doc, page, layer, x, y, VP_W, VP_H)

            sm = ::Layout::SketchUpModel.new(
              path,
              Geom::Bounds2d.new(x.mm, y.mm, VP_W.mm, VP_H.mm)
            )
            sm.preserve_scale_on_resize = true
            begin
              sm.display_background = false
            rescue StandardError => _
            end
            # ortho-проекция обязательна — model_to_paper_point бросает
            # «view must be orthographic» иначе.
            begin
              sm.perspective = false
            rescue StandardError => _
            end

            std = STD_VIEW_MAP[vp[:std_view]]
            begin
              sm.view = std
            rescue StandardError => e
              puts "[LayoutGen] failed sm.view = #{std}: #{e.message}"
            end

            scale = fit_scale(vp[:std_view], bounds, VP_W, VP_H)
            begin
              sm.scale = scale
            rescue StandardError => e
              puts "[LayoutGen] failed sm.scale = #{scale}: #{e.message}"
            end

            doc.add_entity(sm, layer, page)
            sm.render

            # Размерные линии ВНУТРИ viewport, прикреплённые к paper-проекции
            # axis intersections рамы (нижняя/правая/левая грани в зависимости
            # от проекции). Размер позиционируется на самой детали,
            # не под viewport-ом.
            draw_viewport_dims(doc, page, layer, vp, sm, ab)
          end
        end

        # Размерные линии ВНУТРИ viewport, привязанные к 3D-точкам модели через
        # `Layout::SketchUpModel#model_to_paper_point`. Размер расположен на
        # самой детали (под нижней гранью / справа от правой), не под viewport-ом.
        # Реализация — через тонкие rectangles + text, не Layout::LinearDimension
        # (его custom_text не сохраняется, всегда показывает paper distance в дюймах).
        #
        # Требует sm.perspective = false — иначе model_to_paper_point бросает
        # «view must be orthographic».
        def draw_viewport_dims(doc, page, layer, vp, sm, ab)
          return if ab.nil?

          # Точки модели для главного размера (по нижней грани оси проекции).
          # Для :top рамы: bottom edge от (0,0,0) до (width,0,0).
          # Для :front: bottom edge XZ.
          # Для :right: bottom edge YZ → проецируется на right face (x=width).
          dim_specs = case vp[:std_view]
                      when :top
                        # Нижняя грань (Y=0): width; правая грань (X=width): depth
                        bottom_left  = Geom::Point3d.new(0,             0,             0)
                        bottom_right = Geom::Point3d.new(ab[:width].mm, 0,             0)
                        top_right    = Geom::Point3d.new(ab[:width].mm, ab[:depth].mm, 0)
                        [
                          { p1: bottom_left, p2: bottom_right, label: "#{ab[:width]} мм", side: :below },
                          { p1: bottom_right, p2: top_right,   label: "#{ab[:depth]} мм", side: :right }
                        ]
                      when :front
                        # Нижняя грань (Z=0): width
                        bl = Geom::Point3d.new(0,             0, 0)
                        br = Geom::Point3d.new(ab[:width].mm, 0, 0)
                        [{ p1: bl, p2: br, label: "#{ab[:width]} мм", side: :below }]
                      when :right
                        # Нижняя грань (Z=0): depth (Y direction)
                        bl = Geom::Point3d.new(ab[:width].mm, 0,             0)
                        br = Geom::Point3d.new(ab[:width].mm, ab[:depth].mm, 0)
                        [{ p1: bl, p2: br, label: "#{ab[:depth]} мм", side: :below }]
                      when :iso
                        # Iso — пропускаем, сложно правильно расположить
                        []
                      else
                        []
                      end

          dim_specs.each do |spec|
            p1_paper = sm.model_to_paper_point(spec[:p1])
            p2_paper = sm.model_to_paper_point(spec[:p2])
            draw_dim_paper(doc, page, layer, p1_paper, p2_paper, spec[:side], spec[:label])
          end
        rescue StandardError => e
          puts "[LayoutGen] draw_viewport_dims failed for #{vp[:key]}: #{e.class}: #{e.message}"
        end

        # Рисует размер между двумя paper-points, со смещением (offset perpendicular).
        # side: :below — линия чуть ниже p1-p2; :right — правее; :above; :left.
        # Все p1/p2 должны быть на одной горизонтальной/вертикальной линии для simple cases.
        def draw_dim_paper(doc, page, layer, p1, p2, side, label_text)
          dx = p2.x - p1.x
          dy = p2.y - p1.y
          horizontal = dx.abs >= dy.abs

          offset_mm = 4.0
          tick_mm = DIM_TICK_HALF_MM

          if horizontal
            # Горизонтальная линия — y фиксирован
            line_y_in = ([p1.y, p2.y].max + offset_mm.mm)  # под edge модели в paper
            # paper Y растёт вниз, "below" = больше Y
            x1 = p1.x; x2 = p2.x
            x1, x2 = x2, x1 if x1 > x2

            line_y_mm = line_y_in.to_mm
            x1_mm = x1.to_mm; x2_mm = x2.to_mm
            add_rect(doc, page, layer, x1_mm, line_y_mm, x2_mm - x1_mm, DIM_LINE_W_MM)
            add_rect(doc, page, layer, x1_mm,                 line_y_mm - tick_mm, DIM_LINE_W_MM, tick_mm * 2)
            add_rect(doc, page, layer, x2_mm - DIM_LINE_W_MM, line_y_mm - tick_mm, DIM_LINE_W_MM, tick_mm * 2)
            # leader lines от модели до dim line
            add_rect(doc, page, layer, x1_mm, p1.y.to_mm, DIM_LINE_W_MM, line_y_mm - p1.y.to_mm)
            add_rect(doc, page, layer, x2_mm - DIM_LINE_W_MM, p2.y.to_mm, DIM_LINE_W_MM, line_y_mm - p2.y.to_mm)
            # Text над линией
            text_w = 22
            text_h = 3
            cx_mm = (x1_mm + x2_mm) / 2.0
            add_text_center(doc, page, layer, cx_mm - text_w / 2.0, line_y_mm - 3.5, text_w, text_h, label_text)
          else
            # Вертикальная линия — x фиксирован
            line_x_in = (side == :left ? [p1.x, p2.x].min - offset_mm.mm : [p1.x, p2.x].max + offset_mm.mm)
            y1 = p1.y; y2 = p2.y
            y1, y2 = y2, y1 if y1 > y2
            line_x_mm = line_x_in.to_mm
            y1_mm = y1.to_mm; y2_mm = y2.to_mm
            add_rect(doc, page, layer, line_x_mm, y1_mm, DIM_LINE_W_MM, y2_mm - y1_mm)
            add_rect(doc, page, layer, line_x_mm - tick_mm, y1_mm,                 tick_mm * 2, DIM_LINE_W_MM)
            add_rect(doc, page, layer, line_x_mm - tick_mm, y2_mm - DIM_LINE_W_MM, tick_mm * 2, DIM_LINE_W_MM)
            # leader lines от модели до dim line
            add_rect(doc, page, layer, p1.x.to_mm, y1_mm, line_x_mm - p1.x.to_mm, DIM_LINE_W_MM)
            add_rect(doc, page, layer, p2.x.to_mm, y2_mm - DIM_LINE_W_MM, line_x_mm - p2.x.to_mm, DIM_LINE_W_MM)
            text_w = 12
            text_h = 3
            cy_mm = (y1_mm + y2_mm) / 2.0
            add_text_center(doc, page, layer, line_x_mm + 0.5, cy_mm - text_h / 2.0, text_w, text_h, label_text)
          end
        end

        # Компактная подпись над viewport: только инфа о ДЕТАЛИ.
        # Размеры конструкции рисуются размерными линиями вокруг viewport
        # (`draw_viewport_dim_h/v`), не дублируем их в подписи — иначе
        # текст не вмещается в 92.5mm и наезжает на соседний viewport.
        def augment_label(vp, _ab, piece)
          return vp[:label] if piece.nil?
          "#{vp[:label]} · #{piece[:label]}"
        end

        # Возвращает форматированный размер «1350 × 1350 мм» / «1350 мм».
        # Скрывает нулевую ось (для плоской рамы).
        def format_dims(a, b)
          if a > 0 && b > 0
            "#{a} × #{b} мм"
          elsif a > 0 || b > 0
            "#{[a, b].max} мм"
          else
            nil
          end
        end

        # Размер одной детали — типоразмер + длина. Если все детали одинаковые,
        # показываем «40×40×2 L=1350». Если разные — только сечение трубы (если
        # тоже одно), иначе nil.
        def piece_dims_mm(model)
          groups = group_rect_tubes(model)
          return nil if groups.empty?
          typesizes = groups.values.map { |d| d[:typesize] }.uniq
          lengths   = groups.values.map { |d| d[:length_mm] }.uniq
          if typesizes.size == 1 && lengths.size == 1
            { label: "#{typesizes.first} · L=#{lengths.first} мм" }
          elsif typesizes.size == 1
            { label: typesizes.first.to_s }
          else
            nil
          end
        end

        def draw_cut_list(doc, page, layer, model)
          cl = CUT_LIST
          groups = group_rect_tubes(model)
          rows_count = [groups.size, 1].max
          total_w = cl[:cols].sum { |_, w| w }
          total_h = cl[:header_h] + rows_count * cl[:row_h] + cl[:row_h]

          add_rect(doc, page, layer, cl[:x], cl[:y], total_w, total_h)
          add_rect(doc, page, layer, cl[:x], cl[:y], total_w, cl[:header_h])
          x_acc = cl[:x]
          cl[:cols].each do |label, w|
            add_rect(doc, page, layer, x_acc, cl[:y], w, cl[:header_h])
            add_text_center(doc, page, layer, x_acc, cl[:y], w, cl[:header_h], label)
            x_acc += w
          end

          totals = { count: 0, length_mm: 0.0, mass_kg: 0.0 }
          groups.each_with_index do |(_key, data), idx|
            y = cl[:y] + cl[:header_h] + idx * cl[:row_h]
            cnt = data[:count]
            len_per_piece = data[:length_mm].to_f
            sum_len = len_per_piece * cnt
            sum_mass = (data[:mass_per_m_kg] || 0).to_f * (sum_len / 1000.0)
            totals[:count]     += cnt
            totals[:length_mm] += sum_len
            totals[:mass_kg]   += sum_mass
            values = [
              (idx + 1).to_s,
              data[:typesize].to_s,
              data[:gost].to_s,
              data[:steel].to_s,
              len_per_piece.round(0).to_s,
              cnt.to_s,
              sum_len.round(0).to_s,
              format("%.2f", sum_mass)
            ]
            x_acc = cl[:x]
            cl[:cols].each_with_index do |(_, w), ci|
              add_rect(doc, page, layer, x_acc, y, w, cl[:row_h])
              add_text_center(doc, page, layer, x_acc, y, w, cl[:row_h], values[ci])
              x_acc += w
            end
          end

          y_total = cl[:y] + cl[:header_h] + groups.size * cl[:row_h]
          add_rect(doc, page, layer, cl[:x], y_total, total_w, cl[:row_h])
          total_values = [
            "", "ИТОГО", "", "", "",
            totals[:count].to_s,
            totals[:length_mm].round(0).to_s,
            format("%.2f", totals[:mass_kg])
          ]
          x_acc = cl[:x]
          cl[:cols].each_with_index do |(_, w), ci|
            add_rect(doc, page, layer, x_acc, y_total, w, cl[:row_h])
            add_text_center(doc, page, layer, x_acc, y_total, w, cl[:row_h], total_values[ci])
            x_acc += w
          end
        end

        def collect_cut_list(model)
          groups = group_rect_tubes(model)
          totals = { count: 0, length_mm: 0.0, mass_kg: 0.0 }
          groups.each do |_, d|
            sum_len = d[:length_mm].to_f * d[:count]
            totals[:count]     += d[:count]
            totals[:length_mm] += sum_len
            totals[:mass_kg]   += (d[:mass_per_m_kg] || 0).to_f * (sum_len / 1000.0)
          end
          [groups.size, totals]
        end

        # Bounding box по ОСЯМ всех rect_tube инстансов (in mm).
        # Это даёт «чистый» габарит конструкции (не включая толщину сечения):
        # для рамы 1350x1350 из трубы 40 — bbox по осям = 1350x1350 (а не 1390).
        # Используется для подписей размеров на viewport'ах.
        def axis_bbox_mm(model)
          pts = []
          model.entities.grep(::Sketchup::ComponentInstance).each do |inst|
            attrs = inst.definition.attribute_dictionary("nn_metalfab")
            next unless attrs && attrs["profile_type"] == "rect_tube"
            length_mm = attrs["length_mm"].to_f
            tr = inst.transformation
            pts << Geom::Point3d.new(0, 0, 0).transform(tr)
            pts << Geom::Point3d.new(0, 0, length_mm.mm).transform(tr)
          end
          return nil if pts.empty?
          xs = pts.map { |p| p.x.to_mm }
          ys = pts.map { |p| p.y.to_mm }
          zs = pts.map { |p| p.z.to_mm }
          {
            width:  (xs.max - xs.min).round(0),
            depth:  (ys.max - ys.min).round(0),
            height: (zs.max - zs.min).round(0)
          }
        end

        # Группирует rect_tube инстансы по паре (typesize × length_mm) — чтобы
        # каждая комбинация «сечение и длина одной детали» = одна строка
        # cut-list. Раньше группировали только по typesize: «4 шт» в одной
        # строке без длины каждой штуки. Теперь — «4 шт × 1350 мм = 5400 мм».
        # Длину округляем до 1 мм — типичная production-точность.
        def group_rect_tubes(model)
          groups = Hash.new do |h, k|
            h[k] = {
              count: 0, typesize: nil, length_mm: nil,
              gost: nil, mass_per_m_kg: nil, steel: nil
            }
          end
          model.entities.grep(::Sketchup::ComponentInstance).each do |inst|
            attrs = inst.definition.attribute_dictionary("nn_metalfab")
            next unless attrs
            next unless attrs["profile_type"] == "rect_tube"
            typesize = attrs["typesize"].to_s
            length = attrs["length_mm"].to_f.round(0)
            key = "#{typesize}|#{length}"
            g = groups[key]
            g[:count]    += 1
            g[:typesize] = typesize
            g[:length_mm] = length
            g[:gost] ||= attrs["gost"]
            g[:mass_per_m_kg] ||= attrs["mass_per_m_kg"]
            g[:steel] ||= attrs["steel_grade"]
          end
          # Сортируем для стабильного порядка: typesize, потом длина (по убыванию).
          groups.sort_by { |_, d| [d[:typesize].to_s, -d[:length_mm].to_i] }.to_h
        end

        # ----- Geometry helpers -----

        def add_rect(doc, page, layer, x_mm, y_mm, w_mm, h_mm)
          ent = ::Layout::Rectangle.new(
            Geom::Bounds2d.new(x_mm.mm, y_mm.mm, w_mm.mm, h_mm.mm)
          )
          doc.add_entity(ent, layer, page)
          ent
        end

        def add_text_center(doc, page, layer, x_mm, y_mm, w_mm, h_mm, str)
          s = str.to_s
          # Layout::FormattedText.new throws ArgumentError on empty string.
          return nil if s.strip.empty?
          cx = x_mm + w_mm / 2.0
          cy = y_mm + h_mm / 2.0
          ent = ::Layout::FormattedText.new(
            s,
            Geom::Point2d.new(cx.mm, cy.mm),
            ::Layout::FormattedText::ANCHOR_TYPE_CENTER_CENTER
          )
          doc.add_entity(ent, layer, page)
          ent
        end
      end
    end
  end
end
