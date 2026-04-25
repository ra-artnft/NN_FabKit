# encoding: UTF-8

require "json"

module NN
  module MetalFab
    # Загружает JSON-каталоги сортамента из catalogs/. Сейчас — только gost-30245-rect-tube.
    # Канонический исходник — docs/knowledge-base/gost-30245-rect-tube.json; копия в catalogs/
    # доставляется в .rbz, чтобы плагин был автономен. Синхронизация — вручную.
    module Catalog
      RECT_TUBE_PATH = File.join(__dir__, "catalogs", "gost-30245-rect-tube.json")

      module_function

      def rect_tube
        @rect_tube ||= JSON.parse(File.read(RECT_TUBE_PATH, encoding: "UTF-8"))
      end

      def rect_tube_items
        rect_tube["items"] || []
      end

      def rect_tube_typesizes
        rect_tube_items.map { |i| i["typesize"] }
      end

      def find_rect_tube(typesize)
        rect_tube_items.find { |i| i["typesize"] == typesize }
      end

      def rect_tube_grades
        rect_tube["available_grades"] || []
      end

      def rect_tube_default_grade
        rect_tube["default_grade"]
      end
    end
  end
end
