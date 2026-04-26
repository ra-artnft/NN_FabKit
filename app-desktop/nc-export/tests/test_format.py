"""Тесты низкоуровневого форматирования IGES."""

import pytest

from nn_fabkit_nc_export.iges.format import (
    DATA_WIDTH,
    LINE_WIDTH,
    P_DATA_WIDTH,
    fnum,
    format_d_fields,
    hstr,
    pad_d_line,
    pad_p_line,
    pad_section_line,
    wrap_p_data,
)


def test_fnum_zero_normalizes():
    assert fnum(0.0) == "0.0"
    assert fnum(-0.0) == "0.0"


def test_fnum_strips_trailing_zeros():
    assert fnum(1.0) == "1.0"
    assert fnum(40.0) == "40.0"
    assert fnum(1.5) == "1.5"
    assert fnum(0.001) == "0.001"


def test_fnum_no_exponent_for_small_values():
    # 0.000001 (precision floor) — без экспоненты
    s = fnum(0.000001)
    assert "e" not in s.lower()
    assert s.startswith("0.")


def test_fnum_negative():
    assert fnum(-40.0) == "-40.0"


def test_hstr_ascii():
    assert hstr("MM") == "2HMM"
    assert hstr("") == "0H"
    assert hstr("NN FabKit") == "9HNN FabKit"


def test_pad_section_line_is_80_chars():
    line = pad_section_line("hello", "S", 1)
    assert len(line) == LINE_WIDTH
    assert line[72] == "S"
    assert line[73:] == "      1"


def test_pad_d_line_is_80_chars():
    data = format_d_fields([110, 1, 0, 0, 0, 0, 0, 0, "00000000"])
    line = pad_d_line(data, 1)
    assert len(line) == LINE_WIDTH
    assert line[72] == "D"


def test_pad_p_line_is_80_chars():
    line = pad_p_line("110,0.0,0.0,0.0,1.0,1.0,1.0;", de_back=1, seq_num=1)
    assert len(line) == LINE_WIDTH
    assert line[72] == "P"
    # back-pointer в cols 66-72 (1-based 65-72 = index 64-71 with col 65 = blank)
    assert line[64] == " "  # col 65 — blank separator
    assert line[65:72] == "      1"


def test_pad_section_line_overflow_raises():
    too_long = "x" * (DATA_WIDTH + 1)
    with pytest.raises(ValueError):
        pad_section_line(too_long, "S", 1)


def test_format_d_fields_exactly_72_cols():
    out = format_d_fields([110, 1, 0, 0, 0, 0, 0, 0, "00000000"])
    assert len(out) == DATA_WIDTH


def test_wrap_p_data_short_record():
    rec = "110,0.0,0.0,0.0,1.0,2.0,3.0;"
    chunks = wrap_p_data(rec)
    assert chunks == [rec]


def test_wrap_p_data_long_record_splits_on_comma():
    rec = "122," + ",".join([f"1.{i:06d}" for i in range(20)]) + ";"
    chunks = wrap_p_data(rec)
    assert all(len(c) <= P_DATA_WIDTH for c in chunks)
    # При склейке получаем исходную строку
    assert "".join(chunks) == rec
