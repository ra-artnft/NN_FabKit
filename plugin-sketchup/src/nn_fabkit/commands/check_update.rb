# encoding: UTF-8

module NN
  module FabKit
    module Commands
      # UI-команда: проверка обновлений плагина с remote URL.
      # При первом запуске спрашивает manifest URL и сохраняет в SU preferences.
      # Потом — точечно: проверка → диалог «есть новая версия» → скачка → install.
      module CheckUpdate
        TITLE = "NN FabKit — Обновление".freeze

        module_function

        def call
          url = ensure_manifest_url
          return unless url

          begin
            result = Updater.check(url)
          rescue StandardError => e
            ::UI.messagebox(
              "Не удалось проверить обновления.\n\n" \
              "URL: #{url}\n" \
              "Ошибка: #{e.class}: #{e.message}\n\n" \
              "Проверь URL: Extensions → NN FabKit → Сменить URL обновлений…"
            )
            return
          end

          if result[:up_to_date]
            ::UI.messagebox(
              "У вас актуальная версия: v#{result[:current]}.\n\nManifest: #{url}"
            )
            return
          end

          notes = result[:release_notes].to_s
          confirm = ::UI.messagebox(
            "Доступна новая версия: v#{result[:latest]} (текущая: v#{result[:current]}).\n\n" \
            "#{notes.empty? ? '' : "Что нового:\n#{notes}\n\n"}" \
            "Скачать и установить сейчас?",
            MB_YESNO
          )
          return unless confirm == IDYES

          begin
            ok = Updater.install(result[:rbz_url])
          rescue StandardError => e
            ::UI.messagebox(
              "Не удалось установить обновление.\n\n#{e.class}: #{e.message}"
            )
            return
          end

          if ok
            ::UI.messagebox(
              "Обновление установлено (v#{result[:latest]}).\n\n" \
              "Полностью закрой и снова открой SketchUp, чтобы плагин загрузил " \
              "новую версию."
            )
          else
            ::UI.messagebox(
              "Sketchup.install_from_archive вернул false. Возможно файл " \
              ".rbz повреждён или extension загрузка отключена настройкой " \
              "Extensions Loading Policy."
            )
          end
        end

        # Проверка / опрос URL манифеста. Возвращает URL или nil (если пользователь отменил).
        def ensure_manifest_url
          current = Updater.manifest_url
          if current == Updater::DEFAULT_MANIFEST_URL
            entered = ::UI.inputbox(
              ["Manifest URL"],
              [""],
              [""],
              "NN FabKit — задать URL обновлений"
            )
            return nil unless entered
            url = entered.first.to_s.strip
            if url.empty?
              ::UI.messagebox(
                "URL не задан. Manifest должен указывать на JSON вида:\n\n" \
                "{\n  \"latest_version\": \"0.4.1\",\n  \"rbz_url\": \"https://.../nn_fabkit-0.4.1.rbz\",\n" \
                "  \"release_notes\": \"...\"\n}"
              )
              return nil
            end
            Updater.manifest_url = url
            url
          else
            current
          end
        end

        # Отдельная команда для смены URL.
        def change_url
          current = Updater.manifest_url
          entered = ::UI.inputbox(
            ["Manifest URL"],
            [current],
            [""],
            "NN FabKit — сменить URL обновлений"
          )
          return unless entered
          url = entered.first.to_s.strip
          return if url.empty?
          Updater.manifest_url = url
          ::UI.messagebox("URL сохранён:\n\n#{url}")
        end
      end
    end
  end
end
