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
      file_loaded(__FILE__)
    end
  end
end
