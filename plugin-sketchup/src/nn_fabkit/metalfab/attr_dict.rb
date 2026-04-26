# encoding: UTF-8

module NN
  module MetalFab
    # Хелперы для записи/чтения нашего attribute_dictionary `nn_metalfab` (ADR-005).
    # Параллельно DC-атрибутам, не мешает OCL и встроенным словарям SketchUp.
    module AttrDict
      DICT = "nn_metalfab".freeze

      module_function

      def write_rect_tube(definition, typesize:, gost:, width_mm:, height_mm:, wall_mm:,
                          outer_radius_mm:, length_mm:, mass_per_m_kg: nil, steel_grade: nil,
                          cut_z0_angle_deg: 0.0, cut_zL_angle_deg: 0.0)
        write(definition, "profile_type",     "rect_tube")
        write(definition, "gost",             gost)
        write(definition, "typesize",         typesize)
        write(definition, "width_mm",         width_mm.to_f)
        write(definition, "height_mm",        height_mm.to_f)
        write(definition, "wall_mm",          wall_mm.to_f)
        write(definition, "outer_radius_mm",  outer_radius_mm.to_f)
        write(definition, "length_mm",        length_mm.to_f)
        write(definition, "mass_per_m_kg",    mass_per_m_kg.to_f) if mass_per_m_kg
        write(definition, "steel_grade",      steel_grade) if steel_grade
        write(definition, "length_axis",      "z")
        # Cut-info: 0.0 = perpendicular (no mitre); >0 = mitre angle в degrees.
        # FabKit CAD tool пишет/читает эти поля. nc-export использует их при
        # генерации IGES чтобы сгенерить mitre-геометрию вместо perpendicular.
        write(definition, "cut_z0_angle_deg", cut_z0_angle_deg.to_f)
        write(definition, "cut_zL_angle_deg", cut_zL_angle_deg.to_f)
      end

      # Прочитать состояние резов с definition / instance.
      # Возвращает Hash { z0: angle_deg, zL: angle_deg }. 0.0 = perpendicular.
      def read_cut_state(entity)
        {
          z0: (read(entity, "cut_z0_angle_deg") || 0.0).to_f,
          zL: (read(entity, "cut_zL_angle_deg") || 0.0).to_f
        }
      end

      # Прочитать все параметры профиля для regenerate.
      # Возвращает Hash или nil если definition не из плагина (нет profile_type).
      def read_rect_tube_params(entity)
        return nil unless read(entity, "profile_type") == "rect_tube"
        {
          typesize:        read(entity, "typesize"),
          gost:            read(entity, "gost"),
          width_mm:        read(entity, "width_mm").to_f,
          height_mm:       read(entity, "height_mm").to_f,
          wall_mm:         read(entity, "wall_mm").to_f,
          outer_radius_mm: read(entity, "outer_radius_mm").to_f,
          length_mm:       read(entity, "length_mm").to_f,
          mass_per_m_kg:   read(entity, "mass_per_m_kg"),
          steel_grade:     read(entity, "steel_grade"),
          cut_z0_angle_deg: (read(entity, "cut_z0_angle_deg") || 0.0).to_f,
          cut_zL_angle_deg: (read(entity, "cut_zL_angle_deg") || 0.0).to_f
        }
      end

      def write_geom_budget(definition, faces:, edges:, faces_limit:, edges_limit:)
        write(definition, "geom_budget_faces",       faces)
        write(definition, "geom_budget_edges",       edges)
        write(definition, "geom_budget_faces_limit", faces_limit)
        write(definition, "geom_budget_edges_limit", edges_limit)
        heavy = faces > faces_limit || edges > edges_limit
        write(definition, "heavy", heavy)
        heavy
      end

      def write(entity, key, value)
        entity.set_attribute(DICT, key, value)
      end

      def read(entity, key)
        entity.get_attribute(DICT, key)
      end
    end
  end
end
