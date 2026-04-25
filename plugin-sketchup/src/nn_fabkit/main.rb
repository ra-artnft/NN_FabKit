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
    Sketchup.require "nn_fabkit/metalfab/iges_exporter/wireframe"
    Sketchup.require "nn_fabkit/metalfab/commands/create_rect_tube"
    Sketchup.require "nn_fabkit/metalfab/commands/export_iges"

    # FabKit зонтик — общие команды (updater и т.п.)
    Sketchup.require "nn_fabkit/updater"
    Sketchup.require "nn_fabkit/commands/check_update"

    Sketchup.require "nn_fabkit/ui/menu"

    unless file_loaded?(__FILE__)
      NN::FabKit::UI::Menu.register!
      file_loaded(__FILE__)
    end
  end
end
