# encoding: UTF-8

module NN
  module MetalFab
    module ProfileGenerator
      # Mitre-cut генератор для перпендикулярной rect_tube.
      #
      # Стратегия — vertex displacement через `Entities#transform_by_vectors`:
      # 1. Построить perpendicular tube (RectTube.build) с original params
      # 2. Найти все вершины на cut-конце (z=0 или z=length)
      # 3. Сдвинуть каждую по формуле dz = sign * y * tan(angle):
      #    - +Z end mitre под 45°: y=+H/2 → dz=+H/2; y=-H/2 → dz=-H/2
      #    - Остальные точки получают пропорциональный dz
      # 4. SU автоматически деформирует connected faces (side walls становятся
      #    trapezoid'ами, endcap наклонная плоскость остаётся планарной — все
      #    вершины cap'а удовлетворяют тому же z = length + y*tan(angle))
      # 5. Обновить attribute_dictionary `nn_metalfab` с cut info
      #
      # Преимущества vs intersect_with + erase:
      # - Не нужно создавать temp cutting face и iterate erase
      # - Нет артефактов open holes / unfilled cuts
      # - Деформация атомарная (transform_by_vectors), нет risk of mid-state corruption
      module RectTubeMitre
        # Перестроить definition с mitre cut на одном из концов.
        #
        # definition       — Sketchup::ComponentDefinition tube'а
        # end_axis_sign    — +1 если cut на z=length (top), -1 если на z=0 (bottom)
        # angle_deg        — угол mitre в градусах (0 = perpendicular, 45 = классический mitre)
        # params           — Hash от AttrDict.read_rect_tube_params (перед очисткой definition)
        # rebuild_with_cut с указанием направления «long side» mitre.
        #
        # tilt_dir_local — Geom::Vector3d в local coords трубы (XY, z=0).
        # Это направление куда extends длинная сторона mitre. Например:
        #   (0, 1, 0) → длинная сторона на +Y (cut tilts about X axis)
        #   (1, 0, 0) → длинная сторона на +X (cut tilts about Y axis)
        #   (0, -1, 0) → длинная сторона на -Y
        #   (1, 1, 0).normalize → диагональный mitre
        def self.rebuild_with_cut(definition, end_axis_sign:, angle_deg:, params:,
                                  tilt_dir_local: Geom::Vector3d.new(0, 1, 0))
          raise "definition пустой" unless definition && definition.valid?
          raise "params пустые"     unless params && params[:length_mm]
          raise "angle_deg вне диапазона (0..89)" unless angle_deg.between?(0.0, 89.0)
          raise "end_axis_sign должен быть +1 или -1" unless [1, -1].include?(end_axis_sign)

          tilt_dir = tilt_dir_local.normalize

          existing_z0_cut = params[:cut_z0_angle_deg] || 0.0
          existing_zL_cut = params[:cut_zL_angle_deg] || 0.0

          RectTube.build(
            definition,
            width_mm:        params[:width_mm],
            height_mm:       params[:height_mm],
            wall_mm:         params[:wall_mm],
            length_mm:       params[:length_mm],
            outer_radius_mm: params[:outer_radius_mm],
            typesize:        params[:typesize],
            gost:            params[:gost],
            mass_per_m_kg:   params[:mass_per_m_kg],
            steel_grade:     params[:steel_grade]
          )

          if angle_deg > 1.0e-3
            apply_mitre(definition.entities, end_axis_sign, angle_deg,
                        params[:length_mm], tilt_dir)
          end

          # Восстановить cut на втором конце если он был. Direction для restore —
          # default +Y (поскольку мы не сохраняли исходный direction).
          # FUTURE: сохранять tilt_dir в attr_dict для precise restore.
          default_dir = Geom::Vector3d.new(0, 1, 0)
          if end_axis_sign > 0 && existing_z0_cut > 1.0e-3
            apply_mitre(definition.entities, -1, existing_z0_cut,
                        params[:length_mm], default_dir)
            new_z0 = existing_z0_cut
            new_zL = angle_deg
          elsif end_axis_sign < 0 && existing_zL_cut > 1.0e-3
            apply_mitre(definition.entities, +1, existing_zL_cut,
                        params[:length_mm], default_dir)
            new_zL = existing_zL_cut
            new_z0 = angle_deg
          else
            new_z0 = end_axis_sign < 0 ? angle_deg : 0.0
            new_zL = end_axis_sign > 0 ? angle_deg : 0.0
          end

          AttrDict.write(definition, "cut_z0_angle_deg", new_z0.to_f)
          AttrDict.write(definition, "cut_zL_angle_deg", new_zL.to_f)

          definition
        end

        # Сдвинуть вершины cut-конца по проекции pos на tilt_dir:
        #   dz = sign * (pos · tilt_dir) * tan(angle)
        # Направление tilt_dir определяет какая сторона трубы extends.
        def self.apply_mitre(entities, end_axis_sign, angle_deg, length_mm, tilt_dir_local)
          cut_z = end_axis_sign > 0 ? length_mm.mm : 0.0
          tol   = 1.0e-3.mm

          vertices = collect_cut_vertices(entities, cut_z, tol)
          return if vertices.empty?

          tan_a = Math.tan(angle_deg * Math::PI / 180.0)
          dx, dy = tilt_dir_local.x, tilt_dir_local.y
          vectors = vertices.map do |v|
            pos = v.position
            dot_mm = pos.x.to_mm * dx + pos.y.to_mm * dy
            dz_mm = end_axis_sign * dot_mm * tan_a
            Geom::Vector3d.new(0, 0, dz_mm.mm)
          end

          entities.transform_by_vectors(vertices, vectors)
        end

        # Собрать все вершины с z ≈ cut_z (учитывая tolerance в SU internal units).
        # Используем grep(Sketchup::Edge) → endpoints, т.к. у entities нет
        # прямого vertices accessor (кроме через faces/edges).
        def self.collect_cut_vertices(entities, cut_z, tol)
          seen = {}  # vertex.entityID → vertex (uniq)
          entities.grep(Sketchup::Edge).each do |edge|
            [edge.start, edge.end].each do |v|
              next unless v && v.valid?
              next if seen.key?(v.entityID)
              if (v.position.z - cut_z).abs < tol
                seen[v.entityID] = v
              end
            end
          end
          seen.values
        end
      end
    end
  end
end
