# encoding: UTF-8

module NN
  module FabKit
    module UI
      # NN FabKit toolbar — одна кнопка «Inspector» в верхней workspace
      # area SU. v0.10.2: переименован из «NN FabKit» → «NN FabKit Tools»
      # чтобы flush'нуть кэшированный «sticky floating» state в SU registry,
      # который оставался от broken v0.9.0 SVG-попытки.
      module Toolbar
        # NB: имя сменено в v0.10.2. Если оставить «NN FabKit», SU 2025
        # помнит floating-position из v0.9.0 и не позволяет dock'нуть.
        # Новое имя = свежий entry в HKCU\Software\SketchUp\...\Toolbars.
        TOOLBAR_NAME = "NN FabKit Tools".freeze
        LOG_PREFIX = "[NN::FabKit::UI::Toolbar]".freeze

        class << self
          def register!
            return if @toolbar
            puts "#{LOG_PREFIX} register! called (name=#{TOOLBAR_NAME})"

            cmd = ::UI::Command.new("NN FabKit Inspector") { Inspector.show }
            cmd.tooltip         = "NN FabKit — открыть Inspector"
            cmd.menu_text       = "Inspector"
            cmd.status_bar_text = "NN FabKit Inspector — боковая панель плагина"

            icons_dir = File.join(__dir__, "icons")
            small = File.join(icons_dir, "inspector-16.png")
            large = File.join(icons_dir, "inspector-24.png")
            puts "#{LOG_PREFIX} icons exist: small=#{File.exist?(small)} large=#{File.exist?(large)}"
            cmd.small_icon = small
            cmd.large_icon = large

            tb = ::UI::Toolbar.new(TOOLBAR_NAME)
            tb.add_item(cmd)
            puts "#{LOG_PREFIX} toolbar created, item count=#{tb.count}"

            state = tb.get_last_state
            puts "#{LOG_PREFIX} get_last_state=#{state} " \
                 "(NEVER=#{TB_NEVER_SHOWN} HIDDEN=#{TB_HIDDEN} VISIBLE=#{TB_VISIBLE})"

            # Deferred show через 0.5s — даём SU UI fully settle перед
            # созданием toolbar window. Иначе на некоторых системах SU 2025
            # рендерит toolbar в «полу-broken» state без drag-to-dock.
            ::UI.start_timer(0.5, false) do
              begin
                if state == TB_NEVER_SHOWN
                  puts "#{LOG_PREFIX} TB_NEVER_SHOWN → tb.show"
                  tb.show
                else
                  puts "#{LOG_PREFIX} not first time → tb.restore"
                  tb.restore
                end
                puts "#{LOG_PREFIX} after show/restore: visible=#{tb.visible?}"
              rescue StandardError => e
                puts "#{LOG_PREFIX} ERROR in timer: #{e.class}: #{e.message}"
              end
            end

            @toolbar = tb
            puts "#{LOG_PREFIX} register! complete"
          end
        end
      end
    end
  end
end
