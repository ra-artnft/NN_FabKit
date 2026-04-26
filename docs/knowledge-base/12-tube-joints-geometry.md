# 12. Стыки профильных труб: геометрия и правила раскроя

> Справочник по геометрии стыков (joints) трёх базовых сечений
> NN FabKit MetalFab: **прямоугольная труба** (W×H, W ≠ H), **квадратная**
> (W = H — частный случай прямоугольной) и **круглая** (round tube, D).
> Назначение — фиксировать «правильную» геометрию каждого стыка, чтобы
> FabKit CAD генерил cut'ы без зазоров и overlap'ов, а NC-экспорт давал
> траектории для laser tube cutter / mitre saw, дающие после сварки
> бесшовное соединение «как нарисовано».
>
> Дата составления: 2026-04-26. Кодировка: UTF-8 без BOM.
>
> **Принцип, который этот документ закрепляет:** угол между трубами
> в сборке после раскроя НЕ должен меняться. Если в модели две трубы
> сходятся под 90°, после mitre 45/45 они должны встретиться без зазора
> и без перекрытия — «положил рядом и заварил по контуру».

## Содержание

1. [Терминология](#1-терминология)
2. [Принцип bisecting plane](#2-принцип-bisecting-plane)
3. [L-corner: mitre joint двух труб](#3-l-corner-mitre-joint-двух-труб)
   1. [Геометрия для прямоугольной трубы W×H](#31-геометрия-для-прямоугольной-трубы-wh)
   2. [Квадратная труба (W=H)](#32-квадратная-труба-wh)
   3. [Длина детали после mitre](#33-длина-детали-после-mitre)
   4. [Влияние outer radius (скруглённые углы сечения)](#34-влияние-outer-radius-скруглённые-углы-сечения)
   5. [Asymmetric mitre (разные сечения)](#35-asymmetric-mitre-разные-сечения)
4. [T-joint: труба упирается в стенку другой](#4-t-joint-труба-упирается-в-стенку-другой)
5. [X / Cross joint](#5-x--cross-joint)
6. [Y / K joints (фермы)](#6-y--k-joints-фермы)
7. [Круглая труба (round tube)](#7-круглая-труба-round-tube)
8. [Production aspects: сварка и допуски](#8-production-aspects-сварка-и-допуски)
9. [Сводная таблица: профиль × тип стыка → реализация в FabKit](#9-сводная-таблица-профиль--тип-стыка--реализация-в-fabkit)
10. [Связь с FabKit CAD tool](#10-связь-с-fabkit-cad-tool)
11. [Open questions](#11-open-questions)
12. [Источники](#12-источники)

---

## 1. Терминология

| Термин | Английский | Описание |
|---|---|---|
| **Косой рез / усовое соединение** | mitre cut, mitre joint | Рез плоскостью под углом к оси трубы. Обе трубы в стыке режутся под половинным углом стыка. |
| **Стыковое соединение** | butt joint | Рез плоскостью, ⟂ оси (поперечный). Часто для T-joint. |
| **Седловой рез** | saddle cut, cope, fishmouth | Фигурный рез, в форме «отпечатка» другой трубы на поверхности этой. Обязателен для round-on-round T-joint. |
| **Врезка / гнездование** | notch, mortise | Вырез в стенке одной трубы под профиль другой. Для rect-rect T-joint с full envelope. |
| **Угол стыка** | joint angle, θ | Угол между **осями** (axes) двух труб. Для L-corner 90° — это 90°. |
| **Угол реза** | mitre angle, α | Угол между плоскостью реза и плоскостью, ⟂ оси трубы. Для symmetric joint α = (180° − θ)/2 = 90° − θ/2. **NB**: иногда определяется наоборот — как угол между плоскостью реза и осью трубы; в FabKit принят первый вариант (0° = perpendicular cut, 45° = классический mitre под 90° L-corner). |
| **Биссектрисная плоскость** | bisecting plane | Плоскость, содержащая точку пересечения осей и делящая угол между осями пополам. Для symmetric mitre cut'ы обеих труб лежат в этой плоскости. |
| **Long side / short side mitre** | tilt direction | Направление, в котором длинная сторона реза смещена относительно поперечного сечения. Для L-corner long side всегда смотрит «внутрь угла» (TO body другой трубы). |
| **Tilt direction** | — | Local-coord проекция вектора «куда уходит другая труба» на cross-section plane. Используется в FabKit CAD для compute_tilt_dir. |
| **Asymmetric mitre** | unequal mitre | Стык труб с разными сечениями: углы реза каждой трубы могут отличаться (нужны для совмещения внешних контуров). Реже встречается в реальных конструкциях. |

---

## 2. Принцип bisecting plane

Базовая идея, к которой сводятся все mitre-стыки:

> Если две трубы должны встретиться концами под углом θ и сохранить этот
> угол в сборке, существует **единственная плоскость** (биссектрисная),
> которая (а) проходит через точку пересечения их осей и (б) делит угол
> между осями пополам. Cut на каждой трубе должен совпадать с этой
> плоскостью. Тогда оба cut'а становятся ОДНОЙ плоскостью в пространстве —
> трубы соединяются без зазора и overlap'а.

**Условия применимости:**

- Обе трубы — с одинаковым сечением (symmetric joint). Если сечения
  разные, см. [3.5](#35-asymmetric-mitre-разные-сечения).
- Оси пересекаются в одной точке. Если они skew (не пересекаются в 3D —
  классический случай для нагруженных рам), см. [11](#11-open-questions).
- Резка выполняется в одной плоскости (planar cut). Это работает для
  rect/square труб; для round-round нужен cope cut, см. [7](#7-круглая-труба-round-tube).

**Геометрическая формула:**

| Угол стыка θ (между осями) | Mitre angle α (на каждой трубе) |
|---|---|
| 90° | 45° |
| 120° (тупой L) | 30° |
| 60° (острый L, Y-joint brace) | 60° |
| 45° (острый Y) | 67.5° |
| 180° (collinear, butt) | 0° (perpendicular cut) |

Общая формула: **α = (180° − θ) / 2 = 90° − θ/2**.

**NB:** в FabKit CAD текущая реализация ([fabkit_cad_tool.rb](../../plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb)
строка 242) считает `mitre_angle = angle_between_deg / 2`, где
`angle_between_deg` — это **острый** угол между осями (взят через
`acos(dot.abs)`). Для L-corner с θ=90° получается 45° — корректно.
Для θ=120° получится `angle_between=60°` (острая дополнительная) → mitre
60°. Это **неверно** для тупого L (правильный ответ — 30°). Баг возникает
при θ > 90° и фиксируется отдельным TODO (см. [11](#11-open-questions)).

---

## 3. L-corner: mitre joint двух труб

L-corner — две трубы, концы которых сходятся в одну точку под углом θ.
Самый частый стык в рамных металлоконструкциях (рамы ворот, каркасы,
лестничные ограждения, мебель).

```
        end_A
          ●────────────tube_A────────● far_A
          │
          │ tube_B
          │
        far_B ●
```

Точка `●` (end_A == end_B) — joint point. Биссектрисная плоскость для
90° L: вертикальная плоскость, содержащая joint point и идущая под 45°
к обеим осям.

### 3.1. Геометрия для прямоугольной трубы W×H

**Дано:**
- Труба сечения W (width, по local +X) × H (height, по local +Y).
- Длина — `length_mm` по local +Z.
- Mitre на конце z=length, угол α = 45° (для θ=90° L-corner).
- Tilt direction = `(0, 1, 0)` (long side mitre на +Y, например труба B
  лежит выше трубы A в L-corner).

**Cut plane** проходит через точку `(0, 0, length)` с normal-vector,
наклонённым на α от оси Z в направлении tilt:
```
n = (-sin(α)·tilt_x, -sin(α)·tilt_y, cos(α)) = (0, -sin(45°), cos(45°))
```

Плоскость определяется уравнением `n · (P - center) = 0`, где
`center = (0, 0, length)`.

**4 угловых точек cut'а** (на пересечении плоскости со стенками
прямоугольника W×H):

| Local (x, y, z) | Описание |
|---|---|
| `(+W/2, +H/2, length + (H/2)·tan(α))` | Long side, NE corner |
| `(-W/2, +H/2, length + (H/2)·tan(α))` | Long side, NW corner |
| `(-W/2, -H/2, length - (H/2)·tan(α))` | Short side, SW corner |
| `(+W/2, -H/2, length - (H/2)·tan(α))` | Short side, SE corner |

Для α=45° (`tan(α) = 1`):
- Long side z = length + H/2
- Short side z = length − H/2
- Разница high-low = H

**Cut surface** (плоский четырёхугольник):
- Короткие стороны (along ±X): длина = W
- Длинные стороны (along tilt direction): длина = H / cos(α) = H·√2 при 45°
- Площадь = W × H / cos(α) = W·H·√2 при 45°

**Видимые швы на каждой грани** трубы после mitre:
- Top face (y=+H/2): cut пересекает её по линии от
  `(+W/2, +H/2, length+H/2)` до `(-W/2, +H/2, length+H/2)` — **горизонтальная**
  линия на z=length+H/2, длина W. (Эта грань удлиняется на H/2.)
- Bottom face (y=-H/2): аналогично на z=length-H/2, длина W. (Грань
  укорачивается на H/2.)
- Side faces (x=±W/2): cut по диагонали, от низкой точки до высокой —
  **диагональная** линия от `(±W/2, -H/2, length-H/2)` до
  `(±W/2, +H/2, length+H/2)`. Длина диагонали = √(H² + H²) = H·√2.
  Угол наклона диагонали относительно оси трубы — 45°.

### 3.2. Квадратная труба (W=H)

Все формулы выше с подстановкой H = W. Особенности:
- Cut surface — квадрат W × W·√2 (диагональный прямоугольник).
- На side faces (любых из четырёх) — диагональная линия по точно 45°.
- Вид сверху на mitre line: ничем не выделяется по сравнению с rect —
  направление tilt задаёт ориентацию диагонали, но геометрия стыка
  симметрична относительно поворота на 90°.

В реальной поставке (ГОСТ 30245-2003) квадратные трубы — самые частые
сечения для рам каркасов; типовые типоразмеры **20×20**, **40×40**,
**60×60**, **80×80**, **100×100**. Для всех L-mitre 45° даёт стандартный
joint.

### 3.3. Длина детали после mitre

Это критичный момент для production: cut-list и NC должны видеть
**фактическую** длину детали после раскроя, а не «pre-cut» длину
трубы в модели.

**Definition (FabKit convention):**
- `length_mm` детали = расстояние от **far endpoint** (конец, противоположный
  joint) до **точки пересечения axes** (или `Geom.closest_points` для skew
  axes), измеренное вдоль оси трубы.

**Пример L-corner 90°, рама 1000×600 мм по внешнему контуру:**

```
  ┌──────────────tube_A (1000)────────────┐
  │                                       │
  │                                       │
  tube_B (600)
  │
  ⋮
```

После mitre 45/45:
- tube_A проходит от (0, 0) до (1000, 0) в плане; far_A на (0,0), joint
  на (1000, 0).
- tube_B от (1000, 600) (far_B) до (1000, 0) (joint).
- Axes пересекаются в (1000, 0).
- new_length(tube_A) = distance(far_A, intersection) = 1000 mm.
- new_length(tube_B) = distance(far_B, intersection) = 600 mm.

**Ключевое наблюдение:** `length_mm` после trim'а — это **расстояние
между осевыми точками концов**, не «длина по внешней грани» и не «длина
по внутренней грани». Для квадратной трубы 60×60 и L-mitre 45/45:
- Длина внешней грани = `length_mm + (W/2)·tan(α) = length_mm + W/2`.
- Длина внутренней грани = `length_mm − W/2`.
- Длина по оси = `length_mm` (то, что пишется в cut-list).

Производство и поставка считают трубы **по оси** (как привезли с завода —
заводская длина). После раскроя cut-list тоже даёт длину по оси. Это
универсальное соглашение, которому FabKit должен следовать.

### 3.4. Влияние outer radius (скруглённые углы сечения)

Реальная труба ГОСТ 30245-2003 / 8639-82 имеет скруглённые внешние углы
с радиусом R ≈ 1.5..3 × t (см. [11-gost-profile-tubes-radii](11-gost-profile-tubes-radii.md)).

При mitre cut под углом α, плоскость пересекает цилиндрическую часть
закругления (Cylinder R вокруг оси, параллельной оси трубы) — это даёт
**эллиптическую кривую** на cut surface, а не прямой угол.

Для NC (laser tube cutter):
- Прямой `Cut at 45°` cuts через скругление дают эллипс с осями
  `R` (малая) и `R/cos(α)` (большая, вдоль наклона).
- Для α=45°: эллипс с осями `R` и `R·√2`.
- Это критично для feature recognition в CypTube — laser трактует
  4 mitre arcs (по углам) + 4 straight segments (по граням) как один
  замкнутый контур реза.

В наш Python `nc-export` (см. [`rect_tube.py:rect_tube_hollow_mitre_xl_45`](../../app-desktop/nc-export/src/nn_fabkit_nc_export/tube/rect_tube.py))
эллиптические дуги уже реализованы для 45° hollow mitre — это reference
implementation. Ruby-side в плагине пока даёт LOD-1 multilateral
approximation (8 сегментов на угол), что **хорошо для визуализации**, но
для NC-экспорта эллипс должен генериться как Type 100/126 IGES entity
(arc / parametric spline), не как polyline.

**Важно для FabKit CAD:** vertex displacement в `rect_tube_mitre.rb`
сейчас работает с уже-сегментированной геометрией LOD-1 (8 точек на
скруглении), что даёт визуально гладкий cut. Однако mitre line на
скруглении получается из 8 коротких сегментов, а не из аналитического
эллипса. Это OK для preview, но **не передаётся в IGES** в текущей
форме; nc-export должен реконструировать аналитическую кривую из
attributes (`outer_radius_mm`, `cut_angle`, `tilt_dir`), а не из сетки
вершин SU.

### 3.5. Asymmetric mitre (разные сечения)

Если две трубы в L-corner имеют **разные сечения** (например 60×60 и
60×40), стандартный 45/45 mitre не даёт совпадения внешних контуров.

**Случай 1 — внешние грани совпадают на одной стороне:**
- Trubai 60×40 имеет H=40, trubai 60×60 имеет H=60.
- Если они совпадают по нижней грани (y=0 в общей системе), верхняя
  грань 60×40 — на y=40, верхняя 60×60 — на y=60. Разница 20 мм
  необходимо «зашить» — либо угол mitre отличается на каждой, либо
  допустить overlap/gap.
- Реально на производстве такие стыки обычно **избегают** — компоновщик
  выбирает одно сечение для всей рамы.

**Случай 2 — оси совпадают (центры сечений на пересечении axes):**
- Mitre 45/45 на каждой даёт зазор в области, где сечения отличаются
  (большая труба «торчит» за пределы маленькой).
- Эстетически приемлемо для каркасов с разными нагрузками (главные
  балки толще, второстепенные — тоньше).

**FabKit CAD на этом этапе** — symmetric mitre only. Asymmetric — TODO
(см. [11](#11-open-questions)).

---

## 4. T-joint: труба упирается в стенку другой

T-joint — одна труба упирается своим концом в **боковую стенку** другой
(не в её конец). Самый частый стык в рамных конструкциях после L-corner.

```
        ●━━━━━━tube_chord (главная)━━━━━━━●
                       ┃
                       ┃ tube_brace
                       ┃
                       ●
```

**Три варианта подгонки brace'а к chord'у:**

### (a) Butt joint (perpendicular cut)
- Brace обрезается **perpendicular** оси (mitre angle = 0°).
- Chord — БЕЗ cut'а.
- Brace упирается «торцом» в плоскую стенку chord'а.
- Сварной шов по периметру cross-section brace'а (4 segment'а для
  rect/square, 1 окружность для round).
- **Pro:** простая геометрия, минимум cut'ов, дешёвое production.
- **Contra:** сварной шов короткий → low strength для tension/moment
  loads. OK для compression.
- **Production:** mitre saw / laser tube cut.
- **FabKit CAD приоритет:** да, после L-mitre.

### (b) Notch / coping (envelope cope cut)
- Brace обрезается фигурным резом, повторяющим **профиль** chord'а
  (envelope).
- Chord — БЕЗ cut'а.
- Brace «обнимает» chord — площадь контакта существенно больше.
- Сварной шов по контуру notch'а — длиннее, лучше прочность.
- **Pro:** высокая strength, стандарт для нагруженных HSS-конструкций.
- **Contra:** сложная геометрия cut'а — нужен laser tube cutter (mitre
  saw не справится).
- **Production:** только laser/plasma tube cutter с feature recognition.
- **FabKit CAD приоритет:** TODO для этапа 3, см. [10](#10-связь-с-fabkit-cad-tool).

### (c) Insert / mortise
- Brace **проходит** сквозь chord (через дырки в верхней и нижней
  стенках). Используется для специфических нагрузок (в основном — балки
  через колонны).
- Chord имеет вырезы в стенках (mortise hole), brace проходит насквозь.
- **Production:** laser tube cutter обязателен для chord, brace —
  perpendicular cut.
- **FabKit CAD приоритет:** низкий (специфическая нагрузка, не общий
  case).

### Геометрия brace cut для (a) butt
- Cross-section brace'а в плоскости, ⟂ его оси.
- z_cut = brace.length (или 0, в зависимости от ориентации).
- Никаких vertex displacement'ов — cut уже plain perpendicular.
- В FabKit terms: `mitre_angle = 0`, ничего рендерить не надо.

### Геометрия brace cut для (b) notch — для rect-on-rect
- Brace W_b × H_b, chord W_c × H_c.
- Cut surface — пересечение цилиндра brace'а (фигурного — rectangle
  cross-section, проложенный вдоль brace axis) с **плоскостью** chord wall.
- Если brace ⟂ chord: cut surface — это просто W_b × H_b прямоугольник
  на плоскости chord wall, **сдвинутый** в направлении brace axis на
  «глубину обнятия» (= corner radius chord'а или конструктивный gap).
- Если brace под углом β к chord wall: cut surface — параллелограмм
  с проекцией W_b × H_b/sin(β).

### Геометрия brace cut для (b) notch — для rect-on-round
- Cut surface — седловой («cope») contour: пересечение rect cross-section
  brace'а с цилиндрической поверхностью chord'а (D_chord).
- Не plain plane — поверхность с переменной кривизной.
- Generation: для каждой точки на периметре brace cross-section вычислить
  z = `R_chord − sqrt(R_chord² − x²)` (depth of cope), где x — расстояние
  от brace axis в плоскости, ⟂ chord axis.

### Геометрия brace cut для (b) notch — для round-on-round
- Классический fishmouth — synus-like cope, см. [7](#7-круглая-труба-round-tube).

---

## 5. X / Cross joint

X-joint — 4 трубы сходятся в одной точке. Два варианта:

### Симметричный X (4× mitre 45°)
- Все 4 трубы режутся под 45° к bisecting plane each-other.
- Стандартно для +-каркасов: вертикаль + горизонталь, две диагонали.
- FabKit: расширение L-mitre на 4 truby (выделение 4 → авто-detect).

### One-through cross (1 сквозная + 2 butt + 1 butt с другой стороны)
- Одна труба проходит без cut'а; остальные три butt-joint к ней.
- Используется когда главная труба значительно толще.
- FabKit: может реализоваться через комбинацию T-joint butt'ов.

**FabKit CAD приоритет:** этап 4, после T-joint.

---

## 6. Y / K joints (фермы)

Y-joint и K-joint — стыки brace'ов с chord в плоских и пространственных
фермах. Геометрия описывается отдельной literature (EN 1993-1-8, AISC 360).

### Y-joint
- Chord (горизонтальная труба) + 1 brace под углом β к chord axis.
- Brace cut: либо butt (mitre под 90° + β), либо envelope cope.
- Strength formulas — chord plastification, chord side wall failure, etc.

### K-joint
- Chord + 2 brace'а с одной стороны, симметрично.
- Geometry: gap или overlap между brace'ами на chord'е.
- Strength heavily depends on brace-to-chord ratio (β = b_brace / b_chord)
  и chord wall thickness ratio.

**Использование в продукте:** в проектах заказчика-0 (мебель + рамы)
ферм пока не было, поэтому это **низкий приоритет**. Когда появятся —
вернёмся к этому разделу с production-ready формулами.

---

## 7. Круглая труба (round tube)

Круглая профильная труба (ГОСТ 10704-91 — электросварная, ГОСТ 8732-78 —
бесшовная) — сечение D × t. В реальной поставке заказчика-0 пока не
встречалась, но MetalFab должен её поддержать (часто заказывается
для перил, ограждений, оборудования).

### 7.1. Round-on-round mitre (L-corner 90°)
- Mitre cut одной плоскостью на 45° даёт **эллиптический** контур
  на surface цилиндра.
- Полуоси эллипса: `D/2` (малая, по плоскости круга) и
  `(D/2)/cos(45°) = D/(2√2)` ≈ 0.707·(D/2)... wait. Если плоскость
  под углом α к ⟂-сечению, эллипс имеет малую полуось `D/2` и большую
  `(D/2)/sin(90°−α) = (D/2)/cos(α)`. Для α=45°: большая полуось
  `D/(2·cos(45°)) = D·√2/2`. Большая ось параллельна tilt direction.

### 7.2. Round-on-round T-joint (cope / fishmouth)
- Brace round D_b mounts perpendicular to chord round D_c.
- Cut surface на конце brace'а — синусоидальная кривая («fishmouth»):
  `z(θ) = R_c − sqrt(R_c² − R_b²·cos²(θ))`, где θ — angular position
  по периметру brace.
- При β ≠ 90° (Y-joint) формула усложняется (rotation matrix).
- Generation: классическая «pipe coping» геометрия, описанная в любом
  HSS-handbook'е (AISC 360 chapter K) и реализованная в Friendess
  CypTube и других tube CAM. **Не plane cut** — это essential difference
  с rect/square trubами.

### 7.3. Production
- Laser tube cutter обязателен.
- Mitre saw на round тоже работает (для plane mitre), но НЕ для cope.
- Plasma — да, но качество кромки хуже.

**FabKit приоритет:** низкий. Реализуем после rect/square закроем
все варианты L/T/X.

---

## 8. Production aspects: сварка и допуски

### 8.1. Длина сварного шва

Для L-mitre 90° (rect W×H):
- Периметр поперечного сечения: `2·(W+H)`.
- Длина сварного шва по контуру cut'а: `2·(W+H)/cos(α) = 2·(W+H)·√2` при 45°.
- Для 60×60 → шов 60×4·√2 ≈ 339 мм.

Это база для оценки трудоёмкости сварки и расчёта количества проволоки/электродов.

### 8.2. Подготовка кромок (chamfer, разделка)

Для **толстостенных** труб (t > 4 мм) под полупроникающий или
полнопроникающий шов нужна **разделка**:
- V-разделка (углы стенок скошены под 30°) — для 4 < t ≤ 8 мм.
- X-разделка (двусторонняя V) — для 8 < t ≤ 16 мм с двусторонним
  доступом.
- ГОСТ 14771-76 «Сварка в защитных газах» — формы разделки.

**Для FabKit на этом этапе:** разделку НЕ моделируем (LOD-2 будет ≤4 мм
толщин в основном). Когда появятся толстые трубы — добавим параметр
`chamfer_angle_deg` в attribute_dictionary.

### 8.3. Допуски на размер и углы

**ГОСТ 30245-2003** допуски (профильная труба):
- Размер сечения W, H: ±0.5 мм при W≤50; ±0.8 мм при 50<W≤100; ±1.0 мм
  при W>100.
- Толщина t: ±10% от номинальной.
- Длина: ±3 мм при L≤6 м.

**Допуски на mitre angle при production:**
- Mitre saw с угловым шаблоном: **±0.5°**.
- Laser tube cutter: **±0.1°** (digital control).
- Plasma: **±1°**.

**Practical implication для FabKit:**
- Геометрию модели ВЕДЁМ в номинальных размерах.
- При проектировании предусматриваем сборочный gap **1–2 мм** в
  ответственных стыках для compensation tolerance + thermal expansion +
  weld bead width.
- Опциональный параметр `joint_gap_mm` в FabKit CAD: shorten каждую
  трубу дополнительно на (joint_gap / 2) — TODO для будущего.

### 8.4. Last-pass weld bead width
- MIG/MAG: 4–8 мм ширина шва.
- TIG: 2–4 мм.
- Это «съедает» геометрию — при близком расположении труб (clearance
  < weld bead width) сварной шов перекрывается с соседним → дефект.

---

## 9. Сводная таблица: профиль × тип стыка → реализация в FabKit

| Профиль ↓ / Стык → | L-corner 90° | L-corner ≠90° | T-joint butt | T-joint notch | T-joint mortise | X-cross | Y/K (фермы) |
|---|---|---|---|---|---|---|---|
| **Rect (W×H)** | ✅ v0.11.5 (mitre 45/45 + trim) | ⚠️ TODO bug в формуле α при θ>90° | 🔜 этап 2 (mitre=0) | 🔜 этап 3 (envelope cope) | 🟡 не приоритет | 🔜 этап 4 | ⏸ далеко |
| **Square (W=W)** | ✅ как rect (W=H) | ⚠️ TODO | 🔜 этап 2 | 🔜 этап 3 | 🟡 не приоритет | 🔜 этап 4 | ⏸ далеко |
| **Round (D)** | 🟡 mitre plain plane возможен (даёт эллипс) | 🟡 same | 🟡 mitre=0 simple | 🔴 fishmouth cope — нужен отдельный generator | ⏸ далеко | 🔜 после rect-X | ⏸ далеко |

Легенда:
- ✅ реализовано
- 🔜 на ближайшем этапе
- 🟡 возможно, но не приоритет
- ⚠️ известный баг
- 🔴 требует separate generator (cope cut, не plane)
- ⏸ pending other features

---

## 10. Связь с FabKit CAD tool

### Текущее состояние (v0.11.5)

**Что работает:**
- Selection-based detection: 2 выделенных rect_tube DC → joint detected
  по closest endpoints.
- Joint angle θ = угол между axes (через `axis_a.dot(axis_b).abs`).
- Mitre angle α = θ/2 (для θ ≤ 90° — корректно).
- Tilt direction = вектор от joint к far_end other tube, projected на
  cross-section plane self tube ([fabkit_cad_tool.rb:333](../../plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb)).
- Trim mode (default ON, T toggle): caждая труба shortened/extended до
  axis intersection (`Geom.closest_points`) перед mitre — `length_mm`
  обновляется.
- Vertex displacement в [rect_tube_mitre.rb](../../plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube_mitre.rb)
  смещает вершины cut endpoint'а по `dz = sign · (pos · tilt_dir) · tan(α)`.

**Ограничения:**
- Только rect_tube (square = частный case rect).
- Только L-mitre 2-tube selection.
- Symmetric mitre (одинаковый α на обеих).
- При θ > 90° — баг: используется `acos(dot.abs)` вместо `acos(dot)`,
  что даёт острый угол, даже если реальный обтуз. Mitre получается
  «not as expected».

### Roadmap

| Этап | Содержание | Приоритет | Версия |
|---|---|---|---|
| 1 | L-mitre rect 90°/<90° symmetric + trim | ✅ done | v0.11.5 |
| 1.1 | Fix θ > 90° (тупой L-corner) | ⚠️ TODO | tbd |
| 2 | T-joint butt (perpendicular cut на brace) | 🔜 next | v0.12.x |
| 3 | T-joint notch (envelope cope rect-on-rect) | 🔜 | v0.13.x |
| 4 | X-cross 4-tube symmetric | 🔜 | v0.14.x |
| 5 | Asymmetric L-mitre (разные сечения) | 🟡 | tbd |
| 6 | Round-tube L-mitre (plane cut → эллипс) | 🟡 | v0.15.x |
| 7 | Round-on-round fishmouth cope | 🟡 | v0.16.x |
| 8 | Y / K фермы | ⏸ | tbd |

### Где «правильная геометрия» из этого документа конвертируется в код

| Раздел документа | Файл |
|---|---|
| 3.1, 3.2 (rect/square mitre formulas) | [rect_tube_mitre.rb](../../plugin-sketchup/src/nn_fabkit/metalfab/profile_generator/rect_tube_mitre.rb) — `apply_mitre` |
| 3.3 (length после trim) | [fabkit_cad_tool.rb](../../plugin-sketchup/src/nn_fabkit/metalfab/tools/fabkit_cad_tool.rb) — `compute_trim` |
| 3.4 (эллипс на скруглении для NC) | [rect_tube.py](../../app-desktop/nc-export/src/nn_fabkit_nc_export/tube/rect_tube.py) — `rect_tube_hollow_mitre_xl_45` |
| 4 (T-joint geometry) | TODO — будущий `t_joint.rb` |
| 5 (X-cross) | TODO — будущий `x_cross.rb` |
| 7 (round) | TODO — будущий `round_tube.rb`, `round_tube_cope.rb` |

---

## 11. Open questions

1. **Тупой L-corner (θ > 90°)** — текущая формула в FabKit CAD сводит
   все углы к острому через `acos(dot.abs)`. Для θ = 120° даём mitre
   60° вместо 30°. Fix: убрать `.abs`, выбирать угол с учётом
   end_axis sign.

2. **Skew axes** — оси двух труб не пересекаются точно (есть offset в
   3D). `Geom.closest_points` возвращает 2 разные точки. Текущая
   FabKit CAD trim'ит каждую трубу до СВОЕЙ closest point — joint
   получается с visible зазором ~skew distance. Альтернативы:
   (а) trim'ить обе до midpoint между closest points (даёт
   симметричный joint, но визуальный skew виден на side faces);
   (б) выводить ошибку «axes не пересекаются — настрой геометрию».

3. **Asymmetric mitre** (разные сечения) — какая bisecting plane?
   Простейший подход — всё ещё bisects угол axes, mitre = θ/2 на
   обеих, но external contours разной высоты. Альтернатива: подобрать
   углы так, чтобы внешние грани совпали — даёт unequal mitre angles
   (нестандартно, нет в катало production tooling).

4. **Joint gap** для production — на сколько укорачивать каждую
   трубу под weld bead + tolerance (typical 1–2 мм). Параметр
   `joint_gap_mm` в FabKit CAD VCB — TODO.

5. **Round tube fishmouth** — нужен ли отдельный subagent для
   generation cope cut по координатам, или хватает analytical formula
   в `round_tube_cope.rb`? Зависит от complexity (Y-joint с β ≠ 90°
   — нетривиальная геометрия).

6. **Y/K joint formulas** — после первого реального заказа с фермой
   из заказчика-0. Сейчас scope не покрыт.

---

## 12. Источники

### Российские стандарты
- ГОСТ 30245-2003 — Профили стальные гнутые замкнутые сварные.
  Сортамент. (См. [11-gost-profile-tubes-radii.md](11-gost-profile-tubes-radii.md))
- ГОСТ 8639-82 — Трубы стальные квадратные. Сортамент.
- ГОСТ 8645-68 — Трубы стальные прямоугольные. Сортамент.
- ГОСТ 10704-91 — Трубы стальные электросварные прямошовные. Сортамент.
- ГОСТ 8732-78 — Трубы стальные бесшовные горячедеформированные. Сортамент.
- ГОСТ Р 53383-2009 — Сварные конструкции. Сварные соединения. Общие
  требования.
- ГОСТ 14771-76 — Сварка в защитных газах. Соединения сварные. Основные
  типы, конструктивные элементы и размеры.

### Международные standards
- AISC 360 — Specification for Structural Steel Buildings (chapter K —
  HSS connections, welded joints).
- EN 1993-1-8 — Eurocode 3: Design of steel structures, Part 1-8:
  Design of joints (хорошие формулы для K/N/X-joints на CHS/RHS).
- AWS D1.1 — Structural Welding Code.
- CIDECT Design Guides Vols 1, 3 — Design of Welded Hollow Section
  Joints (rectangular and circular).

### Tool-specific
- Friendess CypTube manual — feature recognition rules, supported cut
  types (mitre planar, fishmouth cope, hole patterns).
- Lantek Flex3d Pipe — referenced для plane-cut + cope generation
  algorithms.

### Internal
- [11-gost-profile-tubes-radii.md](11-gost-profile-tubes-radii.md) — радиусы
  скругления выводят, как cut проходит через corners.
- [10-iges-for-tube-nc.md](10-iges-for-tube-nc.md) — IGES Type 110
  (line) и Type 100 (arc) для трансляции cut geometry в NC.
- [09-architecture-decisions.md](09-architecture-decisions.md) — ADR-014
  (LOD-1, LOD-2 определения), ADR-017 (свой IGES-конвертёр в MVP).
