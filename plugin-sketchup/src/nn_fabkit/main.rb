# encoding: UTF-8

module NN
  module FabKit
    Sketchup.require "nn_fabkit/version"
    Sketchup.require "nn_fabkit/skp_dump"
    Sketchup.require "nn_fabkit/ui/menu"

    unless file_loaded?(__FILE__)
      NN::FabKit::UI::Menu.register!
      file_loaded(__FILE__)
    end
  end
end
