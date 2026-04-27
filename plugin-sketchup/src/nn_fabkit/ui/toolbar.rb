# encoding: UTF-8

module NN
  module FabKit
    module UI
      # NN FabKit toolbar — кнопки в верхней workspace area SU.
      # v0.10.3: добавлена вторая кнопка «Создать трубу» — toolbar
      # становится шире, drag handle area крупнее, dock-detection в SU 2025
      # работает (single-button toolbar имел слишком тонкий drag handle).
      #
      # Кнопки:
      #   1. Inspector — открыть боковую панель.
      #   2. Создать трубу — UI.inputbox flow (CreateRectTube.call).
      #   3. FabKit CAD — interactive mitre cut tool.
      #   4. PDF cut-list — A4 чертёж с 4 viewport-ами + cut-list (v0.12.3+).
      module Toolbar
        TOOLBAR_NAME = "NN FabKit Tools".freeze
        LOG_PREFIX = "[NN::FabKit::UI::Toolbar]".freeze

        class << self
          def register!
            return if @toolbar
            puts "#{LOG_PREFIX} register! called (name=#{TOOLBAR_NAME})"

            tb = ::UI::Toolbar.new(TOOLBAR_NAME)
            tb.add_item(build_inspector_command)
            tb.add_item(build_create_tube_command)
            tb.add_item(build_fabkit_cad_command)
            tb.add_item(build_pdf_cut_list_command)
            puts "#{LOG_PREFIX} toolbar created, item count=#{tb.count}"

            state = tb.get_last_state
            puts "#{LOG_PREFIX} get_last_state=#{state} " \
                 "(NEVER=#{TB_NEVER_SHOWN} HIDDEN=#{TB_HIDDEN} VISIBLE=#{TB_VISIBLE})"

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

          private

          def build_inspector_command
            cmd = ::UI::Command.new("NN FabKit Inspector") { Inspector.show }
            cmd.tooltip         = "NN FabKit — открыть Inspector"
            cmd.menu_text       = "Inspector"
            cmd.status_bar_text = "NN FabKit Inspector — боковая панель плагина"
            small, large = icon_paths("inspector")
            cmd.small_icon = small
            cmd.large_icon = large
            cmd
          end

          def build_create_tube_command
            cmd = ::UI::Command.new("NN FabKit — Создать трубу") {
              NN::MetalFab::Commands::CreateRectTube.call
            }
            cmd.tooltip         = "Создать «Профильная труба» из каталога"
            cmd.menu_text       = "Создать трубу"
            cmd.status_bar_text = "Создать DC «Профильная труба» по типоразмеру из ГОСТ-каталога"
            small, large = icon_paths("create-tube")
            cmd.small_icon = small
            cmd.large_icon = large
            cmd
          end

          def build_fabkit_cad_command
            cmd = ::UI::Command.new("FabKit CAD") {
              ::Sketchup.active_model.select_tool(NN::MetalFab::Tools::FabKitCadTool.new)
            }
            cmd.tooltip         = "FabKit CAD — interactive mitre cut на трубе"
            cmd.menu_text       = "FabKit CAD"
            cmd.status_bar_text = "Кликни вершину трубы → выбери угол среза мышью или цифрой в VCB"
            small, large = icon_paths("fabkit-cad")
            cmd.small_icon = small
            cmd.large_icon = large
            cmd
          end

          def build_pdf_cut_list_command
            cmd = ::UI::Command.new("PDF cut-list") {
              NN::MetalFab::Commands::ExportLayoutPdf.call
            }
            cmd.tooltip         = "Создать PDF cut-list (A4 + 4 вида + спецификация)"
            cmd.menu_text       = "PDF cut-list"
            cmd.status_bar_text = "Сгенерировать LayOut-чертёж + PDF: title block, " \
                                  "Изо/Сверху/Спереди/Сбоку, спецификация по деталям"
            small, large = icon_paths("pdf-cut-list")
            cmd.small_icon = small
            cmd.large_icon = large
            cmd
          end

          def icon_paths(name)
            dir = File.join(__dir__, "icons")
            small = File.join(dir, "#{name}-16.png")
            large = File.join(dir, "#{name}-24.png")
            puts "#{LOG_PREFIX} icons #{name}: small=#{File.exist?(small)} large=#{File.exist?(large)}"
            [small, large]
          end
        end
      end
    end
  end
end
