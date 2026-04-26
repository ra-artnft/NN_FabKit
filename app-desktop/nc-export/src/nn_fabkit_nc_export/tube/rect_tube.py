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
    # Blank composite + Type 142 для outer endcap boundary, чтобы CypTube
    # не подсвечивал outer rounded-rect endcap'а как cut path (perpendicular
    # to tube axis выглядит для CypTube как самостоятельный cut feature).
    composite.iges_status = "01010500"
    cos = CurveOnParametricSurface(
        surface=surface, boundary_3d=composite, label=f"O_{label[:6]}",
    )
    cos.iges_status = "01010500"
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
    hollow: bool = False,
) -> IGESDocument:
    """Прямоугольная труба, surface-модель.

    radius_mm:
      None  → авто-расчёт по ГОСТ 30245-2003: 2.0×t (t≤6), 2.5×t (6<t≤10), 3.0×t (>10)
      0     → плоские углы (без скруглений)
      >0    → явно заданный радиус наружного скругления

    hollow:
      False (default) — LOD-1: только outer surface, endcaps без отверстия.
                        96 entities при R>0, 48 при R=0.
      True            — LOD-2: outer + inner surface, endcaps annular (с отверстием
                        от стенки). ~190 entities при R>0.

    LOD-2 требует: wall_mm > 0 и (W - 2*wall) > 0, (H - 2*wall) > 0.
    """
    if width_mm <= 0 or height_mm <= 0 or length_mm <= 0:
        raise ValueError("width_mm, height_mm, length_mm должны быть > 0")
    if wall_mm < 0:
        raise ValueError("wall_mm должно быть ≥ 0")

    if radius_mm is None:
        radius_mm = _supplier_default_radius(wall_mm)

    if radius_mm < 0:
        raise ValueError("radius_mm должен быть ≥ 0")
    if radius_mm > min(width_mm, height_mm) / 2.0:
        raise ValueError(
            f"radius_mm={radius_mm} больше половины меньшего размера сечения"
        )

    if hollow:
        if wall_mm <= 0:
            raise ValueError("hollow=True требует wall_mm > 0")
        if width_mm - 2 * wall_mm <= 0 or height_mm - 2 * wall_mm <= 0:
            raise ValueError(
                f"hollow: 2*wall_mm ({2 * wall_mm}) >= меньшего размера сечения"
            )
        if radius_mm == 0:
            raise ValueError("hollow=True требует radius_mm > 0 (LOD-2)")

    hw = width_mm / 2.0
    hh = height_mm / 2.0
    L = length_mm
    R = radius_mm

    if hollow:
        hw_in = hw - wall_mm
        hh_in = hh - wall_mm
        R_in = max(R - wall_mm, 0.0)
    else:
        hw_in = hh_in = R_in = 0.0  # not used

    description = _build_description(
        length_mm, width_mm, height_mm, wall_mm, radius_mm, hollow
    )

    doc = IGESDocument(description=description)

    if R == 0:
        _emit_box_no_radius(doc, hw, hh, L)
    elif not hollow:
        _emit_outer_shell(doc, hw, hh, R, L)
        # Simple rounded endcaps (no hole)
        for e in _build_rounded_endcap(0.0, hw, hh, R, outer_normal_sign=-1, label="E_X0"):
            doc.add(e)
        for e in _build_rounded_endcap(L, hw, hh, R, outer_normal_sign=+1, label="E_XL"):
            doc.add(e)
    else:
        # LOD-2: outer + inner + annular endcaps
        _emit_outer_shell(doc, hw, hh, R, L)
        _emit_inner_shell(doc, hw_in, hh_in, R_in, L)
        for e in _emit_annular_endcap(
            x_plane=0.0,
            hw=hw, hh=hh, R=R,
            hw_in=hw_in, hh_in=hh_in, R_in=R_in,
            outer_normal_sign=-1, label="E_X0",
        ):
            doc.add(e)
        for e in _emit_annular_endcap(
            x_plane=L,
            hw=hw, hh=hh, R=R,
            hw_in=hw_in, hh_in=hh_in, R_in=R_in,
            outer_normal_sign=+1, label="E_XL",
        ):
            doc.add(e)

    return doc


def _build_description(L, W, H, t, R, hollow: bool) -> str:
    base = (
        f"NN FabKit rect-tube {'LOD-2 hollow' if hollow else 'LOD-1'} (BREP): "
        f"L={L} (X) x W={W} (Y) x H={H} (Z), wall={t}, R={R} mm. "
    )
    if R == 0:
        return base + "6 plane faces (no radius)."
    if not hollow:
        return base + "4 plane + 4 cylinder + 2 rounded endcaps."
    return base + "Outer + inner shell + 2 annular endcaps."


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


def _emit_outer_shell(
    doc: IGESDocument, hw: float, hh: float, R: float, L: float
) -> None:
    """4 outer plane (между скруглениями) + 4 outer cylindrical corner."""
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

    eY_p = (0.0,  1.0, 0.0); eY_m = (0.0, -1.0, 0.0)
    eZ_p = (0.0,  0.0, 1.0); eZ_m = (0.0,  0.0, -1.0)
    corners = [
        ("C_PP",  hw - R,    hh - R,  eY_p, eZ_p),
        ("C_MP", -(hw - R),  hh - R,  eZ_p, eY_m),
        ("C_MM", -(hw - R), -(hh - R), eY_m, eZ_m),
        ("C_PM",  hw - R,   -(hh - R), eZ_m, eY_p),
    ]
    for label, ay, az, e1, e2 in corners:
        for e in _build_trimmed_cylinder_corner(
            axis_y=ay, axis_z=az, radius=R, length_x=L,
            e1=e1, e2=e2, label=label,
        ):
            doc.add(e)


def _emit_inner_shell(
    doc: IGESDocument, hw_in: float, hh_in: float, R_in: float, L: float
) -> None:
    """4 inner plane (нормаль внутрь cavity) + 4 inner cylindrical corner.

    Для inner plane: cp-порядок выбран так, чтобы нормаль = -outer_normal
    (т.е. для +Y inner face нормаль -Y → внутрь cavity).
    Для inner cylinder: используется тот же helper что для outer; нормаль
    Type 120 идёт радиально outward от axis. На inner cylinder это выводит
    нормаль в (+e1+e2) сторону, т.е. в сторону wall material (а не cavity).
    Для CypTube feature recognition это, вероятно, OK — inner surfaces
    интерпретируются по контексту через annular endcap trim.
    """
    # 4 inner plane faces — порядок углов CCW при view ИЗНУТРИ cavity
    # (т.е. с противоположной стороны от outer normal). Это даёт нормаль -outer.
    planes = [
        # +Y inner face: y=hw_in. Normal должен быть -Y (внутрь cavity).
        # a=+X, b=+Z → +X × +Z = -Y ✓
        ("I_YPLUS",
         (0.0, hw_in, -(hh_in - R_in)),  (L,   hw_in, -(hh_in - R_in)),
         (L,   hw_in,  hh_in - R_in),    (0.0, hw_in,  hh_in - R_in)),
        # +Z inner face: z=hh_in. Normal -Z.
        # a=+Y, b=+X → +Y × +X = -Z ✓
        ("I_ZPLUS",
         (0.0, -(hw_in - R_in), hh_in),  (0.0,  hw_in - R_in,   hh_in),
         (L,    hw_in - R_in,   hh_in),  (L,   -(hw_in - R_in), hh_in)),
        # -Y inner face: y=-hw_in. Normal +Y.
        # a=+Z, b=+X → +Z × +X = +Y ✓
        ("I_YMINS",
         (0.0, -hw_in, -(hh_in - R_in)), (0.0, -hw_in, hh_in - R_in),
         (L,   -hw_in,  hh_in - R_in),   (L,   -hw_in, -(hh_in - R_in))),
        # -Z inner face: z=-hh_in. Normal +Z.
        # a=+X, b=+Y → +X × +Y = +Z ✓
        ("I_ZMINS",
         (0.0, -(hw_in - R_in), -hh_in), (L,   -(hw_in - R_in), -hh_in),
         (L,    hw_in - R_in,   -hh_in), (0.0,  hw_in - R_in,   -hh_in)),
    ]
    for label, c00, c10, c11, c01 in planes:
        for e in _build_trimmed_plane(c00, c10, c11, c01, label):
            doc.add(e)

    # 4 inner cylindrical corners. Если R_in == 0, скругления нет — пропустить.
    if R_in <= 0:
        return
    eY_p = (0.0,  1.0, 0.0); eY_m = (0.0, -1.0, 0.0)
    eZ_p = (0.0,  0.0, 1.0); eZ_m = (0.0,  0.0, -1.0)
    # Axes inner cylinders are at SAME positions as outer (corners of inner profile
    # at hw-wall-R_in = hw-R same X/Y as outer). Radius is R_in.
    # axis_in_y/z = hw_in - R_in = (hw - wall) - (R - wall) = hw - R.
    corners = [
        ("I_CPP",  hw_in - R_in,    hh_in - R_in,  eY_p, eZ_p),
        ("I_CMP", -(hw_in - R_in),  hh_in - R_in,  eZ_p, eY_m),
        ("I_CMM", -(hw_in - R_in), -(hh_in - R_in), eY_m, eZ_m),
        ("I_CPM",  hw_in - R_in,   -(hh_in - R_in), eZ_m, eY_p),
    ]
    for label, ay, az, e1, e2 in corners:
        for e in _build_trimmed_cylinder_corner(
            axis_y=ay, axis_z=az, radius=R_in, length_x=L,
            e1=e1, e2=e2, label=label,
        ):
            doc.add(e)


def _emit_annular_endcap(
    x_plane: float,
    hw: float, hh: float, R: float,
    hw_in: float, hh_in: float, R_in: float,
    outer_normal_sign: int,
    label: str,
) -> list:
    """Endcap-кольцо: outer rounded-rect + inner rounded-rect inner-loop.

    Отверстие в endcap'е соответствует cavity трубы (внутреннему просвету).
    Inner boundary loop направлен в **противоположную** сторону outer loop
    (CW когда outer CCW), что по IGES конвенции означает «дырка».
    """
    # 1. NURBS surface — плоскость с bbox outer
    if outer_normal_sign > 0:
        cp00 = (x_plane, -hw, -hh); cp10 = (x_plane,  hw, -hh)
        cp01 = (x_plane, -hw,  hh); cp11 = (x_plane,  hw,  hh)
    else:
        cp00 = (x_plane, -hw,  hh); cp10 = (x_plane,  hw,  hh)
        cp01 = (x_plane, -hw, -hh); cp11 = (x_plane,  hw, -hh)
    surface = NurbsSurface(
        cp00=cp00, cp10=cp10, cp01=cp01, cp11=cp11, label=f"S_{label[:6]}",
    )

    # 2. Outer boundary. Blank его Type 142 + composite, чтобы CypTube не
    # подсвечивал outer rounded-rect endcap'а как самостоятельный cut path.
    # На side faces (cylinder/plane) outer Type 142 visible (видно в reference),
    # но на endcap perpendicular to tube axis CypTube трактует его как cut feature.
    outer_entities, outer_cos = _make_rounded_rect_boundary(
        x_plane, hw, hh, R, outer_normal_sign,
        surface=surface, label_prefix=f"O_{label[:5]}",
    )
    outer_cos.iges_status = "01010500"  # blanked, subord, parametric
    # Find composite in outer_entities (последний элемент перед cos)
    for e in outer_entities:
        if e.type_number == 102:
            e.iges_status = "01010500"
            break

    # 3. Inner boundary — обратное направление обхода (CW когда outer CCW).
    # Inner Type 142 ОСТАЁТСЯ visible — CypTube подсвечивает inner endcap rect
    # как cut path (cavity hole), это правильное поведение.
    if R_in > 0:
        inner_entities, inner_cos = _make_rounded_rect_boundary(
            x_plane, hw_in, hh_in, R_in, -outer_normal_sign,
            surface=surface, label_prefix=f"I_{label[:5]}",
        )
    else:
        inner_entities, inner_cos = _make_plain_rect_boundary(
            x_plane, hw_in, hh_in, -outer_normal_sign,
            surface=surface, label_prefix=f"I_{label[:5]}",
        )

    trimmed = TrimmedSurface(
        surface=surface,
        outer_boundary=outer_cos,
        inner_boundaries=[inner_cos],
        label=label[:8],
    )

    return outer_entities + inner_entities + [surface, trimmed]


def _make_rounded_rect_boundary(
    x_plane: float,
    hw: float, hh: float, R: float,
    outer_normal_sign: int,
    surface: "NurbsSurface",
    label_prefix: str,
) -> tuple[list, "CurveOnParametricSurface"]:
    """Сборка boundary loop rounded rectangle (8 кривых) + Composite + COS."""
    R_ = R
    x = x_plane
    p_yp_zm = (x,  hw, -hh + R_)
    p_yp_zp = (x,  hw,  hh - R_)
    p_yc_zp_p = (x,  hw - R_,  hh)
    p_yc_zp_m = (x, -hw + R_,  hh)
    p_ym_zp = (x, -hw,  hh - R_)
    p_ym_zm = (x, -hw, -hh + R_)
    p_yc_zm_m = (x, -hw + R_, -hh)
    p_yc_zm_p = (x,  hw - R_, -hh)

    c_pp = (x,  hw - R_,  hh - R_)
    c_mp = (x, -hw + R_,  hh - R_)
    c_mm = (x, -hw + R_, -hh + R_)
    c_pm = (x,  hw - R_, -hh + R_)

    eY_p = (0.0, 1.0, 0.0); eY_m = (0.0, -1.0, 0.0)
    eZ_p = (0.0, 0.0, 1.0); eZ_m = (0.0, 0.0, -1.0)

    if outer_normal_sign > 0:
        # CCW from +X view
        line_yp = Line(p1=p_yp_zm, p2=p_yp_zp, label=f"{label_prefix}L1")
        arc_pp  = _nurbs_arc_90(c_pp, eY_p, eZ_p, R_, label=f"{label_prefix}A1")
        line_zp = Line(p1=p_yc_zp_p, p2=p_yc_zp_m, label=f"{label_prefix}L2")
        arc_mp  = _nurbs_arc_90(c_mp, eZ_p, eY_m, R_, label=f"{label_prefix}A2")
        line_ym = Line(p1=p_ym_zp, p2=p_ym_zm, label=f"{label_prefix}L3")
        arc_mm  = _nurbs_arc_90(c_mm, eY_m, eZ_m, R_, label=f"{label_prefix}A3")
        line_zm = Line(p1=p_yc_zm_m, p2=p_yc_zm_p, label=f"{label_prefix}L4")
        arc_pm  = _nurbs_arc_90(c_pm, eZ_m, eY_p, R_, label=f"{label_prefix}A4")
        curves = [line_yp, arc_pp, line_zp, arc_mp, line_ym, arc_mm, line_zm, arc_pm]
    else:
        # CCW from -X view (mirror — обратное направление обхода)
        line_yp = Line(p1=p_yp_zp, p2=p_yp_zm, label=f"{label_prefix}L1")
        arc_pm  = _nurbs_arc_90(c_pm, eY_p, eZ_m, R_, label=f"{label_prefix}A1")
        line_zm = Line(p1=p_yc_zm_p, p2=p_yc_zm_m, label=f"{label_prefix}L2")
        arc_mm  = _nurbs_arc_90(c_mm, eZ_m, eY_m, R_, label=f"{label_prefix}A2")
        line_ym = Line(p1=p_ym_zm, p2=p_ym_zp, label=f"{label_prefix}L3")
        arc_mp  = _nurbs_arc_90(c_mp, eY_m, eZ_p, R_, label=f"{label_prefix}A3")
        line_zp = Line(p1=p_yc_zp_m, p2=p_yc_zp_p, label=f"{label_prefix}L4")
        arc_pp  = _nurbs_arc_90(c_pp, eZ_p, eY_p, R_, label=f"{label_prefix}A4")
        curves = [line_yp, arc_pm, line_zm, arc_mm, line_ym, arc_mp, line_zp, arc_pp]

    composite = CompositeCurve(sub_curves=curves, label=f"{label_prefix}C")
    cos = CurveOnParametricSurface(
        surface=surface, boundary_3d=composite, label=f"{label_prefix}O",
    )
    return curves + [composite], cos


def _make_plain_rect_boundary(
    x_plane: float,
    hw: float, hh: float,
    outer_normal_sign: int,
    surface: "NurbsSurface",
    label_prefix: str,
) -> tuple[list, "CurveOnParametricSurface"]:
    """Plain rectangle boundary (4 lines) — для inner contour когда R_in=0."""
    x = x_plane
    if outer_normal_sign > 0:
        # CCW from +X
        l1 = Line(p1=(x,  hw, -hh), p2=(x,  hw,  hh), label=f"{label_prefix}L1")
        l2 = Line(p1=(x,  hw,  hh), p2=(x, -hw,  hh), label=f"{label_prefix}L2")
        l3 = Line(p1=(x, -hw,  hh), p2=(x, -hw, -hh), label=f"{label_prefix}L3")
        l4 = Line(p1=(x, -hw, -hh), p2=(x,  hw, -hh), label=f"{label_prefix}L4")
    else:
        # CCW from -X (reversed)
        l1 = Line(p1=(x,  hw,  hh), p2=(x,  hw, -hh), label=f"{label_prefix}L1")
        l2 = Line(p1=(x,  hw, -hh), p2=(x, -hw, -hh), label=f"{label_prefix}L2")
        l3 = Line(p1=(x, -hw, -hh), p2=(x, -hw,  hh), label=f"{label_prefix}L3")
        l4 = Line(p1=(x, -hw,  hh), p2=(x,  hw,  hh), label=f"{label_prefix}L4")
    curves = [l1, l2, l3, l4]
    composite = CompositeCurve(sub_curves=curves, label=f"{label_prefix}C")
    cos = CurveOnParametricSurface(
        surface=surface, boundary_3d=composite, label=f"{label_prefix}O",
    )
    return curves + [composite], cos


def _supplier_default_radius(wall_mm: float) -> float:
    """Supplier convention (Юг-Сталь, ГОСТ 8639/8645 «по соглашению»):
    R = 1.5×t для t ≤ 6 мм, R = 2.0×t для t > 6 мм.

    Это формула, которая фактически производится поставщиком и подтверждается
    reference-файлами заказчика (60×10×1.5 R=2.25, 40×20×2 R=3). Совпадает с
    нижней границей допуска ГОСТ 30245-2003 (1.6t–2.4t для t ≤ 6).
    Если нужен ГОСТ 30245 nominal — задать --radius явно (R = 2.0×t для t ≤ 6).
    """
    if wall_mm <= 0:
        return 0.0
    if wall_mm <= 6.0:
        return 1.5 * wall_mm
    return 2.0 * wall_mm
