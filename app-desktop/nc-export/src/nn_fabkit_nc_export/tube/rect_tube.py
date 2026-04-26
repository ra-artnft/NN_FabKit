"""Прямоугольная труба → IGES surface-модель (Type 128 + Type 144 BREP).

Координаты — в конвенции Friendess CypTube:
  X — axial direction (ось трубы, длина L)
  Y — ширина профиля (W)
  Z — высота профиля (H)
Профиль трубы лежит в плоскости YZ; экструзия идёт по +X от 0 до L.

Единицы: миллиметры (G-section unit flag = 2).

Структура каждой плоской грани (для feature recognition в CypTube):
  - 4 × Type 110 Line — boundary edges в 3D (CCW relative to normal)
  - 1 × Type 102 Composite Curve — собирает 4 lines в loop
  - 1 × Type 128 Rational B-Spline Surface (degree 1×1, 2×2 control points)
  - 1 × Type 142 Curve on Parametric Surface — связывает boundary с surface
  - 1 × Type 144 Trimmed Surface — финальная закрытая грань

Итого 8 entities на одну плоскую грань. Box (6 граней) = 48 entities.

Шаг 1 — `hello_surface`: одна trimmed plane.
Шаг 2 — `rect_tube_box`: closed box LOD-1 без скруглений (6 trimmed planes).
"""

from __future__ import annotations

from ..iges.document import IGESDocument
from ..iges.entities import (
    CompositeCurve,
    CurveOnParametricSurface,
    Line,
    NurbsSurface,
    TrimmedSurface,
)


def _build_trimmed_plane(
    cp00: tuple[float, float, float],
    cp10: tuple[float, float, float],
    cp11: tuple[float, float, float],
    cp01: tuple[float, float, float],
    label: str,
) -> list:
    """Построить минимальную BREP плоскую грань из 4 corners.

    Порядок corners — CCW при взгляде с outer normal:
      cp00 → cp10 → cp11 → cp01 → back to cp00

    Возвращает список из 8 entities. Caller добавляет их в IGESDocument
    в порядке возврата (boundary lines первыми, trimmed surface последней).

    Нормаль грани = (cp10 - cp00) × (cp01 - cp00). Для outer-facing нужно
    выбрать порядок углов так, чтобы это правило давало правильную нормаль.
    """
    surface = NurbsSurface(
        cp00=cp00, cp10=cp10, cp01=cp01, cp11=cp11, label=f"S_{label[:6]}"
    )
    # Boundary edges в 3D, CCW: bottom → right → top(reversed) → left(reversed)
    e1 = Line(p1=cp00, p2=cp10, label=f"E1_{label[:5]}")
    e2 = Line(p1=cp10, p2=cp11, label=f"E2_{label[:5]}")
    e3 = Line(p1=cp11, p2=cp01, label=f"E3_{label[:5]}")
    e4 = Line(p1=cp01, p2=cp00, label=f"E4_{label[:5]}")
    composite = CompositeCurve(sub_curves=[e1, e2, e3, e4], label=f"C_{label[:6]}")
    cos = CurveOnParametricSurface(
        surface=surface, boundary_3d=composite, label=f"O_{label[:6]}"
    )
    trimmed = TrimmedSurface(
        surface=surface, outer_boundary=cos, label=label[:8]
    )
    # Возвращаем topo-sorted: edges → composite → surface → cos → trimmed
    return [e1, e2, e3, e4, composite, surface, cos, trimmed]


def hello_surface(width_mm: float, length_mm: float) -> IGESDocument:
    """Одна плоская trimmed грань L (X) × W (Y), z=0.

    8 entities: 4 lines + composite + surface + curve-on-surface + trimmed.
    """
    if width_mm <= 0 or length_mm <= 0:
        raise ValueError("width_mm и length_mm должны быть > 0")

    hw = width_mm / 2.0
    L = length_mm
    doc = IGESDocument(
        description=(
            f"NN FabKit hello-surface (BREP): one trimmed plane Type 144, "
            f"L={length_mm}mm (X) x W={width_mm}mm (Y), z=0."
        ),
    )

    # 4 corners в плоскости z=0, CCW from +Z normal:
    # (0,-hw,0) → (L,-hw,0) → (L,+hw,0) → (0,+hw,0)
    entities = _build_trimmed_plane(
        cp00=(0.0, -hw, 0.0),
        cp10=(L,   -hw, 0.0),
        cp11=(L,    hw, 0.0),
        cp01=(0.0,  hw, 0.0),
        label="HELLO",
    )
    for e in entities:
        doc.add(e)
    return doc


def rect_tube_box(
    width_mm: float,
    height_mm: float,
    wall_mm: float,
    length_mm: float,
) -> IGESDocument:
    """Closed box LOD-1 без скруглений: 6 trimmed surfaces, всего 48 entities.

    Ось трубы — X (от 0 до L). Профиль W×H в плоскости YZ:
      W — по Y (ширина), H — по Z (высота).

    `wall_mm` принимается, но в LOD-1-без-скруглений не используется
    (нет внутренней геометрии). Endcaps без отверстий — обычные plane trimmed
    surfaces. Скругления + отверстие в endcaps — следующие шаги.
    """
    if width_mm <= 0 or height_mm <= 0 or length_mm <= 0:
        raise ValueError("width_mm, height_mm, length_mm должны быть > 0")
    if wall_mm < 0:
        raise ValueError("wall_mm должно быть ≥ 0")

    hw = width_mm / 2.0   # half-width (Y)
    hh = height_mm / 2.0  # half-height (Z)
    L = length_mm

    doc = IGESDocument(
        description=(
            f"NN FabKit rect-tube box LOD-1 (BREP, no radius): "
            f"L={length_mm} (X) x W={width_mm} (Y) x H={height_mm} (Z), "
            f"wall={wall_mm} mm. 6 Type 144 trimmed surfaces."
        ),
    )

    # 6 граней. Для каждой указываем 4 corner-points так, чтобы нормаль NURBS
    # surface (cp10 - cp00) × (cp01 - cp00) смотрела наружу.
    # Аргументы _build_trimmed_plane: (cp00, cp10, cp11, cp01).
    # cp10 = cp00 + a_dir * a_length, cp01 = cp00 + b_dir * b_length,
    # cp11 = cp00 + a_dir + b_dir, где (a_dir × b_dir) = outer_normal.
    faces = [
        # +Y face (y=+hw): outer normal +Y. a=+Z, b=+X. base=(0,hw,-hh).
        ("F_YPLUS",
         (0.0, hw, -hh),  (0.0, hw, hh),
         (L,   hw, hh),   (L,   hw, -hh)),
        # +Z face (z=+hh): outer normal +Z. a=+X, b=+Y. base=(0,-hw,hh).
        ("F_ZPLUS",
         (0.0, -hw, hh),  (L,   -hw, hh),
         (L,    hw, hh),  (0.0,  hw, hh)),
        # -Y face (y=-hw): outer normal -Y. a=+X, b=+Z. base=(0,-hw,-hh).
        ("F_YMINS",
         (0.0, -hw, -hh), (L,   -hw, -hh),
         (L,   -hw, hh),  (0.0, -hw, hh)),
        # -Z face (z=-hh): outer normal -Z. a=+Y, b=+X. base=(0,-hw,-hh).
        ("F_ZMINS",
         (0.0, -hw, -hh), (0.0,  hw, -hh),
         (L,    hw, -hh), (L,   -hw, -hh)),
        # x=0 endcap (x=0): outer normal -X. a=+Z, b=+Y. base=(0,-hw,-hh).
        ("F_X0",
         (0.0, -hw, -hh), (0.0, -hw, hh),
         (0.0,  hw, hh),  (0.0,  hw, -hh)),
        # x=L endcap (x=L): outer normal +X. a=+Y, b=+Z. base=(L,-hw,-hh).
        ("F_XL",
         (L, -hw, -hh),   (L,  hw, -hh),
         (L,  hw, hh),    (L, -hw, hh)),
    ]
    for label, c00, c10, c11, c01 in faces:
        for e in _build_trimmed_plane(c00, c10, c11, c01, label):
            doc.add(e)

    return doc
