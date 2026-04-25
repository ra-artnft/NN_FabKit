"""FastMCP server exposing NN FabKit SketchUp tools to MCP clients (Claude Code, Desktop, …).

Tools just thin-proxy to the Ruby-side TCP server inside SketchUp.
"""

from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from nn_fabkit_mcp.transport import RpcError, TcpClient, TransportError

mcp = FastMCP("nn-fabkit")
_client = TcpClient()


@mcp.tool()
def eval_ruby(code: str) -> dict[str, Any]:
    """Execute arbitrary Ruby code inside the running SketchUp instance.

    The plugin (NN::FabKit) is loaded so `Sketchup.*`, `NN::FabKit::*`, `NN::MetalFab::*`
    are all in scope. `puts`/`print` output is captured.

    Args:
        code: Ruby source to evaluate. Returned as the value of the last expression.

    Returns:
        dict with keys:
          - `value`: serialized return value of the last expression (primitives, arrays,
            hashes preserved; complex SU objects come back as `inspect` strings).
          - `stdout`: anything printed via `puts`/`print` during execution.

    Example:
        eval_ruby("Sketchup.active_model.title")
        eval_ruby("NN::MetalFab::ProfileGenerator::RectTube.build(...)")
    """
    return _call("eval_ruby", {"code": code})


@mcp.tool()
def get_scene_info() -> dict[str, Any]:
    """Quick snapshot of the current SketchUp model.

    Returns title, path, counts (definitions/instances/materials/selection),
    bounds in mm, and a brief listing of up to 20 selected entities (with
    `nn_metalfab` metadata if they are NN FabKit components).

    Cheap call — does not dump full geometry. For full dump, use `dump_model`.
    """
    return _call("get_scene_info")


@mcp.tool()
def dump_model(path: str | None = None) -> dict[str, Any]:
    """Dump the entire SketchUp model to a structured JSON file via NN::FabKit::SkpDump.

    Args:
        path: optional output path. If omitted, saves next to the .skp file
            (or to Desktop if model is unsaved), using `<basename>.dump.json`.

    Returns:
        dict with `saved_to` (final path) and `size_kb`.
    """
    return _call("dump_model", {"path": path} if path else {})


# ----- Internal -----


def _call(method: str, params: dict[str, Any] | None = None) -> Any:
    """Single-point error handling: wrap transport/RPC errors so MCP gets a clean message."""
    try:
        return _client.request(method, params)
    except RpcError as e:
        # Re-raise so FastMCP returns a tool error to the client with a helpful message.
        # MCP framework will surface this as an "isError: true" content.
        raise RuntimeError(str(e)) from e
    except TransportError as e:
        raise RuntimeError(str(e)) from e


def main() -> None:
    """Entry point for `nn-fabkit-mcp` script and `python -m nn_fabkit_mcp`."""
    mcp.run()


if __name__ == "__main__":
    main()
