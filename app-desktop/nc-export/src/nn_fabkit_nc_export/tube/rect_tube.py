"""Прямоугольная труба → IGES surface-модель (BREP с Type 144 trim).

Координаты — конвенция Friendess CypTube:
  X — axial direction (ось трубы, длина L)
  Y — ширина профиля (W)
  Z — высота профиля (H)
Профиль трубы лежит в плоскости YZ; экструзия идёт по +X от 0 до L.

Единицы: миллиметры (G-section unit flag = 2).

LOD-1 со скруглениями (с радиусом R на углах профиля):
- 4 outer plane faces — между скруглениями (Type 144 + Type 128 + boundary)
- 4 outer cylindrical roundings — Type 144 + Type 120 (Surface of Revolution)
  с прямой generatrix параллельной X и axis тоже параллельной X.
- 2 endcaps — Type 144 + Type 128 (плоскость) с rounded-rectangle boundary
  (4 Line + 4 NurbsArc 90° через Type 126).

Без скруглений (R=0): просто 6 Type 144 trimmed planes (как было в v0.2.0).

Полая труба LOD-2 (с inner cavity) — следующий шаг.
"""

from __future__ import annotations

import math

from ..iges.document import IGESDocument
from ..iges.entities import (
    CompositeCurve,
    CurveOnParametricSurface,
    Line,
    NurbsCurve,
    NurbsSurface,
    SurfaceOfRevolution,
    TrimmedSurface,
)


# ----------------------------------------------------------------------
# Helpers: NURBS-arc 90°, trimmed plane, trimmed cylinder
# ----------------------------------------------------------------------

_W_90DEG = math.sqrt(2.0) / 2.0  # cos(π/4) — вес средней ctrl-точки arc 90°


def _nurbs_arc_90(
    center: tuple[float, float, float],
    e1: tuple[float, float, float],
    e2: tuple[float, float, float],
    radius: float,
    label: str = "ARC",
) -> NurbsCurve:
    """90° arc как Type 126 NURBS curve degree 2, 3 control points.

    Дуга в плоскости, заданной парой ortho-normalised единичных векторов (e1, e2).
    Идёт от точки `center + R*e1` к точке `center + R*e2` через corner
    `center + R*(e1 + e2)` (control point с весом cos(π/4)).
    """
    cx, cy, cz = center
    p0 = (cx + radius * e1[0], cy + radius * e1[1], cz + radius * e1[2])
    p1 = (
        cx + radius * (e1[0] + e2[0]),
        cy + radius * (e1[1] + e2[1]),
        cz + radius * (e1[2] + e2[2]),
    )
    p2 = (cx + radius * e2[0], cy + radius * e2[1], cz + radius * e2[2])
    # Normal к плоскости arc: e1 × e2
    nx = e1[1] * e2[2] - e1[2] * e2[1]
    ny = e1[2] * e2[0] - e1[0] * e2[2]
    nz = e1[0] * e2[1] - e1[1] * e2[0]
    return NurbsCurve(
        K=2, M=2,
        knots=[0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        weights=[1.0, _W_90DEG, 1.0],
        control_points=[p0, p1, p2],
        v_start=0.0, v_end=1.0,
        normal=(nx, ny, nz),
        is_polynomial=False, is_planar=True,
        is_closed=False, is_periodic=False,
        label=label[:8],
    )


def _build_trimmed_plane(
    cp00: tuple[float, float, float],
    cp10: tuple[float, float, float],
    cp11: tuple[float, float, float],
    cp01: tuple[float, float, float],
    label: str,
) -> list:
    """Минимальная BREP плоская грань из 4 corners (8 entities).

    Порядок corners: cp00 → cp10 → cp11 → cp01. Нормаль грани =
    (cp10 - cp00) × (cp01 - cp00) — для outer-facing подобрать порядок.
    """
    surface = NurbsSurface(
        cp00=cp00, cp10=cp10, cp01=cp01, cp11=cp11, label=f"S_{label[:6]}"
    )
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
    return [e1, e2, e3, e4, composite, surface, cos, trimmed]


def _build_trimmed_cylinder_corner(
    axis_y: float,
    axis_z: float,
    radius: float,
    length_x: float,
    e1: tuple[float, float, float],
    e2: tuple[float, float, float],
    label: str,
) -> list:
    """Четверть-цилиндр на углу профиля. Ось параллельна X.

    axis at (axis_y, axis_z) в YZ. e1, e2 — ortho-normal vectors в YZ
    задающие угловой extent: surface от θ=0 (направление e1) до θ=π/2 (e2).

    Возвращает 10 entities: axis, generatrix, surface, 2 axial edges,
    2 arc edges, composite, curve_on_surface, trimmed_surface.
    """
    L = length_x
    R = radius
    # Ось revolution parallel to +X
    axis_line = Line(
        p1=(0.0, axis_y, axis_z), p2=(L, axis_y, axis_z),
        label=f"AX_{label[:5]}",
    )
    # Generatrix parallel to axis at θ=0 (направление +e1 от axis)
    g_y = axis_y + R * e1[1]
    g_z = axis_z + R * e1[2]
    generatrix = Line(
        p1=(0.0, g_y, g_z), p2=(L, g_y, g_z),
        label=f"GN_{label[:5]}",
    )
    surface = SurfaceOfRevolution(
        axis=axis_line, generatrix=generatrix,
        start_angle=0.0, end_angle=math.pi / 2.0,
        label=f"S_{label[:6]}",
    )

    # Координаты 4 corner-точек цилиндрической поверхности
    e1_y = axis_y + R * e1[1]; e1_z = axis_z + R * e1[2]
    e2_y = axis_y + R * e2[1]; e2_z = axis_z + R * e2[2]
    p_e1_x0 = (0.0, e1_y, e1_z)
    p_e1_xL = (L,   e1_y, e1_z)
    p_e2_x0 = (0.0, e2_y, e2_z)
    p_e2_xL = (L,   e2_y, e2_z)

    # Boundary edges (CCW from outer normal):
    # 1. Axial at θ=0 from x=0 to x=L
    edge_axial_start = Line(
        p1=p_e1_x0, p2=p_e1_xL, label=f"AS_{label[:5]}"
    )
    # 2. Arc at v=L from θ=0 to θ=π/2
    arc_at_L = _nurbs_arc_90(
        center=(L, axis_y, axis_z),
        e1=e1, e2=e2, radius=R,
        label=f"BL_{label[:5]}",
    )
    # 3. Axial at θ=π/2 from x=L to x=0 (reversed)
    edge_axial_end = Line(
        p1=p_e2_xL, p2=p_e2_x0, label=f"AE_{label[:5]}"
    )
    # 4. Arc at v=0 from θ=π/2 to θ=0 (reversed direction → swap e1, e2)
    arc_at_0 = _nurbs_arc_90(
        center=(0.0, axis_y, axis_z),
        e1=e2, e2=e1, radius=R,
        label=f"B0_{label[:5]}",
    )

    composite = CompositeCurve(
        sub_curves=[edge_axial_start, arc_at_L, edge_axial_end, arc_at_0],
        label=f"C_{label[:6]}",
    )
    cos = CurveOnParametricSurface(
        surface=surface, boundary_3d=composite, label=f"O_{label[:6]}",
    )
    trimmed = TrimmedSurface(
        surface=surface, outer_boundary=cos, label=label[:8],
    )

    return [
        axis_line, generatrix,
        edge_axial_start, edge_axial_end,
        arc_at_L, arc_at_0,
        composite, surface, cos, trimmed,
    ]


def _build_rounded_endcap(
    x_plane: float,
    hw: float, hh: float, radius: float,
    outer_normal_sign: int,  # +1 для x=L, -1 для x=0
    label: str,
) -> list:
    """Endcap с rounded-rectangle boundary в плоскости x = x_plane.

    Surface — Type 128 NURBS plane (4 control points обнимают bbox профиля).
    Trim обрезает её до rounded rectangle (4 axial-в-плоскости lines + 4 arcs).

    outer_normal_sign определяет направление наружной нормали (±X).
    Контрольные точки NURBS surface подобраны так, что
    (cp10 - cp00) × (cp01 - cp00) даёт нормаль в направлении outer_normal_sign·X.
    """
    R = radius
    # 4 corner-точки rounded rect (концы прямых сегментов)
    # Идём CCW при view от +X (для x=L endcap, outer_normal +X):
    # Правый-нижний → правый-верхний → левый-верхний → левый-нижний.
    # «Правый» — это +Y direction; «верхний» — +Z.
    # Для x=0 (outer_normal -X), обходим CW при той же ориентации, чтобы
    # boundary loop оставался CCW от стороны нормали.

    # Точки между прямыми сегментами и arcs (8 точек на rounded rect):
    #   на стороне +Y (правая): от (y=hw, z=-hh+R) до (y=hw, z=hh-R)
    #   на стороне +Z (верхняя): от (y=hw-R, z=hh) до (y=-hw+R, z=hh)
    #   на стороне -Y (левая): от (y=-hw, z=hh-R) до (y=-hw, z=-hh+R)
    #   на стороне -Z (нижняя): от (y=-hw+R, z=-hh) до (y=hw-R, z=-hh)
    x = x_plane

    # Coordinates of 8 corner points (между прямыми и arcs)
    p_yp_zm = (x,  hw, -hh + R)   # right side, lower end
    p_yp_zp = (x,  hw,  hh - R)   # right side, upper end
    p_yc_zp_p = (x,  hw - R,  hh)  # top side, right end
    p_yc_zp_m = (x, -hw + R,  hh)  # top side, left end
    p_ym_zp = (x, -hw,  hh - R)   # left side, upper end
    p_ym_zm = (x, -hw, -hh + R)   # left side, lower end
    p_yc_zm_m = (x, -hw + R, -hh)  # bottom side, left end
    p_yc_zm_p = (x,  hw - R, -hh)  # bottom side, right end

    # Centers for arcs (in YZ plane, x = x_plane)
    c_pp = (x,  hw - R,  hh - R)  # +Y +Z corner center
    c_mp = (x, -hw + R,  hh - R)  # -Y +Z corner center
    c_mm = (x, -hw + R, -hh + R)  # -Y -Z corner center
    c_pm = (x,  hw - R, -hh + R)  # +Y -Z corner center

    # Direction unit vectors in YZ plane (in 3D form, x-component = 0)
    eY_p = (0.0,  1.0, 0.0)
    eY_m = (0.0, -1.0, 0.0)
    eZ_p = (0.0, 0.0,  1.0)
    eZ_m = (0.0, 0.0, -1.0)

    if outer_normal_sign > 0:
        # x=L endcap (outer normal +X). CCW обход от +X view:
        # (Y→right, Z→up):  start at +Y mid-bottom, go up.
        # 1. Line +Y side (z=-hh+R → hh-R), z-up: p_yp_zm → p_yp_zp
        # 2. Arc +Y +Z corner: from +Y direction to +Z direction (CCW around c_pp)
        # 3. Line +Z side (y=hw-R → -hw+R), y-down: p_yc_zp_p → p_yc_zp_m
        # 4. Arc -Y +Z corner
        # 5. Line -Y side: p_ym_zp → p_ym_zm
        # 6. Arc -Y -Z corner
        # 7. Line -Z side: p_yc_zm_m → p_yc_zm_p
        # 8. Arc +Y -Z corner
        line_yp = Line(p1=p_yp_zm, p2=p_yp_zp, label=f"L1_{label[:5]}")
        arc_pp = _nurbs_arc_90(c_pp, e1=eY_p, e2=eZ_p, radius=R, label=f"A1_{label[:5]}")
        line_zp = Line(p1=p_yc_zp_p, p2=p_yc_zp_m, label=f"L2_{label[:5]}")
        arc_mp = _nurbs_arc_90(c_mp, e1=eZ_p, e2=eY_m, radius=R, label=f"A2_{label[:5]}")
        line_ym = Line(p1=p_ym_zp, p2=p_ym_zm, label=f"L3_{label[:5]}")
        arc_mm = _nurbs_arc_90(c_mm, e1=eY_m, e2=eZ_m, radius=R, label=f"A3_{label[:5]}")
        line_zm = Line(p1=p_yc_zm_m, p2=p_yc_zm_p, label=f"L4_{label[:5]}")
        arc_pm = _nurbs_arc_90(c_pm, e1=eZ_m, e2=eY_p, radius=R, label=f"A4_{label[:5]}")
        boundary_curves = [line_yp, arc_pp, line_zp, arc_mp, line_ym, arc_mm, line_zm, arc_pm]

        # NURBS surface: control points чтобы (cp10-cp00) × (cp01-cp00) = +X.
        # cp10-cp00 = +Y direction; cp01-cp00 = +Z direction.
        # +Y × +Z = +X ✓
        cp00 = (x, -hw, -hh); cp10 = (x,  hw, -hh)
        cp01 = (x, -hw,  hh); cp11 = (x,  hw,  hh)
    else:
        # x=0 endcap (outer normal -X). CCW обход от -X view (mirror Y).
        # При взгляде из -X направления Y идёт «налево» (для нас в 3D).
        # Loop: start at +Y mid-bottom, идём вниз (CCW from -X side).
        line_yp = Line(p1=p_yp_zp, p2=p_yp_zm, label=f"L1_{label[:5]}")
        arc_pm = _nurbs_arc_90(c_pm, e1=eY_p, e2=eZ_m, radius=R, label=f"A1_{label[:5]}")
        line_zm = Line(p1=p_yc_zm_p, p2=p_yc_zm_m, label=f"L2_{label[:5]}")
        arc_mm = _nurbs_arc_90(c_mm, e1=eZ_m, e2=eY_m, radius=R, label=f"A2_{label[:5]}")
        line_ym = Line(p1=p_ym_zm, p2=p_ym_zp, label=f"L3_{label[:5]}")
        arc_mp = _nurbs_arc_90(c_mp, e1=eY_m, e2=eZ_p, radius=R, label=f"A3_{label[:5]}")
        line_zp = Line(p1=p_yc_zp_m, p2=p_yc_zp_p, label=f"L4_{label[:5]}")
        arc_pp = _nurbs_arc_90(c_pp, e1=eZ_p, e2=eY_p, radius=R, label=f"A4_{label[:5]}")
        boundary_curves = [line_yp, arc_pm, line_zm, arc_mm, line_ym, arc_mp, line_zp, arc_pp]

        # NURBS surface для x=0: (cp10-cp00) × (cp01-cp00) = -X.
        # cp10-cp00 = +Y; cp01-cp00 = -Z. +Y × -Z = -X ✓
        cp00 = (x, -hw,  hh); cp10 = (x,  hw,  hh)
        cp01 = (x, -hw, -hh); cp11 = (x,  hw, -hh)

    surface = NurbsSurface(
        cp00=cp00, cp10=cp10, cp01=cp01, cp11=cp11,
        label=f"S_{label[:6]}",
    )
    composite = CompositeCurve(sub_curves=boundary_curves, label=f"C_{label[:6]}")
    cos = CurveOnParametricSurface(
        surface=surface, boundary_3d=composite, label=f"O_{label[:6]}",
    )
    trimmed = TrimmedSurface(
        surface=surface, outer_boundary=cos, label=label[:8],
    )
    return boundary_curves + [composite, surface, cos, trimmed]


# ----------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------


def hello_surface(width_mm: float, length_mm: float) -> IGESDocument:
    """Одна плоская trimmed грань L (X) × W (Y), z=0. 8 entities."""
    if width_mm <= 0 or length_mm <= 0:
        raise ValueError("width_mm и length_mm должны быть > 0")
    hw = width_mm / 2.0
    L = length_mm
    doc = IGESDocument(
        description=(
            f"NN FabKit hello-surface (BREP): one trimmed plane, "
            f"L={length_mm}mm (X) x W={width_mm}mm (Y), z=0."
        ),
    )
    for e in _build_trimmed_plane(
        cp00=(0.0, -hw, 0.0), cp10=(L, -hw, 0.0),
        cp11=(L,  hw, 0.0),  cp01=(0.0, hw, 0.0),
        label="HELLO",
    ):
        doc.add(e)
    return doc


def rect_tube_box(
    width_mm: float,
    height_mm: float,
    wall_mm: float,
    length_mm: float,
    radius_mm: float | None = None,
) -> IGESDocument:
    """Прямоугольная труба, surface-модель (без полости пока, LOD-1).

    radius_mm:
      None  → авто-расчёт по ГОСТ 30245-2003: 2.0×t (t≤6), 2.5×t (6<t≤10), 3.0×t (>10)
      0     → плоские углы (старая no-radius логика)
      >0    → явно заданный радиус наружного скругления

    Структура (с радиусом):
      4 outer plane faces (между скруглениями) — по 8 entities
      4 outer cylindrical roundings (Type 120 + Type 144 trim) — по 10 entities
      2 endcaps (rounded-rectangle boundary) — по 12 entities
    Итого: 32 + 40 + 24 = 96 entities.

    Без радиуса — 6 trimmed planes = 48 entities (как v0.2.0).
    """
    if width_mm <= 0 or height_mm <= 0 or length_mm <= 0:
        raise ValueError("width_mm, height_mm, length_mm должны быть > 0")
    if wall_mm < 0:
        raise ValueError("wall_mm должно быть ≥ 0")

    if radius_mm is None:
        radius_mm = _gost_30245_radius(wall_mm)

    if radius_mm < 0:
        raise ValueError("radius_mm должен быть ≥ 0")
    if radius_mm > min(width_mm, height_mm) / 2.0:
        raise ValueError(
            f"radius_mm={radius_mm} больше половины меньшего размера сечения"
        )

    hw = width_mm / 2.0
    hh = height_mm / 2.0
    L = length_mm
    R = radius_mm

    description = (
        f"NN FabKit rect-tube LOD-1 (BREP): "
        f"L={length_mm} (X) x W={width_mm} (Y) x H={height_mm} (Z), "
        f"wall={wall_mm} mm, R={radius_mm} mm. "
    )
    description += (
        "6 plane faces (no radius)." if R == 0
        else "4 plane + 4 cylinder roundings + 2 rounded endcaps."
    )

    doc = IGESDocument(description=description)

    if R == 0:
        # Старая box без скруглений (back-compat, для отладки)
        _emit_box_no_radius(doc, hw, hh, L)
    else:
        _emit_box_with_radius(doc, hw, hh, R, L)

    return doc


def _emit_box_no_radius(doc: IGESDocument, hw: float, hh: float, L: float) -> None:
    """Шесть плоских граней без скруглений (legacy mode)."""
    faces = [
        ("F_YPLUS",  (0.0, hw, -hh),  (0.0, hw, hh),  (L, hw, hh),   (L, hw, -hh)),
        ("F_ZPLUS",  (0.0, -hw, hh),  (L,   -hw, hh), (L, hw, hh),   (0.0, hw, hh)),
        ("F_YMINS",  (0.0, -hw, -hh), (L,   -hw,-hh), (L, -hw, hh),  (0.0, -hw, hh)),
        ("F_ZMINS",  (0.0, -hw, -hh), (0.0,  hw,-hh), (L,  hw, -hh), (L,   -hw, -hh)),
        ("F_X0",     (0.0, -hw, -hh), (0.0, -hw, hh), (0.0, hw, hh), (0.0,  hw, -hh)),
        ("F_XL",     (L,   -hw, -hh), (L,    hw,-hh), (L,   hw, hh), (L,   -hw, hh)),
    ]
    for label, c00, c10, c11, c01 in faces:
        for e in _build_trimmed_plane(c00, c10, c11, c01, label):
            doc.add(e)


def _emit_box_with_radius(
    doc: IGESDocument, hw: float, hh: float, R: float, L: float
) -> None:
    """Truba с outer rounded corners. 4 plane + 4 cylinder + 2 endcap."""
    # 4 plane faces (между скруглениями)
    # +Y plane: y=hw, x∈[0,L], z∈[-(hh-R), +(hh-R)]
    # +Z plane: z=hh, x∈[0,L], y∈[-(hw-R), +(hw-R)]
    # -Y plane: y=-hw, ...
    # -Z plane: z=-hh, ...
    planes = [
        # +Y face: outer normal +Y. (cp10-cp00) × (cp01-cp00) = +Y → a=+Z, b=+X
        ("F_YPLUS",
         (0.0, hw, -(hh - R)),  (0.0, hw, hh - R),
         (L,   hw, hh - R),     (L,   hw, -(hh - R))),
        # +Z face: outer normal +Z. a=+X, b=+Y
        ("F_ZPLUS",
         (0.0, -(hw - R), hh),  (L,   -(hw - R), hh),
         (L,    hw - R,    hh), (0.0,  hw - R,    hh)),
        # -Y face: outer normal -Y. a=+X, b=+Z
        ("F_YMINS",
         (0.0, -hw, -(hh - R)), (L,   -hw, -(hh - R)),
         (L,   -hw,  hh - R),   (0.0, -hw,  hh - R)),
        # -Z face: outer normal -Z. a=+Y, b=+X
        ("F_ZMINS",
         (0.0, -(hw - R), -hh), (0.0,  hw - R,    -hh),
         (L,    hw - R,    -hh), (L,   -(hw - R), -hh)),
    ]
    for label, c00, c10, c11, c01 in planes:
        for e in _build_trimmed_plane(c00, c10, c11, c01, label):
            doc.add(e)

    # 4 outer cylindrical corner roundings
    eY_p = (0.0,  1.0, 0.0)
    eY_m = (0.0, -1.0, 0.0)
    eZ_p = (0.0, 0.0,  1.0)
    eZ_m = (0.0, 0.0, -1.0)

    corners = [
        # +Y +Z corner: axis center (hw-R, hh-R), e1=+Y, e2=+Z
        ("C_PP", hw - R,  hh - R, eY_p, eZ_p),
        # -Y +Z corner: axis (-hw+R, hh-R), e1=+Z, e2=-Y
        ("C_MP", -(hw - R),  hh - R, eZ_p, eY_m),
        # -Y -Z corner: axis (-hw+R, -hh+R), e1=-Y, e2=-Z
        ("C_MM", -(hw - R), -(hh - R), eY_m, eZ_m),
        # +Y -Z corner: axis (hw-R, -hh+R), e1=-Z, e2=+Y
        ("C_PM",  hw - R, -(hh - R), eZ_m, eY_p),
    ]
    for label, ay, az, e1, e2 in corners:
        for e in _build_trimmed_cylinder_corner(
            axis_y=ay, axis_z=az, radius=R, length_x=L,
            e1=e1, e2=e2, label=label,
        ):
            doc.add(e)

    # 2 endcaps (rounded rectangle boundary)
    for e in _build_rounded_endcap(0.0, hw, hh, R, outer_normal_sign=-1, label="E_X0"):
        doc.add(e)
    for e in _build_rounded_endcap(L,   hw, hh, R, outer_normal_sign=+1, label="E_XL"):
        doc.add(e)


def _gost_30245_radius(wall_mm: float) -> float:
    """ГОСТ 30245-2003 п. 3.5."""
    if wall_mm <= 0:
        return 0.0
    if wall_mm <= 6.0:
        return 2.0 * wall_mm
    if wall_mm <= 10.0:
        return 2.5 * wall_mm
    return 3.0 * wall_mm
