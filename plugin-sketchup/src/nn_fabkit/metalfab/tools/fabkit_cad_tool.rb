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
        # Skew axes tolerance: если оси не пересекаются точно (closest_points
        # дают 2 разные точки на расстоянии > этого значения, мм) — joint
        # отклоняется. Геометрически невозможно «дотянуть» обе трубы до общей
        # точки изменением length: пришлось бы двигать каждую off-axis.
        SKEW_TOLERANCE_MM = 1.0

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

          @last_error_reason = nil
          @last_skew_distance_mm = nil
          @joint = find_joint(tubes[0], tubes[1])
          if @joint.nil?
            case @last_error_reason
            when :skew_axes
              @state = :skew_axes
              skew_str = format("%.2f", @last_skew_distance_mm || 0.0)
              @message = "FabKit CAD: оси труб не пересекаются (skew=#{skew_str} мм). Подвинь одну трубу так, чтобы оси встретились."
              puts "[FabKitCadTool] skew axes: #{skew_str} mm"
              ::UI.messagebox(
                "Оси этих 2 труб не пересекаются в одной точке " \
                "(расстояние между ними = #{skew_str} мм > #{SKEW_TOLERANCE_MM} мм).\n\n" \
                "Mitre joint требует, чтобы оси сходились — иначе геометрически " \
                "невозможно сделать стык без зазора (трубу пришлось бы двигать " \
                "перпендикулярно своей оси).\n\n" \
                "Подвинь одну из труб так, чтобы её ось пересеклась с осью другой, " \
                "и запусти FabKit CAD заново."
              )
            when :parallel
              @state = :parallel
              @message = "FabKit CAD: трубы параллельны, mitre не определён."
              puts "[FabKitCadTool] parallel tubes — no mitre defined"
              ::UI.messagebox(
                "Эти 2 трубы параллельны (или коллинеарны и направлены в одну сторону). " \
                "Mitre joint геометрически не определён."
              )
            else
              @state = :no_joint
              @message = "FabKit CAD: 2 трубы выбраны, но их концы не сходятся. Расположи концами к точке стыка."
              puts "[FabKitCadTool] no joint detected"
              ::UI.messagebox(
                "Эти 2 трубы не сходятся концами. Расположи их так, чтобы по одному " \
                "концу каждой было близко друг к другу."
              )
            end
            ::Sketchup.active_model.select_tool(nil)
            return
          end

          if tubes[0].definition.entityID == tubes[1].definition.entityID
            puts "[FabKitCadTool] same definition (copies)"
            # Determine which tube был создан позднее (выше persistent_id) и
            # предложить сделать на нём Make Unique. Persistent_id монотонно
            # возрастает в порядке создания entity в SU.
            later = tubes.max_by(&:persistent_id)
            earlier = tubes.find { |t| t.persistent_id != later.persistent_id }
            answer = ::UI.messagebox(
              "Эти 2 трубы — копии одного definition «#{tubes[0].definition.name}». " \
              "Mitre на копии нарушит обе.\n\n" \
              "Сделать Make Unique для более поздней (created позднее)?\n" \
              "→ ОК: автоматически делается unique у trubы (pid=#{later.persistent_id})\n" \
              "    после чего FabKit CAD продолжит работу.\n" \
              "→ Cancel: tool отменяется, сделай Make Unique вручную.",
              MB_OKCANCEL
            )
            if answer == IDOK
              ::Sketchup.active_model.start_operation("Make Unique для FabKit CAD", true, false, false)
              later.make_unique
              ::Sketchup.active_model.commit_operation
              puts "[FabKitCadTool] made unique tube pid=#{later.persistent_id} → new def name=#{later.definition.name}"
              # Re-analyze: теперь definitions разные, продолжаем normal flow
              # (recursive call безопасный — после make_unique больше не same_definition)
              analyze_selection
              return
            else
              @state = :same_definition
              @message = "FabKit CAD: отмена — нужен Make Unique вручную"
              ::Sketchup.active_model.select_tool(nil)
              return
            end
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

          # Joint angle θ — full angle (0..180°) между трубами в стыке.
          # Считается из joint-to-far vectors (от near-endpoint каждой трубы
          # к её far-endpoint), а НЕ из axis vectors с .abs. Это даёт правильный
          # угол для любого θ, включая тупой L (θ > 90°).
          #
          # Семантика:
          #   90°  — perpendicular L → mitre 45°
          #   60°  — острый L (Y-brace) → mitre 60°
          #   120° — тупой L → mitre 30°
          #   180° — collinear butt → mitre 0° (perpendicular cut)
          #
          # Old bug (до v0.12.0): use .abs всегда сворачивал угол в [0, 90°],
          # для 120° давало mitre 60° вместо 30°.
          ends_a_all = tube_endpoints(tube_a)
          ends_b_all = tube_endpoints(tube_b)
          far_a = ends_a_all.find { |e| e[:end_axis] != best[:end_a][:end_axis] }
          far_b = ends_b_all.find { |e| e[:end_axis] != best[:end_b][:end_axis] }

          v_a = (far_a[:point] - best[:end_a][:point])
          v_b = (far_b[:point] - best[:end_b][:point])
          if v_a.length < 1.0e-9 || v_b.length < 1.0e-9
            return nil
          end
          v_a.normalize!
          v_b.normalize!
          dot_jf = v_a.dot(v_b).clamp(-1.0, 1.0)
          theta_rad = Math.acos(dot_jf)
          theta_deg = theta_rad * 180.0 / Math::PI

          # Защита: при theta ≈ 0 трубы параллельны и идут в одну сторону
          # (overlap, не joint). Mitre геометрически не определён.
          if theta_deg < 1.0
            @last_error_reason = :parallel
            return nil
          end

          mitre_angle = (180.0 - theta_deg) / 2.0

          # Joint point: ОСЬ-ИНТЕРСЕКЦИЯ через Geom.closest_points.
          # Не midpoint endpoints (тот off-axis от обеих труб) — а точка, где
          # пересекаются (или ближе всего сходятся) оси.
          axis_a = tube_axis_world(tube_a)
          axis_b = tube_axis_world(tube_b)
          line_a = [tube_a.transformation.origin, axis_a]
          line_b = [tube_b.transformation.origin, axis_b]
          closest = Geom.closest_points(line_a, line_b)

          # Skew detection: если оси не пересекаются в одной точке (closest[0]
          # != closest[1]), геометрически нельзя дотянуть обе трубы до общей
          # точки одной только сменой length — пришлось бы двигать оси off-line.
          # Раньше тихо trim'или каждую к своей closest_point → видимый gap
          # на стыке. Теперь явно abort'имся.
          skew_dist_mm = closest[0].distance(closest[1]).to_mm
          if skew_dist_mm > SKEW_TOLERANCE_MM
            @last_error_reason = :skew_axes
            @last_skew_distance_mm = skew_dist_mm
            return nil
          end
          jp = Geom::Point3d.linear_combination(0.5, closest[0], 0.5, closest[1])

          angle_between_deg = theta_deg

          # Trim params: каждая труба резается до СВОЕЙ closest_point (на её axis).
          # new_length = distance от far endpoint до этой точки.
          trim_a = compute_trim(tube_a, best[:end_a], closest[0])
          trim_b = compute_trim(tube_b, best[:end_b], closest[1])

          # Tilt direction для каждой трубы — TO body другой трубы (в local coords).
          # Передаём end_data of OTHER tube (не self) — нужен joint endpoint
          # other tube'а, чтобы правильно вычислить вектор «от joint к телу other».
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
            tilt_dir_b_local: tilt_b,
            trim_a: trim_a,
            trim_b: trim_b
          }
        end

        # Trim params для одной трубы.
        # target_world — точка world coords куда должен попасть joint endpoint
        # после trim (closest_point на axis этой трубы к axis другой).
        def compute_trim(tube, end_data, target_world)
          far = tube_endpoints(tube).find { |e| e[:end_axis] != end_data[:end_axis] }
          new_length_mm = far[:point].distance(target_world).to_mm
          if end_data[:end_axis] > 0
            # Joint at z=length: transformation.origin = far end, не двигается
            { new_length_mm: new_length_mm, new_origin_world: nil, endpoint_world: target_world }
          else
            # Joint at z=0: двигаем transformation.origin до target
            { new_length_mm: new_length_mm, new_origin_world: target_world, endpoint_world: target_world }
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
        # explicit вектор «AWAY from body of OTHER tube» — toward OUTER corner L.
        # Long side mitre extends в direction outer corner (где обе трубы дальше
        # всего от joint), short side — в inner corner.
        #
        # Геометрически: vector от far_endpoint(other) к joint_endpoint(other),
        # projected в local self's cross-section plane. Не зависит от axis sign
        # convention'ов — работает для любых end_axis комбинаций.
        #
        # end_data_other — endpoint of tube_other который при joint.
        def compute_tilt_dir(tube_self, tube_other, end_data_other)
          ends_other = tube_endpoints(tube_other)
          far_other = ends_other.find { |e| e[:end_axis] != end_data_other[:end_axis] }
          # vector AWAY from body (joint - far): от body OTHER tube наружу
          to_outer_world = end_data_other[:point] - far_other[:point]

          # Convert в local coords tube_self (vector#transform применяет только
          # rotation часть, translation игнорируется)
          inv = tube_self.transformation.inverse
          to_outer_local = to_outer_world.transform(inv)

          # Project на cross-section plane (XY local of tube_self)
          proj = Geom::Vector3d.new(to_outer_local.x, to_outer_local.y, 0)
          if proj.length < 1.0e-6
            # Оси параллельны (other tube collinear self) — fallback +Y
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
          # Marker at joint point — magenta cross. Это axis intersection
          # (после trim — endpoint обеих труб совпадёт здесь).
          jp = @joint[:joint_point]
          marker_size = 30.mm
          view.line_width = 3
          view.drawing_color = "magenta"
          view.draw(GL_LINES, [
            jp.offset(X_AXIS, -marker_size), jp.offset(X_AXIS, marker_size),
            jp.offset(Y_AXIS, -marker_size), jp.offset(Y_AXIS, marker_size),
            jp.offset(Z_AXIS, -marker_size), jp.offset(Z_AXIS, marker_size)
          ])

          # Cut plane preview — рисуется в TRIMMED endpoint каждой трубы
          # (на bisecting plane joint'а). Для perpendicular L два rect совпадают
          # в одной плоскости — visually выглядит как ОДИН cut.
          draw_cut_plane(view, @joint[:tube_a], @joint[:end_a],
                         @joint[:mitre_angle_deg], @joint[:tilt_dir_a_local],
                         @joint[:trim_a][:endpoint_world])
          draw_cut_plane(view, @joint[:tube_b], @joint[:end_b],
                         @joint[:mitre_angle_deg], @joint[:tilt_dir_b_local],
                         @joint[:trim_b][:endpoint_world])

          # Label с углом возле joint point
          view.drawing_color = "white"
          screen_pt = view.screen_coords(jp)
          view.draw_text(screen_pt,
                         format("Mitre %.1f° (joint %.1f° между трубами)",
                                @joint[:mitre_angle_deg],
                                @joint[:angle_between_deg]))
          view.line_width = 1
        end

        # endpoint_world — где будет cut endpoint после trim (axis intersection),
        # вместо текущего endpoint трубы. Cut rect рисуется centred на этой точке
        # в orientation tube.transformation, с tilt по mitre angle.
        def draw_cut_plane(view, tube, end_data, angle_deg, tilt_dir_local, endpoint_world)
          width_mm = AttrDict.read(tube.definition, "width_mm").to_f
          height_mm = AttrDict.read(tube.definition, "height_mm").to_f
          end_sign = end_data[:end_axis]
          tan_a = Math.tan(angle_deg * Math::PI / 180.0)
          half_w = width_mm / 2.0
          half_h = height_mm / 2.0
          dx, dy = tilt_dir_local.x, tilt_dir_local.y

          # Local axis directions в world (rotation only)
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
            endpoint_world.offset(x_world, lx.mm).offset(y_world, ly.mm).offset(z_world, dz_mm.mm)
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
          model.start_operation("FabKit CAD: trim+mitre joint #{mitre.round(1)}°", true, false, false)
          begin
            apply_to_one_tube(@joint[:tube_a], @joint[:end_a], mitre,
                              @joint[:tilt_dir_a_local], @joint[:trim_a])
            apply_to_one_tube(@joint[:tube_b], @joint[:end_b], mitre,
                              @joint[:tilt_dir_b_local], @joint[:trim_b])
            model.commit_operation
            puts "[FabKitCadTool] applied trim+mitre joint #{mitre}°"
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

          # CRITICAL (v0.11.12): auto make_unique если definition shared.
          # Страховка от user-skip Make Unique button. Без этого apply mitre
          # на одной trubе модифицировал shared definition → соседняя «удлинялась».
          if tube.definition.instances.length > 1
            old_def_name = tube.definition.name
            tube.make_unique
            puts "[FabKitCadTool] auto make_unique pid=#{tube.persistent_id}: " \
                 "#{old_def_name} → #{tube.definition.name}"
            params = AttrDict.read_rect_tube_params(tube.definition) || params
          end

          # Trim: shift transformation если joint at z=0; обновить length_mm.
          # CRITICAL (v0.11.12): pure translation × old_transformation сохраняет
          # rotation TOOH (без FP drift). Прежний подход через .axes() rebuild
          # пере-вычислял xaxis/yaxis/zaxis из old_t каждый apply, накапливая
          # FP errors в orthonormal basis → tubes «крутились» на 0.01° после
          # ~5 операций.
          if trim_data
            if trim_data[:new_origin_world]
              old_t = tube.transformation
              delta = trim_data[:new_origin_world] - old_t.origin
              tube.transformation = Geom::Transformation.translation(delta) * old_t
            end
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
