# encoding: UTF-8

module NN
  module MetalFab
    module Tools
      # FabKit CAD — selection-based auto-mitre tool.
      #
      # Workflow:
      #   1. Пользователь стандартным SU select tool'ом выделяет 2 трубы
      #      которые сходятся концами.
      #   2. Кликает «FabKit CAD» в toolbar.
      #   3. Tool анализирует геометрию — находит ближайшую пару концов,
      #      вычисляет угол между осями трубы, определяет mitre angle =
      #      (180° - angle_between) / 2.
      #   4. Рисует BRIGHT preview в 3D — magenta-плоскости cut'ов на
      #      обеих трубах + label с углом.
      #   5. Enter → применить mitre на обе трубы (один undo group);
      #      Esc или клик по empty space → отмена.
      #
      # NB: Selection state читается на activate. Если selection пустой
      # или не 2 tube DC — status bar объясняет что нужно.
      class FabKitCadTool
        DEFAULT_ANGLE_DEG = 45.0
        # Tolerance для «ends близко друг к другу» — в долях от max width.
        JOINT_TOLERANCE_FACTOR = 2.0

        # ----------------------------------------------------------------
        # SU Tool lifecycle
        # ----------------------------------------------------------------

        def activate
          puts "[FabKitCadTool] activated"
          analyze_selection
          ::Sketchup.active_model.active_view.invalidate
        end

        def deactivate(view)
          puts "[FabKitCadTool] deactivated"
          ::Sketchup.set_status_text("", SB_PROMPT)
          view.invalidate
        end

        def resume(view)
          analyze_selection  # переанализировать на случай изменения selection
          view.invalidate
        end

        def suspend(view); view.invalidate; end

        def onCancel(reason, view)
          puts "[FabKitCadTool] onCancel reason=#{reason}"
          ::Sketchup.active_model.select_tool(nil)
        end

        # ----------------------------------------------------------------
        # Mouse / keyboard
        # ----------------------------------------------------------------

        def onLButtonDown(flags, x, y, view)
          # Click anywhere = apply (если есть готовый preview)
          if @state == :preview_ready
            apply_cut(view)
          end
        end

        def onReturn(view)
          apply_cut(view) if @state == :preview_ready
        end

        # VCB позволяет override угол перед применением.
        def onUserText(text, view)
          return unless @state == :preview_ready
          val = text.to_f
          if val.between?(0.1, 89.0)
            @joint[:mitre_angle_deg] = val
            puts "[FabKitCadTool] override angle = #{val}°"
            set_status_text
            view.invalidate
          else
            ::UI.beep
          end
        end

        def enableVCB?
          @state == :preview_ready
        end

        # ----------------------------------------------------------------
        # Selection analysis
        # ----------------------------------------------------------------

        def analyze_selection
          model = ::Sketchup.active_model
          tubes = model.selection.to_a.select do |e|
            e.is_a?(Sketchup::ComponentInstance) &&
              AttrDict.read(e.definition, "profile_type") == "rect_tube"
          end

          if tubes.length == 0
            @state = :no_selection
            @message = "FabKit CAD: выдели 2 трубы (Select tool, Ctrl+клик), потом запусти заново"
            puts "[FabKitCadTool] no tubes selected"
            ::UI.messagebox(
              "Сначала выдели 2 трубы (стандартным Select tool'ом, Ctrl+клик " \
              "по второй для добавления к selection), потом запусти FabKit CAD."
            )
            ::Sketchup.active_model.select_tool(nil)
            return
          elsif tubes.length == 1
            @state = :one_tube
            @message = "FabKit CAD: выделена 1 труба, нужны 2. Добавь вторую трубу (Ctrl+клик)."
            puts "[FabKitCadTool] only 1 tube selected"
            ::UI.messagebox(
              "Выделена только 1 труба. Добавь вторую (Ctrl+клик) и запусти FabKit CAD заново."
            )
            ::Sketchup.active_model.select_tool(nil)
            return
          elsif tubes.length > 2
            @state = :too_many
            @message = "FabKit CAD: #{tubes.length} труб выделено, нужно ровно 2"
            puts "[FabKitCadTool] too many tubes: #{tubes.length}"
            ::UI.messagebox(
              "Выделено #{tubes.length} труб. FabKit CAD работает с парой — выдели ровно 2."
            )
            ::Sketchup.active_model.select_tool(nil)
            return
          end

          @joint = find_joint(tubes[0], tubes[1])
          if @joint.nil?
            @state = :no_joint
            @message = "FabKit CAD: 2 трубы выбраны, но их концы не сходятся. Расположи концами к точке стыка."
            puts "[FabKitCadTool] no joint detected"
            ::UI.messagebox(
              "Эти 2 трубы не сходятся концами. Расположи их так, чтобы по одному " \
              "концу каждой было близко друг к другу."
            )
            ::Sketchup.active_model.select_tool(nil)
            return
          end

          if tubes[0].definition.entityID == tubes[1].definition.entityID
            @state = :same_definition
            @message = "FabKit CAD: 2 трубы используют один definition (копии). Не поддерживается."
            puts "[FabKitCadTool] same definition (copies)"
            ::UI.messagebox(
              "Эти 2 трубы — копии одного definition. Mitre на копии нарушит обе. " \
              "Сделай Make Unique (правый клик → Make Unique) на одной из них."
            )
            ::Sketchup.active_model.select_tool(nil)
            return
          end

          @state = :preview_ready
          set_status_text
          puts "[FabKitCadTool] joint detected: angle_between=#{@joint[:angle_between_deg].round(1)}°, " \
               "mitre=#{@joint[:mitre_angle_deg].round(1)}°"
        end

        def set_status_text
          if @state == :preview_ready
            ::Sketchup.set_status_text(
              "FabKit CAD: mitre #{@joint[:mitre_angle_deg].round(1)}° на обеих трубах. " \
              "Enter / клик — применить, Esc — отмена. VCB — поменять угол.",
              SB_PROMPT
            )
            ::Sketchup.set_status_text("Угол", SB_VCB_LABEL)
            ::Sketchup.set_status_text(format("%.1f", @joint[:mitre_angle_deg]), SB_VCB_VALUE)
          else
            ::Sketchup.set_status_text(@message || "", SB_PROMPT)
          end
        end

        # Найти ближайшую пару концов между двумя трубами + угол между осями.
        # Возвращает Hash с full joint info, либо nil если не joint.
        def find_joint(tube_a, tube_b)
          ends_a = tube_endpoints(tube_a)
          ends_b = tube_endpoints(tube_b)

          # Найти пару (один конец от каждой трубы) с min distance
          best = nil
          ends_a.each do |ea|
            ends_b.each do |eb|
              d = ea[:point].distance(eb[:point])
              if best.nil? || d < best[:dist]
                best = { end_a: ea, end_b: eb, dist: d }
              end
            end
          end

          # Tolerance: расстояние должно быть < макс размер сечения
          width_a = AttrDict.read(tube_a.definition, "width_mm").to_f
          height_a = AttrDict.read(tube_a.definition, "height_mm").to_f
          width_b = AttrDict.read(tube_b.definition, "width_mm").to_f
          height_b = AttrDict.read(tube_b.definition, "height_mm").to_f
          max_size = [width_a, height_a, width_b, height_b].max
          tolerance = max_size * JOINT_TOLERANCE_FACTOR

          return nil if best.nil?
          return nil if best[:dist] > tolerance.mm

          # Угол между осями (в world coords)
          axis_a = tube_axis_world(tube_a)
          axis_b = tube_axis_world(tube_b)

          # Учитываем направления концов: end_axis_sign +1 значит конец на +Z
          # стороне local axis. Для joint axes должны "сходиться" друг к другу,
          # т.е. концы должны смотреть навстречу. Возможно нужна нормализация
          # через end_axis_sign — для simplicity используем abs(dot).
          dot = axis_a.dot(axis_b).clamp(-1.0, 1.0)
          angle_between_rad = Math.acos(dot.abs)
          angle_between_deg = angle_between_rad * 180.0 / Math::PI

          # Mitre angle: для 90° corner = 45°.
          # Формула: mitre = (180 - 2*angle_between_supplementary) / 2 = 90 - angle_between/2
          # Wait — let's think carefully.
          # If two tubes meet at 90° angle (perpendicular), each gets 45° mitre.
          # angle_between (acute) = 90°. mitre = 45°.
          # Formula: mitre = angle_between / 2.
          # If two tubes are parallel (angle_between=0°): no mitre (or 0).
          # If two tubes are at 60°: each gets 30° mitre.
          # → mitre = angle_between / 2  (for symmetric joint)
          mitre_angle = angle_between_deg / 2.0

          # Joint point: midpoint of best pair
          jp = Geom::Point3d.linear_combination(
            0.5, best[:end_a][:point],
            0.5, best[:end_b][:point]
          )

          # Tilt direction для каждой трубы — TO body другой трубы (в local
          # coords). Передаём end_data of OTHER tube (не self) — нужно знать
          # какой конец другой трубы при joint, чтобы определить sign её axis.
          tilt_a = compute_tilt_dir(tube_a, tube_b, best[:end_b])
          tilt_b = compute_tilt_dir(tube_b, tube_a, best[:end_a])

          {
            tube_a: tube_a, tube_b: tube_b,
            end_a: best[:end_a], end_b: best[:end_b],
            joint_point: jp,
            distance: best[:dist],
            angle_between_deg: angle_between_deg,
            mitre_angle_deg: mitre_angle,
            tilt_dir_a_local: tilt_a,
            tilt_dir_b_local: tilt_b
          }
        end

        # Endpoints трубы в world coords + end_axis_sign (+1 = z=length, -1 = z=0)
        def tube_endpoints(instance)
          length_mm = AttrDict.read(instance.definition, "length_mm").to_f
          tr = instance.transformation
          [
            { point: Geom::Point3d.new(0, 0, 0).transform(tr), end_axis: -1 },
            { point: Geom::Point3d.new(0, 0, length_mm.mm).transform(tr), end_axis: +1 }
          ]
        end

        def tube_axis_world(instance)
          Geom::Vector3d.new(0, 0, 1).transform(instance.transformation).normalize
        end

        # Tilt direction для tube_self в его local coords (XY plane):
        # вектор куда long side mitre должна faceть = TO body другой трубы.
        #
        # end_data_other — endpoint other tube'а который при joint. Используется
        # чтобы определить sign axis: если joint at +Z конце other tube, body
        # extends в -Z direction (axis_world.reverse).
        def compute_tilt_dir(tube_self, tube_other, end_data_other)
          axis_world = tube_axis_world(tube_other)
          # Direction FROM joint TO body другой трубы:
          #   end_axis_other == +1 (joint at z=length) → body extends -axis_world
          #   end_axis_other == -1 (joint at z=0)      → body extends +axis_world
          to_body_world = end_data_other[:end_axis] > 0 ? axis_world.reverse : axis_world

          # Convert в local coords tube_self (только rotation effect для vector)
          inv = tube_self.transformation.inverse
          to_body_local = to_body_world.transform(inv).normalize

          # Project на cross-section plane (XY local of tube_self)
          proj = Geom::Vector3d.new(to_body_local.x, to_body_local.y, 0)
          if proj.length < 1.0e-6
            # Оси параллельны (другая труба коллинеарна self) — fallback на +Y
            return Geom::Vector3d.new(0, 1, 0)
          end

          proj.normalize
        end

        # ----------------------------------------------------------------
        # Drawing — bright preview
        # ----------------------------------------------------------------

        def draw(view)
          return unless @state == :preview_ready && @joint
          draw_preview(view)
        end

        def draw_preview(view)
          # Marker at joint point — magenta cross
          jp = @joint[:joint_point]
          marker_size = 30.mm
          view.line_width = 3
          view.drawing_color = "magenta"
          view.draw(GL_LINES, [
            jp.offset(X_AXIS, -marker_size), jp.offset(X_AXIS, marker_size),
            jp.offset(Y_AXIS, -marker_size), jp.offset(Y_AXIS, marker_size),
            jp.offset(Z_AXIS, -marker_size), jp.offset(Z_AXIS, marker_size)
          ])

          # Cut plane preview на каждой трубе
          draw_cut_plane(view, @joint[:tube_a], @joint[:end_a],
                         @joint[:mitre_angle_deg], @joint[:tilt_dir_a_local])
          draw_cut_plane(view, @joint[:tube_b], @joint[:end_b],
                         @joint[:mitre_angle_deg], @joint[:tilt_dir_b_local])

          # Label с углом возле joint point
          view.drawing_color = "white"
          screen_pt = view.screen_coords(jp)
          view.draw_text(screen_pt,
                         format("Mitre %.1f° (joint %.1f° между трубами)",
                                @joint[:mitre_angle_deg],
                                @joint[:angle_between_deg]))
          view.line_width = 1
        end

        def draw_cut_plane(view, tube, end_data, angle_deg, tilt_dir_local)
          # 4 угла rectangle на cut plane в local coords
          width_mm = AttrDict.read(tube.definition, "width_mm").to_f
          height_mm = AttrDict.read(tube.definition, "height_mm").to_f
          length_mm = AttrDict.read(tube.definition, "length_mm").to_f
          end_z_mm = end_data[:end_axis] > 0 ? length_mm : 0.0
          end_sign = end_data[:end_axis]

          # Cut plane проходит через (0, 0, end_z) с normal в направлении
          # axis_z + tilt_dir * tan(angle).
          # Для preview: 4 угла = corners cross-section перетранслированные по dz.
          tan_a = Math.tan(angle_deg * Math::PI / 180.0)
          half_w = width_mm / 2.0
          half_h = height_mm / 2.0
          dx, dy = tilt_dir_local.x, tilt_dir_local.y

          local_corners = [
            [+half_w, +half_h], [+half_w, -half_h],
            [-half_w, -half_h], [-half_w, +half_h]
          ]
          world_corners = local_corners.map do |(lx, ly)|
            dz_mm = end_sign * (lx * dx + ly * dy) * tan_a
            local_pt = Geom::Point3d.new(lx.mm, ly.mm, (end_z_mm + dz_mm).mm)
            local_pt.transform(tube.transformation)
          end

          # Draw outline + diagonal hatch — bright cyan (or yellow)
          view.line_width = 3
          view.drawing_color = "cyan"
          loop_pts = world_corners + [world_corners.first]
          view.draw_polyline(loop_pts)

          # Cross diagonals — visual «X» indicator на cut plane
          view.drawing_color = "yellow"
          view.line_width = 2
          view.draw(GL_LINES, [
            world_corners[0], world_corners[2],
            world_corners[1], world_corners[3]
          ])
          view.line_width = 1
        end

        # ----------------------------------------------------------------
        # Apply
        # ----------------------------------------------------------------

        def apply_cut(view)
          return unless @joint
          model = ::Sketchup.active_model

          mitre = @joint[:mitre_angle_deg]
          model.start_operation("FabKit CAD: mitre joint #{mitre.round(1)}°", true, false, false)
          begin
            apply_to_one_tube(@joint[:tube_a], @joint[:end_a], mitre, @joint[:tilt_dir_a_local])
            apply_to_one_tube(@joint[:tube_b], @joint[:end_b], mitre, @joint[:tilt_dir_b_local])
            model.commit_operation
            puts "[FabKitCadTool] applied mitre joint #{mitre}°"
          rescue StandardError => e
            model.abort_operation
            puts "[FabKitCadTool] ERROR: #{e.class}: #{e.message}"
            puts e.backtrace.first(8).map { |l| "  #{l}" }.join("\n")
            ::UI.messagebox("Ошибка применения mitre joint:\n\n#{e.class}: #{e.message}")
          end

          @state = :idle
          @joint = nil
          ::Sketchup.active_model.select_tool(nil)
          view.invalidate
        end

        def apply_to_one_tube(tube, end_data, angle_deg, tilt_dir_local)
          params = AttrDict.read_rect_tube_params(tube.definition)
          unless params
            raise "Не удалось прочитать params трубы #{tube.definition.name}"
          end

          existing_cut = end_data[:end_axis] > 0 ?
                           params[:cut_zL_angle_deg] :
                           params[:cut_z0_angle_deg]
          if existing_cut > 0.001
            raise "На конце #{tube.definition.name} уже mitre #{existing_cut.round(1)}°. Сначала Ctrl+Z."
          end

          ProfileGenerator::RectTubeMitre.rebuild_with_cut(
            tube.definition,
            end_axis_sign: end_data[:end_axis],
            angle_deg: angle_deg,
            tilt_dir_local: tilt_dir_local,
            params: params
          )
        end
      end
    end
  end
end
