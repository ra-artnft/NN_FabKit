# encoding: UTF-8

module NN
  module MetalFab
    module Commands
      # UI command: «Создать PDF cut-list».
      #
      # Workflow:
      #   1. Проверить что .skp сохранён (Layout::SketchUpModel читает с диска).
      #   2. UI.savepanel — куда сохранить PDF (default — рядом с .skp,
      #      имя `<basename>_cut_list.pdf`).
      #   3. Сгенерировать .layout (рядом с PDF, тот же basename) + export PDF.
      #   4. UI.messagebox со сводкой + предложить открыть.
      module ExportLayoutPdf
        module_function

        def call
          model = ::Sketchup.active_model
          unless model
            ::UI.messagebox("Открой .skp в SketchUp перед запуском.")
            return
          end
          if model.path.nil? || model.path.empty?
            ::UI.messagebox(
              "Сохрани .skp файл сначала (File → Save).\n\n" \
              "LayOut viewport читает 3D-модель с диска — для embedded views " \
              "нужен сохранённый .skp."
            )
            return
          end

          base = File.basename(model.path, ".*")
          dir = File.dirname(model.path)
          default_pdf_name = "#{base}_cut_list.pdf"

          pdf_path = ::UI.savepanel("Сохранить PDF cut-list", dir, default_pdf_name)
          return unless pdf_path  # user cancelled

          # SketchUp savepanel может не добавить расширение
          pdf_path = "#{pdf_path}.pdf" unless pdf_path.downcase.end_with?(".pdf")
          layout_path = pdf_path.sub(/\.pdf\z/i, ".layout")

          begin
            stats = NN::MetalFab::LayoutGen::TemplateCutList.generate(
              output_path: layout_path,
              meta: nil,
              pdf_path: pdf_path
            )
          rescue Errno::EACCES => e
            ::UI.messagebox(
              "Не удалось записать файл — возможно, он открыт в LayOut/PDF " \
              "viewer. Закрой и попробуй снова.\n\nДетали: #{e.message}"
            )
            return
          rescue StandardError => e
            ::UI.messagebox("Ошибка генерации: #{e.class}: #{e.message}")
            puts "[ExportLayoutPdf] #{e.class}: #{e.message}"
            puts e.backtrace.first(10).map { |l| "  #{l}" }.join("\n")
            return
          end

          msg = "Готово.\n\n" \
                "PDF: #{stats['pdf_path']}\n" \
                "    (#{stats['pdf_size_kb']} KB)\n\n" \
                "LayOut: #{stats['saved_to']}\n" \
                "    (#{stats['size_kb']} KB)\n\n" \
                "Деталей: #{stats['total_count']} шт, " \
                "#{stats['total_length_mm']} мм, " \
                "#{stats['total_mass_kg']} кг.\n\n" \
                "Открыть PDF?"
          if ::UI.messagebox(msg, MB_YESNO) == IDYES
            ::UI.openURL("file:///#{stats['pdf_path']}")
          end
        end
      end
    end
  end
end
