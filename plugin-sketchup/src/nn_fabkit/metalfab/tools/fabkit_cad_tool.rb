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
        # Default trim mode — резать на bisecting plane (axis intersection),
        # а не на endpoint трубы. Устраняет visible overlap когда концы труб
        # пересекаются в L-corner. T key переключает.
        DEFAULT_TRIM_MODE = true
        VK_T = 84  # ASCII 'T'

        # ----------------------------------------------------------------
        # SU Tool lifecycle
        # ----------------------------------------------------------------

        def activate
          puts "[FabKitCadTool] activated"
          @trim_mode = DEFAULT_TRIM_MODE
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

        # T — toggle trim mode (cut на bisecting plane vs на endpoint трубы).
        def onKeyDown(key, repeat, flags, view)
          if @state == :preview_ready && key == VK_T && repeat == 1
            @trim_mode = !@trim_mode
            puts "[FabKitCadTool] trim_mode = #{@trim_mode}"
            set_status_text
            view.invalidate
            return true
          end
          false
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
            mode_label = @trim_mode ? "ТРИМ ВКЛ" : "ТРИМ ВЫКЛ"
            ::Sketchup.set_status_text(
              "FabKit CAD: mitre #{@joint[:mitre_angle_deg].round(1)}°. [#{mode_label}] " \
              "Enter/клик — применить, T — переключить trim, Esc — отмена. VCB — угол.",
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

          # Trim params — где будет cut при @trim_mode=true.
          # `Geom.closest_points` для двух axis lines возвращает [pt_on_a, pt_on_b]
          # — ближайшие точки на каждой axis. Для пересекающихся axes обе
          # совпадают, для skew (немного непараллельных в 3D) — две близкие.
          # Каждая труба trimmed до СВОЕЙ closest point — это сохраняет
          # геометрию строго на её axis line.
          line_a = [tube_a.transformation.origin, axis_a]
          line_b = [tube_b.transformation.origin, axis_b]
          closest = Geom.closest_points(line_a, line_b)
          trim_a = compute_trim(tube_a, best[:end_a], closest[0])
          trim_b = compute_trim(tube_b, best[:end_b], closest[1])

          {
            tube_a: tube_a, tube_b: tube_b,
            end_a: best[:end_a], end_b: best[:end_b],
            joint_point: jp,
            distance: best[:dist],
            angle_between_deg: angle_between_deg,
            mitre_angle_deg: mitre_angle,
            tilt_dir_a_local: tilt_a,
            tilt_dir_b_local: tilt_b,
            trim_a: trim_a,
            trim_b: trim_b
          }
        end

        # Trim params для одной трубы.
        # target_world — точка world coords куда должен попасть joint endpoint
        # после trim (closest_point на axis этой трубы к axis другой).
        #
        # Returns Hash:
        #   new_length_mm — новая длина definition (distance от far endpoint
        #                   до target_world по axis)
        #   new_origin_world — новая transformation.origin (только для
        #                      end_axis=-1, иначе nil)
        #   endpoint_world — где будет cut endpoint в world (= target_world)
        def compute_trim(tube, end_data, target_world)
          far = tube_endpoints(tube).find { |e| e[:end_axis] != end_data[:end_axis] }
          new_length_mm = far[:point].distance(target_world).to_mm

          if end_data[:end_axis] > 0
            # Joint at z=length: transformation.origin = z=0 endpoint = far,
            # не двигаем. Меняется только length.
            { new_length_mm: new_length_mm,
              new_origin_world: nil,
              endpoint_world: target_world }
          else
            # Joint at z=0: transformation.origin = z=0 endpoint = joint.
            # Двигаем origin до target_world; length меняется.
            { new_length_mm: new_length_mm,
              new_origin_world: target_world,
              endpoint_world: target_world }
          end
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
        # Реализация: explicit vector от joint endpoint OTHER tube до её far
        # endpoint. Это direction body OTHER tube в world coords. Не зависит
        # от axis sign conventions (не использует tube_axis_world).
        #
        # end_data_other — endpoint other tube'а который при joint.
        def compute_tilt_dir(tube_self, tube_other, end_data_other)
          ends_other = tube_endpoints(tube_other)
          far_other = ends_other.find { |e| e[:end_axis] != end_data_other[:end_axis] }
          to_body_world = far_other[:point] - end_data_other[:point]

          # Convert в local coords tube_self (только rotation effect для vector;
          # transform на Vector3d игнорирует translation часть transformation'а).
          inv = tube_self.transformation.inverse
          to_body_local = to_body_world.transform(inv)

          # Project на cross-section plane (XY local of tube_self).
          # Z-компонента = насколько body other tube extends along self axis,
          # для tilt direction она нерелевантна.
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

          # Где рисовать cut plane: при @trim_mode — на trimmed endpoint
          # (axis intersection), иначе — на текущем endpoint трубы.
          ep_a = @trim_mode ? @joint[:trim_a][:endpoint_world] : current_endpoint_world(@joint[:tube_a], @joint[:end_a])
          ep_b = @trim_mode ? @joint[:trim_b][:endpoint_world] : current_endpoint_world(@joint[:tube_b], @joint[:end_b])

          draw_cut_plane(view, @joint[:tube_a], @joint[:end_a],
                         @joint[:mitre_angle_deg], @joint[:tilt_dir_a_local], ep_a)
          draw_cut_plane(view, @joint[:tube_b], @joint[:end_b],
                         @joint[:mitre_angle_deg], @joint[:tilt_dir_b_local], ep_b)

          # Label с углом + mode возле joint point
          view.drawing_color = "white"
          screen_pt = view.screen_coords(jp)
          mode_str = @trim_mode ? "ТРИМ ВКЛ (T)" : "ТРИМ ВЫКЛ (T)"
          view.draw_text(screen_pt,
                         format("Mitre %.1f° (joint %.1f°)  %s",
                                @joint[:mitre_angle_deg],
                                @joint[:angle_between_deg],
                                mode_str))
          view.line_width = 1
        end

        def current_endpoint_world(tube, end_data)
          length_mm = AttrDict.read(tube.definition, "length_mm").to_f
          z_mm = end_data[:end_axis] > 0 ? length_mm : 0.0
          Geom::Point3d.new(0, 0, z_mm.mm).transform(tube.transformation)
        end

        # Рисует cut plane preview rectangle с tilt вокруг endpoint_world.
        # Использует rotation из tube.transformation (local axis directions),
        # но centroid плоскости задаётся через endpoint_world — это позволяет
        # рисовать preview на trimmed endpoint без модификации definition.
        def draw_cut_plane(view, tube, end_data, angle_deg, tilt_dir_local, endpoint_world)
          width_mm = AttrDict.read(tube.definition, "width_mm").to_f
          height_mm = AttrDict.read(tube.definition, "height_mm").to_f
          end_sign = end_data[:end_axis]
          tan_a = Math.tan(angle_deg * Math::PI / 180.0)
          half_w = width_mm / 2.0
          half_h = height_mm / 2.0
          dx, dy = tilt_dir_local.x, tilt_dir_local.y

          # Local axis directions трубы в world (rotation only, без translation —
          # вектор transform игнорирует translation часть).
          t = tube.transformation
          x_world = Geom::Vector3d.new(1, 0, 0).transform(t).normalize
          y_world = Geom::Vector3d.new(0, 1, 0).transform(t).normalize
          z_world = Geom::Vector3d.new(0, 0, 1).transform(t).normalize

          local_corners = [
            [+half_w, +half_h], [+half_w, -half_h],
            [-half_w, -half_h], [-half_w, +half_h]
          ]
          world_corners = local_corners.map do |(lx, ly)|
            dz_mm = end_sign * (lx * dx + ly * dy) * tan_a
            endpoint_world
              .offset(x_world, lx.mm)
              .offset(y_world, ly.mm)
              .offset(z_world, dz_mm.mm)
          end

          view.line_width = 3
          view.drawing_color = "cyan"
          loop_pts = world_corners + [world_corners.first]
          view.draw_polyline(loop_pts)

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
          op_label = @trim_mode ? "FabKit CAD: trim+mitre #{mitre.round(1)}°" :
                                   "FabKit CAD: mitre #{mitre.round(1)}°"
          model.start_operation(op_label, true, false, false)
          begin
            apply_to_one_tube(@joint[:tube_a], @joint[:end_a], mitre,
                              @joint[:tilt_dir_a_local],
                              @trim_mode ? @joint[:trim_a] : nil)
            apply_to_one_tube(@joint[:tube_b], @joint[:end_b], mitre,
                              @joint[:tilt_dir_b_local],
                              @trim_mode ? @joint[:trim_b] : nil)
            model.commit_operation
            puts "[FabKitCadTool] applied #{op_label}"
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

        # trim_data: nil = без trim (cut на текущем endpoint).
        # trim_data: Hash от compute_trim — переопределяет length_mm и (для
        # end_axis=-1) сдвигает transformation.origin до new endpoint.
        def apply_to_one_tube(tube, end_data, angle_deg, tilt_dir_local, trim_data)
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

          if trim_data
            # 1. Сдвинуть transformation если joint at z=0 — local origin
            # должен попасть на trimmed endpoint world.
            if trim_data[:new_origin_world]
              old_t = tube.transformation
              x_axis = Geom::Vector3d.new(1, 0, 0).transform(old_t)
              y_axis = Geom::Vector3d.new(0, 1, 0).transform(old_t)
              z_axis = Geom::Vector3d.new(0, 0, 1).transform(old_t)
              tube.transformation = Geom::Transformation.axes(
                trim_data[:new_origin_world], x_axis, y_axis, z_axis
              )
            end
            # 2. Override length для rebuild_with_cut.
            params = params.merge(length_mm: trim_data[:new_length_mm])
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
