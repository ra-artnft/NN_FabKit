# encoding: UTF-8
# ============================================================================
# skp_dump.rb — SketchUp-модель → JSON-дамп для корпуса примеров
# ----------------------------------------------------------------------------
# Назначение: выгружает текущую модель SketchUp в структурированный JSON-файл,
# который потом кладётся в папку примера (см. ADR-015) и используется Claude
# как входной контекст.
#
# Применение:
#   - Из плагина: Extensions → NN FabKit → Dump в JSON…
#   - Из Ruby Console: NN::FabKit::SkpDump.run(path: "C:/tmp/my.dump.json")
#
# Поведение (без явного path):
#   - Если модель сохранена — рядом с .skp файлом, имя <basename>.dump.json.
#   - Если модель не сохранена — на Рабочий стол с timestamp'ом.
#
# Совместимость: SketchUp 2021+, Ruby 2.7 синтаксис.
#
# Канонический исходник: docs/knowledge-base/tools/skp_dump.rb. Этот файл
# в плагине — синхронизированная копия (без автозапуска при загрузке).
# ============================================================================

require "json"
require "fileutils"

module NN
  module FabKit
    module SkpDump
      VERSION = "1.0.0"
      SCHEMA_VERSION = "1.0"

      # Единицы: в SketchUp всё хранится в дюймах. В дампе — в миллиметрах
      # с точностью до 3 знаков. Удобнее и для чтения, и для анализа.
      INCH_TO_MM = 25.4

      # Чтобы не ронять SketchUp на моделях с десятками тысяч entities,
      # ставим потолок на детали внутри definition. По достижении лимита
      # дамп переходит в режим summary (только faces/edges counts).
      ENTITIES_DETAIL_LIMIT = 5000

      module_function

      def run(path: nil)
        model = Sketchup.active_model
        unless model
          puts "[SkpDump] Sketchup.active_model вернул nil — модель не открыта."
          return nil
        end

        started = Time.now
        output_path = resolve_output_path(model, path)

        puts "[SkpDump] Старт. Путь: #{output_path}"

        data = build_dump(model)

        FileUtils.mkdir_p(File.dirname(output_path))
        File.open(output_path, "w:UTF-8") do |f|
          f.write(JSON.pretty_generate(data))
        end

        elapsed = (Time.now - started).round(2)
        size_kb = (File.size(output_path) / 1024.0).round(1)
        puts "[SkpDump] Готово. #{size_kb} KB за #{elapsed} сек."
        puts "[SkpDump] Файл: #{output_path}"
        output_path
      rescue StandardError => e
        puts "[SkpDump] ОШИБКА: #{e.class}: #{e.message}"
        puts e.backtrace.first(8).map { |l| "  #{l}" }.join("\n")
        nil
      end

      # ------------------------------------------------------------------
      # Path resolution
      # ------------------------------------------------------------------

      def resolve_output_path(model, explicit)
        return explicit if explicit && !explicit.empty?

        skp_path = model.path
        if skp_path && !skp_path.empty?
          base = File.basename(skp_path, ".*")
          dir = File.dirname(skp_path)
          File.join(dir, "#{base}.dump.json")
        else
          # Модель не сохранена. Кладём на рабочий стол с timestamp'ом.
          desktop = if Sketchup.platform == :platform_win
                      File.join(ENV["USERPROFILE"] || Dir.home, "Desktop")
                    else
                      File.join(Dir.home, "Desktop")
                    end
          timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
          File.join(desktop, "skp-dump-#{timestamp}.dump.json")
        end
      end

      # ------------------------------------------------------------------
      # Top-level dump assembly
      # ------------------------------------------------------------------

      def build_dump(model)
        {
          "$schema_version" => SCHEMA_VERSION,
          "dumper" => {
            "name" => "NN::FabKit::SkpDump",
            "version" => VERSION
          },
          "dumped_at" => Time.now.iso8601,
          "sketchup" => sketchup_env,
          "model" => model_meta(model),
          "units" => units_info(model),
          "layers" => dump_layers(model),
          "materials" => dump_materials(model),
          "styles" => dump_styles(model),
          "pages" => dump_pages(model),
          "definitions" => dump_definitions(model),
          "root_entities" => dump_entities(model.entities, context: "model_root"),
          "statistics" => statistics(model)
        }
      end

      # ------------------------------------------------------------------
      # Environment metadata
      # ------------------------------------------------------------------

      def sketchup_env
        {
          "version" => Sketchup.version,
          "version_number" => Sketchup.version_number,
          "is_pro" => Sketchup.is_pro?,
          "platform" => Sketchup.platform.to_s,
          "ruby_version" => RUBY_VERSION
        }
      end

      def model_meta(model)
        {
          "title" => model.title,
          "path" => model.path,
          "guid" => model.guid,
          "description" => model.description,
          "active_path" => (model.active_path ? model.active_path.map(&:persistent_id) : nil),
          "attributes" => dump_attribute_dictionaries(model)
        }
      end

      def units_info(model)
        opts = model.options["UnitsOptions"]
        return nil unless opts
        {
          "length_unit" => opts["LengthUnit"],     # 0=inch, 1=feet, 2=mm, 3=cm, 4=m
          "length_format" => opts["LengthFormat"],
          "length_precision" => opts["LengthPrecision"],
          "angle_unit" => opts["AngleUnit"],
          "angle_precision" => opts["AnglePrecision"]
        }
      rescue StandardError => e
        { "error" => e.message }
      end

      # ------------------------------------------------------------------
      # Layers / Tags
      # ------------------------------------------------------------------

      def dump_layers(model)
        model.layers.map do |layer|
          {
            "name" => layer.name,
            "display_name" => layer.display_name,
            "visible" => layer.visible?,
            "color" => color_to_hash(layer.color),
            "line_style" => (layer.line_style ? layer.line_style.name : nil),
            "persistent_id" => layer.persistent_id
          }
        end
      end

      # ------------------------------------------------------------------
      # Materials
      # ------------------------------------------------------------------

      def dump_materials(model)
        model.materials.map do |m|
          {
            "name" => m.name,
            "display_name" => m.display_name,
            "color" => color_to_hash(m.color),
            "alpha" => m.alpha,
            "texture" => (m.texture ? texture_info(m.texture) : nil),
            "attributes" => dump_attribute_dictionaries(m)
          }
        end
      end

      def texture_info(tex)
        {
          "filename" => tex.filename,
          "width_mm" => (tex.width.to_f * INCH_TO_MM).round(3),
          "height_mm" => (tex.height.to_f * INCH_TO_MM).round(3)
        }
      rescue StandardError
        nil
      end

      # ------------------------------------------------------------------
      # Styles / Pages (scenes)
      # ------------------------------------------------------------------

      def dump_styles(model)
        {
          "count" => model.styles.size,
          "active" => (model.styles.active_style ? model.styles.active_style.name : nil)
        }
      end

      def dump_pages(model)
        model.pages.map do |page|
          {
            "name" => page.name,
            "label" => page.label,
            "description" => page.description,
            "hidden" => page.hidden?,
            "transition_time" => page.transition_time,
            "delay_time" => page.delay_time,
            "use_camera" => page.use_camera?,
            "use_rendering_options" => page.use_rendering_options?,
            "use_hidden_geometry" => (page.respond_to?(:use_hidden_geometry?) ? page.use_hidden_geometry? : nil),
            "use_axes" => page.use_axes?,
            "use_section_planes" => page.use_section_planes?
          }
        end
      end

      # ------------------------------------------------------------------
      # Component Definitions
      # ------------------------------------------------------------------

      def dump_definitions(model)
        model.definitions.map do |defn|
          next nil if defn.image?  # пропускаем image-definitions
          {
            "name" => defn.name,
            "guid" => defn.guid,
            "persistent_id" => defn.persistent_id,
            "description" => defn.description,
            "path" => defn.path,
            "is_group_definition" => defn.group?,
            "instance_count" => defn.count_used_instances,
            "bounds_mm" => bounds_to_hash(defn.bounds),
            "insertion_point_mm" => point_to_hash(defn.insertion_point),
            "attributes" => dump_attribute_dictionaries(defn),
            "entities_summary" => entities_summary(defn.entities),
            "entities_detail" => (defn.group? ? nil : dump_entities(defn.entities, context: "definition:#{defn.name}"))
          }
        end.compact
      end

      # ------------------------------------------------------------------
      # Entities inside a container (model root / definition / group)
      # ------------------------------------------------------------------

      def dump_entities(entities, context:)
        count = entities.size
        if count > ENTITIES_DETAIL_LIMIT
          return {
            "note" => "skipped_detail_due_to_size",
            "limit" => ENTITIES_DETAIL_LIMIT,
            "actual" => count,
            "summary" => entities_summary(entities)
          }
        end

        result = {
          "summary" => entities_summary(entities),
          "component_instances" => [],
          "groups" => [],
          "faces" => [],
          "edges" => [],
          "construction_lines" => [],
          "construction_points" => [],
          "texts" => [],
          "dimensions" => [],
          "section_planes" => [],
          "images" => []
        }

        entities.each do |ent|
          case ent
          when Sketchup::ComponentInstance then result["component_instances"] << dump_component_instance(ent)
          when Sketchup::Group             then result["groups"]              << dump_group(ent)
          when Sketchup::Face              then result["faces"]               << dump_face(ent)
          when Sketchup::Edge              then result["edges"]               << dump_edge(ent)
          when Sketchup::ConstructionLine  then result["construction_lines"]  << dump_cline(ent)
          when Sketchup::ConstructionPoint then result["construction_points"] << dump_cpoint(ent)
          when Sketchup::Text              then result["texts"]               << dump_text(ent)
          when Sketchup::Dimension         then result["dimensions"]          << dump_dimension(ent)
          when Sketchup::SectionPlane      then result["section_planes"]      << dump_section_plane(ent)
          when Sketchup::Image             then result["images"]              << dump_image(ent)
          end
        end

        result
      end

      def entities_summary(entities)
        summary = Hash.new(0)
        entities.each do |ent|
          summary[ent.class.name.split("::").last] += 1
        end
        summary["total"] = entities.size
        summary
      end

      # ------------------------------------------------------------------
      # Individual entity dumpers
      # ------------------------------------------------------------------

      def dump_component_instance(inst)
        {
          "persistent_id" => inst.persistent_id,
          "name" => inst.name,
          "definition_name" => inst.definition.name,
          "definition_guid" => inst.definition.guid,
          "layer" => (inst.layer ? inst.layer.name : nil),
          "material" => (inst.material ? inst.material.name : nil),
          "hidden" => inst.hidden?,
          "locked" => inst.locked?,
          "transformation" => transformation_to_hash(inst.transformation),
          "bounds_mm" => bounds_to_hash(inst.bounds),
          "attributes" => dump_attribute_dictionaries(inst)
        }
      end

      def dump_group(grp)
        {
          "persistent_id" => grp.persistent_id,
          "name" => grp.name,
          "definition_name" => (grp.respond_to?(:definition) ? grp.definition.name : nil),
          "layer" => (grp.layer ? grp.layer.name : nil),
          "material" => (grp.material ? grp.material.name : nil),
          "hidden" => grp.hidden?,
          "locked" => grp.locked?,
          "transformation" => transformation_to_hash(grp.transformation),
          "bounds_mm" => bounds_to_hash(grp.bounds),
          "attributes" => dump_attribute_dictionaries(grp),
          "entities" => dump_entities(grp.entities, context: "group:#{grp.name}")
        }
      end

      def dump_face(face)
        {
          "persistent_id" => face.persistent_id,
          "area_mm2" => (face.area.to_f * INCH_TO_MM * INCH_TO_MM).round(3),
          "normal" => vector_to_hash(face.normal),
          "material" => (face.material ? face.material.name : nil),
          "back_material" => (face.back_material ? face.back_material.name : nil),
          "layer" => (face.layer ? face.layer.name : nil),
          "vertex_count" => face.vertices.size,
          "loop_count" => face.loops.size,
          "has_inner_loops" => face.loops.any? { |l| !l.outer? },
          "outer_vertices_mm" => face.outer_loop.vertices.map { |v| point_to_hash(v.position) },
          "attributes" => dump_attribute_dictionaries(face)
        }
      end

      def dump_edge(edge)
        {
          "persistent_id" => edge.persistent_id,
          "length_mm" => (edge.length.to_f * INCH_TO_MM).round(3),
          "start_mm" => point_to_hash(edge.start.position),
          "end_mm" => point_to_hash(edge.end.position),
          "soft" => edge.soft?,
          "smooth" => edge.smooth?,
          "hidden" => edge.hidden?,
          "layer" => (edge.layer ? edge.layer.name : nil),
          "faces_count" => edge.faces.size
        }
      end

      def dump_cline(cline)
        {
          "persistent_id" => cline.persistent_id,
          "start_mm" => point_to_hash(cline.start),
          "end_mm" => point_to_hash(cline.end),
          "stipple" => cline.stipple,
          "layer" => (cline.layer ? cline.layer.name : nil)
        }
      end

      def dump_cpoint(cpt)
        {
          "persistent_id" => cpt.persistent_id,
          "position_mm" => point_to_hash(cpt.position),
          "layer" => (cpt.layer ? cpt.layer.name : nil)
        }
      end

      def dump_text(txt)
        {
          "persistent_id" => txt.persistent_id,
          "text" => txt.text,
          "point_mm" => point_to_hash(txt.point),
          "leader_type" => txt.leader_type,
          "layer" => (txt.layer ? txt.layer.name : nil)
        }
      end

      def dump_dimension(dim)
        {
          "persistent_id" => dim.persistent_id,
          "class" => dim.class.name,
          "text" => (dim.respond_to?(:text) ? dim.text : nil),
          "layer" => (dim.layer ? dim.layer.name : nil)
        }
      end

      def dump_section_plane(sp)
        {
          "persistent_id" => sp.persistent_id,
          "name" => sp.name,
          "symbol" => sp.symbol,
          "active" => sp.active?,
          "layer" => (sp.layer ? sp.layer.name : nil)
        }
      end

      def dump_image(img)
        {
          "persistent_id" => img.persistent_id,
          "path" => img.path,
          "width_mm" => (img.width.to_f * INCH_TO_MM).round(3),
          "height_mm" => (img.height.to_f * INCH_TO_MM).round(3),
          "origin_mm" => point_to_hash(img.origin),
          "layer" => (img.layer ? img.layer.name : nil)
        }
      end

      # ------------------------------------------------------------------
      # Attribute dictionaries
      # ------------------------------------------------------------------

      def dump_attribute_dictionaries(entity)
        dicts = entity.attribute_dictionaries
        return {} unless dicts
        result = {}
        dicts.each do |dict|
          result[dict.name] = dump_dictionary(dict)
        end
        result
      end

      def dump_dictionary(dict)
        data = {}
        dict.each_pair do |key, value|
          data[key.to_s] = serialize_attribute_value(value)
        end
        data
      end

      def serialize_attribute_value(value)
        case value
        when nil, true, false, String, Integer, Float
          value
        when Length
          (value.to_f * INCH_TO_MM).round(3)
        when Geom::Point3d
          point_to_hash(value)
        when Geom::Vector3d
          vector_to_hash(value)
        when Sketchup::Color
          color_to_hash(value)
        when Array
          value.map { |v| serialize_attribute_value(v) }
        when Time
          value.iso8601
        else
          # Fallback: аккуратно приводим к строке, чтобы не уронить дамп на экзотике.
          { "_unserialized_class" => value.class.name, "inspect" => value.inspect }
        end
      end

      # ------------------------------------------------------------------
      # Geom helpers: всё наружу отдаём в мм
      # ------------------------------------------------------------------

      def point_to_hash(pt)
        return nil unless pt
        {
          "x" => (pt.x.to_f * INCH_TO_MM).round(3),
          "y" => (pt.y.to_f * INCH_TO_MM).round(3),
          "z" => (pt.z.to_f * INCH_TO_MM).round(3)
        }
      end

      def vector_to_hash(vec)
        return nil unless vec
        {
          "x" => vec.x.to_f.round(6),
          "y" => vec.y.to_f.round(6),
          "z" => vec.z.to_f.round(6)
        }
      end

      def bounds_to_hash(b)
        return nil unless b
        {
          "min_mm" => point_to_hash(b.min),
          "max_mm" => point_to_hash(b.max),
          "width_mm" => (b.width.to_f * INCH_TO_MM).round(3),
          "height_mm" => (b.height.to_f * INCH_TO_MM).round(3),
          "depth_mm" => (b.depth.to_f * INCH_TO_MM).round(3),
          "diagonal_mm" => (b.diagonal.to_f * INCH_TO_MM).round(3)
        }
      end

      def transformation_to_hash(t)
        return nil unless t
        arr = t.to_a  # 16 floats, column-major
        {
          "matrix_column_major" => arr.map { |v| v.to_f.round(9) },
          "origin_mm" => point_to_hash(t.origin),
          "xaxis" => vector_to_hash(t.xaxis),
          "yaxis" => vector_to_hash(t.yaxis),
          "zaxis" => vector_to_hash(t.zaxis),
          "scale_uniform" => (uniform_scale?(t) ? t.xscale.to_f.round(6) : nil),
          "xscale" => t.xscale.to_f.round(6),
          "yscale" => t.yscale.to_f.round(6),
          "zscale" => t.zscale.to_f.round(6),
          "identity" => t.identity?
        }
      end

      def uniform_scale?(t)
        sx = t.xscale.to_f
        sy = t.yscale.to_f
        sz = t.zscale.to_f
        (sx - sy).abs < 1e-6 && (sy - sz).abs < 1e-6
      end

      def color_to_hash(color)
        return nil unless color
        {
          "r" => color.red,
          "g" => color.green,
          "b" => color.blue,
          "a" => color.alpha
        }
      end

      # ------------------------------------------------------------------
      # Aggregate statistics
      # ------------------------------------------------------------------

      def statistics(model)
        defs = model.definitions.reject(&:image?)
        instances = defs.flat_map(&:instances)
        total_faces = 0
        total_edges = 0

        defs.each do |d|
          next if d.group?  # считаем только через instances чтобы не множить
          d.entities.each do |e|
            case e
            when Sketchup::Face then total_faces += 1
            when Sketchup::Edge then total_edges += 1
            end
          end
        end

        {
          "definitions_total" => defs.size,
          "definitions_components" => defs.count { |d| !d.group? },
          "definitions_groups" => defs.count(&:group?),
          "instances_total" => instances.size,
          "materials_total" => model.materials.size,
          "layers_total" => model.layers.size,
          "pages_total" => model.pages.size,
          "root_entities_total" => model.entities.size,
          "faces_in_definitions" => total_faces,
          "edges_in_definitions" => total_edges
        }
      end
    end
  end
end
