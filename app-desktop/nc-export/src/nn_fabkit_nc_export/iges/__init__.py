"""IGES 5.3 writer — минимальное подмножество для трубного NC.

Что умеем (v0.1.0):
- Type 110 Line Entity
- Type 100 Circular Arc Entity
- Type 122 Tabulated Cylinder
- Type 128 Rational B-Spline Surface (degree 1×1, для прямоугольных граней)

Что планируется:
- Type 144 Trimmed Surface (для endcaps с отверстием от стенки)
- Type 142 Curve on Parametric Surface
- Type 102 Composite Curve

Спецификация: см. docs/knowledge-base/10-iges-for-tube-nc.md
"""

from .document import IGESDocument
from . import entities

__all__ = ["IGESDocument", "entities"]
