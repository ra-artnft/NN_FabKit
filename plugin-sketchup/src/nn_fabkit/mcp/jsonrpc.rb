# encoding: UTF-8

module NN
  module FabKit
    module Mcp
      # Helpers для JSON-RPC 2.0 ответов и dispatch'а методов в Handlers registry.
      module JsonRpc
        module_function

        # Принимает разобранный hash запроса, возвращает hash ответа.
        # Все StandardError ловятся и упаковываются в стандартный error response,
        # чтобы клиент всегда получал валидный JSON-RPC, а сервер не падал.
        def dispatch(request)
          method_name = request["method"].to_s
          params      = request["params"] || {}
          id          = request["id"]

          handler = Handlers.lookup(method_name)
          return error_response(id, -32601, "Method not found: #{method_name}") unless handler

          begin
            result = handler.call(params)
            success_response(id, result)
          rescue ArgumentError => e
            error_response(id, -32602, "Invalid params: #{e.message}")
          rescue StandardError => e
            error_response(id, -32603, "Internal error: #{e.class}: #{e.message}",
                           data: { backtrace: e.backtrace.first(10) })
          end
        end

        def success_response(id, result)
          { "jsonrpc" => "2.0", "id" => id, "result" => result }
        end

        def error_response(id, code, message, data: nil)
          err = { "code" => code, "message" => message }
          err["data"] = data if data
          { "jsonrpc" => "2.0", "id" => id, "error" => err }
        end
      end
    end
  end
end
