"""IGES entity classes — минимальный набор для surface-модели трубы.

Entity объекты — pure data: они описывают геометрию, но не знают о sequence
numbers и DE-pointers. Назначение pointers и резолвинг cross-references — забота
IGESDocument при сериализации.

Type 110 (Line Entity)              — прямой отрезок 3D
Type 100 (Circular Arc Entity)      — дуга в плоскости z=Zt (Xt-Yt plane)
Type 122 (Tabulated Cylinder)       — поверхность экструзии directrix-кривой
Type 128 (Rational B-Spline Surface) — параметрическая поверхность (для будущего)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

from .format import fnum

# Type alias: функция, превращающая Entity → DE sequence number.
# Document резолвит cross-refs через эту функцию.
Resolver = Callable[["Entity"], int]


@dataclass
class Entity:
    """Базовый класс. Конкретная Entity знает свой type_number и умеет
    выдать P-параметры (без префикса type и без терминатора)."""

    type_number: int = field(init=False, default=0)
    form_number: int = 0
    label: str = ""
    # Optional per-instance Status field override (8-char string per IGES 5.3
    # §2.2.4.4). Если задан — переопределяет per-type default из document._STATUS_BY_TYPE.
    iges_status: str | None = None

    def parameters(self, resolver: Resolver) -> list[str]:
        raise NotImplementedError


@dataclass
class Line(Entity):
    """Type 110 — Line Entity. Прямой отрезок от P1 до P2.

    P-record: 110, X1, Y1, Z1, X2, Y2, Z2;
    """

    p1: tuple[float, float, float] = (0.0, 0.0, 0.0)
    p2: tuple[float, float, float] = (0.0, 0.0, 0.0)

    def __post_init__(self) -> None:
        self.type_number = 110

    def parameters(self, resolver: Resolver) -> list[str]:
        return [
            fnum(self.p1[0]), fnum(self.p1[1]), fnum(self.p1[2]),
            fnum(self.p2[0]), fnum(self.p2[1]), fnum(self.p2[2]),
        ]


@dataclass
class CircularArc(Entity):
    """Type 100 — Circular Arc Entity.

    Дуга лежит в плоскости z=Zt (parallel to XT-YT). Координаты центра/start/end
    — в этой плоскости.

    P-record: 100, ZT, X1, Y1, X2, Y2, X3, Y3;
    где (X1,Y1) — центр, (X2,Y2) — start, (X3,Y3) — end (CCW).
    """

    zt: float = 0.0
    center: tuple[float, float] = (0.0, 0.0)
    start: tuple[float, float] = (0.0, 0.0)
    end: tuple[float, float] = (0.0, 0.0)

    def __post_init__(self) -> None:
        self.type_number = 100

    def parameters(self, resolver: Resolver) -> list[str]:
        return [
            fnum(self.zt),
            fnum(self.center[0]), fnum(self.center[1]),
            fnum(self.start[0]),  fnum(self.start[1]),
            fnum(self.end[0]),    fnum(self.end[1]),
        ]


@dataclass
class TabulatedCylinder(Entity):
    """Type 122 — Tabulated Cylinder.

    Поверхность, образованная параллельным переносом directrix-кривой вдоль
    прямой generatrix. Для нашей трубы: directrix = прямая (Line) или дуга
    (CircularArc) на торце z=0, generatrix = вектор (0, 0, length).

    P-record: 122, DE_directrix, LX, LY, LZ;
    где (LX,LY,LZ) — координаты КОНЦА generatrix (т.е. точка на directrix
    смещённая на вектор экструзии). Стандарт: берётся как образ начальной
    точки directrix после переноса.
    """

    directrix: Entity | None = None
    # Координаты конечной точки generatrix (terminate point of the generating line).
    # Это образ начальной точки directrix после параллельного переноса.
    terminate: tuple[float, float, float] = (0.0, 0.0, 0.0)

    def __post_init__(self) -> None:
        self.type_number = 122
        if self.directrix is None:
            raise ValueError("TabulatedCylinder requires directrix entity")

    def parameters(self, resolver: Resolver) -> list[str]:
        de = resolver(self.directrix)
        return [
            str(de),
            fnum(self.terminate[0]),
            fnum(self.terminate[1]),
            fnum(self.terminate[2]),
        ]

    def referenced_entities(self) -> list[Entity]:
        return [self.directrix]


@dataclass
class NurbsSurface(Entity):
    """Type 128 — Rational B-Spline Surface.

    Минимальный case: degree 1×1 в обоих направлениях с 2×2 control points
    задаёт плоский четырёхугольник в 3D. Это «правильное» представление
    плоской грани трубы для CypTube/Friendess (Type 122 у них не работает).

    Параметризация: U по длине грани (axial), V поперёк. Control points
    ordered как cp[0,0], cp[1,0], cp[0,1], cp[1,1]. Нормаль определяется
    cross-product (dS/du × dS/dv) = (cp10 - cp00) × (cp01 - cp00).

    P-record: 128, K1, K2, M1, M2, PROP1..5, U_knots(4), V_knots(4),
              weights(4), cp00(xyz), cp10(xyz), cp01(xyz), cp11(xyz),
              U0, U1, V0, V1;
    """

    cp00: tuple[float, float, float] = (0.0, 0.0, 0.0)
    cp10: tuple[float, float, float] = (0.0, 0.0, 0.0)
    cp01: tuple[float, float, float] = (0.0, 0.0, 0.0)
    cp11: tuple[float, float, float] = (0.0, 0.0, 0.0)

    def __post_init__(self) -> None:
        self.type_number = 128

    def parameters(self, resolver: Resolver) -> list[str]:
        # Degree 1×1, 2×2 control points (K1=K2=1, M1=M2=1)
        # PROP: closed_u=0, closed_v=0, polynomial=1, periodic_u=0, periodic_v=0
        # Standard clamped knot vector for degree 1 with 2 cp: [0, 0, 1, 1]
        params: list[str] = [
            "1", "1", "1", "1",          # K1, K2, M1, M2
            "0", "0", "1", "0", "0",      # PROP1..5
            "0.0", "0.0", "1.0", "1.0",   # U knots
            "0.0", "0.0", "1.0", "1.0",   # V knots
            "1.0", "1.0", "1.0", "1.0",   # weights (polynomial → all 1)
        ]
        for cp in (self.cp00, self.cp10, self.cp01, self.cp11):
            params.extend([fnum(cp[0]), fnum(cp[1]), fnum(cp[2])])
        params.extend(["0.0", "1.0", "0.0", "1.0"])  # U0, U1, V0, V1
        return params


@dataclass
class SurfaceOfRevolution(Entity):
    """Type 120 — Surface of Revolution.

    Поверхность, образованная вращением кривой (generatrix) вокруг оси (axis line).
    Для трубы со скруглёнными углами: каждый угол профиля — это четверть-цилиндр,
    образованный вращением прямой generatrix (параллельной оси трубы) вокруг
    axis line (тоже параллельной оси трубы) на угол π/2.

    P-record: 120, AXIS_DE, GENERATRIX_DE, START_ANGLE, END_ANGLE;
      AXIS_DE     — DE на Type 110 Line (ось вращения)
      GENERATRIX_DE — DE на curve entity (Type 110/100/126)
      START_ANGLE — radians
      END_ANGLE   — radians, должен быть > START_ANGLE
    """

    axis: Entity | None = None
    generatrix: Entity | None = None
    start_angle: float = 0.0
    end_angle: float = 6.283185307179586  # 2π

    def __post_init__(self) -> None:
        self.type_number = 120
        if self.axis is None or self.generatrix is None:
            raise ValueError("SurfaceOfRevolution requires axis and generatrix")

    def parameters(self, resolver: Resolver) -> list[str]:
        return [
            str(resolver(self.axis)),
            str(resolver(self.generatrix)),
            fnum(self.start_angle),
            fnum(self.end_angle),
        ]

    def referenced_entities(self) -> list[Entity]:
        return [self.axis, self.generatrix]


@dataclass
class NurbsCurve(Entity):
    """Type 126 — Rational B-Spline Curve.

    Используется для arc'ов в произвольной плоскости (когда Type 100 не подходит
    из-за ограничения «arc lies in plane parallel to XT-YT»). Для NURBS-arc
    degree 2 с 3 control points и весами [1, cos(θ/2), 1].

    P-record (для нашего minimal case — planar non-rational):
      126, K, M, PROP1, PROP2, PROP3, PROP4,
           knots(K+M+2 values),
           weights(K+1 values),
           ctrl_points 3D (3*(K+1) values),
           V0, V1,
           normal_x, normal_y, normal_z;

    PROP1 = 0 if planar curve (norm vector задан); 1 if non-planar
    PROP2 = 1 if closed curve, 0 if open
    PROP3 = 1 if polynomial (all weights == 1), 0 if rational
    PROP4 = 1 if periodic, 0 if non-periodic
    """

    K: int = 2  # upper index = ctrl_points_count - 1
    M: int = 2  # degree
    knots: list[float] = field(default_factory=list)
    weights: list[float] = field(default_factory=list)
    control_points: list[tuple[float, float, float]] = field(default_factory=list)
    v_start: float = 0.0
    v_end: float = 1.0
    normal: tuple[float, float, float] = (0.0, 0.0, 1.0)
    is_polynomial: bool = False
    is_planar: bool = True
    is_closed: bool = False
    is_periodic: bool = False

    def __post_init__(self) -> None:
        self.type_number = 126
        expected_knots = self.K + self.M + 2
        if len(self.knots) != expected_knots:
            raise ValueError(
                f"NurbsCurve: knots count {len(self.knots)} != K+M+2={expected_knots}"
            )
        if len(self.weights) != self.K + 1:
            raise ValueError(
                f"NurbsCurve: weights count {len(self.weights)} != K+1={self.K + 1}"
            )
        if len(self.control_points) != self.K + 1:
            raise ValueError(
                f"NurbsCurve: ctrl points count {len(self.control_points)} "
                f"!= K+1={self.K + 1}"
            )

    def parameters(self, resolver: Resolver) -> list[str]:
        params: list[str] = [
            str(self.K),
            str(self.M),
            "0" if self.is_planar else "1",     # PROP1
            "1" if self.is_closed else "0",      # PROP2
            "1" if self.is_polynomial else "0",  # PROP3
            "1" if self.is_periodic else "0",    # PROP4
        ]
        params.extend(fnum(k) for k in self.knots)
        params.extend(fnum(w) for w in self.weights)
        for cp in self.control_points:
            params.extend([fnum(cp[0]), fnum(cp[1]), fnum(cp[2])])
        params.append(fnum(self.v_start))
        params.append(fnum(self.v_end))
        params.extend([fnum(self.normal[0]), fnum(self.normal[1]), fnum(self.normal[2])])
        return params


@dataclass
class CompositeCurve(Entity):
    """Type 102 — Composite Curve.

    Соединяет N sub-curves (Type 110, 100, 126, ...) в единую кривую/loop.
    Для boundary loop прямоугольной грани: N=4, sub-curves = 4 Line entities.

    P-record: 102, N, DE1, DE2, ..., DEN;
    """

    sub_curves: list[Entity] = field(default_factory=list)

    def __post_init__(self) -> None:
        self.type_number = 102

    def parameters(self, resolver: Resolver) -> list[str]:
        params = [str(len(self.sub_curves))]
        for c in self.sub_curves:
            params.append(str(resolver(c)))
        return params

    def referenced_entities(self) -> list[Entity]:
        return list(self.sub_curves)


@dataclass
class CurveOnParametricSurface(Entity):
    """Type 142 — Curve on a Parametric Surface.

    Связывает boundary curve с поверхностью. Для нашего минимального case
    используем CRTN=2 (curve constructed from model space) + только 3D-curve,
    BPTR=0 (без UV-параметрической версии). PREF=2 (предпочесть 3D).

    P-record: 142, CRTN, SPTR, BPTR, CPTR, PREF;
    """

    surface: Entity | None = None
    boundary_3d: Entity | None = None  # Type 102 composite curve in 3D
    crtn: int = 2  # 2 = constructed from 3D
    pref: int = 2  # 2 = prefer 3D representation

    def __post_init__(self) -> None:
        self.type_number = 142
        if self.surface is None or self.boundary_3d is None:
            raise ValueError("CurveOnParametricSurface requires surface and boundary_3d")

    def parameters(self, resolver: Resolver) -> list[str]:
        return [
            str(self.crtn),
            str(resolver(self.surface)),
            "0",  # BPTR (UV curve) — отсутствует в нашем минимальном варианте
            str(resolver(self.boundary_3d)),
            str(self.pref),
        ]

    def referenced_entities(self) -> list[Entity]:
        return [self.surface, self.boundary_3d]


@dataclass
class TrimmedSurface(Entity):
    """Type 144 — Trimmed Parametric Surface.

    Завершающая обёртка для feature recognition в CypTube. Берёт surface
    (Type 128 / Type 120) и outer boundary (Type 142), и формирует
    «настоящую» закрытую грань с границами.

    P-record: 144, PTS, N1, N2, PT0[, PT1, PT2, ...];
      PTS — surface DE
      N1  — outer boundary flag (1 если outer задан явно, 0 — by parametric extents)
      N2  — number of inner boundaries (для отверстий)
      PT0 — outer boundary DE (Type 142)
      PT1...PTN — inner boundary DEs
    """

    surface: Entity | None = None
    outer_boundary: Entity | None = None  # Type 142
    inner_boundaries: list[Entity] = field(default_factory=list)  # Type 142, для отверстий

    def __post_init__(self) -> None:
        self.type_number = 144
        if self.surface is None or self.outer_boundary is None:
            raise ValueError("TrimmedSurface requires surface and outer_boundary")

    def parameters(self, resolver: Resolver) -> list[str]:
        params = [
            str(resolver(self.surface)),
            "1",  # N1 — outer boundary present
            str(len(self.inner_boundaries)),
            str(resolver(self.outer_boundary)),
        ]
        for inner in self.inner_boundaries:
            params.append(str(resolver(inner)))
        return params

    def referenced_entities(self) -> list[Entity]:
        return [self.surface, self.outer_boundary, *self.inner_boundaries]


def referenced_entities(entity: Entity) -> list[Entity]:
    """Получить cross-references entity (для топологической сортировки)."""
    method = getattr(entity, "referenced_entities", None)
    if method is None:
        return []
    return method()
