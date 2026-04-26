# encoding: UTF-8

module NN
  module MetalFab
    module Commands
      # UI-команда: создаёт новый definition `Профильная труба` по выбранным
      # типоразмеру и марке стали из ГОСТ 30245-2003 каталога, и кладёт инстанс
      # в начало координат текущей модели.
      module CreateRectTube
        TITLE = "NN FabKit — Создать «Профильная труба»".freeze
        DEFAULT_LENGTH_MM = 1000

        module_function

        def call
          model = Sketchup.active_model
          unless model
            ::UI.messagebox("Открой модель в SketchUp перед созданием компонента.")
            return
          end

          typesizes = Catalog.rect_tube_typesizes
          if typesizes.empty?
            ::UI.messagebox("Каталог ГОСТ 30245 пуст. Проверь catalogs/gost-30245-rect-tube.json.")
            return
          end

          grades = Catalog.rect_tube_grades
          default_grade = Catalog.rect_tube_default_grade || grades.first || ""
          default_typesize = typesizes.include?("40x20x2") ? "40x20x2" : typesizes.first

          prompts  = ["Сечение", "Марка стали", "Длина, мм"]
          defaults = [default_typesize, default_grade, DEFAULT_LENGTH_MM.to_s]
          lists    = [typesizes.join("|"), grades.join("|"), ""]
          result = ::UI.inputbox(prompts, defaults, lists, TITLE)
          return unless result

          typesize_str, grade_str, length_str = result
          length_mm = length_str.to_f
          outcome = create_with_params(typesize_str, grade_str, length_mm)

          if outcome[:ok]
            ::UI.messagebox(
              "Создан компонент «#{outcome[:name]}»\n\n" \
              "Сечение: #{outcome[:typesize]} " \
              "(#{outcome[:width_mm]}×#{outcome[:height_mm]}, " \
              "стенка #{outcome[:wall_mm]} мм, R=#{outcome[:radius_mm]} мм)\n" \
              "Длина: #{outcome[:length_mm].to_i} мм\n" \
              "Марка: #{outcome[:grade].empty? ? '—' : outcome[:grade]}\n" \
              "Масса погонная: #{outcome[:mass_per_m_kg] || '—'} кг/м"
            )
          else
            ::UI.messagebox(outcome[:error])
          end
        end

        # Программный вход (для Inspector / MCP / тестов). Возвращает Hash:
        #   { ok: true,  name:, typesize:, width_mm:, height_mm:, wall_mm:,
        #     radius_mm:, length_mm:, grade:, mass_per_m_kg: }
        # либо
        #   { ok: false, error: "<сообщение>" }
        # UI здесь не показываем — caller сам решает.
        def create_with_params(typesize_str, grade_str, length_mm)
          model = Sketchup.active_model
          return { ok: false, error: "Нет открытой модели в SketchUp." } unless model

          item = Catalog.find_rect_tube(typesize_str)
          unless item
            return { ok: false, error: "Типоразмер «#{typesize_str}» не найден в каталоге." }
          end

          length_mm = length_mm.to_f
          if length_mm <= 0
            return { ok: false, error: "Длина должна быть положительным числом." }
          end

          grade_str = grade_str.to_s
          params  = item["params"]  || {}
          derived = item["derived"] || {}

          definition = nil
          model.start_operation("NN FabKit: создать «Труба #{typesize_str}»", true, false, false)
          begin
            definition = build_definition(model, item, grade_str, length_mm)
            material   = ensure_material(model, typesize_str, grade_str)
            place_instance(model, definition, material)
            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            puts "[NN::MetalFab] CreateRectTube ERROR: #{e.class}: #{e.message}"
            puts e.backtrace.first(8).map { |l| "  #{l}" }.join("\n")
            return { ok: false, error: "#{e.class}: #{e.message}" }
          end

          {
            ok:            true,
            name:          definition.name,
            typesize:      typesize_str,
            width_mm:      params["width_mm"],
            height_mm:     params["height_mm"],
            wall_mm:       params["wall_mm"],
            radius_mm:     params["outer_radius_mm"],
            length_mm:     length_mm,
            grade:         grade_str,
            mass_per_m_kg: derived["mass_per_m_kg"]
          }
        end

        def build_definition(model, item, grade_str, length_mm)
          params  = item["params"]
          derived = item["derived"] || {}
          typesize = item["typesize"]

          # Уникальное имя в текущей модели — definitions.add разрешает коллизии,
          # но имя для DC лучше делать предсказуемым: «Труба 40x20x2» или с суффиксом #N.
          base_name = "Труба #{typesize}"
          name = unique_definition_name(model, base_name)

          definition = model.definitions.add(name)
          definition.description = "Профильная труба ГОСТ 30245-2003, #{typesize}"

          ProfileGenerator::RectTube.build(
            definition,
            width_mm:        params["width_mm"].to_f,
            height_mm:       params["height_mm"].to_f,
            wall_mm:         params["wall_mm"].to_f,
            outer_radius_mm: params["outer_radius_mm"].to_f,
            length_mm:       length_mm,
            typesize:        typesize,
            gost:            "30245-2003",
            mass_per_m_kg:   derived["mass_per_m_kg"],
            steel_grade:     (grade_str.nil? || grade_str.empty? ? nil : grade_str)
          )

          definition
        end

        def unique_definition_name(model, base)
          existing = model.definitions.map(&:name)
          return base unless existing.include?(base)
          i = 2
          loop do
            candidate = "#{base} ##{i}"
            return candidate unless existing.include?(candidate)
            i += 1
          end
        end

        # Имя материала — наша конвенция (ADR-016, не OCL):
        #   «Труба 40x20x2 Ст3сп», или «Труба 40x20x2» если марка не задана.
        # OCL-атрибуты на материале НЕ ставим (ADR-016).
        def ensure_material(model, typesize, grade_str)
          name = grade_str.nil? || grade_str.empty? ? "Труба #{typesize}" : "Труба #{typesize} #{grade_str}"
          mat = model.materials[name]
          return mat if mat

          mat = model.materials.add(name)
          mat.color = Sketchup::Color.new(64, 64, 64) # нейтральный тёмно-серый, как у заказчика-0
          mat.alpha = 1.0
          mat
        end

        def place_instance(model, definition, material)
          tr = Geom::Transformation.new(Geom::Point3d.new(0, 0, 0))
          instance = model.entities.add_instance(definition, tr)
          instance.material = material if material
          instance
        end
      end
    end
  end
end
