"""IGESDocument — собирает entities в финальный .igs.

Алгоритм сериализации:
  1. Топ-сорт entities (referenced раньше referencing).
  2. Назначение D-section sequence: каждая entity занимает 2 строки;
     entity[i] → D-sequence (2*i + 1) для line1, (2*i + 2) для line2.
  3. Построение P-records (CSV "<type>,<params>;") с резолвом cross-refs
     через Resolver(entity) → D-sequence.
  4. Разбиение P-records на chunks ≤64 cols.
  5. Построение D-section pairs.
  6. Сборка G-section (25 параметров).
  7. Сборка S-section (свободный текст-описание).
  8. T-section с счётчиками строк.
  9. Финальная сборка с правильной нумерацией и back-pointer'ами в P.

Encoding: ASCII, line endings CRLF (соглашение для Windows-CAM).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone

from .. import __version__
from .entities import Entity, referenced_entities
from .format import (
    format_d_fields,
    hstr,
    pad_d_line,
    pad_p_line,
    pad_section_line,
    wrap_p_data,
)


@dataclass
class IGESDocument:
    """Контейнер entities + G-section metadata.

    Метаданные имеют разумные defaults; для production-экспорта стоит передать
    реальные values (file_name, author, organization).
    """

    entities: list[Entity] = field(default_factory=list)

    # S-section
    description: str = "NN FabKit nc-export"

    # G-section metadata
    sender_product_id: str = "NN FabKit"
    file_name: str = ""
    system_id: str = "NN FabKit nc-export"
    preprocessor_version: str = ""  # default → __version__
    receiver_product_id: str = ""
    author: str = ""
    organization: str = ""
    # G[20] — approximate maximum coordinate value, мм
    # 13000 мм = 13 м, реалистичный потолок длины трубы для NC.
    max_coord: float = 13000.0
    # G[19] — minimum user-intended resolution (precision floor), мм
    min_resolution: float = 0.001

    def add(self, entity: Entity) -> Entity:
        """Добавить entity в документ. Возвращает её же для удобства chain."""
        self.entities.append(entity)
        return entity

    def serialize(self) -> str:
        """Вернуть содержимое .igs как строку (ASCII, CRLF)."""
        sorted_entities = self._topological_sort()

        # D-pointers: для каждой entity её sequence в D-section (line1 row).
        de_pointers: dict[int, int] = {
            id(e): idx * 2 + 1 for idx, e in enumerate(sorted_entities)
        }

        def resolver(e: Entity) -> int:
            try:
                return de_pointers[id(e)]
            except KeyError:
                raise ValueError(
                    f"Entity Type {e.type_number} ссылается на entity "
                    f"которой нет в документе"
                )

        # 1. Build P-records (with type prefix and ';' terminator).
        p_records: list[str] = []
        for e in sorted_entities:
            params = e.parameters(resolver)
            record = f"{e.type_number}," + ",".join(params) + ";"
            p_records.append(record)

        # 2. Wrap into chunks; track P-sequence start per entity.
        p_lines: list[str] = []
        p_starts: list[int] = []  # P-sequence (1-based) of first chunk per entity
        param_line_counts: list[int] = []
        for record in p_records:
            p_starts.append(len(p_lines) + 1)
            chunks = wrap_p_data(record)
            param_line_counts.append(len(chunks))
            p_lines.extend(chunks)

        # 3. Build D-section pairs.
        d_lines: list[str] = []
        for idx, e in enumerate(sorted_entities):
            d_lines.extend(_build_d_pair(e, p_starts[idx], param_line_counts[idx]))

        # 4. Build G-section.
        g_lines = self._build_g_section()

        # 5. S-section: свободный текст. Разбиваем по 72 cols.
        s_lines = self._build_s_section()

        # 6. Assemble output with correct sequence numbering.
        out: list[str] = []
        for i, l in enumerate(s_lines, start=1):
            out.append(pad_section_line(l, "S", i))
        for i, l in enumerate(g_lines, start=1):
            out.append(pad_section_line(l, "G", i))
        for i, l in enumerate(d_lines, start=1):
            out.append(pad_d_line(l, i))

        # P-section: each chunk gets a back-pointer to its entity's D-line1.
        p_to_de: dict[int, int] = {}
        for idx, _e in enumerate(sorted_entities):
            de_seq = idx * 2 + 1
            for j in range(param_line_counts[idx]):
                p_to_de[p_starts[idx] + j] = de_seq
        for i, l in enumerate(p_lines, start=1):
            out.append(pad_p_line(l, p_to_de[i], i))

        # 7. T-section: 1 строка вида "S<7d>G<7d>D<7d>P<7d>".
        t_data = (
            f"S{len(s_lines):>7d}"
            f"G{len(g_lines):>7d}"
            f"D{len(d_lines):>7d}"
            f"P{len(p_lines):>7d}"
        )
        out.append(pad_section_line(t_data, "T", 1))

        return "\r\n".join(out) + "\r\n"

    def write(self, path) -> None:
        """Записать .igs файл (ASCII, CRLF, без BOM)."""
        from pathlib import Path

        Path(path).write_bytes(self.serialize().encode("ascii"))

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _topological_sort(self) -> list[Entity]:
        """DFS post-order: referenced раньше referencing.

        Гарантирует, что Type 110 directrix идёт перед своим Type 122
        TabulatedCylinder — обязательное требование IGES (DE-pointer ссылается
        вперёд по файлу не запрещено стандартом, но многие парсеры спотыкаются).
        """
        visited: set[int] = set()
        order: list[Entity] = []

        def visit(e: Entity) -> None:
            if id(e) in visited:
                return
            visited.add(id(e))
            for ref in referenced_entities(e):
                visit(ref)
            order.append(e)

        for e in self.entities:
            visit(e)
        return order

    def _build_g_section(self) -> list[str]:
        """25 параметров G-section, разбитых на ≤64-col строки."""
        ts = datetime.now(timezone.utc).strftime("%Y%m%d.%H%M%S")
        version = self.preprocessor_version or f"NN FabKit nc-export {__version__}"
        params = [
            "1H,",                              # 1. Parameter delimiter
            "1H;",                              # 2. Record delimiter
            hstr(self.sender_product_id),       # 3. Sender Product ID
            hstr(self.file_name),               # 4. File name
            hstr(self.system_id),               # 5. System ID
            hstr(version),                      # 6. Preprocessor version
            "32",                               # 7. Integer bits
            "38",                               # 8. Single precision magnitude
            "6",                                # 9. Single precision significance
            "308",                              # 10. Double precision magnitude
            "15",                               # 11. Double precision significance
            hstr(self.receiver_product_id),     # 12. Receiver Product ID
            "1.0",                              # 13. Model space scale
            "2",                                # 14. Unit flag (2 = MM)
            hstr("MM"),                         # 15. Unit name
            "32",                               # 16. Max line weight gradations
            "1.0",                              # 17. Max line weight width (mm)
            hstr(ts),                           # 18. File generation timestamp
            f"{self.min_resolution}",           # 19. Min user-intended resolution
            f"{self.max_coord}",                # 20. Approx max coord
            hstr(self.author),                  # 21. Author
            hstr(self.organization),            # 22. Organization
            "11",                               # 23. IGES version flag (11 = 5.3)
            "0",                                # 24. Drafting standard
            hstr(ts),                           # 25. Last model modification
        ]
        record = ",".join(params) + ";"
        return wrap_p_data(record)

    def _build_s_section(self) -> list[str]:
        """S-section — свободный текст. Бьём на куски по 72 cols."""
        if not self.description:
            return ["NN FabKit nc-export"]
        text = self.description
        chunks: list[str] = []
        while len(text) > 72:
            chunks.append(text[:72])
            text = text[72:]
        if text:
            chunks.append(text)
        return chunks


# Status field в D-section по IGES 5.3 §2.2.4.4:
#   digits 1-2: Blank Status (00=visible, 01=blanked)
#   digits 3-4: Subordinate Switch (00=independent, 01=physical, 02=logical, 03=both)
#   digits 5-6: Entity Use Flag (00=geometry, 01=annot, 02=def, 03=other,
#                                04=logical, 05=2D parametric, 06=construction)
#   digits 7-8: Hierarchy (00=global, 01=use, 02=use hierarchy)
#
# Конвенция «как делает SolidWorks» (по reference IGS заказчика):
#   видимыми оставляем только Type 144 (TrimmedSurface) и Type 142
#   (CurveOnParametricSurface). Остальные — blanked (subordinate parts BREP'а),
#   что убирает лишние iso-curves и axis/generatrix lines в CAM viewport.
_STATUS_BY_TYPE: dict[int, str] = {
    100: "01010000",  # Circular Arc — blanked, subordinate
    102: "01010000",  # Composite Curve — blanked, subordinate
    110: "01010000",  # Line — blanked, subordinate
    120: "01010000",  # Surface of Revolution — blanked, subordinate
    126: "01010500",  # Rational B-Spline Curve — blanked, subordinate, parametric
    128: "01010000",  # Rational B-Spline Surface — blanked, subordinate
    142: "00010500",  # Curve on Parametric Surface — VISIBLE, subordinate, parametric
    144: "00000000",  # Trimmed Surface — VISIBLE, independent (top-level)
}


def _build_d_pair(entity: Entity, p_pointer: int, param_line_count: int) -> list[str]:
    """Построить 2-строчную D-запись для одной entity.

    Поля по IGES 5.3 §2.2.4. Все pointer-поля, которые мы не используем,
    пишутся как 0 (= no association). Status field — per type lookup
    (см. `_STATUS_BY_TYPE` выше).
    """
    type_num = entity.type_number
    form_num = entity.form_number
    label = (entity.label or "")[:8]
    status = entity.iges_status or _STATUS_BY_TYPE.get(type_num, "00000000")

    line1_fields: list = [
        type_num,    # 1. Entity Type Number
        p_pointer,   # 2. Parameter Data Pointer (P-sequence first chunk)
        0,           # 3. Structure
        0,           # 4. Line Font Pattern
        0,           # 5. Level
        0,           # 6. View
        0,           # 7. Transformation Matrix
        0,           # 8. Label Display Associativity
        status,      # 9. Status Number (8-char string per type)
    ]
    line2_fields: list = [
        type_num,         # 1. (repeat)
        0,                # 2. Line Weight Number
        0,                # 3. Color Number
        param_line_count, # 4. Parameter Line Count
        form_num,         # 5. Form Number
        "",               # 6. Reserved (blank)
        "",               # 7. Reserved (blank)
        label,            # 8. Entity Label (≤8 chars)
        0,                # 9. Entity Subscript Number
    ]
    return [format_d_fields(line1_fields), format_d_fields(line2_fields)]
