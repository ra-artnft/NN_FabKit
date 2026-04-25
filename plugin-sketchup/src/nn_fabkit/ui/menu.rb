# encoding: UTF-8

module NN
  module FabKit
    module UI
      module Menu
        def self.register!
          parent = ::UI.menu("Extensions").add_submenu("NN FabKit")

          # Общие команды зонтика
          parent.add_item("Dump в JSON…")    { dump_to_json }

          # Submenu MetalFab — металл-ветка
          metalfab = parent.add_submenu("MetalFab")
          metalfab.add_item("Создать «Профильная труба»…") { create_rect_tube }

          parent.add_separator
          parent.add_item("О плагине…")      { show_about }
        end

        def self.dump_to_json
          model = Sketchup.active_model
          unless model
            ::UI.messagebox("Открой модель в SketchUp перед запуском дампа.")
            return
          end

          path = NN::FabKit::SkpDump.run
          if path && File.exist?(path)
            ::UI.messagebox("Дамп сохранён:\n\n#{path}")
          else
            ::UI.messagebox(
              "Не удалось создать дамп.\n\n" \
              "Подробности — в Window → Ruby Console (префикс [SkpDump])."
            )
          end
        end

        def self.create_rect_tube
          NN::MetalFab::Commands::CreateRectTube.call
        end

        def self.show_about
          ::UI.messagebox(
            "NN FabKit v#{NN::FabKit::VERSION}\n\n" \
            "Плагин для проектирования металлоконструкций и мебели.\n\n" \
            "SketchUp #{Sketchup.version}"
          )
        end
      end
    end
  end
end
