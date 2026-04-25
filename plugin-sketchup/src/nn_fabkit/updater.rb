# encoding: UTF-8

require "net/http"
require "uri"
require "json"
require "tempfile"

module NN
  module FabKit
    # Удалённое обновление плагина: читает manifest по URL, сравнивает
    # версии, скачивает .rbz и устанавливает через Sketchup.install_from_archive.
    #
    # Manifest формат (любой URL, выбираемый заказчиком):
    # {
    #   "latest_version": "0.4.1",
    #   "rbz_url":        "https://.../nn_fabkit-0.4.1.rbz",
    #   "release_notes":  "Что нового..."
    # }
    #
    # URL manifest'а живёт в SketchUp::Sketchup.read_default/write_default —
    # сохраняется между сессиями. Дефолт — заглушка, заказчик устанавливает свой.
    module Updater
      DEFAULT_MANIFEST_URL = "https://example.invalid/nn_fabkit/update.json".freeze
      PREF_SECTION = "NN_FabKit".freeze
      PREF_KEY     = "update_manifest_url".freeze

      module_function

      # === Persisted manifest URL ==================================================

      def manifest_url
        Sketchup.read_default(PREF_SECTION, PREF_KEY, DEFAULT_MANIFEST_URL)
      end

      def manifest_url=(url)
        Sketchup.write_default(PREF_SECTION, PREF_KEY, url.to_s)
      end

      # === Public API ==============================================================

      # Проверка обновления. Возвращает hash:
      #   { up_to_date: true,  current: "0.4.0", latest: "0.4.0" }
      #   { up_to_date: false, current: "0.4.0", latest: "0.4.1", rbz_url: "...", release_notes: "..." }
      # Поднимает StandardError при сетевых/парсинговых проблемах.
      def check(url = manifest_url)
        body = http_get_text(url)
        manifest = JSON.parse(body)
        latest    = manifest.fetch("latest_version").to_s
        rbz_url   = manifest["rbz_url"].to_s
        notes     = manifest["release_notes"].to_s

        cmp = compare_versions(latest, NN::FabKit::VERSION)
        if cmp <= 0
          { up_to_date: true, current: NN::FabKit::VERSION, latest: latest }
        else
          {
            up_to_date:    false,
            current:       NN::FabKit::VERSION,
            latest:        latest,
            rbz_url:       rbz_url,
            release_notes: notes
          }
        end
      end

      # Скачать .rbz с url во временный файл и поставить через Sketchup API.
      # SketchUp требует рестарт после Install — об этом сигнализирует UI-команда.
      def install(rbz_url)
        raise "rbz_url пуст" if rbz_url.to_s.empty?

        tmp = Tempfile.new(["nn_fabkit_update", ".rbz"])
        tmp.binmode
        begin
          tmp.write(http_get_binary(rbz_url))
        ensure
          tmp.close
        end

        ok = Sketchup.install_from_archive(tmp.path)
        tmp.unlink
        ok
      end

      # === Networking ==============================================================

      def http_get_text(url)
        body, code = http_fetch(url, binary: false)
        raise "HTTP #{code} при запросе #{url}" unless code.between?(200, 299)
        body
      end

      def http_get_binary(url)
        body, code = http_fetch(url, binary: true)
        raise "HTTP #{code} при загрузке #{url}" unless code.between?(200, 299)
        body
      end

      def http_fetch(url, binary:, max_redirects: 5)
        uri = URI.parse(url)
        max_redirects.times do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.read_timeout = 15
          http.open_timeout = 10

          req = Net::HTTP::Get.new(uri.request_uri)
          req["User-Agent"] = "NN-FabKit-Updater/#{NN::FabKit::VERSION}"

          res = http.request(req)
          case res
          when Net::HTTPSuccess
            return [res.body, res.code.to_i]
          when Net::HTTPRedirection
            location = res["location"]
            uri = URI.parse(location)
            next
          else
            return [res.body || "", res.code.to_i]
          end
        end
        raise "Слишком много редиректов на #{url}"
      end

      # === Version comparison ======================================================

      # "0.3.10" > "0.3.2": числовое сравнение по сегментам.
      # "0.4.0-beta" принимаем за "0.4.0" (suffix игнорируется в MVP).
      def compare_versions(a, b)
        ai = parse_version(a)
        bi = parse_version(b)
        max = [ai.size, bi.size].max
        max.times do |i|
          x = ai[i] || 0
          y = bi[i] || 0
          return -1 if x < y
          return  1 if x > y
        end
        0
      end

      def parse_version(s)
        s.to_s.split(/[.\-+]/).first(3).map(&:to_i)
      end
    end
  end
end
