"""rect-tube — closed box LOD-1 (BREP с trimmed surfaces).

Default: со скруглениями по ГОСТ 30245-2003.
no-radius: 6 trimmed planes (legacy).
"""

from nn_fabkit_nc_export.iges.format import LINE_WIDTH
from nn_fabkit_nc_export.tube.rect_tube import rect_tube_box


def _split(content: str) -> list[str]:
    return content.replace("\r\n", "\n").rstrip("\n").split("\n")


# ----------------------------------------------------------------------
# Default (с радиусами по ГОСТ 30245-2003)
# ----------------------------------------------------------------------


def test_rect_tube_default_radius_from_supplier():
    """Default radius для wall=2 → supplier convention 1.5×t = R=3.0."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    # Должны присутствовать 10 Type 144 (4 plane + 4 cylinder + 2 endcap)
    trimmed = [e for e in doc.entities if e.type_number == 144]
    assert len(trimmed) == 10
    # Должны быть Type 120 (Surface of Revolution) для скруглений
    sor = [e for e in doc.entities if e.type_number == 120]
    assert len(sor) == 4
    # Должны быть Type 126 NURBS arcs для boundary углов
    arcs = [e for e in doc.entities if e.type_number == 126]
    # 4 cylinder × 2 arcs (на v=0 и v=L) + 2 endcap × 4 arcs = 16
    assert len(arcs) == 16


def test_rect_tube_default_total_entity_count():
    """4 plane (×8) + 4 cylinder (×10) + 2 endcap (×12) = 32+40+24 = 96."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    assert len(doc.entities) == 96


def test_rect_tube_default_d_section_size():
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    lines = _split(doc.serialize())
    d_lines = [l for l in lines if l[72] == "D"]
    assert len(d_lines) == 192  # 96 entities × 2


def test_rect_tube_default_serializes_valid_iges():
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    lines = _split(doc.serialize())
    assert all(len(l) == LINE_WIDTH for l in lines)
    sections = {l[72] for l in lines}
    assert sections == {"S", "G", "D", "P", "T"}


def test_rect_tube_default_writes_file(tmp_path):
    out = tmp_path / "tube.igs"
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    doc.write(out)
    assert out.exists()
    raw = out.read_bytes()
    assert not raw.startswith(b"\xef\xbb\xbf")
    assert all(b < 128 for b in raw)


def test_rect_tube_explicit_radius():
    """Explicit radius_mm overrides ГОСТ-формулу."""
    doc = rect_tube_box(
        width_mm=60, height_mm=10, wall_mm=1.5, length_mm=992, radius_mm=2.25
    )
    # 10 trimmed surfaces (как в reference)
    trimmed = [e for e in doc.entities if e.type_number == 144]
    assert len(trimmed) == 10


def test_rect_tube_invalid_radius_too_large():
    """radius > min(W,H)/2 невалиден."""
    import pytest
    with pytest.raises(ValueError):
        rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600, radius_mm=15)


# ----------------------------------------------------------------------
# no-radius mode (legacy)
# ----------------------------------------------------------------------


def test_rect_tube_no_radius_has_48_entities():
    """6 граней × 8 entities = 48 (legacy no-radius)."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600, radius_mm=0)
    assert len(doc.entities) == 48
    type_counts: dict[int, int] = {}
    for e in doc.entities:
        type_counts[e.type_number] = type_counts.get(e.type_number, 0) + 1
    assert type_counts[110] == 24
    assert type_counts[102] == 6
    assert type_counts[128] == 6
    assert type_counts[142] == 6
    assert type_counts[144] == 6


def test_rect_tube_no_radius_serializes_valid_iges():
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600, radius_mm=0)
    lines = _split(doc.serialize())
    assert all(len(l) == LINE_WIDTH for l in lines)


def test_rect_tube_no_radius_face_normals_outer_facing():
    """no-radius: 6 NURBS surfaces, нормали наружу."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600, radius_mm=0)
    nurbs = [e for e in doc.entities if e.type_number == 128]
    assert len(nurbs) == 6
    expected_normals_signs = [
        (0,  1,  0), (0,  0,  1), (0, -1,  0),
        (0,  0, -1), (-1, 0,  0), (1,  0,  0),
    ]
    for face, expected in zip(nurbs, expected_normals_signs):
        a = (face.cp10[0]-face.cp00[0], face.cp10[1]-face.cp00[1], face.cp10[2]-face.cp00[2])
        b = (face.cp01[0]-face.cp00[0], face.cp01[1]-face.cp00[1], face.cp01[2]-face.cp00[2])
        cross = (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
        for c, e in zip(cross, expected):
            if e == 0:
                assert abs(c) < 1e-9
            elif e > 0:
                assert c > 0, f"face {face.label}: cross={cross}"
            else:
                assert c < 0, f"face {face.label}: cross={cross}"


def test_rect_tube_invalid_inputs():
    import pytest
    with pytest.raises(ValueError):
        rect_tube_box(width_mm=0, height_mm=20, wall_mm=2, length_mm=600)
    with pytest.raises(ValueError):
        rect_tube_box(width_mm=40, height_mm=20, wall_mm=-1, length_mm=600)
    with pytest.raises(ValueError):
        rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600, radius_mm=-1)


# ----------------------------------------------------------------------
# rect_tube_hollow_mitre_xl_45 — proper LOD-2 hollow с 45° mitre на +X конце
# ----------------------------------------------------------------------

import math
from nn_fabkit_nc_export.tube.rect_tube import rect_tube_hollow_mitre_xl_45


def test_hollow_mitre_basic_entity_counts():
    """Composition: 4 outer plane + 4 outer cyl + 4 inner plane + 4 inner cyl
    + 1 perpendicular endcap + 1 mitre endcap = 18 Type 144."""
    doc = rect_tube_hollow_mitre_xl_45(
        width_mm=40, height_mm=20, wall_mm=1.5, length_mm=600,
    )
    trimmed = [e for e in doc.entities if e.type_number == 144]
    assert len(trimmed) == 18
    labels = {e.label for e in trimmed}
    expected = {
        "F_YPLUS", "F_YMINS", "F_ZPLUS", "F_ZMINS",
        "C_PP", "C_MP", "C_MM", "C_PM",
        "I_YPLUS", "I_YMINS", "I_ZPLUS", "I_ZMINS",
        "I_CPP", "I_CMP", "I_CMM", "I_CPM",
        "E_X0", "E_XL_MIT",
    }
    assert labels == expected


def test_hollow_mitre_serializes_valid_iges():
    doc = rect_tube_hollow_mitre_xl_45(
        width_mm=40, height_mm=20, wall_mm=1.5, length_mm=600,
    )
    lines = _split(doc.serialize())
    assert all(len(l) == LINE_WIDTH for l in lines)
    sections = {l[72] for l in lines}
    assert sections == {"S", "G", "D", "P", "T"}


def test_hollow_mitre_writes_file(tmp_path):
    out = tmp_path / "mitre.igs"
    doc = rect_tube_hollow_mitre_xl_45(
        width_mm=40, height_mm=20, wall_mm=1.5, length_mm=600,
    )
    doc.write(out)
    assert out.exists()
    raw = out.read_bytes()
    assert not raw.startswith(b"\xef\xbb\xbf")  # без UTF-8 BOM
    assert all(b < 128 for b in raw)  # ASCII-only


def test_hollow_mitre_body_extends_correctly():
    """+Z plane должен extend до x=L+hh, -Z до x=L-hh."""
    L, W, H = 600.0, 40.0, 20.0
    hh = H / 2.0
    doc = rect_tube_hollow_mitre_xl_45(
        width_mm=W, height_mm=H, wall_mm=1.5, length_mm=L,
    )
    surfs = {e.label: e for e in doc.entities if e.type_number == 128}
    # _build_trimmed_plane creates surface с label = f"S_{label[:6]}".
    # "F_ZPLUS"[:6] = "F_ZPLU"; full surface label = "S_F_ZPLU".
    fzp = surfs["S_F_ZPLU"]
    max_x_zplus = max(p[0] for p in [fzp.cp00, fzp.cp10, fzp.cp01, fzp.cp11])
    assert math.isclose(max_x_zplus, L + hh, abs_tol=1e-6)
    fzm = surfs["S_F_ZMIN"]
    max_x_zmins = max(p[0] for p in [fzm.cp00, fzm.cp10, fzm.cp01, fzm.cp11])
    assert math.isclose(max_x_zmins, L - hh, abs_tol=1e-6)


def test_hollow_mitre_elliptic_arcs_use_sqrt2_over_2_weight():
    """NURBS arcs в mitre cylinder corner и mitre endcap должны иметь
    weight √2/2 средней ctrl-точки (стандарт rational quadratic для 90°)."""
    doc = rect_tube_hollow_mitre_xl_45(
        width_mm=40, height_mm=20, wall_mm=1.5, length_mm=600,
    )
    arcs = [e for e in doc.entities if e.type_number == 126]
    expected_w = math.sqrt(2.0) / 2.0
    for arc in arcs:
        assert math.isclose(arc.weights[1], expected_w, abs_tol=1e-9), (
            f"arc {arc.label}: weight={arc.weights[1]}"
        )


def test_hollow_mitre_invalid_inputs():
    import pytest
    # wall=0
    with pytest.raises(ValueError):
        rect_tube_hollow_mitre_xl_45(
            width_mm=40, height_mm=20, wall_mm=0, length_mm=600,
        )
    # wall too large (cavity collapse)
    with pytest.raises(ValueError):
        rect_tube_hollow_mitre_xl_45(
            width_mm=40, height_mm=20, wall_mm=15, length_mm=600,
        )
    # explicit radius_mm=0 (no roundings — illegal для hollow mitre LOD-2)
    with pytest.raises(ValueError):
        rect_tube_hollow_mitre_xl_45(
            width_mm=40, height_mm=20, wall_mm=1.5, length_mm=600, radius_mm=0,
        )
