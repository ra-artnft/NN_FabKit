# encoding: UTF-8

module NN
  module FabKit
    module Commands
      # UI-команда: проверка обновлений плагина с remote URL.
      # При первом запуске спрашивает manifest URL и сохраняет в SU preferences.
      # Потом — точечно: проверка → диалог «есть новая версия» → скачка → install.
      module CheckUpdate
        TITLE = "NN FabKit — Обновление".freeze

        # Prefs ключ для версии, от которой пользователь нажал «Игнорировать»
        # в фоновом popup'е. Не показываем popup для той же версии повторно.
        DISMISSED_VERSION_KEY = "dismissed_update_version".freeze
        # Задержка перед фоновой проверкой при старте — даём SU прогрузиться
        # полностью, чтобы popup не вылетал поверх splash screen.
        STARTUP_CHECK_DELAY_S = 3.0
        # Один раз за сессию SU. Без guard'а timer'ы могут срабатывать
        # повторно при reload.
        @startup_check_done = false

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
          # Default URL теперь — официальный канал релизов на GitHub. Если он
          # уже стоит — используем без переспроса. Кастомный URL можно задать
          # отдельной командой «Сменить URL обновлений…».
          current
        end

        # Фоновая проверка при старте SketchUp. Через 3 секунды после
        # загрузки плагина → Updater.check (тихо). Если есть новая версия
        # И пользователь её не «Игнорировал» в прошлом session'е — popup
        # с MB_YESNO «Доступна v..., обновить?». YES → install + restart
        # message. NO → запоминаем в prefs (DISMISSED_VERSION_KEY), больше
        # не дёргаем для этой же версии.
        #
        # Сетевые ошибки и offline-старт глотаем тихо — не цель fail
        # запуска SU.
        def background_check_on_startup
          return if @startup_check_done
          @startup_check_done = true

          ::UI.start_timer(STARTUP_CHECK_DELAY_S, false) { run_background_check }
        end

        def run_background_check
          url = Updater.manifest_url
          return if url.nil? || url.to_s.strip.empty?

          begin
            result = Updater.check(url)
          rescue StandardError => e
            puts "[NN::FabKit] background update check failed: #{e.class}: #{e.message}"
            return
          end

          return if result[:up_to_date]

          # User уже сказал «Игнорировать» для именно этой версии — silent.
          return if dismissed?(result[:latest])

          show_update_prompt(result)
        end

        def show_update_prompt(result)
          notes = result[:release_notes].to_s
          confirm = ::UI.messagebox(
            "Обновление NN FabKit доступно: v#{result[:latest]} (у вас v#{result[:current]}).\n\n" \
            "#{notes.empty? ? '' : "Что нового:\n#{notes}\n\n"}" \
            "Обновить сейчас?",
            MB_YESNO
          )

          if confirm == IDYES
            install_and_notify(result)
          else
            dismiss!(result[:latest])
            puts "[NN::FabKit] user dismissed v#{result[:latest]}; " \
                 "popup не появится для этой версии. Проверить вручную: " \
                 "Extensions → NN FabKit → Проверить обновления…"
          end
        end

        def install_and_notify(result)
          ok =
            begin
              Updater.install(result[:rbz_url])
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

        def dismissed?(version)
          Sketchup.read_default(Updater::PREF_SECTION, DISMISSED_VERSION_KEY) == version
        end

        def dismiss!(version)
          Sketchup.write_default(Updater::PREF_SECTION, DISMISSED_VERSION_KEY, version)
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
