"""Низкоуровневое форматирование IGES 5.3 fixed-format.

IGES line layout (80 cols, ASCII):
  cols 1-72   data (S/G), 1-64 data + 65-72 P-back-pointer (P), 1-72 data (D/T)
  col  73     section letter (S/G/D/P/T)
  cols 74-80  sequence number (1-based, right-aligned, zero-padded не строго,
              но мы пишем zero-padded для консистентности)

Числа: формат — "%.6f" с обрезкой trailing zeros, без экспоненты.
Hollerith-строки: "<len>H<text>".
"""

from __future__ import annotations

DATA_WIDTH = 72         # cols 1-72 — data (S/G/D/T)
P_DATA_WIDTH = 64       # cols 1-64 — data в P секции
SECTION_COL = 73        # col 73 — буква секции
SEQUENCE_WIDTH = 7      # cols 74-80 — sequence number
LINE_WIDTH = 80


def fnum(v: float) -> str:
    """Format float for IGES — мм с точностью до 0.000001, без экспонент.

    Trailing zeros убраны, но всегда минимум одна цифра после точки.
    -0.0 нормализуется в 0.0 (некоторые парсеры спотыкаются на минус-нуле).
    """
    if v == 0:
        return "0.0"
    s = f"{float(v):.6f}".rstrip("0").rstrip(".")
    if "." not in s:
        s += ".0"
    return s


def hstr(text: str) -> str:
    """IGES Hollerith encoding: '<byte-len>H<text>'.

    Длина считается в байтах ASCII. Не-ASCII не поддерживается стандартом IGES;
    в G-section пишем только ASCII.
    """
    encoded = text.encode("ascii", errors="replace")
    return f"{len(encoded)}H{encoded.decode('ascii')}"


def pad_section_line(data: str, sect_letter: str, seq_num: int) -> str:
    """S/G/T-секция: data в cols 1-72, sect letter col 73, seq cols 74-80."""
    if len(data) > DATA_WIDTH:
        raise ValueError(
            f"Section {sect_letter} line {seq_num}: data {len(data)} chars "
            f"exceeds {DATA_WIDTH} (data='{data[:80]}...')"
        )
    padded = data.ljust(DATA_WIDTH)
    return f"{padded}{sect_letter}{seq_num:>{SEQUENCE_WIDTH}d}"


def pad_d_line(data: str, seq_num: int) -> str:
    """D-секция: 9 fields × 8 chars = 72, seq cols 74-80."""
    if len(data) > DATA_WIDTH:
        raise ValueError(
            f"D line {seq_num}: data {len(data)} chars exceeds {DATA_WIDTH}"
        )
    padded = data.ljust(DATA_WIDTH)
    return f"{padded}D{seq_num:>{SEQUENCE_WIDTH}d}"


def pad_p_line(data: str, de_back: int, seq_num: int) -> str:
    """P-секция: data cols 1-64, blank col 65, DE-pointer cols 66-72, seq cols 74-80.

    de_back — sequence number первой строки соответствующего entity в D-секции
    (всегда нечётное число: 1, 3, 5, ...).
    """
    if len(data) > P_DATA_WIDTH:
        raise ValueError(
            f"P line {seq_num}: data {len(data)} chars exceeds {P_DATA_WIDTH}"
        )
    padded = data.ljust(P_DATA_WIDTH)
    back_ptr = f"{de_back:>{SEQUENCE_WIDTH}d}"  # 7 digits in cols 66-72
    return f"{padded} {back_ptr}P{seq_num:>{SEQUENCE_WIDTH}d}"


def wrap_p_data(record: str) -> list[str]:
    """Разбить P-record (CSV с ';' в конце) на строки ≤ P_DATA_WIDTH chars.

    Разбиение по запятым (если возможно). Запятая остаётся в конце предыдущей
    строки (так делают большинство IGES writer'ов).
    """
    if len(record) <= P_DATA_WIDTH:
        return [record]

    chunks: list[str] = []
    remaining = record
    while len(remaining) > P_DATA_WIDTH:
        # Ищем последнюю запятую в первых P_DATA_WIDTH символах
        split = remaining.rfind(",", 0, P_DATA_WIDTH)
        if split == -1:
            # Нет запятой — режем по жёсткой границе (плохо, но не падаем)
            split = P_DATA_WIDTH - 1
        chunks.append(remaining[: split + 1])
        remaining = remaining[split + 1 :]
    if remaining:
        chunks.append(remaining)
    return chunks


def format_d_fields(fields: list) -> str:
    """D-секция: 9 полей × 8 chars = 72 cols. Right-aligned."""
    parts: list[str] = []
    for f in fields:
        if isinstance(f, int):
            parts.append(f"{f:>8d}")
        else:
            # Status string ("00000000") или blank
            parts.append(str(f).rjust(8))
    out = "".join(parts)
    if len(out) != DATA_WIDTH:
        raise ValueError(
            f"D-fields total width {len(out)} ≠ {DATA_WIDTH} (fields={fields})"
        )
    return out
