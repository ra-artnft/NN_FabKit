# encoding: UTF-8

require "stringio"

module NN
  module FabKit
    module Mcp
      # Registry для tools. `Handlers.lookup("eval_ruby") → Proc`.
      # Регистрация — Handlers.register("name") { |params| ... }.
      module Handlers
        REGISTRY = {}

        module_function

        def lookup(name)
          REGISTRY[name]
        end

        def register(name, &block)
          REGISTRY[name.to_s] = block
        end

        # ----- Built-in tools -----

        # eval_ruby — universal escape hatch. Выполняет произвольный Ruby код в
        # main object SketchUp. Перехватывает $stdout (puts/print) и возвращает
        # value + captured output. Доступ к Sketchup, NN::FabKit::*, NN::MetalFab::*.
        register("eval_ruby") do |params|
          code = params["code"].to_s
          raise ArgumentError, "params.code is required (non-empty string)" if code.empty?

          captured = StringIO.new
          original = $stdout
          $stdout = captured

          value = nil
          begin
            value = TOPLEVEL_BINDING.eval(code)
          ensure
            $stdout = original
          end

          {
            "value" => Handlers.serialize_value(value),
            "stdout" => captured.string
          }
        end

        # get_scene_info — быстрый снапшот модели (без heavy dump).
        register("get_scene_info") do |_params|
          model = Sketchup.active_model
          if model.nil?
            { "model" => nil }
          else
            sel = model.selection
            bounds = model.bounds
            {
              "title"             => model.title.to_s,
              "path"              => model.path.to_s,
              "definitions_count" => model.definitions.size,
              "instances_count"   => model.entities.grep(Sketchup::ComponentInstance).size,
              "materials_count"   => model.materials.size,
              "selection_count"   => sel.size,
              "selection"         => sel.to_a.first(20).map { |e| Handlers.entity_brief(e) },
              "bounds_mm"         => Handlers.bounds_to_mm(bounds)
            }
          end
        end

        # dump_model — обёртка над SkpDump. Возвращает путь и размер.
        register("dump_model") do |params|
          path = params["path"]
          path = nil if path.is_a?(String) && path.empty?
          result_path = NN::FabKit::SkpDump.run(path: path)
          raise "SkpDump failed (model not open or write error)" unless result_path
          {
            "saved_to" => result_path,
            "size_kb"  => (File.size(result_path) / 1024.0).round(2)
          }
        end

        # layout_create_template — A4 portrait LayOut-документ для активной
        # SU-сцены: title block + 3D viewport + cut-list по rect_tube
        # инстансам. Реквизиты meta перекрывают default'ы (project, customer,
        # date, scale, header).
        register("layout_create_template") do |params|
          path = params["path"].to_s
          raise ArgumentError, "params.path is required (.layout output path)" if path.empty?
          meta = params["meta"]
          meta = nil unless meta.is_a?(Hash)
          NN::MetalFab::LayoutGen::TemplateCutList.generate(
            output_path: path,
            meta: meta
          )
        end

        # layout_export_pdf — экспортирует существующий .layout в PDF.
        register("layout_export_pdf") do |params|
          src = params["layout_path"].to_s
          dst = params["pdf_path"].to_s
          raise ArgumentError, "params.layout_path is required" if src.empty?
          raise ArgumentError, "params.pdf_path is required" if dst.empty?
          NN::MetalFab::LayoutGen::TemplateCutList.export_pdf(
            layout_path: src,
            pdf_path: dst
          )
        end

        # ----- Helpers -----

        def serialize_value(v)
          case v
          when nil, true, false, Numeric, String
            v
          when Symbol
            v.to_s
          when Array
            v.map { |x| serialize_value(x) }
          when Hash
            v.each_with_object({}) { |(k, val), h| h[k.to_s] = serialize_value(val) }
          when Sketchup::Color
            { "r" => v.red, "g" => v.green, "b" => v.blue, "a" => v.alpha }
          when Geom::Point3d
            [(v.x.to_f * 25.4).round(3), (v.y.to_f * 25.4).round(3), (v.z.to_f * 25.4).round(3)]
          when Geom::Vector3d
            [v.x.to_f.round(6), v.y.to_f.round(6), v.z.to_f.round(6)]
          else
            # Безопасный fallback на inspect — не теряем информацию, но не пытаемся
            # сериализовать неизвестные SU-объекты глубоко.
            v.inspect
          end
        end

        def entity_brief(ent)
          base = { "class" => ent.class.name, "persistent_id" => ent.persistent_id }
          case ent
          when Sketchup::ComponentInstance
            base["definition_name"] = ent.definition.name
            base["nn_metalfab"] = (ent.definition.attribute_dictionary("nn_metalfab")&.to_h || {})
          when Sketchup::Group
            base["name"] = ent.name
          end
          base
        end

        def bounds_to_mm(b)
          {
            "min"  => [(b.min.x.to_f * 25.4).round(3), (b.min.y.to_f * 25.4).round(3), (b.min.z.to_f * 25.4).round(3)],
            "max"  => [(b.max.x.to_f * 25.4).round(3), (b.max.y.to_f * 25.4).round(3), (b.max.z.to_f * 25.4).round(3)],
            "size" => [(b.width.to_f * 25.4).round(3), (b.height.to_f * 25.4).round(3), (b.depth.to_f * 25.4).round(3)]
          }
        end
      end
    end
  end
end
