"""CLI: nn-fabkit-nc-export <subcommand> [args].

Подкоманды:
  hello-surface   — одна плоская грань (Type 110 + Type 122) для smoke-теста CAM
  rect-tube       — прямоугольная труба, surface-модель

Пример:
  nn-fabkit-nc-export hello-surface --width 40 --length 600 -o hello.igs
  nn-fabkit-nc-export rect-tube --width 40 --height 20 --wall 2 --length 600 \\
                                --no-radius -o tube.igs
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__
from .tube.rect_tube import hello_surface, rect_tube_box


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nn-fabkit-nc-export",
        description="NN FabKit NC-export — IGES writer для CNC трубопрофилерезов.",
    )
    parser.add_argument(
        "--version", action="version", version=f"nn-fabkit-nc-export {__version__}"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # hello-surface
    p_hello = sub.add_parser(
        "hello-surface",
        help="одна плоская грань (smoke-тест совместимости с CAM)",
    )
    p_hello.add_argument("--width", type=float, required=True, help="ширина грани, мм")
    p_hello.add_argument("--length", type=float, required=True, help="длина грани, мм")
    p_hello.add_argument(
        "-o", "--output", type=Path, required=True, help="путь сохранения .igs"
    )

    # rect-tube
    p_tube = sub.add_parser(
        "rect-tube",
        help="прямоугольная труба, surface-модель",
    )
    p_tube.add_argument("--width", type=float, required=True, help="внешняя ширина профиля, мм")
    p_tube.add_argument("--height", type=float, required=True, help="внешняя высота профиля, мм")
    p_tube.add_argument("--wall", type=float, default=2.0, help="толщина стенки, мм (для будущих шагов)")
    p_tube.add_argument("--length", type=float, required=True, help="длина трубы, мм")
    p_tube.add_argument(
        "--no-radius",
        action="store_true",
        help="плоские углы 90° (без скруглений). По умолчанию — со скруглениями (ГОСТ 30245-2003).",
    )
    p_tube.add_argument(
        "--radius", type=float, default=None,
        help="радиус наружного скругления, мм. Если не задан — авто по ГОСТ 30245-2003 (R=2.0t / 2.5t / 3.0t).",
    )
    p_tube.add_argument(
        "-o", "--output", type=Path, required=True, help="путь сохранения .igs"
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.command == "hello-surface":
        doc = hello_surface(width_mm=args.width, length_mm=args.length)
        doc.file_name = args.output.name
        doc.write(args.output)
        print(
            f"nc-export {__version__}  hello-surface "
            f"{args.width}x{args.length} mm -> {args.output} "
            f"({len(doc.entities)} entities)"
        )
        return 0

    if args.command == "rect-tube":
        if args.no_radius:
            radius = 0.0
        else:
            radius = args.radius  # None → авто по ГОСТ
        doc = rect_tube_box(
            width_mm=args.width,
            height_mm=args.height,
            wall_mm=args.wall,
            length_mm=args.length,
            radius_mm=radius,
        )
        doc.file_name = args.output.name
        doc.write(args.output)
        print(
            f"nc-export {__version__}  rect-tube "
            f"{args.width}x{args.height}x{args.wall} L={args.length} mm -> "
            f"{args.output} ({len(doc.entities)} entities)"
        )
        return 0

    parser.error(f"Неизвестная подкоманда: {args.command}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
