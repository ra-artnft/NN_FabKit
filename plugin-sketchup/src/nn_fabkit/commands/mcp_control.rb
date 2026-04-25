# encoding: UTF-8

module NN
  module FabKit
    module Commands
      # UI-команды управления MCP-сервером. Запуск — явный, с предупреждением
      # про мощь eval_ruby (любой процесс на машине может исполнять Ruby в SU,
      # пока сервер активен).
      module McpControl
        WARNING = "MCP-сервер слушает 127.0.0.1:9876 и принимает команды eval_ruby — " \
                  "любой процесс на этом компьютере может выполнять произвольный Ruby " \
                  "в SketchUp, пока сервер активен.\n\n" \
                  "Запускай только если доверяешь окружению (своя машина, известные " \
                  "процессы). Останови когда закончишь.\n\n" \
                  "Запустить?".freeze

        module_function

        def start
          if NN::FabKit::Mcp.running?
            ::UI.messagebox("MCP-сервер уже запущен на 127.0.0.1:9876.")
            return
          end

          confirm = ::UI.messagebox(WARNING, MB_YESNO)
          return unless confirm == IDYES

          ok = NN::FabKit::Mcp.start
          if ok
            ::UI.messagebox(
              "MCP-сервер запущен на 127.0.0.1:9876.\n\n" \
              "Подключение со стороны Claude — `claude mcp add nn-fabkit -- python -m nn_fabkit_mcp` " \
              "(см. README в папке mcp-bridge)."
            )
          else
            ::UI.messagebox(
              "Не удалось запустить MCP-сервер. Возможно порт 9876 занят " \
              "другим процессом. Подробности — в Window → Ruby Console (префикс [NN::FabKit::Mcp])."
            )
          end
        end

        def stop
          unless NN::FabKit::Mcp.running?
            ::UI.messagebox("MCP-сервер не запущен.")
            return
          end
          NN::FabKit::Mcp.stop
          ::UI.messagebox("MCP-сервер остановлен.")
        end

        def status
          s = NN::FabKit::Mcp.status
          if s[:running]
            ::UI.messagebox("MCP-сервер: ЗАПУЩЕН на #{s[:host]}:#{s[:port]}")
          else
            ::UI.messagebox("MCP-сервер: не запущен")
          end
        end
      end
    end
  end
end
