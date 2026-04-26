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
