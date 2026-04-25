# encoding: UTF-8

module NN
  module MetalFab
    # Хелперы для записи/чтения нашего attribute_dictionary `nn_metalfab` (ADR-005).
    # Параллельно DC-атрибутам, не мешает OCL и встроенным словарям SketchUp.
    module AttrDict
      DICT = "nn_metalfab".freeze

      module_function

      def write_rect_tube(definition, typesize:, gost:, width_mm:, height_mm:, wall_mm:,
                          outer_radius_mm:, mass_per_m_kg:, steel_grade: nil)
        write(definition, "profile_type",     "rect_tube")
        write(definition, "gost",             gost)
        write(definition, "typesize",         typesize)
        write(definition, "width_mm",         width_mm.to_f)
        write(definition, "height_mm",        height_mm.to_f)
        write(definition, "wall_mm",          wall_mm.to_f)
        write(definition, "outer_radius_mm",  outer_radius_mm.to_f)
        write(definition, "mass_per_m_kg",    mass_per_m_kg.to_f) if mass_per_m_kg
        write(definition, "steel_grade",      steel_grade) if steel_grade
        write(definition, "length_axis",      "z")
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
