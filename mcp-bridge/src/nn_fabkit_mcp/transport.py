"""TCP transport to the Ruby-side NN::FabKit::Mcp::Server.

Connection-per-request: open socket → write one line of JSON → read until LF →
close. Matches the Ruby server which is single-threaded (UI.start_timer polling)
and accepts one request per accept() call.
"""

from __future__ import annotations

import json
import socket
from typing import Any


class TransportError(RuntimeError):
    """Network or protocol-level failure talking to the SketchUp plugin."""


class RpcError(RuntimeError):
    """JSON-RPC error response from the SketchUp side (method raised, etc.)."""

    def __init__(self, code: int, message: str, data: Any = None) -> None:
        super().__init__(f"[RPC {code}] {message}")
        self.code = code
        self.message = message
        self.data = data


class TcpClient:
    """Thin JSON-RPC 2.0 client over TCP, one request per connection."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 9876,
        timeout_s: float = 30.0,
    ) -> None:
        self.host = host
        self.port = port
        self.timeout_s = timeout_s
        self._next_id = 0

    def request(self, method: str, params: dict[str, Any] | None = None) -> Any:
        """Send a JSON-RPC request, return `result` field, raise RpcError on `error`."""
        self._next_id += 1
        request_id = self._next_id

        payload = (
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "method": method,
                    "params": params or {},
                },
                ensure_ascii=False,
            ).encode("utf-8")
            + b"\n"
        )

        try:
            with socket.create_connection((self.host, self.port), timeout=self.timeout_s) as sock:
                sock.sendall(payload)
                response_data = self._read_until_lf(sock)
        except (ConnectionRefusedError, OSError) as e:
            raise TransportError(
                f"Cannot reach SketchUp MCP server at {self.host}:{self.port}. "
                f"Is the plugin running and is `Extensions → NN FabKit → MCP сервер → Запустить…` "
                f"clicked? Underlying: {e!s}"
            ) from e

        try:
            response = json.loads(response_data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            raise TransportError(f"Malformed JSON-RPC response: {e!s}; raw={response_data!r}") from e

        if "error" in response:
            err = response["error"]
            raise RpcError(err.get("code", -1), err.get("message", "<no message>"), err.get("data"))

        if "result" not in response:
            raise TransportError(f"Response has neither 'result' nor 'error': {response!r}")

        return response["result"]

    @staticmethod
    def _read_until_lf(sock: socket.socket) -> bytes:
        chunks: list[bytes] = []
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break
        data = b"".join(chunks)
        # If the server sends multi-line JSON in the future, split here. For now —
        # one response = one line, terminated by \n.
        return data.split(b"\n", 1)[0]
