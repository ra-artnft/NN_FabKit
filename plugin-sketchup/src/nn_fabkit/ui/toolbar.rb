# encoding: UTF-8

module NN
  module FabKit
    module UI
      # NN FabKit toolbar — одна кнопка «Inspector» в верхней workspace
      # area SU. Стационарная: закрытие диалога Inspector (X в заголовке)
      # НЕ скрывает кнопку. Чтобы убрать из workspace — пользователь сам:
      # `View → Toolbars → NN FabKit` (uncheck) или правый клик по
      # toolbar area → uncheck.
      #
      # Auto-show при первой загрузке после установки (TB_NEVER_SHOWN);
      # при последующих сессиях — restore (уважает выбор пользователя).
      module Toolbar
        TOOLBAR_NAME = "NN FabKit".freeze

        class << self
          def register!
            return if @toolbar  # idempotent — register! может вызваться повторно при reload

            cmd = ::UI::Command.new("NN FabKit Inspector") { open_inspector }
            cmd.tooltip         = "NN FabKit — открыть Inspector"
            cmd.menu_text       = "Inspector"
            cmd.status_bar_text = "NN FabKit Inspector — боковая панель плагина"
            cmd.set_validation_proc {
              Inspector.visible? ? MF_CHECKED : MF_UNCHECKED
            }

            icon_path = File.join(__dir__, "icons", "inspector.svg")
            cmd.small_icon = icon_path
            cmd.large_icon = icon_path

            tb = ::UI::Toolbar.new(TOOLBAR_NAME)
            tb.add_item(cmd)

            # TB_NEVER_SHOWN — первая загрузка плагина после установки.
            # Любое другое состояние = пользователь уже видел toolbar и
            # сам решает показывать его или нет (restore возьмёт last state).
            case tb.get_last_state
            when TB_NEVER_SHOWN
              tb.show
            else
              tb.restore
            end

            @toolbar = tb
          end

          def open_inspector
            Inspector.show
          end
        end
      end
    end
  end
end
