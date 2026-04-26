"""Шаг 2: rect-tube --no-radius — closed box LOD-1 (BREP 6 trimmed surfaces)."""

from nn_fabkit_nc_export.iges.format import LINE_WIDTH
from nn_fabkit_nc_export.tube.rect_tube import rect_tube_box


def _split(content: str) -> list[str]:
    return content.replace("\r\n", "\n").rstrip("\n").split("\n")


def test_rect_tube_box_has_48_entities():
    """6 граней × 8 entities (4 Line + Composite + Surface + COS + Trimmed) = 48."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    assert len(doc.entities) == 48
    type_counts: dict[int, int] = {}
    for e in doc.entities:
        type_counts[e.type_number] = type_counts.get(e.type_number, 0) + 1
    assert type_counts[110] == 24   # 6 граней × 4 boundary edges
    assert type_counts[102] == 6    # composite curves
    assert type_counts[128] == 6    # NURBS surfaces
    assert type_counts[142] == 6    # curve on surface
    assert type_counts[144] == 6    # trimmed surfaces


def test_rect_tube_box_serializes_valid_iges():
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    lines = _split(doc.serialize())
    assert all(len(l) == LINE_WIDTH for l in lines)
    sections = {l[72] for l in lines}
    assert sections == {"S", "G", "D", "P", "T"}


def test_rect_tube_box_d_section_size():
    """48 entities × 2 строки = 96 D-строк."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    lines = _split(doc.serialize())
    d_lines = [l for l in lines if l[72] == "D"]
    assert len(d_lines) == 96


def test_rect_tube_box_writes_file(tmp_path):
    out = tmp_path / "tube.igs"
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    doc.write(out)
    assert out.exists()
    raw = out.read_bytes()
    assert not raw.startswith(b"\xef\xbb\xbf")
    assert all(b < 128 for b in raw)


def test_rect_tube_box_dimensions_in_p_section():
    """Координаты ±W/2, ±H/2, L должны присутствовать в P-section."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    lines = _split(doc.serialize())
    p_lines = [l for l in lines if l[72] == "P"]
    p_text = "".join(l[:64] for l in p_lines)
    assert "20.0" in p_text   # hw = 20
    assert "10.0" in p_text   # hh = 10
    assert "600.0" in p_text  # L


def test_rect_tube_box_invalid_inputs():
    import pytest
    with pytest.raises(ValueError):
        rect_tube_box(width_mm=0, height_mm=20, wall_mm=2, length_mm=600)
    with pytest.raises(ValueError):
        rect_tube_box(width_mm=40, height_mm=20, wall_mm=-1, length_mm=600)


def test_rect_tube_box_face_normals_outer_facing():
    """Для каждой NURBS грани normal = (cp10-cp00) × (cp01-cp00) должна смотреть наружу."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    nurbs = [e for e in doc.entities if e.type_number == 128]
    assert len(nurbs) == 6
    expected_normals_signs = [
        (0,  1,  0),   # F_YPLUS  → +Y
        (0,  0,  1),   # F_ZPLUS  → +Z
        (0, -1,  0),   # F_YMINS  → -Y
        (0,  0, -1),   # F_ZMINS  → -Z
        (-1, 0,  0),   # F_X0     → -X
        (1,  0,  0),   # F_XL     → +X
    ]
    for face, expected in zip(nurbs, expected_normals_signs):
        a = (
            face.cp10[0] - face.cp00[0],
            face.cp10[1] - face.cp00[1],
            face.cp10[2] - face.cp00[2],
        )
        b = (
            face.cp01[0] - face.cp00[0],
            face.cp01[1] - face.cp00[1],
            face.cp01[2] - face.cp00[2],
        )
        cross = (
            a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0],
        )
        for c, e in zip(cross, expected):
            if e == 0:
                assert abs(c) < 1e-9, f"face {face.label}: expected ~0, got {c}"
            elif e > 0:
                assert c > 0, f"face {face.label}: expected +sign, got {cross}"
            else:
                assert c < 0, f"face {face.label}: expected -sign, got {cross}"


def test_rect_tube_box_trimmed_surface_references_nurbs():
    """Каждый Type 144 trimmed surface должен ссылаться на свою Type 128 NURBS."""
    doc = rect_tube_box(width_mm=40, height_mm=20, wall_mm=2, length_mm=600)
    trimmed = [e for e in doc.entities if e.type_number == 144]
    assert len(trimmed) == 6
    for ts in trimmed:
        assert ts.surface is not None
        assert ts.surface.type_number == 128
        assert ts.outer_boundary is not None
        assert ts.outer_boundary.type_number == 142
