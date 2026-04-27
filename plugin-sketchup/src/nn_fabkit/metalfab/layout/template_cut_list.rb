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

        # 2×2 viewport grid в области (10, 60) .. (200, 195) = 190 × 135 мм.
        # Каждая ячейка: viewport 92.5 × 62.5 + label-полоска 5mm над viewport'ом.
        # Зазоры по 5mm между ячейками и сверху (под label).
        VIEWPORT_AREA_X = 10
        VIEWPORT_AREA_Y = 55
        VP_W = 92.5
        VP_H = 62.5
        VP_LABEL_H = 5
        VP_GAP_X = 5
        VP_GAP_Y = 5

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

        CUT_LIST = {
          x: 10, y: 205, header_h: 8, row_h: 6,
          cols: [
            ["№",          10],
            ["Типоразмер", 35],
            ["ГОСТ",       35],
            ["Сталь",      20],
            ["Кол-во, шт", 22],
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

          VIEWPORTS.each do |vp|
            x = VIEWPORT_AREA_X + vp[:col] * (VP_W + VP_GAP_X)
            y = VIEWPORT_AREA_Y + vp[:row] * (VP_H + VP_LABEL_H + VP_GAP_Y) + VP_LABEL_H
            label_y = y - VP_LABEL_H

            # Label НАД viewport
            add_text_center(doc, page, layer, x, label_y, VP_W, VP_LABEL_H, vp[:label])
            # Border вокруг viewport
            add_rect(doc, page, layer, x, y, VP_W, VP_H)

            sm = ::Layout::SketchUpModel.new(
              path,
              Geom::Bounds2d.new(x.mm, y.mm, VP_W.mm, VP_H.mm)
            )
            sm.preserve_scale_on_resize = true
            # Чистый белый фон вместо SU sky/ground — плоские детали
            # (рамы, листы) в front/right views иначе выглядят как линия
            # на фоне неба/земли.
            begin
              sm.display_background = false
            rescue StandardError => _
            end

            # Установить standard view (Layout сам отрисует ortho/iso —
            # не зависит от .skp scenes).
            std = STD_VIEW_MAP[vp[:std_view]]
            begin
              sm.view = std
            rescue StandardError => e
              puts "[LayoutGen] failed sm.view = #{std}: #{e.message}"
            end

            # Auto-fit scale под bounds модели
            scale = fit_scale(vp[:std_view], bounds, VP_W, VP_H)
            begin
              sm.scale = scale
            rescue StandardError => e
              puts "[LayoutGen] failed sm.scale = #{scale}: #{e.message}"
            end

            doc.add_entity(sm, layer, page)
            sm.render
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
          groups.each_with_index do |(typesize, data), idx|
            y = cl[:y] + cl[:header_h] + idx * cl[:row_h]
            cnt = data[:items].size
            sum_len = data[:items].sum
            sum_mass = (data[:mass_per_m_kg] || 0).to_f * (sum_len / 1000.0)
            totals[:count] += cnt
            totals[:length_mm] += sum_len
            totals[:mass_kg] += sum_mass
            values = [
              (idx + 1).to_s, typesize, data[:gost].to_s, data[:steel].to_s,
              cnt.to_s, sum_len.round(0).to_s, format("%.2f", sum_mass)
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
            "", "ИТОГО", "", "",
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
            totals[:count]     += d[:items].size
            totals[:length_mm] += d[:items].sum
            totals[:mass_kg]   += (d[:mass_per_m_kg] || 0).to_f * (d[:items].sum / 1000.0)
          end
          [groups.size, totals]
        end

        def group_rect_tubes(model)
          groups = Hash.new { |h, k| h[k] = { items: [], gost: nil, mass_per_m_kg: nil, steel: nil } }
          model.entities.grep(::Sketchup::ComponentInstance).each do |inst|
            attrs = inst.definition.attribute_dictionary("nn_metalfab")
            next unless attrs
            next unless attrs["profile_type"] == "rect_tube"
            g = groups[attrs["typesize"].to_s]
            g[:items] << attrs["length_mm"].to_f
            g[:gost] ||= attrs["gost"]
            g[:mass_per_m_kg] ||= attrs["mass_per_m_kg"]
            g[:steel] ||= attrs["steel_grade"]
          end
          groups
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
