# encoding: UTF-8

require "socket"
require "json"

module NN
  module FabKit
    module Mcp
      # TCP-сервер JSON-RPC 2.0 на 127.0.0.1:9876, запускается из главного потока
      # SketchUp через UI.start_timer (нельзя Thread.new — SU API не thread-safe).
      # Connection-per-request: client connects → шлёт одну строку JSON → читает
      # одну строку response → disconnect. Это просто и устойчиво.
      class Server
        DEFAULT_HOST    = "127.0.0.1".freeze
        DEFAULT_PORT    = 9876
        POLL_INTERVAL_S = 0.1
        READ_TIMEOUT_S  = 30.0

        attr_reader :host, :port

        def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT)
          @host     = host
          @port     = port
          @running  = false
          @server   = nil
          @timer_id = nil
        end

        def running?
          @running
        end

        def status
          { running: @running, host: @host, port: @port }
        end

        def start
          return true if @running

          @server = TCPServer.new(@host, @port)
          @running = true
          # UI.start_timer(0.1, true) — repeating timer на main thread.
          # Каждые 100мс проверяем accept_nonblock, обслуживаем клиента, идём дальше.
          # SU остаётся отзывчивым — не блокируем UI.
          @timer_id = ::UI.start_timer(POLL_INTERVAL_S, true) { tick }
          log "Listening on #{@host}:#{@port}"
          true
        rescue StandardError => e
          log "Failed to start: #{e.class}: #{e.message}"
          @running = false
          @server  = nil
          @timer_id = nil
          false
        end

        def stop
          return true unless @running

          ::UI.stop_timer(@timer_id) if @timer_id
          @timer_id = nil
          if @server
            begin
              @server.close
            rescue IOError
              # already closed
            end
            @server = nil
          end
          @running = false
          log "Stopped"
          true
        end

        # ----- Internal -----

        def tick
          return unless @running && @server

          ready = IO.select([@server], nil, nil, 0)
          return unless ready

          begin
            client = @server.accept_nonblock
            handle_client(client)
          rescue IO::WaitReadable, Errno::EAGAIN, Errno::EWOULDBLOCK
            # No client waiting right this instant; that's fine.
          rescue StandardError => e
            log "tick error: #{e.class}: #{e.message}"
          end
        end

        def handle_client(client)
          # Read one line — это весь JSON-RPC запрос.
          line = nil
          begin
            client.recv_nonblock(0)  # peek; но проще gets
          rescue IO::WaitReadable, Errno::EAGAIN
            # норма — данные ещё не пришли
          rescue StandardError
            # ignore
          end
          line = client.gets

          if line.nil? || line.empty?
            client.close
            return
          end

          # Windows может отдать в локали — форсируем UTF-8.
          line.force_encoding("UTF-8")

          response = nil
          request_id = nil
          begin
            request = JSON.parse(line)
            request_id = request["id"]
            response = JsonRpc.dispatch(request)
          rescue JSON::ParserError => e
            response = JsonRpc.error_response(request_id, -32700, "Parse error: #{e.message}")
          rescue StandardError => e
            response = JsonRpc.error_response(
              request_id, -32603,
              "Internal: #{e.class}: #{e.message}",
              data: { backtrace: e.backtrace.first(10) }
            )
          end

          payload = response.to_json + "\n"
          client.write(payload)
          client.flush
        rescue StandardError => e
          log "handle_client error: #{e.class}: #{e.message}"
        ensure
          client.close if client && !client.closed?
        end

        def log(msg)
          puts "[NN::FabKit::Mcp] #{msg}"
          $stdout.flush
        end
      end

      # Singleton — один TCP сервер на одну SU-сессию.
      class << self
        def instance
          @instance ||= Server.new
        end

        def start; instance.start; end
        def stop;  instance.stop;  end
        def status; instance.status; end
        def running?; instance.running?; end
      end
    end
  end
end
