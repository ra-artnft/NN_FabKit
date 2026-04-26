# encoding: UTF-8

module NN
  module MetalFab
    module Tools
      # FabKit CAD — interactive mitre cutting tool.
      #
      # Workflow (state machine):
      #   :waiting_for_apex  — пользователь кликает на вершину tube DC.
      #   :waiting_for_angle — protractor live preview; угол через mouse OR VCB.
      #
      # SU Tool API: https://ruby.sketchup.com/Sketchup/Tool.html
      # Активация через Sketchup.active_model.select_tool(FabKitCadTool.new).
      class FabKitCadTool
        STATUS_PICK_APEX  = "FabKit CAD: выбери вершину трубы — апекс угла резa".freeze
        STATUS_PICK_ANGLE = "FabKit CAD: угол %.1f° — клик / Enter для применения, Esc для отмены".freeze

        DEFAULT_ANGLE_DEG = 45.0
        # Tolerance для определения «эта вершина — конец трубы» (z=0 или z=length).
        VERTEX_END_TOL = 1.0e-3

        # ----------------------------------------------------------------
        # SU Tool lifecycle
        # ----------------------------------------------------------------

        def activate
          @input_point = Sketchup::InputPoint.new
          @hover_input_point = Sketchup::InputPoint.new
          reset_state
          ::Sketchup.active_model.active_view.invalidate
          puts "[FabKitCadTool] activated"
        end

        def deactivate(view)
          puts "[FabKitCadTool] deactivated"
          view.invalidate
        end

        def resume(view)
          set_status_text
          view.invalidate
        end

        def suspend(view)
          view.invalidate
        end

        def onCancel(reason, view)
          # reason 0 = Esc, 1 = reselect tool, 2 = undo
          if @state == :waiting_for_angle
            puts "[FabKitCadTool] onCancel — back to apex"
            reset_state
          else
            # Cancel from initial state — switch to default Select tool
            ::Sketchup.active_model.select_tool(nil)
          end
          view.invalidate
        end

        # ----------------------------------------------------------------
        # Mouse events
        # ----------------------------------------------------------------

        def onMouseMove(flags, x, y, view)
          case @state
          when :waiting_for_apex
            @hover_input_point.pick(view, x, y)
            view.invalidate
          when :waiting_for_angle
            update_angle_from_mouse(x, y, view)
            view.invalidate
          end
        end

        def onLButtonDown(flags, x, y, view)
          case @state
          when :waiting_for_apex
            @input_point.pick(view, x, y)
            handle_apex_pick(view) if @input_point.valid?
          when :waiting_for_angle
            apply_cut(view)
          end
        end

        # VCB (Value Control Box, нижний правый угол SU). User набирает число
        # в активном tool'e — SU вызывает onUserText.
        def onUserText(text, view)
          return unless @state == :waiting_for_angle
          val = text.to_f
          if val.between?(0.1, 89.0)
            @current_angle_deg = val
            puts "[FabKitCadTool] VCB angle = #{val}°"
            apply_cut(view)
          else
            ::UI.beep
            ::Sketchup.set_status_text("Угол должен быть 0.1..89°", SB_PROMPT)
          end
        end

        def enableVCB?
          @state == :waiting_for_angle
        end

        # ----------------------------------------------------------------
        # Drawing (protractor + indicator)
        # ----------------------------------------------------------------

        def draw(view)
          if @state == :waiting_for_apex
            @hover_input_point.draw(view) if @hover_input_point.valid?
          elsif @state == :waiting_for_angle
            draw_protractor(view)
          end
        end

        # ----------------------------------------------------------------
        # State management
        # ----------------------------------------------------------------

        def reset_state
          @state = :waiting_for_apex
          @apex = nil
          @tube_instance = nil
          @end_axis_sign = nil
          @current_angle_deg = DEFAULT_ANGLE_DEG
          set_status_text
        end

        def set_status_text
          case @state
          when :waiting_for_apex
            ::Sketchup.set_status_text(STATUS_PICK_APEX, SB_PROMPT)
            ::Sketchup.set_status_text("", SB_VCB_LABEL)
            ::Sketchup.set_status_text("", SB_VCB_VALUE)
          when :waiting_for_angle
            ::Sketchup.set_status_text(format(STATUS_PICK_ANGLE, @current_angle_deg), SB_PROMPT)
            ::Sketchup.set_status_text("Угол", SB_VCB_LABEL)
            ::Sketchup.set_status_text(format("%.1f", @current_angle_deg), SB_VCB_VALUE)
          end
        end

        # ----------------------------------------------------------------
        # Apex pick — найти tube DC от вершины
        # ----------------------------------------------------------------

        def handle_apex_pick(view)
          point = @input_point.position
          # Найти ComponentInstance из instance_path
          path = @input_point.instance_path
          instance = nil
          if path
            (0...path.length).each do |i|
              ent = path[i]
              if ent.is_a?(Sketchup::ComponentInstance)
                # Проверить — это наш rect_tube?
                if AttrDict.read(ent.definition, "profile_type") == "rect_tube"
                  instance = ent
                  break
                end
              end
            end
          end

          unless instance
            ::UI.beep
            ::Sketchup.set_status_text(
              "Эта вершина не на rect_tube DC. Кликни вершину трубы созданной плагином.",
              SB_PROMPT
            )
            return
          end

          # Найти end_axis_sign — какой конец трубы ближе к picked point
          end_axis = determine_end_axis(point, instance)
          unless end_axis
            ::UI.beep
            ::Sketchup.set_status_text(
              "Эта вершина не на конце трубы. Кликни вершину торца (z=0 или z=length).",
              SB_PROMPT
            )
            return
          end

          # Проверить — не уже ли mitred? (MVP: не cut поверх cut)
          existing_cut = AttrDict.read(
            instance.definition,
            end_axis > 0 ? "cut_zL_angle_deg" : "cut_z0_angle_deg"
          ) || 0.0
          if existing_cut > 0.001
            ::UI.messagebox(
              "На этом конце трубы уже применён mitre #{existing_cut.round(1)}°.\n\n" \
              "Сначала отмени (Ctrl+Z) предыдущий cut, потом применяй новый."
            )
            return
          end

          @apex = point
          @tube_instance = instance
          @end_axis_sign = end_axis
          @state = :waiting_for_angle
          @current_angle_deg = DEFAULT_ANGLE_DEG
          set_status_text
          view.invalidate
        end

        # Определить — какой конец трубы (+1 = z=length, -1 = z=0) ближе.
        # Учитывает instance.transformation.
        def determine_end_axis(world_point, instance)
          length_mm = AttrDict.read(instance.definition, "length_mm").to_f
          tr = instance.transformation
          # Конечные точки трубы в model space: (0,0,0) и (0,0,length)
          end_z0 = Geom::Point3d.new(0, 0, 0).transform(tr)
          end_zL = Geom::Point3d.new(0, 0, length_mm.mm).transform(tr)

          d0 = world_point.distance(end_z0)
          dL = world_point.distance(end_zL)

          # Tolerance: должна быть «близко» к одному из концов (в пределах
          # max(width, height) — bounding box диагональ). Иначе вершина в
          # середине трубы — не подходит.
          max_acceptable = [
            AttrDict.read(instance.definition, "width_mm").to_f,
            AttrDict.read(instance.definition, "height_mm").to_f
          ].max.mm

          if d0 < max_acceptable && d0 < dL
            -1
          elsif dL < max_acceptable && dL < d0
            +1
          else
            nil
          end
        end

        # ----------------------------------------------------------------
        # Angle calculation from mouse position
        # ----------------------------------------------------------------

        def update_angle_from_mouse(x, y, view)
          # Cut plane проходит через @apex, нормаль = ось трубы (Z в local, transform в model).
          # Mouse ray → пересечение с plane перпендикулярной оси трубы → angle.
          tr = @tube_instance.transformation
          axis_z_local = Geom::Vector3d.new(0, 0, 1)
          axis_z_world = axis_z_local.transform(tr).normalize

          # Cut plane перпендикулярная оси трубы, проходит через @apex
          plane = [@apex, axis_z_world]

          # Ray от cursor
          ray = view.pickray(x, y)
          intersection = Geom.intersect_line_plane(ray, plane)
          return unless intersection

          # Vector от apex до intersection — radial direction
          radial = intersection - @apex
          radial_len = radial.length
          return if radial_len < 1.0e-6

          # Project radial на cross-section axes трубы (local Y axis в world)
          axis_y_local = Geom::Vector3d.new(0, 1, 0)
          axis_y_world = axis_y_local.transform(tr).normalize

          # Угол между radial и axis_y_world (в plane perpendicular to tube axis)
          # Используем atan2(cross_z, dot) для signed angle
          dot   = radial.dot(axis_y_world)
          cross = axis_y_world.cross(radial).dot(axis_z_world)
          angle_rad = Math.atan2(cross, dot)
          angle_deg = (angle_rad * 180.0 / Math::PI).abs

          # Clamp в [0.1, 89.0] для практического диапазона mitre
          @current_angle_deg = angle_deg.clamp(0.1, 89.0)
          set_status_text
        end

        # ----------------------------------------------------------------
        # Protractor drawing
        # ----------------------------------------------------------------

        def draw_protractor(view)
          tr = @tube_instance.transformation
          axis_z = Geom::Vector3d.new(0, 0, 1).transform(tr).normalize
          axis_y = Geom::Vector3d.new(0, 1, 0).transform(tr).normalize

          # Радиус protractor'а в model units — взять разумный fixed размер
          # пропорционально tube width. Phase B сделает screen-space константу.
          width_mm = AttrDict.read(@tube_instance.definition, "width_mm").to_f
          height_mm = AttrDict.read(@tube_instance.definition, "height_mm").to_f
          radius = [width_mm, height_mm].max.mm * 1.5

          # Draw arc from axis_y direction by @current_angle_deg, in plane perp to axis_z
          segments = 32
          angle_rad = @current_angle_deg * Math::PI / 180.0
          arc_pts = []
          (0..segments).each do |i|
            t = angle_rad * (i.to_f / segments)
            v = transform_2d_to_world(t, radius, axis_y, axis_z)
            arc_pts << @apex.offset(v)
          end

          # Reference line (axis_y direction, full radius)
          ref_end = @apex.offset(axis_y, radius)
          # Indicator line (current angle direction)
          ind_v = transform_2d_to_world(angle_rad, radius, axis_y, axis_z)
          ind_end = @apex.offset(ind_v)

          view.line_width = 2
          view.drawing_color = "blue"
          view.draw_polyline(arc_pts)
          view.drawing_color = "gray"
          view.draw(GL_LINES, [@apex, ref_end])
          view.drawing_color = "red"
          view.draw(GL_LINES, [@apex, ind_end])
          view.line_width = 1

          # Label с углом — рядом с indicator end
          label_pos = view.screen_coords(ind_end)
          view.draw_text(label_pos, format("%.1f°", @current_angle_deg))
        end

        # 2D-в-плоскости-cut → world vector. axis_y = «0°» direction;
        # rotated by `angle_rad` в плоскости perpendicular to axis_z.
        def transform_2d_to_world(angle_rad, radius, axis_y, axis_z)
          # axis_x_in_plane = axis_z × axis_y (right-handed)
          axis_x = axis_z.cross(axis_y).normalize
          v_y = axis_y.clone
          v_y.length = radius * Math.cos(angle_rad)
          v_x = axis_x.clone
          v_x.length = radius * Math.sin(angle_rad)
          v_y + v_x
        end

        # ----------------------------------------------------------------
        # Apply cut
        # ----------------------------------------------------------------

        def apply_cut(view)
          model = ::Sketchup.active_model
          definition = @tube_instance.definition
          params = AttrDict.read_rect_tube_params(definition)
          unless params
            ::UI.messagebox("Не удалось прочитать параметры трубы.")
            reset_state
            return
          end

          end_label = @end_axis_sign > 0 ? "+Z" : "0"
          model.start_operation(
            "FabKit CAD: mitre #{@current_angle_deg.round(1)}° на #{end_label} конце",
            true, false, false
          )
          begin
            ProfileGenerator::RectTubeMitre.rebuild_with_cut(
              definition,
              end_axis_sign: @end_axis_sign,
              angle_deg: @current_angle_deg,
              params: params
            )
            model.commit_operation
            puts "[FabKitCadTool] applied mitre #{@current_angle_deg}° on #{end_label}"
          rescue StandardError => e
            model.abort_operation
            puts "[FabKitCadTool] ERROR: #{e.class}: #{e.message}"
            puts e.backtrace.first(5).map { |l| "  #{l}" }.join("\n")
            ::UI.messagebox("Ошибка применения mitre:\n\n#{e.class}: #{e.message}")
          end

          reset_state
          view.invalidate
        end
      end
    end
  end
end
