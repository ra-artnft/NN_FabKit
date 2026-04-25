# encoding: UTF-8

require "json"

module NN
  module FabKit
    module UI
      # NN FabKit Inspector — постоянная боковая панель плагина (HtmlDialog).
      #
      # Sprint A spec-03 — каркас:
      #   * меню «Открыть Inspector» создаёт/показывает HtmlDialog справа;
      #   * три секции: header (бренд+версия), MetalFab (сортамент трубы),
      #     Selection (заглушка «не выделено»);
      #   * каталог типоразмеров (62 шт) грузится из MetalFab::Catalog
      #     и пушится в JS через execute_script на колбэке `nn_inspector_ready`.
      #
      # Sprint B/C добавят: create-кнопку, фильтры, selection-observer и редактор.
      module Inspector
        DIALOG_TITLE    = "NN FabKit Inspector".freeze
        DIALOG_PREF_KEY = "NN_FabKit_Inspector".freeze
        DEFAULT_WIDTH   = 360
        DEFAULT_HEIGHT  = 720
        MIN_WIDTH       = 300
        MIN_HEIGHT      = 380

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
          end

          def push_bootstrap(dialog)
            payload = {
              version:       NN::FabKit::VERSION,
              catalog:       NN::MetalFab::Catalog.rect_tube,
              grades:        NN::MetalFab::Catalog.rect_tube_grades,
              default_grade: NN::MetalFab::Catalog.rect_tube_default_grade
            }
            json = JSON.generate(payload)
            # JSON ⊆ JS-литералы по синтаксису — можно инлайнить как выражение.
            # Только U+2028 / U+2029 в JSON разрешены, а в JS — это line terminators,
            # которые сломают source. Эскейпим их вручную.
            json = json.gsub(" ", '\\u2028').gsub(" ", '\\u2029')
            dialog.execute_script(
              "if (window.NNInspector) { window.NNInspector.bootstrap(#{json}); }"
            )
          rescue StandardError => e
            puts "[NN::FabKit::UI::Inspector] bootstrap error: #{e.class}: #{e.message}"
          end
        end
      end
    end
  end
end
