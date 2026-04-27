# encoding: UTF-8

module NN
  module FabKit
    Sketchup.require "nn_fabkit/version"
    Sketchup.require "nn_fabkit/skp_dump"

    # MetalFab branch — Sketchup.require рекурсивно подгружает модули металл-ветки.
    Sketchup.require "nn_fabkit/metalfab/attr_dict"
    Sketchup.require "nn_fabkit/metalfab/dc_attrs"
    Sketchup.require "nn_fabkit/metalfab/catalog"
    Sketchup.require "nn_fabkit/metalfab/profile_generator/rect_tube"
    Sketchup.require "nn_fabkit/metalfab/profile_generator/rect_tube_mitre"
    Sketchup.require "nn_fabkit/metalfab/iges_exporter/wireframe"
    Sketchup.require "nn_fabkit/metalfab/commands/create_rect_tube"
    Sketchup.require "nn_fabkit/metalfab/commands/export_iges"
    Sketchup.require "nn_fabkit/metalfab/tools/fabkit_cad_tool"
    # MetalFab × LayOut — генераторы LayOut-чертежей (cut-list, чертежи рам и т.п.)
    Sketchup.require "nn_fabkit/metalfab/layout/template_cut_list"
    Sketchup.require "nn_fabkit/metalfab/commands/export_layout_pdf"

    # FabKit зонтик — общие команды (updater и т.п.)
    Sketchup.require "nn_fabkit/updater"
    Sketchup.require "nn_fabkit/commands/check_update"

    # MCP мост — TCP сервер JSON-RPC для удалённого управления Claude'ом.
    # Сам сервер по умолчанию НЕ стартует (запускается явно из меню — security baseline).
    Sketchup.require "nn_fabkit/mcp/handlers"
    Sketchup.require "nn_fabkit/mcp/jsonrpc"
    Sketchup.require "nn_fabkit/mcp/server"
    Sketchup.require "nn_fabkit/commands/mcp_control"

    # UI — постоянная панель Inspector (HtmlDialog), toolbar-кнопка
    # в верхней workspace area, меню.
    Sketchup.require "nn_fabkit/ui/inspector"
    Sketchup.require "nn_fabkit/ui/toolbar"
    Sketchup.require "nn_fabkit/ui/menu"

    unless file_loaded?(__FILE__)
      NN::FabKit::UI::Menu.register!
      NN::FabKit::UI::Toolbar.register!
      # Фоновая проверка обновлений (через 3 сек после старта SU): если
      # доступна новая версия — popup MB_YESNO «Обновить / Игнорировать».
      # Сетевые ошибки тихо глотает, не блокирует загрузку SU.
      NN::FabKit::Commands::CheckUpdate.background_check_on_startup
      # MCP-сервер auto-start (v0.11.11+) — запускается через UI.start_timer
      # 2s после load чтобы SU успел инициализироваться. TCP порт 127.0.0.1:9876
      # (default). Если порт занят (другой instance SU уже слушает) — log error,
      # SU не падает. Manual control остаётся через menu Extensions → NN FabKit
      # → MCP сервер → Запустить/Остановить.
      ::UI.start_timer(2.0, false) do
        begin
          NN::FabKit::Mcp.start
          puts "[NN::FabKit] MCP сервер auto-started on plugin load"
        rescue StandardError => e
          puts "[NN::FabKit] MCP auto-start failed: #{e.class}: #{e.message}"
        end
      end
      file_loaded(__FILE__)
    end
  end
end
