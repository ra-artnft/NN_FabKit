# encoding: UTF-8

module NN
  module MetalFab
    module Commands
      # UI-команда: экспортирует выбранный инстанс «Профильная труба» в IGES wireframe.
      # Файл сохраняется через savepanel рядом с .skp (или в выбранную пользователем папку).
      module ExportIges
        TITLE = "NN FabKit — Экспорт «Профильная труба» в IGES".freeze

        module_function

        def call
          model = Sketchup.active_model
          unless model
            ::UI.messagebox("Открой модель в SketchUp.")
            return
          end

          selection = model.selection.to_a
          truba_definitions = pick_truba_definitions(selection)

          if truba_definitions.empty?
            ::UI.messagebox(
              "Выдели в модели один инстанс «Профильная труба» (созданный через " \
              "NN FabKit → MetalFab → Создать «Профильная труба»…) и попробуй снова.\n\n" \
              "Признак трубы — наличие atribute_dictionary `nn_metalfab` " \
              "с `profile_type=rect_tube` на definition."
            )
            return
          end

          if truba_definitions.size > 1
            ::UI.messagebox(
              "Выделено #{truba_definitions.size} разных definitions «Профильная труба». " \
              "На этом шаге IGES-экспорт работает по одной трубе. " \
              "Выдели один инстанс и повтори."
            )
            return
          end

          definition = truba_definitions.first
          attrs_dict = definition.attribute_dictionary("nn_metalfab")
          typesize   = attrs_dict["typesize"].to_s
          length_mm  = attrs_dict["length_mm"].to_f
          length_str = length_mm > 0 ? length_mm.to_i.to_s : "?"

          default_name = "truba-#{typesize}-L#{length_str}.igs"
          default_dir  = (model.path && !model.path.empty?) ? File.dirname(model.path) : nil
          path = ::UI.savepanel(TITLE, default_dir, default_name)
          return unless path
          path = "#{path}.igs" unless path.match?(/\.igs$|\.iges$/i)

          begin
            result = IgesExporter::Wireframe.export(definition, path)
          rescue StandardError => e
            ::UI.messagebox("Ошибка при экспорте IGES:\n\n#{e.class}: #{e.message}")
            puts "[NN::MetalFab::ExportIges] ERROR: #{e.class}: #{e.message}"
            puts e.backtrace.first(8).map { |l| "  #{l}" }.join("\n")
            return
          end

          ::UI.messagebox(
            "IGES сохранён:\n\n#{result[:path]}\n\n" \
            "Сущности: #{result[:entity_count]} (lines: #{result[:line_count]}, arcs: #{result[:arc_count]})\n" \
            "Длина: #{result[:length_mm].to_i} мм\n\n" \
            "Это wireframe-представление (Type 110 + Type 100). Для полного " \
            "BREP с поверхностями нужен следующий sprint — surface model."
          )
        end

        # Из selection вытащить уникальные definitions, у которых есть `nn_metalfab.profile_type=rect_tube`.
        def pick_truba_definitions(selection)
          defs = []
          selection.each do |ent|
            next unless ent.is_a?(Sketchup::ComponentInstance)
            d = ent.definition
            dict = d.attribute_dictionary("nn_metalfab")
            next unless dict && dict["profile_type"] == "rect_tube"
            defs << d unless defs.include?(d)
          end
          defs
        end
      end
    end
  end
end
