# encoding: UTF-8

module NN
  module MetalFab
    module Commands
      # Демо-команда: воспроизводит внешнюю рамку перегородки заказчика-0
      # (модель `02-okazov-peregorodka`, ~420×2210 мм из трубы 40×20×2).
      # Sprint A: без запилов 45° — горизонтали вписаны между вертикалями
      # (длина 340 мм). Это proof-of-concept компоновки. Sprint B добавит
      # миттер-резы через Solid Tools, чтобы горизонтали стали полные 420 мм.
      #
      # Параметры компоновки совпадают с реальной перегородкой из корпуса
      # (см. corpus/examples/02-okazov-peregorodka/notes.md).
      module BuildPartitionFrame
        TITLE       = "NN FabKit — Демо: рамка перегородки".freeze
        TYPESIZE    = "40x20x2".freeze
        FRAME_W_MM  = 420
        FRAME_H_MM  = 2210
        DEFAULT_GRADE = "Ст3сп".freeze

        module_function

        def call
          model = Sketchup.active_model
          unless model
            ::UI.messagebox("Открой модель в SketchUp перед запуском демо.")
            return
          end

          item = Catalog.find_rect_tube(TYPESIZE)
          unless item
            ::UI.messagebox("Каталог не содержит типоразмер #{TYPESIZE}.")
            return
          end
          params  = item["params"]
          derived = item["derived"] || {}

          model.start_operation("NN FabKit: демо — рамка перегородки 420×2210", true, false, false)
          begin
            # Размеры рамки
            tube_w = params["width_mm"].to_f       # 40
            tube_h = params["height_mm"].to_f      # 20
            tube_t = params["wall_mm"].to_f        # 2
            tube_r = params["outer_radius_mm"].to_f # 3

            vert_len_mm = FRAME_H_MM
            horz_len_mm = FRAME_W_MM - 2 * tube_w  # 340 мм — вписано между вертикалями (Sprint A)

            # Группа-сборка
            frame_group = model.entities.add_group
            frame_group.name = "Перегородка-демо #{FRAME_W_MM}x#{FRAME_H_MM}"
            ents = frame_group.entities

            # Material (общий на все трубы)
            material = ensure_frame_material(model, TYPESIZE, DEFAULT_GRADE)

            # 4 definition'а — два уникальных по геометрии (vert, horz),
            # инстанцированы по 2 раза.
            vert_def = build_tube_def(model, "Труба #{TYPESIZE} L#{vert_len_mm}", item, vert_len_mm)
            horz_def = build_tube_def(model, "Труба #{TYPESIZE} L#{horz_len_mm}", item, horz_len_mm)

            # Компоновка в плоскости YZ (как в реальной перегородке у заказчика):
            # рамка стоит лицом по +X, ширина по Y (0..420), высота по Z (0..2210).
            # Сечение трубы 40 по X (ширина рамки в третьем измерении), 20 по Y.
            #
            # Вертикали: стоят как есть (длина по Z), сечение 40×20 в плоскости XY.
            #   - левая:  origin (0,   0,         0) — нижний угол
            #   - правая: origin (0,   400,       0) — отступ ширины - tube_h
            #
            # Горизонтали: повёрнуты на -90° вокруг X (длина теперь по +Y, не по +Z).
            #   - нижняя: origin (0, tube_h, 0)             — между вертикалями
            #   - верхняя: origin (0, tube_h, vert_len_mm - tube_h) — у верха

            t_vert_left  = Geom::Transformation.new(Geom::Point3d.new(0, 0,                  0))
            t_vert_right = Geom::Transformation.new(Geom::Point3d.new(0, FRAME_W_MM - tube_h, 0))

            rot_x_minus_90 = Geom::Transformation.rotation(
              Geom::Point3d.new(0, 0, 0),
              Geom::Vector3d.new(1, 0, 0),
              -Math::PI / 2.0
            )
            t_horz_bottom = Geom::Transformation.new(Geom::Point3d.new(0, tube_h.mm, 0)) * rot_x_minus_90
            t_horz_top    = Geom::Transformation.new(
              Geom::Point3d.new(0, tube_h.mm, (vert_len_mm - tube_h).mm)
            ) * rot_x_minus_90

            [
              [vert_def, t_vert_left,  "vert-left"],
              [vert_def, t_vert_right, "vert-right"],
              [horz_def, t_horz_bottom, "horz-bottom"],
              [horz_def, t_horz_top,   "horz-top"]
            ].each do |defn, tr, label|
              inst = ents.add_instance(defn, tr)
              inst.name = label
              inst.material = material if material
            end

            model.commit_operation
          rescue StandardError => e
            model.abort_operation
            ::UI.messagebox("Ошибка при сборке демо:\n\n#{e.class}: #{e.message}")
            puts "[NN::MetalFab] BuildPartitionFrame ERROR: #{e.class}: #{e.message}"
            puts e.backtrace.first(8).map { |l| "  #{l}" }.join("\n")
            return
          end

          ::UI.messagebox(
            "Собрана демо-рамка перегородки\n\n" \
            "Габариты: #{FRAME_W_MM} × #{FRAME_H_MM} мм\n" \
            "Труба: #{TYPESIZE}, марка #{DEFAULT_GRADE}\n" \
            "4 элемента: 2 вертикали по #{FRAME_H_MM} мм + 2 горизонтали по #{FRAME_W_MM - 2 * 40} мм (вписаны).\n\n" \
            "Sprint A — без запилов 45°. Sprint B добавит миттер-резы\n" \
            "(тогда горизонтали станут полные #{FRAME_W_MM} мм)."
          )
        end

        def build_tube_def(model, name, item, length_mm)
          name = unique_def_name(model, name)
          defn = model.definitions.add(name)
          defn.description = "Демо: труба #{TYPESIZE}, L=#{length_mm}мм (рамка перегородки)"
          params  = item["params"]
          derived = item["derived"] || {}

          ProfileGenerator::RectTube.build(
            defn,
            width_mm:        params["width_mm"].to_f,
            height_mm:       params["height_mm"].to_f,
            wall_mm:         params["wall_mm"].to_f,
            outer_radius_mm: params["outer_radius_mm"].to_f,
            length_mm:       length_mm,
            typesize:        item["typesize"],
            gost:            "30245-2003",
            mass_per_m_kg:   derived["mass_per_m_kg"],
            steel_grade:     DEFAULT_GRADE
          )
          defn
        end

        def unique_def_name(model, base)
          existing = model.definitions.map(&:name)
          return base unless existing.include?(base)
          i = 2
          loop do
            cand = "#{base} ##{i}"
            return cand unless existing.include?(cand)
            i += 1
          end
        end

        def ensure_frame_material(model, typesize, grade)
          name = "Труба #{typesize} #{grade}"
          mat = model.materials[name]
          return mat if mat
          mat = model.materials.add(name)
          mat.color = Sketchup::Color.new(64, 64, 64)
          mat.alpha = 1.0
          mat
        end
      end
    end
  end
end
