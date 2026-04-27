# encoding: UTF-8

module NN
  module FabKit
    module UI
      module Menu
        def self.register!
          parent = ::UI.menu("Extensions").add_submenu("NN FabKit")

          # Inspector — основной UI плагина (spec-03). Постоянная боковая
          # панель, через которую идут все команды; меню остаётся как fallback.
          parent.add_item("Открыть Inspector")               { open_inspector }
          parent.add_separator

          # Общие команды зонтика
          parent.add_item("Dump в JSON…")    { dump_to_json }

          # Submenu MetalFab — металл-ветка
          metalfab = parent.add_submenu("MetalFab")
          metalfab.add_item("Создать «Профильная труба»…")          { create_rect_tube }
          metalfab.add_item("FabKit CAD — mitre cut…")              { fabkit_cad }
          metalfab.add_separator
          metalfab.add_item("Создать PDF cut-list…")                { export_layout_pdf }
          metalfab.add_separator
          metalfab.add_item("Экспорт «Профильная труба» в IGES…")   { export_iges }

          # Submenu MCP сервер — мост Claude ⇄ SketchUp
          mcp = parent.add_submenu("MCP сервер")
          mcp.add_item("Запустить…")    { mcp_start }
          mcp.add_item("Остановить")    { mcp_stop }
          mcp.add_item("Статус")        { mcp_status }

          parent.add_separator
          parent.add_item("Проверить обновления…")                  { check_update }
          parent.add_item("Сменить URL обновлений…")                { change_update_url }
          parent.add_item("Test: фоновая проверка (без задержки)")  { force_check_update }
          parent.add_separator
          parent.add_item("О плагине…")                             { show_about }
        end

        def self.open_inspector
          NN::FabKit::UI::Inspector.show
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

        def self.fabkit_cad
          ::Sketchup.active_model.select_tool(NN::MetalFab::Tools::FabKitCadTool.new)
        end

        def self.export_iges
          NN::MetalFab::Commands::ExportIges.call
        end

        def self.export_layout_pdf
          NN::MetalFab::Commands::ExportLayoutPdf.call
        end

        def self.check_update
          NN::FabKit::Commands::CheckUpdate.call
        end

        def self.change_update_url
          NN::FabKit::Commands::CheckUpdate.change_url
        end

        def self.force_check_update
          NN::FabKit::Commands::CheckUpdate.force_check_now
        end

        def self.mcp_start
          NN::FabKit::Commands::McpControl.start
        end

        def self.mcp_stop
          NN::FabKit::Commands::McpControl.stop
        end

        def self.mcp_status
          NN::FabKit::Commands::McpControl.status
        end

        def self.show_about
          mcp = NN::FabKit::Mcp.status
          mcp_line = mcp[:running] ? "MCP: 🟢 #{mcp[:host]}:#{mcp[:port]}" : "MCP: ⚪ не запущен"
          ::UI.messagebox(
            "NN FabKit v#{NN::FabKit::VERSION}\n\n" \
            "Плагин для проектирования металлоконструкций и мебели.\n\n" \
            "SketchUp #{Sketchup.version}\n#{mcp_line}"
          )
        end
      end
    end
  end
end
