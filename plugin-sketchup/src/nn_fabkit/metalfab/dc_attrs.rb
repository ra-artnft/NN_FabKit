# encoding: UTF-8

module NN
  module MetalFab
    # Установка `dynamic_attributes` на definition — чтобы привычный заказчику
    # Component Options (правый клик → Component Options) показывал параметры.
    # На этой итерации все поля помечены _access = "VIEW" (readonly) — DC-движок
    # сам перерисовывать геометрию НЕ умеет (формулы DC меняют только scale, не топологию,
    # см. ADR-002). Регенерация при изменении параметров — следующий sprint (DC-EntityObserver).
    module DcAttrs
      DA = "dynamic_attributes".freeze

      module_function

      def write_rect_tube(definition, name:, width_mm:, height_mm:, wall_mm:, length_mm:, outer_radius_mm:)
        # Сервисные ключи DC-движка
        set(definition, "_name",          name)
        set(definition, "_formatversion", 1.0)
        set(definition, "_hasbehaviors",  1.0)
        set(definition, "_lengthunits",   "MILLIMETERS")
        set(definition, "_lastmodified",  Time.now.strftime("%Y-%m-%d %H:%M"))

        # Размеры в DC-длинах хранятся в дюймах (внутренние единицы SketchUp).
        # Единицы отображения для Component Options — через _*_units.
        set_param(definition, "lenx", "Ширина, мм",  width_mm,  "VIEW")
        set_param(definition, "leny", "Высота, мм",  height_mm, "VIEW")
        set_param(definition, "lenz", "Длина, мм",   length_mm, "VIEW")

        # Кастомные параметры — записываем напрямую, не как _len*.
        # Толщина стенки и радиус — для отображения. Радиус считается формулой R = 1.5 × t (ADR-014).
        set_custom(definition, "wall_mm",         "Стенка, мм",                 wall_mm,         "VIEW")
        set_custom(definition, "outer_radius_mm", "Радиус гиба (R=1.5t), мм",   outer_radius_mm, "VIEW",
                   formula: "=wall_mm * 1.5")
      end

      def set_param(definition, key, label_ru, value_mm, access)
        set(definition, key,                   value_mm.to_f / 25.4) # дюймы — внутренние единицы DC-длин
        set(definition, "_#{key}_label",       key.upcase)           # «LENX», «LENY», «LENZ» — техническая метка
        set(definition, "_#{key}_formlabel",   label_ru)             # отображаемая метка в Component Options
        set(definition, "_#{key}_units",       "MILLIMETERS")
        set(definition, "_#{key}_access",      access)               # "TEXTBOX" / "LIST" / "VIEW" / "NONE"
      end

      def set_custom(definition, key, label_ru, value_mm, access, formula: nil)
        set(definition, key,                   value_mm.to_f)
        set(definition, "_#{key}_label",       key)
        set(definition, "_#{key}_formlabel",   label_ru)
        set(definition, "_#{key}_units",       "MILLIMETERS")
        set(definition, "_#{key}_access",      access)
        set(definition, "_#{key}_formula",     formula) if formula
      end

      def set(entity, key, value)
        entity.set_attribute(DA, key, value)
      end
    end
  end
end
