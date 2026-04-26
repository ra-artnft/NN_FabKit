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
            return if @toolbar  # idempotent

            cmd = ::UI::Command.new("NN FabKit Inspector") { Inspector.show }
            cmd.tooltip         = "NN FabKit — открыть Inspector"
            cmd.menu_text       = "Inspector"
            cmd.status_bar_text = "NN FabKit Inspector — боковая панель плагина"

            # Используем PNG, а не SVG: SVG в SU 2025 рендерится непредсказуемо
            # на toolbar buttons (icon вроде показывается, но drag-to-dock не
            # работает — toolbar остаётся floating даже после ручного перетаскивания
            # в верхнюю workspace area). PNG-fallback гарантирует стандартное
            # поведение docking как у других плагинов (OCL и др.).
            icons_dir = File.join(__dir__, "icons")
            cmd.small_icon = File.join(icons_dir, "inspector-16.png")
            cmd.large_icon = File.join(icons_dir, "inspector-24.png")

            tb = ::UI::Toolbar.new(TOOLBAR_NAME)
            tb.add_item(cmd)

            # Поведение по first-install vs subsequent:
            #   TB_NEVER_SHOWN — первый раз после установки; show в default
            #     position (для большинства плагинов = top, для нас тоже).
            #   Иначе — restore last state (visibility + dock position).
            case tb.get_last_state
            when TB_NEVER_SHOWN
              tb.show
            else
              tb.restore
            end

            @toolbar = tb
          end
        end
      end
    end
  end
end
