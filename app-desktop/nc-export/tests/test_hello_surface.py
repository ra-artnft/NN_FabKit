"""Шаг 1: hello-surface — одна BREP plane (Type 144 trim над Type 128)."""

from nn_fabkit_nc_export.iges.format import LINE_WIDTH
from nn_fabkit_nc_export.tube.rect_tube import hello_surface


def _split(content: str) -> list[str]:
    return content.replace("\r\n", "\n").rstrip("\n").split("\n")


def test_hello_surface_has_8_entities():
    """Trimmed plane = 4 Line + 1 Composite + 1 NurbsSurface + 1 COS + 1 TrimmedSurface."""
    doc = hello_surface(width_mm=40.0, length_mm=600.0)
    types = sorted(e.type_number for e in doc.entities)
    assert types == [102, 110, 110, 110, 110, 128, 142, 144]
    assert len(doc.entities) == 8


def test_hello_surface_serializes_valid_iges():
    doc = hello_surface(width_mm=40.0, length_mm=600.0)
    content = doc.serialize()
    lines = _split(content)
    assert all(len(l) == LINE_WIDTH for l in lines)
    sections = {l[72] for l in lines}
    assert sections == {"S", "G", "D", "P", "T"}


def test_hello_surface_writes_file(tmp_path):
    out = tmp_path / "hello.igs"
    doc = hello_surface(width_mm=40.0, length_mm=600.0)
    doc.write(out)
    assert out.exists()
    raw = out.read_bytes()
    assert not raw.startswith(b"\xef\xbb\xbf")
    assert not raw.startswith(b"\xff\xfe")
    assert all(b < 128 for b in raw)
    assert b"\r\n" in raw


def test_hello_surface_nurbs_control_points():
    """4 control points образуют плоский четырёхугольник W×L в плоскости z=0."""
    doc = hello_surface(width_mm=40.0, length_mm=600.0)
    nurbs = [e for e in doc.entities if e.type_number == 128]
    assert len(nurbs) == 1
    surface = nurbs[0]
    assert surface.cp00 == (0.0, -20.0, 0.0)
    assert surface.cp10 == (600.0, -20.0, 0.0)
    assert surface.cp01 == (0.0, 20.0, 0.0)
    assert surface.cp11 == (600.0, 20.0, 0.0)


def test_hello_surface_p_section_has_all_types():
    doc = hello_surface(width_mm=40.0, length_mm=600.0)
    lines = _split(doc.serialize())
    p_lines = [l for l in lines if l[72] == "P"]
    p_text = "".join(l[:64] for l in p_lines)
    for type_str in ("110,", "102,", "128,", "142,", "144,"):
        assert type_str in p_text, f"missing entity type prefix {type_str!r}"
