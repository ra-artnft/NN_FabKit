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


@mcp.tool()
def layout_create_template(path: str, meta: dict[str, str] | None = None) -> dict[str, Any]:
    """Generate an A4 portrait LayOut document with title block, 3D viewport, and cut-list table.

    The cut-list groups all `rect_tube` ComponentInstances in the active SketchUp model
    by `nn_metalfab.typesize`, with columns: № / Типоразмер / ГОСТ / Сталь / Кол-во / Σ Длина / Σ Масса
    plus an ИТОГО row. Before saving, the active SU view runs `zoom_extents` and the .skp
    is saved (so the embedded `Layout::SketchUpModel` viewport captures the framed model).

    Currently uses millimeters (DECIMAL_MILLIMETERS, precision 0.1mm). Title block fields
    are hardcoded defaults that `meta` can override.

    Args:
        path: output .layout file path. If the file is currently open in LayOut, save
            will fail with `Errno::EACCES` — close it first.
        meta: optional dict overriding title block fields. Keys: `project`, `customer`,
            `date`, `scale`, `header`. Any omitted key falls back to the default.

    Returns:
        dict with `saved_to`, `size_kb`, `cut_list_groups`, `total_count`, `total_length_mm`,
        `total_mass_kg`.
    """
    params: dict[str, Any] = {"path": path}
    if meta:
        params["meta"] = meta
    return _call("layout_create_template", params)


@mcp.tool()
def layout_export_pdf(layout_path: str, pdf_path: str) -> dict[str, Any]:
    """Export an existing .layout file to PDF via `Layout::Document#export`.

    Args:
        layout_path: source .layout file (must exist).
        pdf_path: target .pdf path. Overwritten if exists.

    Returns:
        dict with `pdf_path` and `size_kb`.
    """
    return _call("layout_export_pdf", {"layout_path": layout_path, "pdf_path": pdf_path})


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
