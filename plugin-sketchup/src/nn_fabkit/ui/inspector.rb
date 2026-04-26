# encoding: UTF-8

require "json"

module NN
  module FabKit
    module UI
      # NN FabKit Inspector — постоянная боковая панель плагина (HtmlDialog).
      #
      # Sprint A: каркас + read-only список сортамента (62 типоразмера).
      # Sprint B: + форма «Создать» (длина / марка / кнопка) с двусторонним
      #           обменом через action_callback nn_create_rect_tube.
      # Sprint C добавит: selection-observer и редактор properties.
      module Inspector
        DIALOG_TITLE    = "NN FabKit Inspector".freeze
        DIALOG_PREF_KEY = "NN_FabKit_Inspector".freeze
        DEFAULT_WIDTH   = 360
        DEFAULT_HEIGHT  = 720
        MIN_WIDTH       = 300
        MIN_HEIGHT      = 380

        # U+2028 / U+2029 — JS line separators. Допустимы в JSON, но если их
        # инлайнить в `<script>` — JS-парсер обрывает строку. Заменяем на
        # JSON-эскейпы перед передачей в execute_script.
        JS_LINE_SEP      = " ".freeze
        JS_PARA_SEP      = " ".freeze
        JS_LINE_SEP_ESC  = '\\u2028'.freeze
        JS_PARA_SEP_ESC  = '\\u2029'.freeze

        class << self
          # Показать панель. Создаёт HtmlDialog при первом вызове, дальше
          # переиспользует тот же объект — preferences_key сохраняет позицию
          # и размер между сессиями SketchUp.
          def show
            dialog = singleton
            if dialog.visible?
              dialog.bring_to_front
            else
              dialog.show
            end
            dialog
          end

          # Принудительно пересоздать диалог — нужно при hot-reload в Ruby Console.
          def reset!
            if @dialog && @dialog.visible?
              @dialog.close
            end
            @dialog = nil
          end

          def visible?
            @dialog && @dialog.visible?
          end

          private

          def singleton
            @dialog ||= build_dialog
          end

          def build_dialog
            dialog = ::UI::HtmlDialog.new(
              dialog_title:    DIALOG_TITLE,
              preferences_key: DIALOG_PREF_KEY,
              scrollable:      true,
              resizable:       true,
              width:           DEFAULT_WIDTH,
              height:          DEFAULT_HEIGHT,
              left:            default_left,
              top:             120,
              min_width:       MIN_WIDTH,
              min_height:      MIN_HEIGHT,
              style:           ::UI::HtmlDialog::STYLE_DIALOG
            )
            dialog.set_file(html_path)
            register_callbacks(dialog)
            dialog
          end

          def html_path
            File.join(__dir__, "html", "inspector.html")
          end

          # Грубая «правая» позиция при первом открытии: реального API экранов
          # SketchUp не даёт, поэтому просто 1500px от левого края — на типичном
          # FullHD это правый край без перекрытия Outliner. Дальше пользователь
          # сам подвинет, и preferences_key запомнит позицию.
          def default_left
            1500
          end

          def register_callbacks(dialog)
            dialog.add_action_callback("nn_inspector_ready") do |_ctx|
              push_bootstrap(dialog)
            end

            dialog.add_action_callback("nn_inspector_log") do |_ctx, msg|
              puts "[NN::FabKit::UI::Inspector] #{msg}"
            end

            dialog.add_action_callback("nn_create_rect_tube") do |_ctx, typesize, grade, length_mm|
              outcome = NN::MetalFab::Commands::CreateRectTube
                          .create_with_params(typesize, grade, length_mm.to_f)
              push_create_done(dialog, outcome)
            end
          end

          def push_bootstrap(dialog)
            payload = {
              version:       NN::FabKit::VERSION,
              catalog:       NN::MetalFab::Catalog.rect_tube,
              grades:        NN::MetalFab::Catalog.rect_tube_grades,
              default_grade: NN::MetalFab::Catalog.rect_tube_default_grade
            }
            dialog.execute_script(
              "if (window.NNInspector) { window.NNInspector.bootstrap(#{js_json(payload)}); }"
            )
          rescue StandardError => e
            puts "[NN::FabKit::UI::Inspector] bootstrap error: #{e.class}: #{e.message}"
          end

          def push_create_done(dialog, outcome)
            payload =
              if outcome[:ok]
                { ok: true, name: outcome[:name], typesize: outcome[:typesize] }
              else
                { ok: false, error: outcome[:error] }
              end
            dialog.execute_script(
              "if (window.NNInspector) { window.NNInspector.createDone(#{js_json(payload)}); }"
            )
          rescue StandardError => e
            puts "[NN::FabKit::UI::Inspector] createDone push error: #{e.class}: #{e.message}"
          end

          # JSON ⊆ JS-литералы по синтаксису — можно инлайнить как выражение.
          # Кроме одного места: U+2028/U+2029 в JS — line terminators, ломают
          # source. Эскейпим их вручную в JSON-escape sequence.
          def js_json(payload)
            JSON.generate(payload)
                .gsub(JS_LINE_SEP, JS_LINE_SEP_ESC)
                .gsub(JS_PARA_SEP, JS_PARA_SEP_ESC)
          end
        end
      end
    end
  end
end
