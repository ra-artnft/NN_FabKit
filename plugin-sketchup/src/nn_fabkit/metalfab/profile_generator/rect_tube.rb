# encoding: UTF-8

module NN
  module MetalFab
    module ProfileGenerator
      # Параметрический генератор геометрии прямоугольной/квадратной профильной трубы (LOD-1).
      #
      # Сечение — замкнутый rounded rectangle с inner loop (стенка):
      #   - внешний контур: width × height со скруглёнными углами radius = outer_radius_mm
      #   - внутренний контур: (width − 2×wall) × (height − 2×wall),
      #     inner_radius = max(0, outer_radius − wall)
      # Экструзия — Follow Me вдоль Z на длину length_mm.
      #
      # Бюджет (ADR-014, прямой рез): faces ≤ 60, edges ≤ 100, 8 сегментов на радиус.
      # 4 угла × 8 сегментов × 2 контура (outer+inner) ≈ 64 vertical edges + 64 caps
      # горизонтальных + 4 прямые стороны на каждом контуре. На грани бюджета —
      # фактический счёт пишется в `nn_metalfab.geom_budget_*`, превышение → флаг `heavy`.
      module RectTube
        SEGMENTS_PER_CORNER = 8
        FACES_LIMIT = 60
        EDGES_LIMIT = 100

        # Формула радиуса по умолчанию (06-sortament-ontology):
        # R = 1.5 × t для t ≤ 6 мм; R = 2.0 × t для t > 6 мм.
        # Фактические значения из таблиц ГОСТ могут отличаться в пределах 0.5 мм.
        def self.default_outer_radius(wall_mm)
          k = wall_mm.to_f > 6.0 ? 2.0 : 1.5
          (k * wall_mm.to_f).round(2)
        end

        # Полная сборка definition: чистка → профиль → экструзия → метаданные → бюджет.
        # Должна вызываться внутри start_operation/commit_operation.
        def self.build(definition, width_mm:, height_mm:, wall_mm:, length_mm:,
                       outer_radius_mm: nil, typesize: nil, gost: "30245-2003",
                       mass_per_m_kg: nil, steel_grade: nil)
          outer_radius_mm ||= default_outer_radius(wall_mm)

          ents = definition.entities
          ents.clear!

          profile_face = build_profile(ents, width_mm, height_mm, wall_mm, outer_radius_mm)
          smooth_arc_edges_in_profile(profile_face, width_mm, height_mm)
          extrude(ents, profile_face, length_mm)
          smooth_vertical_arc_edges(ents, length_mm, width_mm, height_mm)

          AttrDict.write_rect_tube(
            definition,
            typesize:        typesize || "#{width_mm}x#{height_mm}x#{wall_mm}",
            gost:            gost,
            width_mm:        width_mm,
            height_mm:       height_mm,
            wall_mm:         wall_mm,
            outer_radius_mm: outer_radius_mm,
            length_mm:       length_mm,
            mass_per_m_kg:   mass_per_m_kg,
            steel_grade:     steel_grade
          )

          DcAttrs.write_rect_tube(
            definition,
            name:            "Профильная труба",
            width_mm:        width_mm,
            height_mm:       height_mm,
            wall_mm:         wall_mm,
            length_mm:       length_mm,
            outer_radius_mm: outer_radius_mm
          )

          faces = ents.grep(Sketchup::Face).size
          edges = ents.grep(Sketchup::Edge).size
          heavy = AttrDict.write_geom_budget(
            definition,
            faces: faces, edges: edges,
            faces_limit: FACES_LIMIT, edges_limit: EDGES_LIMIT
          )
          warn_budget(definition, faces, edges) if heavy

          definition
        end

        # ----------------------------------------------------------------
        # Profile (rounded rect with inner loop) — в плоскости XY на z=0.
        # ----------------------------------------------------------------

        def self.build_profile(entities, width_mm, height_mm, wall_mm, outer_radius_mm)
          outer_pts = rounded_rect_points(width_mm, height_mm, outer_radius_mm, SEGMENTS_PER_CORNER)
          outer_face = entities.add_face(outer_pts)

          if wall_mm.to_f > 0 && wall_mm * 2 < width_mm && wall_mm * 2 < height_mm
            inner_w = width_mm - 2 * wall_mm
            inner_h = height_mm - 2 * wall_mm
            inner_r = [outer_radius_mm - wall_mm, 0.0].max
            inner_pts = rounded_rect_points(inner_w, inner_h, inner_r, SEGMENTS_PER_CORNER)

            # SketchUp-идиома: add_face поверх существующего outer_face в той же
            # плоскости автоматически образует inner loop в outer (отверстие).
            # erase! у inner_face оставляет outer с дыркой — сечение становится полым.
            # ВАЖНО: НЕ строить inner edges по одному через add_line — каждая линия
            # в плоскости face расщепляет face, и outer превращается в Deleted Entity.
            inner_face = entities.add_face(inner_pts)
            inner_face.erase! if inner_face && inner_face.valid?
          end

          # outer_face после операции может быть переcreated/replaced SketchUp'ом
          # при разрезании — перепривязываемся через find_entity_by_persistent_id
          # не нужно: SketchUp возвращает live-handle. Но проверим валидность.
          # Нормаль наверх (+Z), чтобы Follow Me экструдировал в +Z.
          if outer_face && outer_face.valid?
            outer_face.reverse! if outer_face.normal.z < 0
            outer_face
          else
            # Fallback: ищем самую большую face в entities — это наша outer.
            faces = entities.grep(Sketchup::Face)
            raise "Outer face не создалась" if faces.empty?
            biggest = faces.max_by(&:area)
            biggest.reverse! if biggest.normal.z < 0
            biggest
          end
        end

        # 4 угла × (SEGMENTS_PER_CORNER + 1) точек, дубликаты на стыках убираются.
        # Между углами add_face сам создаст прямые рёбра.
        def self.rounded_rect_points(width_mm, height_mm, radius_mm, segs)
          hw = width_mm.mm / 2.0
          hh = height_mm.mm / 2.0
          r  = [[radius_mm.mm, hw].min, hh].min  # cap radius до half-extent

          if r < 1.0e-6.mm
            return [
              Geom::Point3d.new( hw,  hh, 0),
              Geom::Point3d.new(-hw,  hh, 0),
              Geom::Point3d.new(-hw, -hh, 0),
              Geom::Point3d.new( hw, -hh, 0)
            ]
          end

          corners = [
            [ hw - r,  hh - r, 0.0],                   # NE: theta 0..PI/2
            [-hw + r,  hh - r, Math::PI / 2.0],        # NW: theta PI/2..PI
            [-hw + r, -hh + r, Math::PI],              # SW: theta PI..3PI/2
            [ hw - r, -hh + r, 3.0 * Math::PI / 2.0]   # SE: theta 3PI/2..2PI
          ]

          pts = []
          corners.each do |cx, cy, theta_start|
            (0..segs).each do |i|
              t = theta_start + (Math::PI / 2.0) * (i.to_f / segs)
              pts << Geom::Point3d.new(cx + r * Math.cos(t), cy + r * Math.sin(t), 0)
            end
          end

          # Удалить последовательные дубликаты на стыках углов.
          uniq = []
          pts.each do |p|
            uniq << p if uniq.empty? || uniq.last.distance(p) > 1.0e-9.mm
          end
          uniq
        end

        # ----------------------------------------------------------------
        # Extrusion — Follow Me по +Z на length_mm.
        # ----------------------------------------------------------------

        def self.extrude(entities, profile_face, length_mm)
          start_pt = Geom::Point3d.new(0, 0, 0)
          end_pt   = Geom::Point3d.new(0, 0, length_mm.mm)
          path = entities.add_line(start_pt, end_pt)
          profile_face.followme([path])
          path.erase! if path && path.valid?
          nil
        end

        # Помечает arc-edges профиля как soft+smooth: визуально дуга сегментируется
        # из 8 коротких рёбер в одну гладкую кривую. Геометрия не меняется
        # (NC-конвертёр по-прежнему получает 8 точек на радиус, плюс аналитический
        # радиус в nn_metalfab.outer_radius_mm). Меняется только rendering.
        # Прямые рёбра (топ/низ/лево/право прямоугольника) остаются hard.
        def self.smooth_arc_edges_in_profile(face, width_mm, height_mm)
          return unless face && face.valid?
          tol = 1.0e-3.mm
          hw = width_mm.mm / 2.0
          hh = height_mm.mm / 2.0
          face.edges.each do |edge|
            p1 = edge.start.position
            p2 = edge.end.position
            on_right  = (p1.x - hw).abs < tol && (p2.x - hw).abs < tol
            on_left   = (p1.x + hw).abs < tol && (p2.x + hw).abs < tol
            on_top    = (p1.y - hh).abs < tol && (p2.y - hh).abs < tol
            on_bottom = (p1.y + hh).abs < tol && (p2.y + hh).abs < tol
            next if on_right || on_left || on_top || on_bottom

            # Это arc-edge (на скруглении угла outer или на любом ребре inner loop —
            # inner лежит строго внутри outer и не касается его cardinal-границ).
            edge.soft   = true
            edge.smooth = true
          end
        end

        # После Follow Me каждый arc-сегмент порождает вертикальное ребро длиной
        # length_mm — на боковой поверхности трубы видны полоски каждые 11.25°.
        # Помечаем все вертикальные рёбра, не лежащие на 4 «угловых» прямых
        # (X=±hw, Y=±hh) как soft+smooth — труба смотрится как один цилиндр,
        # а не как 32-гранник.
        def self.smooth_vertical_arc_edges(entities, length_mm, width_mm, height_mm)
          tol = 1.0e-3.mm
          target_len = length_mm.mm
          hw = width_mm.mm / 2.0
          hh = height_mm.mm / 2.0
          entities.grep(Sketchup::Edge).each do |edge|
            v = edge.line[1]  # direction vector
            next unless v.parallel?(Z_AXIS)
            next unless (edge.length - target_len).abs < tol
            p = edge.start.position
            on_corner_line =
              (p.x - hw).abs < tol || (p.x + hw).abs < tol ||
              (p.y - hh).abs < tol || (p.y + hh).abs < tol
            next if on_corner_line
            edge.soft   = true
            edge.smooth = true
          end
        end

        def self.warn_budget(definition, faces, edges)
          puts "[NN::MetalFab] WARN: '#{definition.name}' over geometry budget — " \
               "faces=#{faces}/#{FACES_LIMIT}, edges=#{edges}/#{EDGES_LIMIT}"
        end
      end
    end
  end
end
