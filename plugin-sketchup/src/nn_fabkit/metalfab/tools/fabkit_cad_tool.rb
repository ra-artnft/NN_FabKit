# encoding: UTF-8

module NN
  module MetalFab
    module Tools
      # FabKit CAD — interactive mitre cutting tool.
      #
      # Workflow (state machine):
      #   :waiting_for_face  — клик по грани tube DC (PickHelper).
      #     Apex = центр выбранной грани. End (z=0 или z=length) — по
      #     ближайшему концу. Default tilt axis — по normal грани.
      #   :waiting_for_angle — protractor live preview; угол через mouse OR VCB.
      #     Arrow keys меняют tilt axis: → X (red) / ← Y (green); ↑↓ Z beep
      #     (Z = ось трубы, не применимо).
      #
      # SU Tool API: https://ruby.sketchup.com/Sketchup/Tool.html
      class FabKitCadTool
        STATUS_PICK_FACE  = "FabKit CAD: выбери грань на конце трубы (грань = точка резa)".freeze
        STATUS_PICK_ANGLE = "FabKit CAD: угол %.1f° (axis=%s) — клик / Enter / VCB; ←→ axis, Esc".freeze

        DEFAULT_ANGLE_DEG = 45.0

        # ----------------------------------------------------------------
        # SU Tool lifecycle
        # ----------------------------------------------------------------

        def activate
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
          if @state == :waiting_for_angle
            puts "[FabKitCadTool] onCancel — back to face pick"
            reset_state
          else
            ::Sketchup.active_model.select_tool(nil)
          end
          view.invalidate
        end

        # ----------------------------------------------------------------
        # Mouse events
        # ----------------------------------------------------------------

        def onMouseMove(flags, x, y, view)
          case @state
          when :waiting_for_face
            # Не делаем live highlight — просто фиксируем cursor pos для draw.
            @hover_x = x
            @hover_y = y
            view.invalidate
          when :waiting_for_angle
            update_angle_from_mouse(x, y, view)
            view.invalidate
          end
        end

        def onLButtonDown(flags, x, y, view)
          case @state
          when :waiting_for_face
            handle_face_pick(view, x, y)
          when :waiting_for_angle
            apply_cut(view)
          end
        end

        # VCB (Value Control Box). User набирает число в активном tool'e.
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

        # Arrow keys для axis constraint (стандартный SU паттерн —
        # как в Move/Rotate tool'ах).
        def onKeyDown(key, repeat, flags, view)
          return false unless @state == :waiting_for_angle
          case key
          when VK_RIGHT
            @tilt_axis = :x
            puts "[FabKitCadTool] tilt axis → X (red)"
            set_status_text
            view.invalidate
            true
          when VK_LEFT
            @tilt_axis = :y
            puts "[FabKitCadTool] tilt axis → Y (green)"
            set_status_text
            view.invalidate
            true
          when VK_UP, VK_DOWN
            ::UI.beep
            ::Sketchup.set_status_text(
              "Z-tilt не применим для mitre cut (Z = ось трубы)",
              SB_PROMPT
            )
            true
          else
            false
          end
        end

        # ----------------------------------------------------------------
        # Drawing
        # ----------------------------------------------------------------

        def draw(view)
          if @state == :waiting_for_angle
            draw_protractor(view)
          end
        end

        # ----------------------------------------------------------------
        # State management
        # ----------------------------------------------------------------

        def reset_state
          @state = :waiting_for_face
          @apex = nil
          @tube_instance = nil
          @end_axis_sign = nil
          @tilt_axis = :x  # default — переопределяется picked face normal'ью
          @current_angle_deg = DEFAULT_ANGLE_DEG
          @hover_x = nil
          @hover_y = nil
          set_status_text
        end

        def set_status_text
          case @state
          when :waiting_for_face
            ::Sketchup.set_status_text(STATUS_PICK_FACE, SB_PROMPT)
            ::Sketchup.set_status_text("", SB_VCB_LABEL)
            ::Sketchup.set_status_text("", SB_VCB_VALUE)
          when :waiting_for_angle
            axis_label = @tilt_axis.to_s.upcase
            ::Sketchup.set_status_text(
              format(STATUS_PICK_ANGLE, @current_angle_deg, axis_label),
              SB_PROMPT
            )
            ::Sketchup.set_status_text("Угол", SB_VCB_LABEL)
            ::Sketchup.set_status_text(format("%.1f", @current_angle_deg), SB_VCB_VALUE)
          end
        end

        # ----------------------------------------------------------------
        # Face pick — найти tube DC + грань через PickHelper
        # ----------------------------------------------------------------

        def handle_face_pick(view, x, y)
          ph = view.pick_helper
          ph.do_pick(x, y)

          picked_face = nil
          instance = nil
          # Iterate picks (deepest first)
          ph.count.times do |i|
            ent = ph.path_at(i)
            next unless ent
            # path_at(i) возвращает либо Entity, либо InstancePath
            path = ent.is_a?(Sketchup::InstancePath) ? ent.to_a : [ent]
            face_in_path = path.find { |e| e.is_a?(Sketchup::Face) }
            next unless face_in_path
            inst = path.reverse.find { |e|
              e.is_a?(Sketchup::ComponentInstance) &&
                AttrDict.read(e.definition, "profile_type") == "rect_tube"
            }
            if inst
              picked_face = face_in_path
              instance = inst
              break
            end
          end

          # Fallback: ph.picked_face возвращает топовую грань без instance fix
          unless picked_face
            picked_face = ph.picked_face
            if picked_face
              # Найти instance из все pickerd entities path
              ph.count.times do |i|
                p = ph.path_at(i)
                next unless p
                arr = p.is_a?(Sketchup::InstancePath) ? p.to_a : [p]
                inst = arr.reverse.find { |e|
                  e.is_a?(Sketchup::ComponentInstance) &&
                    AttrDict.read(e.definition, "profile_type") == "rect_tube"
                }
                if inst
                  instance = inst
                  break
                end
              end
            end
          end

          unless picked_face && instance
            ::UI.beep
            ::Sketchup.set_status_text(
              "Не найдено грани rect_tube DC. Кликни грань трубы созданной плагином.",
              SB_PROMPT
            )
            return
          end

          # Apex = центр picked face (в model space)
          apex_world = picked_face.bounds.center

          # Determine end (z=0 / z=length) от apex
          end_axis = determine_end_axis(apex_world, instance)
          unless end_axis
            ::UI.beep
            ::Sketchup.set_status_text(
              "Грань не на конце трубы. Кликни грань ближе к z=0 или z=length.",
              SB_PROMPT
            )
            return
          end

          # Existing cut check
          existing_cut = AttrDict.read(
            instance.definition,
            end_axis > 0 ? "cut_zL_angle_deg" : "cut_z0_angle_deg"
          ) || 0.0
          if existing_cut > 0.001
            ::UI.messagebox(
              "На этом конце уже mitre #{existing_cut.round(1)}°.\n\n" \
              "Сначала Ctrl+Z, потом применяй новый."
            )
            return
          end

          # Default tilt axis по picked face normal
          @tilt_axis = default_tilt_axis(picked_face, instance)

          @apex = apex_world
          @tube_instance = instance
          @end_axis_sign = end_axis
          @state = :waiting_for_angle
          @current_angle_deg = DEFAULT_ANGLE_DEG
          set_status_text
          view.invalidate
        end

        # Default tilt axis по normal'и выбранной грани (в local coords трубы).
        # End cap face (normal ‖ Z) → :x (произвольный default).
        # +X / -X side wall → :y (mitre extends в X direction, tilt about Y).
        # +Y / -Y side wall → :x (mitre extends в Y direction, tilt about X).
        def default_tilt_axis(face, instance)
          inv_tr = instance.transformation.inverse
          normal_local = face.normal.transform(inv_tr)
          n = normal_local.normalize
          ax = n.x.abs
          ay = n.y.abs
          az = n.z.abs

          if az >= ax && az >= ay
            :x
          elsif ax >= ay
            :y
          else
            :x
          end
        end

        # Какой конец трубы ближе к apex_world? +1 = z=length, -1 = z=0
        def determine_end_axis(world_point, instance)
          length_mm = AttrDict.read(instance.definition, "length_mm").to_f
          tr = instance.transformation
          end_z0 = Geom::Point3d.new(0, 0, 0).transform(tr)
          end_zL = Geom::Point3d.new(0, 0, length_mm.mm).transform(tr)

          d0 = world_point.distance(end_z0)
          dL = world_point.distance(end_zL)

          width_mm = AttrDict.read(instance.definition, "width_mm").to_f
          height_mm = AttrDict.read(instance.definition, "height_mm").to_f
          max_acceptable = [width_mm, height_mm, length_mm * 0.5].max.mm

          if d0 < max_acceptable && d0 < dL
            -1
          elsif dL < max_acceptable && dL < d0
            +1
          else
            nil
          end
        end

        # ----------------------------------------------------------------
        # Angle calculation from mouse
        # ----------------------------------------------------------------

        def update_angle_from_mouse(x, y, view)
          tr = @tube_instance.transformation
          axis_z_world = Geom::Vector3d.new(0, 0, 1).transform(tr).normalize

          # Cut plane через apex с normal = axis Z
          plane = [@apex, axis_z_world]
          ray = view.pickray(x, y)
          intersection = Geom.intersect_line_plane(ray, plane)
          return unless intersection

          radial = intersection - @apex
          return if radial.length < 1.0e-6

          # Reference axis: tilt_axis_local — в плоскости cut
          # :x tilt → ref = Y direction (+Y world)
          # :y tilt → ref = X direction (+X world)
          ref_local = case @tilt_axis
                      when :x then Geom::Vector3d.new(0, 1, 0)
                      when :y then Geom::Vector3d.new(1, 0, 0)
                      else         Geom::Vector3d.new(0, 1, 0)
                      end
          ref_world = ref_local.transform(tr).normalize

          dot   = radial.dot(ref_world)
          cross = ref_world.cross(radial).dot(axis_z_world)
          angle_rad = Math.atan2(cross, dot)
          angle_deg = (angle_rad * 180.0 / Math::PI).abs

          @current_angle_deg = angle_deg.clamp(0.1, 89.0)
          set_status_text
        end

        # ----------------------------------------------------------------
        # Protractor drawing
        # ----------------------------------------------------------------

        def draw_protractor(view)
          tr = @tube_instance.transformation
          axis_z = Geom::Vector3d.new(0, 0, 1).transform(tr).normalize

          ref_local = case @tilt_axis
                      when :x then Geom::Vector3d.new(0, 1, 0)
                      when :y then Geom::Vector3d.new(1, 0, 0)
                      else         Geom::Vector3d.new(0, 1, 0)
                      end
          ref_world = ref_local.transform(tr).normalize

          width_mm = AttrDict.read(@tube_instance.definition, "width_mm").to_f
          height_mm = AttrDict.read(@tube_instance.definition, "height_mm").to_f
          radius = [width_mm, height_mm].max.mm * 1.5

          segments = 32
          angle_rad = @current_angle_deg * Math::PI / 180.0
          arc_pts = (0..segments).map do |i|
            t = angle_rad * (i.to_f / segments)
            v = transform_2d_to_world(t, radius, ref_world, axis_z)
            @apex.offset(v)
          end

          ref_end = @apex.offset(ref_world, radius)
          ind_v = transform_2d_to_world(angle_rad, radius, ref_world, axis_z)
          ind_end = @apex.offset(ind_v)

          view.line_width = 2
          view.drawing_color = "blue"
          view.draw_polyline(arc_pts)
          view.drawing_color = (@tilt_axis == :x ? "red" : "green")
          view.draw(GL_LINES, [@apex, ref_end])
          view.drawing_color = "red"
          view.draw(GL_LINES, [@apex, ind_end])
          view.line_width = 1

          label_pos = view.screen_coords(ind_end)
          axis_label = @tilt_axis.to_s.upcase
          view.draw_text(label_pos, format("%.1f° (axis %s)", @current_angle_deg, axis_label))
        end

        def transform_2d_to_world(angle_rad, radius, ref, axis_z)
          axis_x = axis_z.cross(ref).normalize
          v_ref = ref.clone
          v_ref.length = radius * Math.cos(angle_rad)
          v_x = axis_x.clone
          v_x.length = radius * Math.sin(angle_rad)
          v_ref + v_x
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
            "FabKit CAD: mitre #{@current_angle_deg.round(1)}° (#{@tilt_axis}) на #{end_label}",
            true, false, false
          )
          begin
            ProfileGenerator::RectTubeMitre.rebuild_with_cut(
              definition,
              end_axis_sign: @end_axis_sign,
              angle_deg: @current_angle_deg,
              tilt_axis: @tilt_axis,
              params: params
            )
            model.commit_operation
            puts "[FabKitCadTool] applied mitre #{@current_angle_deg}° axis=#{@tilt_axis} on #{end_label}"
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
