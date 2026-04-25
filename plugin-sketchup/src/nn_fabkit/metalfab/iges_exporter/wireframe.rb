# encoding: UTF-8

module NN
  module MetalFab
    module IgesExporter
      # Минимальный IGES 5.3 wireframe-экспорт для одной профильной трубы.
      # Использует только Type 110 (Line) и Type 100 (Circular Arc) — самое
      # маленькое подмножество, которое читает любой IGES-viewer/CAM.
      # Это первый шаг к собственному IGES-конвертёру (ADR-017); полный
      # surface-model BREP — отдельный spec для standalone (`app-desktop/`).
      #
      # Что выгружает: каркас прямой трубы (без отверстий и резов под угол) —
      # два endcap-контура (outer + inner rounded rectangle на z=0 и z=length)
      # плюс по 4 «силуэтных» вертикальных ребра на каждом контуре.
      # Это даёт визуальный контроль геометрии в любом IGES viewer.
      module Wireframe
        # Колоночные размеры IGES 5.3 fixed-format
        DATA_WIDTH         = 72   # cols 1-72 — данные
        P_DATA_WIDTH       = 64   # в P секции cols 1-64 — данные, 65 пробел, 66-72 — pointer back на D
        IGES_LINE_WIDTH    = 80   # каждая строка — ровно 80 chars
        SECTION_LETTER_COL = 73   # col 73 — буква секции
        SEQUENCE_WIDTH     = 7    # cols 74-80 — sequence number (zero-padded)

        SEGMENTS_PER_CORNER = 8   # совпадает с RectTube для согласованности

        module_function

        # Public API. Принимает `definition` ранее созданной трубы (через
        # NN::MetalFab::ProfileGenerator::RectTube) и путь сохранения.
        # Возвращает hash с метаданными результата.
        def export(definition, output_path)
          attrs    = read_truba_attrs(definition)
          length   = attrs.fetch(:length_mm)
          entities = build_entities(attrs[:width_mm], attrs[:height_mm],
                                    attrs[:wall_mm], attrs[:outer_radius_mm], length)

          content  = render(entities, File.basename(output_path), definition.name, attrs)
          File.open(output_path, "wb") { |f| f.write(content) }

          {
            path:         output_path,
            entity_count: entities.size,
            line_count:   entities.count { |e| e[:type] == :line },
            arc_count:    entities.count { |e| e[:type] == :arc },
            length_mm:    length
          }
        end

        # ----------------------------------------------------------------
        # Reading nn_metalfab metadata off the definition
        # ----------------------------------------------------------------

        def read_truba_attrs(definition)
          dict = definition.attribute_dictionary("nn_metalfab")
          unless dict && dict["profile_type"] == "rect_tube"
            raise "Это не Профильная труба NN FabKit (нет nn_metalfab.profile_type=rect_tube)."
          end

          length = dict["length_mm"].to_f
          if length <= 0
            # Fallback на bounds.depth (модели до v0.4.0 не писали length_mm).
            length = definition.bounds.depth.to_f * 25.4
          end

          {
            width_mm:        dict["width_mm"].to_f,
            height_mm:       dict["height_mm"].to_f,
            wall_mm:         dict["wall_mm"].to_f,
            outer_radius_mm: dict["outer_radius_mm"].to_f,
            length_mm:       length,
            typesize:        dict["typesize"].to_s,
            gost:            dict["gost"].to_s,
            steel_grade:     dict["steel_grade"]
          }
        end

        # ----------------------------------------------------------------
        # Geometry → entities (in mm — IGES global flag UNIT=2 ставит мм)
        # ----------------------------------------------------------------

        # Endcap контур z=0 + endcap z=length + outer/inner +
        # 4 вертикальные «силуэтные» линии на серединах сторон.
        def build_entities(w, h, wall, r, length)
          ents = []

          # Endcap z=0 outer + inner
          ents.concat(rounded_rect_at(w, h, r, 0.0))
          if wall > 0 && wall * 2 < w && wall * 2 < h
            iw = w - 2 * wall
            ih = h - 2 * wall
            ir = [r - wall, 0.0].max
            ents.concat(rounded_rect_at(iw, ih, ir, 0.0))
          end

          # Endcap z=length outer + inner
          ents.concat(rounded_rect_at(w, h, r, length))
          if wall > 0 && wall * 2 < w && wall * 2 < h
            iw = w - 2 * wall
            ih = h - 2 * wall
            ir = [r - wall, 0.0].max
            ents.concat(rounded_rect_at(iw, ih, ir, length))
          end

          # Vertical silhouette edges (по 4 на каждый контур)
          ents.concat(vertical_silhouettes(w, h, length))
          if wall > 0 && wall * 2 < w && wall * 2 < h
            ents.concat(vertical_silhouettes(w - 2 * wall, h - 2 * wall, length))
          end

          ents
        end

        # 4 прямые стороны + 4 угловые дуги (в плоскости z=zt). CCW orientation.
        def rounded_rect_at(width, height, radius, zt)
          ents = []
          hw = width / 2.0
          hh = height / 2.0
          r  = [[radius, hw].min, hh].min

          if r < 1.0e-6
            # Прямой угол — 4 линии
            ents << line(  hw,  hh, zt,  -hw,  hh, zt)
            ents << line( -hw,  hh, zt,  -hw, -hh, zt)
            ents << line( -hw, -hh, zt,   hw, -hh, zt)
            ents << line(  hw, -hh, zt,   hw,  hh, zt)
            return ents
          end

          # Прямые между скруглениями
          ents << line(  hw - r,  hh, zt,  -hw + r,  hh, zt)  # top
          ents << line(  -hw,  hh - r, zt, -hw, -hh + r, zt)  # left
          ents << line(  -hw + r, -hh, zt,  hw - r, -hh, zt)  # bottom
          ents << line(  hw, -hh + r, zt,  hw,  hh - r, zt)   # right

          # 4 угловые дуги (CCW в плоскости z=zt)
          # NE: center (hw-r, hh-r), от (hw, hh-r) до (hw-r, hh)
          ents << arc(zt, hw - r,   hh - r,   hw,        hh - r,   hw - r,    hh)
          # NW: center (-hw+r, hh-r), от (-hw+r, hh) до (-hw, hh-r)
          ents << arc(zt, -hw + r,  hh - r,   -hw + r,   hh,       -hw,       hh - r)
          # SW: center (-hw+r, -hh+r), от (-hw, -hh+r) до (-hw+r, -hh)
          ents << arc(zt, -hw + r,  -hh + r,  -hw,       -hh + r,  -hw + r,   -hh)
          # SE: center (hw-r, -hh+r), от (hw-r, -hh) до (hw, -hh+r)
          ents << arc(zt, hw - r,   -hh + r,  hw - r,    -hh,      hw,        -hh + r)

          ents
        end

        def vertical_silhouettes(width, height, length)
          hw = width / 2.0
          hh = height / 2.0
          [
            line(  hw,  0.0, 0.0,   hw,  0.0, length),
            line( -hw,  0.0, 0.0,  -hw,  0.0, length),
            line( 0.0,  hh,  0.0,  0.0,  hh,  length),
            line( 0.0, -hh,  0.0,  0.0, -hh,  length)
          ]
        end

        def line(x1, y1, z1, x2, y2, z2)
          { type: :line, x1: x1, y1: y1, z1: z1, x2: x2, y2: y2, z2: z2 }
        end

        def arc(zt, xc, yc, xs, ys, xe, ye)
          { type: :arc, zt: zt, xc: xc, yc: yc, xs: xs, ys: ys, xe: xe, ye: ye }
        end

        # ----------------------------------------------------------------
        # IGES rendering
        # ----------------------------------------------------------------

        # IGES file layout:
        #   S section (Start)     — freeform header description
        #   G section (Global)    — параметры формата (delimiters, units, etc.)
        #   D section (Directory) — 2 строки на entity, fixed-format 10×8 chars
        #   P section (Parameter) — параметры entity, CSV terminated by ';'
        #   T section (Terminate) — счётчики строк секций S, G, D, P
        # Каждая строка — ровно 80 chars, col 73 = section letter, cols 74-80 = sequence.
        def render(entities, filename, defn_name, attrs)
          # 1. Сначала P section (параметры entities) — узнаём размеры P для D pointers.
          p_records = entities.map { |e| build_param_string(e) }
          p_lines   = []
          d_pointers = []  # для каждого entity — sequence number (1-based) старта в P секции

          p_records.each do |rec|
            d_pointers << (p_lines.size + 1)
            wrap_p_data(rec).each { |chunk| p_lines << chunk }
          end

          # 2. D section (2 строки на entity).
          d_lines = []
          entities.each_with_index do |e, idx|
            type_num    = (e[:type] == :line ? 110 : 100)
            param_lines = wrap_p_data(p_records[idx]).size
            d_pointer   = d_pointers[idx]
            d_lines.concat(build_d_pair(type_num, d_pointer, param_lines))
          end

          # 3. G section
          g_lines = build_g_section(filename, attrs)

          # 4. S section
          s_lines = ["NN FabKit IGES wireframe export — '#{defn_name}' (#{attrs[:typesize]}, " \
                     "L=#{attrs[:length_mm].to_i}mm). " \
                     "Lines + Arcs only (Type 110, Type 100)."]

          # 5. Сборка final output с правильной нумерацией
          out = []
          # S — col 1-72 data, col 73 = 'S', cols 74-80 = sequence
          s_lines.each_with_index { |l, i| out << pad_section_line(l, "S", i + 1) }
          # G — то же
          g_lines.each_with_index { |l, i| out << pad_section_line(l, "G", i + 1) }
          # D — фиксированный формат, не padding (он уже 64 cols), плюс seq
          d_lines.each_with_index { |l, i| out << pad_d_line(l, i + 1) }
          # P — данные + pointer back, plus seq
          # build_param_string дал нам plain CSV с ';' в конце; wrap_p_data разбил на куски.
          # Pointer back на D: каждое entity занимает 2 строки в D. d_pointers[k] это P-seq для entity k.
          # Для P-line с порядковым номером N — какой entity это? Нужно реверс-mapping.
          p_to_de = {}  # P-line index (1-based) → D-entry first-line sequence
          entities.each_with_index do |_, idx|
            de_seq = idx * 2 + 1  # D entry first-line sequence (1, 3, 5, …)
            param_lines = wrap_p_data(p_records[idx]).size
            param_lines.times do |j|
              p_to_de[d_pointers[idx] + j] = de_seq
            end
          end
          p_lines.each_with_index do |l, i|
            seq = i + 1
            de_back = p_to_de[seq] || 1
            out << pad_p_line(l, de_back, seq)
          end

          # T section
          t_data = "S%07dG%07dD%07dP%07d" % [s_lines.size, g_lines.size, d_lines.size, p_lines.size]
          out << pad_section_line(t_data, "T", 1)

          out.join("\n") + "\n"
        end

        # Build P section param string for one entity. Ends with ';'.
        # Type 110 (Line):  "110,x1,y1,z1,x2,y2,z2;"
        # Type 100 (Arc):   "100,zt,xc,yc,xs,ys,xe,ye;"
        def build_param_string(e)
          if e[:type] == :line
            "110,#{fnum(e[:x1])},#{fnum(e[:y1])},#{fnum(e[:z1])}," \
            "#{fnum(e[:x2])},#{fnum(e[:y2])},#{fnum(e[:z2])};"
          else
            "100,#{fnum(e[:zt])},#{fnum(e[:xc])},#{fnum(e[:yc])}," \
            "#{fnum(e[:xs])},#{fnum(e[:ys])},#{fnum(e[:xe])},#{fnum(e[:ye])};"
          end
        end

        # Format float for IGES — mm с точностью до 0.001, без экспонент.
        def fnum(v)
          ("%.6f" % v.to_f).sub(/0+$/, "").sub(/\.$/, ".0")
        end

        # Wrap CSV record into chunks ≤ P_DATA_WIDTH chars. Простая
        # break-on-comma логика — реальный IGES может писать длинные строки,
        # но 64 символа — стандарт.
        def wrap_p_data(record)
          return [record] if record.length <= P_DATA_WIDTH
          chunks = []
          remaining = record.dup
          while remaining.length > P_DATA_WIDTH
            split = remaining.rindex(",", P_DATA_WIDTH) || P_DATA_WIDTH
            chunks << remaining[0..split]
            remaining = remaining[(split + 1)..-1] || ""
          end
          chunks << remaining unless remaining.empty?
          chunks
        end

        # Build D section 2-line pair for one entity.
        # 10 fields × 8 chars, right-aligned. See IGES 5.3 §2.2.4.
        def build_d_pair(type_num, p_pointer, param_line_count)
          # Line 1 fields:
          #   1. Entity Type Number
          #   2. Parameter Data Pointer (P sequence of first param line)
          #   3. Structure (0)
          #   4. Line Font Pattern (0)
          #   5. Level (0)
          #   6. View (0)
          #   7. Transformation Matrix Pointer (0 = none)
          #   8. Label Display Associativity (0)
          #   9. Status Number — 8 digits "00000000"
          line1 = format_d_fields([type_num, p_pointer, 0, 0, 0, 0, 0, 0, "00000000"])
          # Line 2 fields:
          #   1. Entity Type Number (повторяется)
          #   2. Line Weight Number (0)
          #   3. Color Number (0)
          #   4. Parameter Line Count
          #   5. Form Number (0)
          #   6. Reserved (blank)
          #   7. Reserved (blank)
          #   8. Entity Label (blank)
          #   9. Entity Subscript Number (0)
          line2 = format_d_fields([type_num, 0, 0, param_line_count, 0, "", "", "", 0])
          [line1, line2]
        end

        def format_d_fields(fields)
          fields.map { |f| f.to_s.rjust(8) }.join
        end

        # Pad data into IGES 80-col line: data (col 1-72) + section letter (73) + seq (74-80).
        def pad_section_line(data, sect_letter, seq_num)
          data_clipped = data[0, DATA_WIDTH] || ""
          padded = data_clipped.ljust(DATA_WIDTH)
          "#{padded}#{sect_letter}%07d" % seq_num
        end

        # D section: data is already 72 chars (10 fields × 8 chars = 80, but строка уже 72 cols D-data),
        # actually 10 fields × 8 chars = 80, и col 73-80 это sect+seq. То есть data = 72 cols.
        # format_d_fields дал нам 9 fields × 8 = 72, что точно вписывается.
        def pad_d_line(data, seq_num)
          padded = data.ljust(DATA_WIDTH)
          "#{padded}D%07d" % seq_num
        end

        # P section: cols 1-64 data, col 65 blank, cols 66-72 = pointer back на D entry.
        def pad_p_line(data, de_back, seq_num)
          data_clipped = data[0, P_DATA_WIDTH] || ""
          padded = data_clipped.ljust(P_DATA_WIDTH)
          back   = (" %7d" % de_back)  # " " + 7-digit
          "#{padded}#{back}P%07d" % seq_num
        end

        # G section: 25 параметров через запятую, terminated by ';'. Разбиваем по 64 cols.
        def build_g_section(filename, attrs)
          now = Time.now
          ts  = now.strftime("%Y%m%d.%H%M%S")
          plugin_version = NN::FabKit::VERSION
          # 25 standard global parameters
          params = [
            "1H,",                     # 1. Parameter delimiter ","
            "1H;",                     # 2. Record delimiter ";"
            hstr("NN FabKit"),         # 3. Sender Product ID
            hstr(filename),            # 4. File name
            hstr("SketchUp #{Sketchup.version}"),  # 5. System ID
            hstr("NN FabKit #{plugin_version}"),   # 6. Preprocessor version
            "32",                      # 7. Integer bits
            "38",                      # 8. Single precision magnitude
            "6",                       # 9. Single precision significance
            "308",                     # 10. Double precision magnitude
            "15",                      # 11. Double precision significance
            hstr(""),                  # 12. Receiver Product ID
            "1.0",                     # 13. Model space scale
            "2",                       # 14. Unit flag (2 = MM)
            hstr("MM"),                # 15. Unit name
            "32",                      # 16. Max lines per drawing
            "10000.0",                 # 17. Max coordinate value
            hstr(ts),                  # 18. Date/time of creation
            "0.001",                   # 19. Min user-intended resolution
            "1000.0",                  # 20. Approx max coord value
            hstr(""),                  # 21. Author
            hstr(""),                  # 22. Author org
            "11",                      # 23. IGES version flag (11 = IGES 5.3)
            "0",                       # 24. Drafting standard (0 = none)
            hstr(ts)                   # 25. Modified date
          ]
          record = params.join(",") + ";"
          wrap_p_data(record)  # переиспользуем логику разбиения по 64 cols
        end

        # IGES Hollerith string encoding: "<len>H<text>"
        def hstr(text)
          "#{text.length}H#{text}"
        end
      end
    end
  end
end
