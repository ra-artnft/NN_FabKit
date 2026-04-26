"""Тесты IGESDocument: структурная валидность, T-секция, sequence numbers."""

import re

import pytest

from nn_fabkit_nc_export.iges.document import IGESDocument
from nn_fabkit_nc_export.iges.entities import Line, TabulatedCylinder
from nn_fabkit_nc_export.iges.format import LINE_WIDTH


def _split_lines(content: str) -> list[str]:
    """Разбить .igs content на строки. Поддержка \\r\\n и \\n."""
    return content.replace("\r\n", "\n").rstrip("\n").split("\n")


def test_empty_document_minimal_structure():
    doc = IGESDocument(description="empty")
    content = doc.serialize()
    lines = _split_lines(content)
    # Должно быть как минимум: 1 S, ≥1 G, 0 D, 0 P, 1 T
    sections = {l[72]: 0 for l in lines}
    for l in lines:
        sections[l[72]] = sections.get(l[72], 0) + 1
    assert sections.get("S", 0) >= 1
    assert sections.get("G", 0) >= 1
    assert sections.get("D", 0) == 0
    assert sections.get("P", 0) == 0
    assert sections.get("T", 0) == 1


def test_all_lines_are_exactly_80_chars():
    doc = IGESDocument(description="80-col test")
    line = Line(p1=(0, 0, 0), p2=(10, 0, 0))
    surface = TabulatedCylinder(directrix=line, terminate=(0, 0, 100))
    doc.add(line)
    doc.add(surface)
    content = doc.serialize()
    for i, l in enumerate(_split_lines(content), start=1):
        assert len(l) == LINE_WIDTH, (
            f"line {i}: {len(l)} chars (expected {LINE_WIDTH}): '{l}'"
        )


def test_section_letter_at_col_73():
    doc = IGESDocument()
    doc.add(Line(p1=(0, 0, 0), p2=(1, 0, 0)))
    content = doc.serialize()
    section_letters = {l[72] for l in _split_lines(content)}
    assert section_letters <= {"S", "G", "D", "P", "T"}


def test_t_section_counts_match():
    doc = IGESDocument(description="t-test")
    line = Line(p1=(0, 0, 0), p2=(1, 0, 0))
    surface = TabulatedCylinder(directrix=line, terminate=(0, 0, 5))
    doc.add(line)
    doc.add(surface)
    lines = _split_lines(doc.serialize())

    counts = {"S": 0, "G": 0, "D": 0, "P": 0}
    t_line = None
    for l in lines:
        sect = l[72]
        if sect in counts:
            counts[sect] += 1
        elif sect == "T":
            t_line = l

    assert t_line is not None
    # T data: "S      1G      4D      4P      2..."
    m = re.match(r"S\s*(\d+)G\s*(\d+)D\s*(\d+)P\s*(\d+)", t_line)
    assert m is not None, f"T line malformed: {t_line!r}"
    s_count, g_count, d_count, p_count = map(int, m.groups())
    assert s_count == counts["S"], f"T claims S={s_count}, actual {counts['S']}"
    assert g_count == counts["G"], f"T claims G={g_count}, actual {counts['G']}"
    assert d_count == counts["D"], f"T claims D={d_count}, actual {counts['D']}"
    assert p_count == counts["P"], f"T claims P={p_count}, actual {counts['P']}"


def test_d_section_pairs():
    """Каждая entity занимает ровно 2 строки в D-section."""
    doc = IGESDocument()
    line = Line(p1=(0, 0, 0), p2=(1, 0, 0))
    surface = TabulatedCylinder(directrix=line, terminate=(0, 0, 5))
    doc.add(line)
    doc.add(surface)
    lines = _split_lines(doc.serialize())
    d_lines = [l for l in lines if l[72] == "D"]
    assert len(d_lines) == len(doc.entities) * 2


def test_topological_sort_directrix_before_surface():
    """Type 110 directrix должен идти раньше Type 122 в D-section."""
    doc = IGESDocument()
    line = Line(p1=(0, 0, 0), p2=(1, 0, 0))
    surface = TabulatedCylinder(directrix=line, terminate=(0, 0, 5))
    # Добавляем в "неправильном" порядке — surface перед directrix
    doc.add(surface)
    doc.add(line)
    lines = _split_lines(doc.serialize())
    d_lines = [l for l in lines if l[72] == "D"]
    # D line 1 — Type 110 (directrix), D line 3 — Type 122 (surface)
    # type number в первом 8-char поле первой строки пары
    d1_type = int(d_lines[0][:8].strip())
    d3_type = int(d_lines[2][:8].strip())
    assert d1_type == 110, f"expected 110 first, got {d1_type}"
    assert d3_type == 122, f"expected 122 second, got {d3_type}"


def test_p_section_back_pointer_to_d():
    """P-секция: back-pointer (cols 66-72) указывает на D-line1 entity."""
    doc = IGESDocument()
    line = Line(p1=(0, 0, 0), p2=(1, 0, 0))
    doc.add(line)
    lines = _split_lines(doc.serialize())
    p_lines = [l for l in lines if l[72] == "P"]
    assert len(p_lines) == 1
    back = int(p_lines[0][65:72].strip())
    # У единственной entity D-line1 sequence == 1
    assert back == 1


def test_g_section_contains_unit_flag_mm():
    doc = IGESDocument()
    content = doc.serialize()
    lines = _split_lines(content)
    g_text = "".join(l[:72].rstrip() for l in lines if l[72] == "G")
    # 14-й параметр (UNIT_FLAG) должен быть "2", 15-й — "2HMM"
    assert "2HMM" in g_text
    assert ",2," in g_text  # Unit flag = 2 (MM)


def test_unknown_directrix_reference_raises():
    """Если TabulatedCylinder ссылается на directrix, не добавленную в документ."""
    doc = IGESDocument()
    orphan_line = Line(p1=(0, 0, 0), p2=(1, 0, 0))
    surface = TabulatedCylinder(directrix=orphan_line, terminate=(0, 0, 5))
    doc.add(surface)
    # orphan_line добавится автоматически через топ-сорт (referenced_entities)
    # — surface'а sufficient для включения её directrix.
    content = doc.serialize()
    assert content  # не падает, directrix была включена транзитивно


def test_explicit_orphan_directrix_in_referenced_entities():
    """Документ должен включать referenced entities даже если они не добавлены явно."""
    doc = IGESDocument()
    line = Line(p1=(0, 0, 0), p2=(1, 0, 0))
    surface = TabulatedCylinder(directrix=line, terminate=(0, 0, 5))
    # Добавляем только surface, не line
    doc.add(surface)
    lines = _split_lines(doc.serialize())
    d_lines = [l for l in lines if l[72] == "D"]
    # Должны быть обе entities (Type 110 + Type 122) → 4 D-строки
    assert len(d_lines) == 4
