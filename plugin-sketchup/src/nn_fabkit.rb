# encoding: UTF-8

if Sketchup.version.to_i < 21
  UI.messagebox("NN FabKit требует SketchUp 2021 или новее.")
  return
end

module NN
  module FabKit
    unless defined?(EXTENSION)
      ext = SketchupExtension.new(
        "NN FabKit",
        File.join(File.dirname(__FILE__), "nn_fabkit", "main")
      )
      ext.creator     = "NN"
      ext.version     = "0.1.0"
      ext.copyright   = "© 2026 NN"
      ext.description = "Проектирование металлоконструкций и мебели: " \
                        "параметрические компоненты, ТЗ в LayOut, экспорт в NC-форматы."
      Sketchup.register_extension(ext, true)
      EXTENSION = ext
    end
  end
end
