# 10. IGES для ЧПУ-обработки профильной трубы

> Справочник для разработчика IGES-конвертёра в составе NN FabKit (см. ADR-017).
> Назначение — практический материал, на основании которого можно написать
> рабочий writer для standalone-приложения, экспортирующий LOD-1 геометрию
> прямоугольной/квадратной профильной трубы (ГОСТ 30245) в формат, принимаемый
> трубопрофилерезами заказчика-0 и аналогичными станками рынка РФ/СНГ.
>
> Дата составления: 2026-04-25. Кодировка: UTF-8 без BOM.
>
> **Не** воспроизводит полную спецификацию IGES 5.3 — только подмножество,
> релевантное для прямой профильной трубы (LOD-1: 4 плоских грани + 4
> цилиндрических скругления + 2 торца). Для более сложных деталей (отверстия,
> резы под углом, fish-mouth) — отдельные разделы с пометкой «расширение».

## Содержание

1. [IGES Entity Types для трубного NC](#1-iges-entity-types-для-трубного-nc)
2. [Что читают трубопрофилерезы (рынок РФ/СНГ)](#2-что-читают-трубопрофилерезы-рынок-рфснг)
3. [Практика генерации IGES для труб](#3-практика-генерации-iges-для-труб)
4. [Минимально работоспособное подмножество](#4-минимально-работоспособное-подмножество)
5. [Альтернативы IGES](#5-альтернативы-iges)
6. [Библиотеки и инструменты](#6-библиотеки-и-инструменты)
7. [Источники](#7-источники)
8. [Рекомендации для нашего конвертёра](#8-рекомендации-для-нашего-конвертёра)

---

## 1. IGES Entity Types для трубного NC

IGES 5.3 определяет около 150 типов сущностей. Для трубного NC нужно знать
сравнительно небольшое подмножество, разделённое на четыре уровня:

| Уровень | Что описывает | Достаточно для |
|---|---|---|
| Wireframe | каркас (рёбра, дуги) | визуальный контроль, простейшие 2D-операции |
| Surface | независимые поверхности (без топологии) | 3D-резка по контурам, если станок умеет «лечить» зазоры |
| Trimmed Surface | поверхности с границами | стандартный путь IGES для тел |
| BREP (MSBO) | полноценное B-Rep тело | NC-программирование с feature recognition |

Текущий MVP NN FabKit (v0.4.0) находится на уровне **wireframe** —
[wireframe.rb](../../plugin-sketchup/src/nn_fabkit/metalfab/iges_exporter/wireframe.rb).
Для NC этого недостаточно — нужно как минимум **trimmed surface model**, а в
идеале — **BREP solid**.

### 1.1. Wireframe-сущности

#### Type 110 — Line Entity

Прямая в 3D, заданная двумя точками.

**Параметры (P-section):**

```
110, X1, Y1, Z1, X2, Y2, Z2;
```

Реальный пример из сэмпла Wikipedia (см. раздел [Источники](#7-источники)):

```
110,0.,-1.,0.,5.,-1.,0.,0,0;                                           9P      5
```

Это линия от `(0, -1, 0)` до `(5, -1, 0)`. Последние два нуля — счётчики
произвольных текстовых указателей (back-pointers); для большинства экспортёров
их пишут как `0,0`.

**Когда использовать:** все прямые рёбра трубы (стороны прямоугольного
сечения, продольные рёбра между торцами). В нашем wireframe-экспортёре —
основной примитив.

#### Type 100 — Circular Arc Entity

Дуга в плоскости, параллельной XT-YT (где XT-YT — плоскость, заданная
transformation matrix данной сущности или базовой системой координат).

**Параметры:**

```
100, ZT, X1, Y1, X2, Y2, X3, Y3;
```

- `ZT` — Z-координата плоскости дуги (в системе сущности).
- `(X1, Y1)` — центр дуги.
- `(X2, Y2)` — стартовая точка.
- `(X3, Y3)` — конечная точка.
- Радиус выводится как `R = sqrt((X2-X1)² + (Y2-Y1)²)`.
- Дуга всегда обходится **против часовой стрелки** (CCW) от старта к концу.

Реальный пример:

```
100,0.,0.,0.,0.,1.,0.,-1.,0,0;                                         5P      3
```

Дуга в плоскости `Z = 0`, центр `(0, 0)`, старт `(0, 1)`, конец `(0, -1)`.
Радиус = 1, обход CCW даёт левую полуокружность от северного полюса к
южному через западный.

**Важно:** Type 100 — двумерная сущность в своей собственной системе
координат. Чтобы поставить её в произвольную плоскость 3D-пространства,
нужна Transformation Matrix Entity (Type 124) и её pointer в DE-line 1
field 7. Для скруглений углов профиля трубы в плоскостях `z=0` и `z=length`
матрица не нужна — `ZT` достаточно.

#### Type 116 — Point Entity

Точка в 3D. `116, X, Y, Z, P;` где `P` — указатель на свойство (обычно 0).
Для NC-trubы используется редко; в трубном wireframe не нужен.

### 1.2. Surface-сущности

#### Type 120 — Surface of Revolution

Поверхность вращения. Для прямой трубы и её цилиндрических углов **не самый
естественный выбор** — труба не есть тело вращения относительно одной оси
(угловое скругление — да, но всю трубу так не описать).

**Параметры:**

```
120, AXIS_PTR, GENERATRIX_PTR, START_ANGLE, TERM_ANGLE;
```

- `AXIS_PTR` — указатель на Type 110 (Line), задающий ось вращения.
- `GENERATRIX_PTR` — указатель на образующую (Line, Arc, Spline).
- Углы — в радианах.

#### Type 122 — Tabulated Cylinder

«Цилиндр по направляющей» — поверхность, образованная переносом
направляющей кривой вдоль вектора. Это **главная surface-сущность для
прямой профильной трубы**: профиль торца — directrix, длина трубы — вектор.

**Параметры:**

```
122, DIRECTRIX_PTR, LX, LY, LZ;
```

- `DIRECTRIX_PTR` — указатель на кривую (composite curve, спайн, дуга, линия).
- `(LX, LY, LZ)` — координаты конечной точки векторной образующей; начальная
  точка совпадает со стартом directrix. Direction вычисляется как
  `terminate_point - directrix_start`.

**Применение к трубе:**
- Профиль трубы (rounded rectangle) собирается как **Composite Curve (Type
  102)** из 4 линий + 4 дуг в плоскости `z=0`.
- Tabulated Cylinder с этим профилем как directrix и `(0, 0, length)` даёт
  внешнюю поверхность стенки трубы.
- Аналогично — внутренняя поверхность (профиль внутреннего контура).

Это эффективно: одна Type 122 заменяет 4 плоскости + 4 цилиндра.

**Подводный камень:** не все импортёры одинаково реагируют на Type 122,
особенно когда directrix — composite curve со сменой типов. По форумным
сообщениям, ArTube (BLM) и cncKad (Metalix) обрабатывают её корректно;
по китайским системам (Bochu/FSCUT) — данных нет, скорее всего им проще
скормить набор Type 144.

#### Type 128 — Rational B-Spline Surface (NURBS)

Универсальная NURBS-поверхность. Для прямой трубы — **избыточно**: NURBS-
описание плоской грани и идеального цилиндра менее точно, чем аналитическое.
Использовать только если станок не умеет читать Type 120/122 (редкий случай).

#### Type 190 — Plane Surface

Плоскость, заданная точкой и нормалью. Для торцов трубы (flat end caps) —
естественный выбор, но обычно используется в составе trimmed surface
(Type 144), а не самостоятельно.

#### Type 108 — Plane Entity

Внимание: это другая сущность, не путать с Type 190.
- Type 108 — плоскость как curve-bounded surface, исторически до 5.3.
- Type 190 — современная замена.
- На практике большинство экспортёров пишут Type 144 (trimmed surface) с
  pointer на «бесконечную» поверхность.

### 1.3. Trimmed Surface

#### Type 142 — Curve on a Parametric Surface

Связь «кривая — поверхность». Не геометрия сама по себе, а указатель: «вот
эта 3D/2D-кривая лежит на вот этой поверхности и может использоваться как
trim curve».

**Параметры:**

```
142, CRTN, SPTR, BPTR, CPTR, PREF;
```

- `CRTN` — как создавалась (0 — неизвестно, 1 — проекция, 2 — пересечение,
  3 — изопараметрическая).
- `SPTR` — указатель на surface (Type 120/122/128/144/190…).
- `BPTR` — указатель на parametric curve (в UV-пространстве surface), 0 если нет.
- `CPTR` — указатель на 3D model-space curve, 0 если нет.
- `PREF` — какое представление считается основным (0 — на усмотрение приёмника,
  1 — SPTR/BPTR, 2 — CPTR, 3 — оба эквивалентны).

**Замечание:** для надёжного импорта в большинство CAD/CAM пишут **обе**
кривые (BPTR и CPTR), `PREF=3`.

#### Type 144 — Trimmed (Parametric) Surface

«Поверхность с границами». Это **главная сущность IGES для surface-моделей
тел**: пишет 95% CAD-экспортёров, читают практически все импортёры.

**Параметры:**

```
144, PTS, N1, N2, PTO, [PTI_1, PTI_2, ..., PTI_N2];
```

- `PTS` — указатель на surface entity.
- `N1` — флаг внешней границы:
  - `0` — внешняя граница совпадает с естественной границей surface.
  - `1` — внешняя граница задана `PTO`.
- `N2` — число внутренних границ (отверстий).
- `PTO` — указатель на curve-on-surface (Type 142), задающую внешний контур.
- `PTI_*` — указатели на curves-on-surface для отверстий.

**Известная проблема ambiguity:** для замкнутых surface (сфера, цилиндр)
IGES не определяет однозначно, какая сторона trim curve — «внутри», какая —
«снаружи». Это решается ориентацией кривых и историческими конвенциями
читающего CAD; разные системы могут понимать одно и то же по-разному.
[Wiki Talk:IGES](https://en.wikipedia.org/wiki/Talk:IGES) приводит пример
со сферой и двумя плоскостями.

**Для прямой трубы:** ambiguity не возникает — trim curves на
не-замкнутом цилиндрическом сегменте однозначны, и боковые стенки
прямоугольной трубы — открытые цилиндры/плоскости.

### 1.4. BREP (Manifold Solid B-Rep) — топологическая модель

#### Type 186 — Manifold Solid B-Rep Object (MSBO)

«Тело», заданное замкнутой оболочкой и набором пустот (внутренних shells).

**Параметры:**

```
186, SHELL_PTR, SOF, N, [VOID_SHELL_1, VOF_1, VOID_SHELL_2, VOF_2, ...];
```

- `SHELL_PTR` — указатель на Type 514 (Shell), внешняя оболочка.
- `SOF` — orientation flag (1 — нормали shell наружу).
- `N` — число void shells (внутренних полостей).
- Затем `N` пар (указатель на shell, флаг ориентации).

Для **профильной трубы** void shell — не пустота в смысле «отверстие в
толще стенки». Труба — это солид с внутренним пустым объёмом, ограниченным
inner shell. То есть: outer shell описывает наружные грани (4 плоскости + 4
скругления + 2 торца), inner shell — внутренние (4 + 4 + 2). Между ними —
толщина стенки.

**Альтернатива:** многие CAD-экспортёры пишут трубу не как один Type 186
с outer + inner shell, а как **два separate solids** или **closed surface
model без BREP**. Это упрощает экспорт, но усложняет feature recognition
у импортёра.

#### Type 502 — Vertex List

Список 3D-точек, на которые ссылаются edges. Form 1 — обычный список.

**Параметры:**

```
502, N, X1, Y1, Z1, X2, Y2, Z2, ..., XN, YN, ZN;
```

#### Type 504 — Edge List

Список рёбер. Каждое ребро — 5 параметров.

**Параметры (per edge):**

```
CURVE_PTR, START_VLIST_PTR, START_VINDEX, END_VLIST_PTR, END_VINDEX
```

- `CURVE_PTR` — указатель на 3D-кривую (Type 110, 100, 102, 126…).
- `START/END_VLIST_PTR` — указатель на Type 502 vertex list.
- `START/END_VINDEX` — индекс в этом списке (1-based).

Form 1 содержит N edges:

```
504, N, C1, V1S, I1S, V1E, I1E, C2, V2S, I2S, V2E, I2E, ...;
```

#### Type 508 — Loop

Замкнутый цикл рёбер на грани. Может быть outer (внешний контур грани)
или inner (отверстие в грани).

**Параметры:**

```
508, N, [TYPE_i, EDGE_PTR_i, EDGE_INDEX_i, ORIENT_i, NPC_i, [PCS_i...]]
```

- `N` — количество edges в loop.
- Для каждого edge: тип (0 — edge, 1 — vertex), указатель, индекс,
  ориентация, число parameter-space кривых, и сами кривые.

#### Type 510 — Face

Грань, заданная surface + outer loop + inner loops.

**Параметры:**

```
510, SURFACE_PTR, N, OF, LOOP_PTR_1, ..., LOOP_PTR_N;
```

- `SURFACE_PTR` — указатель на surface.
- `N` — число loops.
- `OF` — outer loop flag (1 если первый loop — outer).
- `LOOP_PTR_*` — указатели на Type 508.

#### Type 514 — Shell

Замкнутая оболочка из faces.

**Параметры:**

```
514, N, FACE_PTR_1, OF_1, ..., FACE_PTR_N, OF_N;
```

- `N` — число faces.
- Для каждой face: указатель и orientation flag (1 — нормаль наружу shell).

### 1.5. Вспомогательные сущности

#### Type 102 — Composite Curve

Цепочка кривых, соединённых концами. Для профиля трубы — самый
естественный способ описать rounded rectangle.

**Параметры:**

```
102, N, CURVE_PTR_1, CURVE_PTR_2, ..., CURVE_PTR_N;
```

Кривые должны быть «согласованы» — конец одной = начало следующей.

#### Type 124 — Transformation Matrix

4x3 матрица (3x3 rotation + translation).

**Параметры:**

```
124, R11, R12, R13, T1, R21, R22, R23, T2, R31, R32, R33, T3;
```

Применение: `[X', Y', Z']^T = R · [X, Y, Z]^T + T`.

В DE-section field 7 каждой сущности — указатель на Type 124, который
применяется к этой сущности перед интерпретацией.

Для трубы, выровненной по Z, без смещения — Type 124 не нужен (пишем 0
в field 7).

#### Type 314 — Color Definition

Палитра RGB. В принципе для NC цвет неважен, но если станок понимает
цвета как «стороны/торцы» (редкий случай у китайских систем), можно
маркировать.

```
314, R, G, B, [NAME_HOLLERITH];
```

### 1.6. Сравнение представлений: Plane vs Cylinder для прямой трубы

| Подход | Сущности | Плюсы | Минусы |
|---|---|---|---|
| Wireframe (текущий MVP) | 110 + 100 | очень просто, любой viewer прочитает | NC не получит surface data |
| Pure surface | 4 × 144 (plane) + 4 × 144 (cylinder) + 2 × 144 (endcap) | чисто, легко писать | каждая поверхность — независима, нет топологии |
| Tabulated cylinder | 122 (outer) + 122 (inner) + 2 × 144 (endcap) | компактно, аналитически точно | composite curve directrix может не пониматься некоторыми импортёрами |
| BREP MSBO | 186 + 514 + 6 × 510 (внеш) + 6 × 510 (внутр) + edges + vertices | полная топология, лучший feature recognition | сложно писать, легко допустить ошибку ориентации |

**Рекомендация для MVP** (см. раздел 8) — surface model на Type 144 без
BREP. Это наименьший объём кода при сохранении readability большинством
систем.

### 1.7. Торец трубы (flat end cap)

Торец — плоская грань с внешним контуром rounded rectangle и **одним
внутренним loop** (контур внутреннего отверстия).

Для surface-only:
- Surface — Type 190 (Plane) или эквивалентная неограниченная плоскость.
- Trimmed surface (Type 144):
  - `N1=1` (outer boundary не-natural).
  - `PTO` — указатель на 142, ссылающийся на composite curve (102) outer
    contour.
  - `N2=1`.
  - `PTI_1` — указатель на 142 (composite curve inner contour, обходимый
    в **противоположном** направлении).

### 1.8. Прямой рез по нормали vs ус под углом (mitered) — расширение

Для прямого реза трубы под углом 90° (это наш MVP) endcap-плоскость
ортогональна оси. Если рез под углом α (миттер):
- Плоскость endcap — наклонена.
- Outer trim curve — это пересечение наклонной плоскости с боковой
  поверхностью трубы. Для прямоугольной трубы со скруглёнными углами это
  composite curve из 4 наклонных линий + 4 эллиптических дуг (потому что
  плоскость, наклонённая к цилиндру, даёт эллипс, не дугу).
- В IGES эллипс — Type 104 (Conic Arc, form 1) или приближение через NURBS
  (Type 126).

**Это не входит в MVP NN FabKit.** Появится при поддержке угловых резов.

### 1.9. BREP solid vs surface model — что нужно для NC

Опросы операторов трубопрофилерезов (см. ссылки в разделе 7) дают
следующую картину:

| Класс CAM | Нужен BREP? | Минимум | Источник |
|---|---|---|---|
| BLM ArTube | желательно | corret surface model с замкнутым контуром | [BLM ArTube](https://www.blmgroup.com/software/artube) |
| Metalix MTube | да | trimmed surface OR BREP | [Metalix MTube](https://www.metalix.net/product/mtube/) |
| Lantek Flex3D Tubes | желательно | SAT/IGES surface model | [Lantek Flex3D Tubes](https://www.lantek.com/us/tubes-pipes-cad-cam-nesting-software) |
| HGG ProCAM | нет (ProCAM преобразует в DSTV) | DSTV предпочтительнее | [HGG ProCAM](https://www.hgg-group.com/procam/) |
| Bochu/FSCUT (TubesT) | нет (упрощённое представление) | DXF preferred; IGS как «basic format» | [TubesT](https://cypcut.ru/tubest/) |
| TRUMPF TruTops | да | STEP > IGES; BREP ожидается | [TRUMPF PRAXIS CAD](https://trumpf-flux.com/trumpf-praxis-cad/) |

**Вывод:** surface model достаточна для большинства машин. BREP даёт
лучший feature recognition, но требует существенно больше кода. Для MVP
заказчика-0 — surface model (Type 144) без BREP.

---

## 2. Что читают трубопрофилерезы (рынок РФ/СНГ)

### 2.1. Распространённые модели в РФ/СНГ

| Бренд / модель | Происхождение | Управляющая система | CAM-софт | Поддерживаемые форматы импорта |
|---|---|---|---|---|
| BLM Group LT-серия (LT5/LT7/LT8/LT12/LT14/LT24) | Италия | Siemens 840D / собственная | ArTube + ProTube | STEP, IGES, XT (Parasolid), IFC |
| TRUMPF TruLaser Tube 5000/7000 | Германия | TruControl | TruTops Tube + TruTops PFO | DXF, DWG, DXB, STEP, IGES, ACIS, Inventor, CATIA, Creo, I-deas, Solid Edge, SolidWorks (через PRAXIS CAD) |
| Mazak FT-150 / Optiplex 3D | Япония | Mazatrol PreView | MazaCAM | STEP, IGES (через Mazatrol Tube Module) |
| Bystronic ByTube 130 / ByTube Star | Швейцария | ByVision | BySoft 7 (CAM Tube) | UG/NX, IFC, DSTV, PRC, VDAFS, STEP, IGES, SolidWorks add-in |
| Han's Laser Velocity-Q5 / Velocity-T | Китай | собственная (Friendess FSCUT3000/5000) | TubesT / TubePro / CypTube | IGS (IGES), SAT, DXF; не STEP в большинстве конфигураций |
| Bodor T-серия (T230/T260/T350) | Китай | Bochu FSCUT3000/5000 | TubesT / BodorWorks | DXF, AI, PLT, Gerber; IGS — частично; STEP не подтверждён |
| Golden Laser P-серия | Китай | Bochu / собственная | TubesT / TubePro | IGS, SAT, DXF |
| Penta-Chutian Laser | Китай | собственная | proprietary | DXF, IGS |
| HGG SPC, RPC, PCL-series (профилерезы) | Нидерланды | собственная | ProCAM | DSTV (predominant), STEP, IGES (через ProCAM) |
| Vernon Tool | США | Hypertherm | PypeServer | DSTV, IGES, STEP (через PypeServer) |
| Прима Power LaserCell, LaserGenius (на трубу — не основной профиль) | Финляндия | Tulus | NCExpress-T | STEP, IGES |

**Источники:**
- [BLM ArTube](https://www.blmgroup.com/software/artube)
- [TRUMPF PRAXIS CAD](https://trumpf-flux.com/trumpf-praxis-cad/)
- [Bystronic BySoft CAM](https://www.bystronic.com/en/products/software/BySoft-CAM.php)
- [TubesT (Friendess/Bochu)](https://cypcut.ru/tubest/)
- [HGG Profile Cutting](https://www.hgg-group.com/cutting-services/profile-cutting/)
- [Lantek Flex3D Tubes](https://www.lantek.com/us/tubes-pipes-cad-cam-nesting-software)
- [Metalix MTube — Tube Import](https://www.metalix.net/products/mtube/tube-import/)

### 2.2. Заказчик-0 — что у него стоит

По данным сессий с заказчиком-0 (см. Notion `📐 SketchUp — продукт`):
- **Два станка**, оба читают IGES (это критическое для нас условие, см.
  ADR-017).
- Конкретные модели не названы публично (NDA), но по косвенным признакам —
  **из китайского сегмента** (FSCUT-семейство контроллеров, TubesT-
  workflow). Это подтверждается тем, что заказчик упоминает «трубный
  модуль Bochu» и периодически говорит «грузим .igs».

**Следствие для нашего конвертёра:** целевой rendering — то, что **гарантированно
открывается в TubesT/TubePro**. Это упрощает задачу:
- TubesT принимает IGS «basic level» — surface model без BREP.
- Composite curves (Type 102) не любит — лучше писать каждую кривую
  отдельно.
- Единицы только мм (`unit_flag=2`).
- Версия IGES — 5.3 (`version_flag=11`).
- Drafting standard — «none» (`drafting_flag=0`).

### 2.3. Поддерживаемое подмножество IGES 5.3

По данным дилеров и форумов, среднестатистический трубный CAM-софт
читает (с приоритетом сверху вниз):

| Entity | Читается | Комментарий |
|---|---|---|
| 100 (Arc) | да | везде |
| 110 (Line) | да | везде |
| 102 (Composite Curve) | в основном да | TubesT — нет |
| 104 (Conic Arc) | частично | для эллипсов; китайские системы — нет |
| 116 (Point) | да | используется редко |
| 120 (Surface of Revolution) | в большинстве | TubesT — нет |
| 122 (Tabulated Cylinder) | да | везде |
| 124 (Transformation Matrix) | да | везде |
| 126 (B-Spline Curve) | да | NURBS |
| 128 (B-Spline Surface) | да | NURBS |
| 142 (Curve on Surface) | да | пишут не всегда корректно |
| 144 (Trimmed Surface) | **да** | основной surface-носитель |
| 186 (MSBO) | переменно | TRUMPF/BLM — да; китайские системы — часто игнорируют |
| 314 (Color) | да | визуально |
| 502/504/508/510/514 (BREP) | если 186 поддерживается | связка |

«[MSBO] entity remains poorly implemented by CAD exporters»
([cadinterop.com IGES neutral format](https://www.cadinterop.com/en/formats/neutral-format/iges.html)),
плюс существует много CAM-систем, которые BREP полностью игнорируют, —
ещё один аргумент за surface-only подход.

### 2.4. Известные несовместимости и требования к G-section

Из форумных данных и документации:

- **Точность чисел.** Trumpf и BLM требуют не более 1e-6 mm рассогласования
  концов кривых в curve chain. Наша двойная точность (15 значащих цифр)
  это покрывает с запасом.
- **Записи > 80 символов.** Жёсткая ошибка во всех импортёрах. Любой
  writer должен следить за col 73-80 как за «sacred zone».
- **CRLF vs LF.** На Windows-станках встречаются строгие парсеры,
  ожидающие CRLF. На FreeCAD/CAD Assistant — обычно всё равно. Безопасно
  писать CRLF.
- **BOM.** UTF-8 BOM в начале файла **ломает** некоторые парсеры
  (TubesT — да, по форумным сообщениям). Писать без BOM, ASCII-only.
- **Hollerith vs raw strings.** Все строковые поля в G-section должны
  быть Hollerith — `12HSomething.IGS`. Никаких кавычек.
- **Имя файла в G-section field 4** — некоторые импортёры пользуются
  им (а не реальным именем на диске). Лучше всегда заполнять.
- **`max_lines_per_drawing` (G-field 16).** Стандарт говорит 1, но
  большинство пишут «32» или «64». Импортёры обычно игнорируют.

### 2.5. Связанные CAM-системы (детальнее)

Кратко — что попадается в практике:

- **SolidWorks + Metalix cncKad**. Заказчик может моделировать в SW и
  выгружать IGES, дальше cncKad готовит NC. cncKad читает IGES без
  претензий, Type 144/186 — оба.
  ([cncKad Tube Import](https://www.metalix.net/products/mtube/tube-import/))

- **Radan**. Для труб поддержка появилась поздно; в основном
  ориентирован на лист.

- **Lantek Flex3D Tubes**. SAT-приоритет, IGS — чтение есть. Также есть
  CAD Add-Ins для нативных форматов SolidWorks/Solid Edge/Inventor.
  ([Lantek Flex3D Tubes](https://www.lantek.com/us/tubes-pipes-cad-cam-nesting-software))

- **BLM ArTube/Protube**. Самая «всеядная» по форматам. STEP — приоритет,
  но IGES читает корректно, в т.ч. из ниши «другой CAD ↔ ArTube».
  «ArTube can process all formats: STEP, IGES, XT and even IFC»
  ([BLM ArTube](https://www.blmgroup.com/software/artube)).

- **PypeServer (HGG / Vernon Tool)**. Промежуточная САМ — берёт STEP/
  IGES/DSTV и готовит NC под конкретный пайпопрофилерез.
  ([HGG Profile Cutting](https://www.hgg-group.com/cutting-services/profile-cutting/))

- **TubesT / TubePro / CypTube (Friendess/Bochu)**. Для рынка СНГ —
  доминирующий китайский стек. Импортирует IGS («basic format»), SAT,
  DXF. STEP — не во всех версиях.
  ([cypcut.ru/tubest](https://cypcut.ru/tubest/))

---

## 3. Практика генерации IGES для труб

### 3.1. Ориентация — ось трубы Z или X?

В IGES нет жёсткой конвенции. Распространены оба варианта:
- **Z-axis (наша конвенция)**. Профиль в плоскости XY, длина по Z. Это
  совпадает с конвенцией экструдеров и большинства tube-CAD.
- **X-axis (OCL / некоторые DC-плагины)**. Профиль в плоскости YZ, длина
  по X. Это конвенция OpenCutList и совпадает с правилом «длина = X»
  (см. [06-sortament-ontology.md](06-sortament-ontology.md)).

**Что выбрать для NN FabKit:** ось длины **по Z** в IGES, даже если в
SketchUp-плагине направление было другим. Причины:
- Большинство IGES viewers (CAD Assistant, FreeCAD) ориентированы на
  «вертикальный Z» при автокамере.
- TubesT/TubePro в обзоре трубы по умолчанию ставят ось вдоль Z.
- Конвертация SketchUp ↔ IGES — момент, где как раз и применяется
  единое преобразование осей.

### 3.2. Профиль сечения (outer + inner contour)

**Outer contour** — внешний rounded rectangle:
1. 4 прямых отрезка между точками касания скруглений.
2. 4 дуги (по 90°) в углах.

В Composite Curve (Type 102) — 8 элементов в порядке CCW:

```
right-mid → top-right corner arc → top edge → top-left arc → left edge →
bot-left arc → bottom edge → bot-right arc → right-mid (close)
```

**Inner contour** — аналогично, с уменьшенной шириной/высотой и радиусом
`r_inner = max(r_outer - wall, 0)`.

Direction: outer — CCW (нормали наружу), inner — **CW** (relative к outer)
для корректного hole-выреза в endcap-trim.

### 3.3. Единицы измерения в G-section

`unit_flag` (G-field 14) и `unit_name` (G-field 15):

| flag | name | значение |
|---|---|---|
| 1 | "INCH" | дюймы |
| 2 | "MM" | миллиметры |
| 3 | (имя пользовательское) | пользовательские |
| 4 | "FT" | футы |
| 5 | "MI" | мили |
| 6 | "M" | метры |
| 7 | "KM" | километры |
| 8 | "MILS" | тысячные доли дюйма |
| 9 | "MICRON" | микроны |
| 10 | "CM" | сантиметры |
| 11 | "UIN" | микродюймы |

**Для NN FabKit — всегда `2 / "MM"`**. Заказчик, ГОСТ, станки — всё в
миллиметрах.

### 3.4. Радиус гиба аналитически (Type 100) vs полигонально

Текущий wireframe.rb рисует углы как Type 100 — 4 дуги по 90°. Это
**аналитически точно**: импортёр получает идеальную окружность с
заданным центром и радиусом.

**Альтернатива** — полигональная аппроксимация радиуса 8-16 отрезками
(как делает SketchUp при экструзии). Минусы:
- Точность теряется (chord error ≈ r·(1−cos(π/N)), для r=3, N=8 это 0.057 мм).
- CAM системы вынуждены либо сглаживать, либо генерировать N сегментов
  G1.
- Размер файла растёт.

**Использовать всегда Type 100.** Только если станок не понимает дуги
(very unlikely для tube CAM) — переходить на NURBS или линии.

### 3.5. DP (Default Parameter) и точность для NC

В G-section есть три параметра, влияющих на точность:

- G-field 11 — `double_precision_significance` — обычно 15.
- G-field 19 — `min_resolution` — рекомендуется `0.001` для мм
  (0.001 мм = 1 мкм — точность станков плазма/laser).
- G-field 17 — `max_coordinate` — наибольшая ожидаемая координата;
  для трубы 12 м это `12000.0`.

Float-format в P-section: `"%.6f"` (6 знаков после точки) даёт
точность 1 нм при `unit=mm`. Это избыточно, но не вредно.

**Не использовать экспоненту** (`1.5E+02`). Стандарт это допускает, но
некоторые «бюджетные» парсеры, особенно китайские, спотыкаются на
`E`-нотации. Писать всегда desimal `150.0`.

**Не писать ведущий ноль или decimal point** жёстко: `1.0` — да,
`1.` — допустимо, `1` — допустимо, но безопаснее всегда с точкой.

### 3.6. Структура IGES-файла, сборка снизу вверх

При генерации файла стандартно идти **снизу вверх по dependencies**:

1. Vertices (только если BREP).
2. Curves (Type 110 lines, Type 100 arcs).
3. Composite curves (Type 102).
4. Surfaces (Type 122 tabulated cylinder, Type 190 plane).
5. Curves on surfaces (Type 142).
6. Trimmed surfaces (Type 144).
7. Faces / Loops / Edges (если BREP).
8. Shells (Type 514).
9. Solids (Type 186).

Каждая сущность получает **DE-pointer** (D-section sequence number — odd
numbers: 1, 3, 5, ...) и записывается в обе секции D и P.

В нашем wireframe.rb эта логика есть в упрощённом виде — только Type 110
и 100, никаких pointers между сущностями.

---

## 4. Минимально работоспособное подмножество

### 4.1. Минимальный entity set для прямой трубы (LOD-1)

Цель: чтобы трубопрофилерез **сам построил программу резки** на основе
геометрии. Это означает: импортёр должен распознать «эта деталь — отрезок
трубы такого-то профиля длины такой-то» (feature recognition).

| Для чего | Сущности | Количество |
|---|---|---|
| Профиль outer (rounded rectangle) | 110 ×4, 100 ×4, 102 ×1 | 9 |
| Профиль inner (rounded rectangle) | 110 ×4, 100 ×4, 102 ×1 | 9 |
| Surface бок outer | 122 ×1 | 1 |
| Surface бок inner | 122 ×1 | 1 |
| Surface торец (одна плоскость, обе границы) | 190 ×2 | 2 |
| Curves on surface для торцов | 142 ×4 | 4 |
| Trimmed surface бок outer | 144 ×1 | 1 |
| Trimmed surface бок inner | 144 ×1 | 1 |
| Trimmed surface торец z=0 | 144 ×1 | 1 |
| Trimmed surface торец z=L | 144 ×1 | 1 |
| **Итого** |  | **30** |

С BREP — добавляются 6 faces + 12 edges + 8 vertices + 6 loops + 2
shells + 1 solid = ещё ~35 сущностей, итого ~65.

### 4.2. Stub IGES-файл для прямой трубы 40×20×2, L=600 мм

Это **иллюстративный фрагмент**, не полностью корректный для импорта —
показывает структуру и какие куски где живут. Реальный writer должен
тщательно вычислять pointers и param-line counts.

```
NN FabKit — Tube 40x20x2 L=600 GOST 30245-2003 surface model           S      1
1H,,1H;,9HNN_FabKit,12Htube_001.igs,21HSketchUp 24.0 + Plugin,         G      1
13HNN FabKit 0.5,32,38,6,308,15,12Htube_001.igs,1.,2,2HMM,32,          G      2
1000.,13H260425.143012,0.001,12000.,8HCustomer,5HNN_OY,11,0,           G      3
13H260425.143012;                                                      G      4
     110       1       0       0       0       0       0       0       0D      1
     110       0       0       1       0       0       0       0       0D      2
     110       2       0       0       0       0       0       0       0D      3
     110       0       0       1       0       0       0       0       0D      4
     100       3       0       0       0       0       0       0       0D      5
     100       0       0       1       0       0       0       0       0D      6
     ...                                                                D      n
     102      11       0       0       0       0       0       0       0D     17
     102       0       0       1       0       0       0       0       0D     18
     122      12       0       0       0       0       0       0       0D     19
     122       0       0       1       0       0       0       0       0D     20
     190      14       0       0       0       0       0       0       0D     21
     190       0       0       1       0       0       0       0       0D     22
     142      15       0       0       0       0       0       0       0D     23
     142       0       0       1       0       0       0       0       0D     24
     144      19       0       0       0       0       0       0       0D     25
     144       0       0       1       0       0       0       0       0D     26
     ...
110,17.0,0.0,0.0,17.0,0.0,600.0;                                      1P      1
110,-17.0,0.0,0.0,-17.0,0.0,600.0;                                    3P      2
100,0.0,17.0,7.0,17.0,7.0,17.0,7.0;                                   5P      3
102,8,1,3,5,7,9,11,13,15;                                            17P     11
122,17,0.0,0.0,600.0;                                                19P     12
190,0.0,0.0,0.0,0.0,0.0,1.0;                                         21P     14
142,0,21,0,17,3;                                                     23P     15
144,21,1,1,23,25;                                                    25P     19
S      1G      4D     30P     22                                        T      1
```

**Замечания к stub:**
- Sequence numbers слева — это P-section sequence (1-based).
- DE pointer (col 66-72 в P-section, не показано выше из-за упрощения) —
  это back-pointer на DE-line этой entity (1, 3, 5, ...).
- Каждая P-line должна заканчиваться на колонке 64 (или раньше при
  переносе на новую строку), col 65 — пробел, col 66-72 — pointer back,
  col 73 — `P`, col 74-80 — sequence number.
- Углы в Type 100 (поле ZT=0) — для скругления в плоскости z=0.
- Type 102 (composite curve) — список pointers `8,1,3,5,7,9,11,13,15`
  означает 8 кривых: pointers 1,3,5,7,9,11,13,15.
- Type 122 (tabulated cylinder) — directrix=composite curve at pointer
  17, terminate point `(0, 0, 600)`.
- Type 190 (plane) — точка `(0,0,0)`, normal `(0,0,1)` — torcевая
  плоскость z=0.
- Type 142 (curve on surface) — связь composite curve с plane.
- Type 144 — trimmed surface (plane + outer trim) — endcap.

### 4.3. Минимально-минимальный (только wireframe, как у нас сейчас)

То, что уже делает [wireframe.rb](../../plugin-sketchup/src/nn_fabkit/metalfab/iges_exporter/wireframe.rb):

| Что | Сущности |
|---|---|
| Outer endcap profile z=0 | 110 ×4 + 100 ×4 = 8 |
| Outer endcap profile z=L | 110 ×4 + 100 ×4 = 8 |
| Inner endcap profile z=0 | 110 ×4 + 100 ×4 = 8 |
| Inner endcap profile z=L | 110 ×4 + 100 ×4 = 8 |
| Outer vertical silhouette edges | 110 ×4 = 4 |
| Inner vertical silhouette edges | 110 ×4 = 4 |
| **Итого** | **40 entities** |

Этого хватает для **визуальной проверки** в IGES viewer (FreeCAD,
CAD Assistant) — деталь распознаётся как «коробка с радиусами и стенкой».
**Не хватает** для NC: станок не получит surfaces, не сможет посчитать
toolpaths.

---

## 5. Альтернативы IGES

### 5.1. STEP AP203 / AP214 / AP242

STEP (ISO 10303) — преемник IGES. Лучше структурирован, лучше передаёт
BREP, поддерживает PMI (Product and Manufacturing Information).

| Application Protocol | Что добавляет | Поддержка трубных CAM |
|---|---|---|
| AP203 | basic geometry + topology + config management | вся «премиум»-серия (BLM, Trumpf, Bystronic) |
| AP214 | + colors + layers + GD&T + design intent | вся «премиум»-серия |
| AP242 | объединяет 203/214 + полный PMI + advanced manufacturing | новые версии (BLM ArTube 2024+, TruTops 2023+, BySoft 8) |

«AP242 is the preferred choice overall: combines AP203 and AP214 and is
future proof for MBD/MBE workflows»
([Capvidia STEP AP-comparison](https://www.capvidia.com/blog/best-step-file-to-use-ap203-vs-ap214-vs-ap242)).

**Когда STEP лучше IGES:**
- Если станок и его CAM это поддерживают.
- Если нужна богатая мета-информация (марка стали, толщина, ГОСТ — в PMI).
- Если важна точная топология BREP.

**Когда IGES всё ещё лучше:**
- Старые станки (~10+ лет).
- Китайские бюджетные станки (TubesT, Bochu).
- Когда «лишь бы открылось».

**Сложность реализации.** Минимальный STEP-writer существенно сложнее
минимального IGES-writer'а из-за схемы EXPRESS, обязательных
header-сущностей и более жёсткой топологии. Для собственного writer'а в
MVP **IGES проще**.

### 5.2. DSTV / NC1

Стандарт Deutscher Stahlbau-Verband. **Текстовый**, ASCII-блоки.
Целевое назначение — стальные конструкции (балки, профили, листы).

**Профильные коды:**

| Код | Профиль |
|---|---|
| `I` | I-профиль (двутавр) |
| `L` | уголок |
| `U` | швеллер |
| `B` | лист |
| `RU` | круглый пруток |
| `RO` | круглая труба |
| `M` | прямоугольная труба ← **это наш случай** |
| `C` | C-профиль |
| `T` | T-профиль |
| `SO` | специальный |

**Операции:**

| Код | Операция |
|---|---|
| `BO` | отверстие (Bore) |
| `SI` | маркировка |
| `AK` | внешний контур (Auskerbung) |
| `IK` | внутренний контур |
| `PU` | пунктирование |
| `KO` | разметка |

«[DSTV] is a universal interface that allows the geometries of steel
design parts to be transferred in a standardized manner to NC machines
such as drilling and cutting machines, plasma cutters, lasers, etc.»
([Klietsch DSTV NC](https://klietsch.com/?m=page&action=240827&lang=en))

**Поддержка:**
- HGG ProCAM (предпочитает DSTV над IGES).
- Tekla Structures / SDS2 / Bocad / другие PSC.
- FastBEAM Editor / FastCAM.

**Когда DSTV выгоднее IGES:**
- В стальном строительстве (heavy steel) — DSTV — стандарт де-факто.
- Когда нужна разметка отверстий, маркировка, серийные номера.
- Когда geometry проще IGES (это **2.5D**: профиль + продольные
  операции, без полного 3D BREP).

**Сложность реализации:** проще IGES в смысле геометрии (нет 3D-сущностей),
но требует знания «языка операций». Не подходит для
laser/plasma-tube-cutting в general — основан на drilling/punching/sawing
парадигме.

**Решение для NN FabKit:** DSTV-export — отдельный roadmap-item, не в
MVP. Если/когда заказчик подтвердит — добавим writer.

### 5.3. DXF 3D для трубы

DXF (Autodesk) технически поддерживает 3D-сущности (3DSOLID, ACIS-блобы),
но это **не interchange-формат для truby**:
- 3DSOLID — это бинарный ACIS blob внутри DXF, читать/писать его без
  ACIS-лицензии (или OpenCASCADE) — невозможно.
- 2D DXF (LINE, CIRCLE, ARC, POLYLINE, SPLINE) — поддерживается всеми
  трубными CAM, но описывает только **развёртку трубы** (unfolded
  cylinder), не 3D.

**Когда DXF используется для tube cutting:**
- TubesT/TubePro принимают **2D-развёртки** для маркировки.
- DXF — preferred для **листового** cutting (наша другая ветка — Лист).

**Не подходит для прямой трубы в MVP.**

### 5.4. ACIS SAT / Parasolid X_T / X_B

**SAT** (ASCII или binary, Autodesk/Spatial ACIS) — нативный формат
ACIS modeling kernel. **X_T/X_B** — Parasolid (Siemens). Оба — фактические
форматы обмена для «зрелого» BREP.

**Поддержка:**
- TubesT/TubePro — SAT (читает!).
- BLM/Trumpf — X_T (читает).
- Lantek — SAT.

**Сложность реализации:** очень высокая. SAT-writer без ACIS-лицензии —
обратно-инженерная задача (формат документирован, но запутан); X_T —
закрытый формат Siemens (через Parasolid SDK ~$100k).

**Не вариант для MVP.**

### 5.5. Сводка: когда что предлагать

| Сценарий заказчика | Формат |
|---|---|
| Премиум-станок (BLM/Trumpf/Bystronic) | STEP AP242 (если умеем); fallback IGES |
| Китайский TubesT/TubePro (FSCUT) | **IGES surface (ours)** |
| Стальное строительство (HGG/Tekla pipeline) | DSTV NC1 |
| Плоский лист (наш Лист, не труба) | DXF 2D |
| Лазерный труборез без CAM (G-code напрямую) | вне scope NN FabKit (это уровень CAM, не CAD) |

**Для MVP заказчика-0** — IGES surface model. STEP — расширение во второй
версии конвертёра.

---

## 6. Библиотеки и инструменты

### 6.1. pythonocc-core / OpenCASCADE

[OpenCASCADE Technology (OCCT)](https://dev.opencascade.org/) — open-source
3D CAD kernel (LGPL-2.1 + exceptions). pythonocc-core — Python-биндинги.

**Плюсы:**
- Полный BREP-modeller, включая корректный IGES write.
- Один вызов: `IGESControl_Writer("MM", 0).AddShape(shape).Write("file.igs")`
  — даст рабочий IGES с Type 144 (face write mode 0) или Type 510
  (BREP write mode 1).
- Реально хорошая поддержка trimmed surfaces и BREP.
- Пишет с unit conversion, color preservation, names.

**Минусы:**
- **Размер** — OCCT runtime ~150 MB, pythonocc-core wheel ~80 MB.
  Heavy для standalone.
- **Сложность сборки**. На Windows — стабильно через `conda install -c
  conda-forge pythonocc-core`. Через pip — нет, только manylinux.
- **Зависимости.** Tcl/Tk, Freetype, plus C++ runtime — всё нужно
  таскать.
- **Лицензия.** LGPL — ок для динамической линковки, но если хотим
  static-link или включить «as-is» — нужна осторожность.

**Пример minimal IGES export** (С# обёртка, эквивалент в Python тот же):

```cpp
// C++ pseudocode
IGESControl_Controller::Init();
IGESControl_Writer writer("MM", 0);  // mode 0 = Faces (Type 144)
writer.AddShape(myShape);
writer.ComputeModel();
writer.Write("output.igs");
```

В Python:

```python
from OCC.Core.IGESControl import (
    IGESControl_Controller, IGESControl_Writer
)
IGESControl_Controller.Init()
writer = IGESControl_Writer("MM", 0)
writer.AddShape(shape)
writer.ComputeModel()
writer.Write("output.igs")
```

**Вердикт для NN FabKit:** мощно, но избыточно для прямой трубы. Если/когда
дойдём до сложных деталей (с резами под углом, отверстиями, сборками) —
переходим на pythonocc. Для MVP — самописный writer (см. раздел 8).

### 6.2. Минимальные writers (для bootstrap)

**[roseengineering/igeswrite](https://github.com/roseengineering/igeswrite)**

Pure-Python writer (~300 строк). Поддерживает:
- Lines (Type 110)
- Planes (XZ, YZ, generic) — но не как Type 190, а как замкнутые контуры
  4 линий
- Cubes — собирает 6 «планов»

Минимальный пример:

```python
from igeswrite import Iges

iges = Iges()
iges.cube((100, 80, -1.6), origin=(-50, -40, 0))
iges.write()
```

Что такая библиотека показывает по структуре:
- Hollerith helper: `f"{len(s)}H{s}"`.
- 80-col padding: `f"{line:64s}{index:>8s}{section}{lineno:7d}\n"` (где
  data — 64, index/back-pointer — 8, section letter — 1, sequence — 7).
- Terminate: `f"S{nS:7d}G{nG:7d}D{nD:7d}P{nP:7d}{'':40s}T{1:7d}\n"`.

Это **отличный starting-point** для собственного writer'а на любом языке.

**[pyvista/pyiges](https://github.com/pyvista/pyiges)** — reader,
не writer. Полезен для **валидации**: открыли файл — увидели сущности,
координаты.

**[cfinch/IGES-File-Reader](https://github.com/cfinch/IGES-File-Reader)** —
reader на чистом Python с разбором по entity types. Для смотрения
«что у нас получилось».

### 6.3. ezdxf

[ezdxf](https://ezdxf.readthedocs.io/) — для DXF, не IGES. Полезен, если
понадобится DXF-экспорт (для листа). MIT license, pure Python.

### 6.4. FreeCAD (как библиотека и как viewer)

[FreeCAD](https://www.freecad.org/) — open-source MCAD (LGPL-2.1+).

Можно использовать **headless** через Python API:

```python
import FreeCAD
import Part
shape = Part.makeCylinder(20, 600)  # r=20, h=600
shape.exportIges("tube.igs")
```

Плюсы: установлен у многих заказчиков, IGES-writer построен на OCCT
внутри.

Минусы: тяжёлый процесс, медленный старт (5-10 секунд init).

**Применение для NN FabKit:** не как библиотека (тяжёлая зависимость), а
как **бесплатный viewer для валидации** наших IGES.

### 6.5. gmsh

[gmsh](https://gmsh.info/) — meshing tool с IGES-импортом для FEM. Не
писатель IGES в нашем смысле; для трубного NC бесполезен.

### 6.6. Самостоятельный writer — на чём писать

Опции для NN FabKit standalone (`app-desktop/`):

| Язык | Плюсы | Минусы |
|---|---|---|
| Python | быстрый старт; рядом — pyiges для проверки; cross-platform | runtime ~30 MB; PyInstaller bundle ~50-100 MB |
| Rust | компактный binary (~5 MB); fast | дольше писать; для IGES готовых crate нет |
| Go | компактный binary; fast; хороший cross-compile | для IGES готовых пакетов нет; нужен с нуля writer |
| C++ | возможна интеграция OCCT нативно | дольше всего; cross-platform — морока |
| C# / .NET | удобно на Windows; UI вместе с writer | runtime требует .NET |
| Ruby | можно встроить в плагин SketchUp прямо | для standalone — нестандартно |

**Кандидаты:**

- **Python**. Минимальный writer на 500-800 строк (по образцу igeswrite,
  расширенный до Type 122/144), плюс pyiges для тестов. Standalone через
  PyInstaller или Briefcase. Минусы — bundle size.

- **Rust**. Если standalone должен быть супер-компактным и fast-cold-
  start (чего trivially не нужно для tube конвертёра). Минимальный
  writer ~600 строк Rust. Расширения (parser, validator) сложнее.

- **C#**. Если заказчик-0 на Windows-only и UI standalone делается на
  WPF/WinUI — естественный выбор. Можно даже OCCT через wrapper
  (occt.NET, или сделать P/Invoke).

**Рекомендация (см. раздел 8):** Python для скорости MVP, опционально
переписать на Rust в release-версии когда standalone стабилизируется.

### 6.7. Валидация и просмотр готового IGES

| Инструмент | Тип | Лицензия | Заметки |
|---|---|---|---|
| FreeCAD | open-source MCAD | LGPL-2.1+ | импорт через OCCT, надёжный, медленный |
| Open Cascade CAD Assistant | freeware standalone | бесплатно для commercial use | официальный viewer от OCCT-team, поддерживает IGES 5.1/5.3 |
| eDrawings | freeware (SolidWorks) | freeware | лучше с STEP/SLDPRT, IGES — да |
| sharecad.org | онлайн | freemium | загружаешь файл — смотришь в браузере; ограничения по размеру |
| HilPCB online viewer | онлайн | бесплатно | базовый |
| IGES Viewer (NIST) | старый academic | public domain | устаревший, но всё ещё запускается на современной Windows |
| pyiges | Python lib | MIT | для unit-test'ов |
| CADfix | commercial (ITI) | платный | gold standard для validation в industry; есть free trial |
| TransMagic | commercial | платный | aggressive auto-fix |

**Workflow для NN FabKit:**

1. Generate IGES.
2. Откатить в FreeCAD (обязательно) — есть ли surfaces, корректные ли
   координаты.
3. Откатить в CAD Assistant — финальная sanity-check, проверка structure.
4. (Опционально) загрузить в TubesT/TubePro у заказчика — реальная
   проверка на target system.

### 6.8. Open-source примеры minimal IGES writer

| Репо | Язык | Тип | Заметка |
|---|---|---|---|
| [roseengineering/igeswrite](https://github.com/roseengineering/igeswrite) | Python 3 | writer | минимум; lines, planes, cubes |
| [Open-Cascade-SAS/OCCT](https://github.com/Open-Cascade-SAS/OCCT) | C++ | full kernel | Source of truth для IGES read/write |
| [tpaviot/pythonocc-core](https://github.com/tpaviot/pythonocc-core) | Python (OCCT bindings) | writer + reader | через `OCC.Core.IGESControl` |
| [pyvista/pyiges](https://github.com/pyvista/pyiges) | Python | reader | базовая поддержка для visualization |
| [cfinch/IGES-File-Reader](https://github.com/cfinch/IGES-File-Reader) | Python | reader | хорошо документированный parser |

К сожалению, **минималистичных Rust/Go/C# writers в open-source — нет**
(на момент 2026-04-25). Это пробел; если идти в Rust, надо будет писать
с нуля.

---

## 7. Источники

### Спецификации

- [IGES 5.3 PDF (Paul Bourke mirror)](https://paulbourke.net/dataformats/iges/IGES.pdf) —
  полный текст стандарта IGES 5.3 (1996), официально US PRO/IPO-100-1996.
  Критически важный документ для writer'а.
- [Eclipse IGES File Specification Wiki](https://wiki.eclipse.org/IGES_file_Specification) —
  сжатый обзор структуры файла с примерами G-section.
- [Wikipedia — IGES](https://en.wikipedia.org/wiki/IGES) — историческая
  справка + хороший пример полного IGES-файла (slot.igs от 1987).
- [IGES File Format (docs.fileformat.com)](https://docs.fileformat.com/cad/iges/) —
  справочник по структуре.
- [opendwgfile.com — IGES](https://opendwgfile.com/iges.html) — обзор
  G-section.
- [CAD Interoperability — IGES](https://www.cadinterop.com/en/formats/neutral-format/iges.html) —
  объективный анализ ограничений IGES (включая «poorly implemented MSBO»).
- [TransMagic — IGES](https://transmagic.com/iges/) — практическая
  справка по entity types.
- [Solidworks — IGES Files](https://help.solidworks.com/2021/english/SolidWorks/sldworks/c_IGES_Files_igs_iges.htm) —
  как SW интерпретирует IGES.
- [Strand7 — IGES Entities](https://www.strand7.com/strand7r3help/Content/Topics/FileFormats/FileFormatsSupportedIGESEntities.htm) —
  список поддерживаемых entity-types в FEA-системе.

### Документация трубных CAM-систем

- [BLM ArTube](https://www.blmgroup.com/software/artube) — формат:
  «STEP, IGES, XT, IFC».
- [BLM ArTube — DirectIndustry datasheet](https://www.directindustry.com/prod/blm-group/product-6136-465935.html)
- [TRUMPF TruTops PFO](https://www.trumpf.com/en_US/products/software/programming-software/trutops-pfo/)
- [TRUMPF PRAXIS CAD](https://trumpf-flux.com/trumpf-praxis-cad/) —
  «20+ форматов: IGES, STEP, ACIS, Inventor, CATIA, Creo, Solid Edge, SW».
- [Bystronic BySoft CAM](https://www.bystronic.com/en/products/software/BySoft-CAM.php)
- [Bystronic BySoft 7](https://www.bystronic.com/en/products/software/BySoft-7.php)
- [Metalix MTube](https://www.metalix.net/product/mtube/)
- [Metalix MTube — Tube Import](https://www.metalix.net/products/mtube/tube-import/)
- [Metalix cncKad](https://www.metalix.net/product/cnckad/)
- [Lantek Flex3D Tubes](https://www.lantek.com/us/tubes-pipes-cad-cam-nesting-software)
- [Lantek Flex3D Steelwork](https://www.lantek.com/us/lantek-flex3d-steelwork)
- [Lantek Flex3D CAD Add-ins](https://www.lantek.com/us/lantek-flex3d-addins)
- [HGG Profile Cutting](https://www.hgg-group.com/cutting-services/profile-cutting/)
- [HGG ProCAM](https://www.hgg-group.com/procam/)
- [HGG ProCAM Lite (free DSTV viewer)](https://www.hgg-group.com/hgg-procam-lite/)
- [TubesT (cypcut.ru)](https://cypcut.ru/tubest/) — Friendess/Bochu для
  китайских станков.
- [TubePro (cypcut.ru)](https://cypcut.ru/tubepro/)
- [Bochu FSCUT](https://www.bochu.com/en/product/)
- [Bochu — Basics: Import Drawing](https://www.bochu.com/tutorials/basics-import-drawing/)
- [Mazak FT-150 (через MGLaser)](https://mglaser.com/collections/trulaser-tube-5000-7000)

### DSTV / NC1

- [Klietsch DSTV NC Data — general info](https://klietsch.com/?m=page&action=240827&lang=en)
- [Tekla DSTV file description](https://support.tekla.com/doc/tekla-structures/2025/int_nc_dstv_file_description)
- [Tekla NC files](https://support.tekla.com/doc/tekla-structures/2025/int_create_nc_files)
- [Strucsoft CMS DSTV NC1 Converter](https://strucsoftsolutions.com/cms-dstv-conversion/)
- [The Fabricator — File export fundamentals](https://www.thefabricator.com/thefabricator/article/cadcamsoftware/file-export-fundamentals-in-structural-steel-fabrication)
- [Kinetic — DSTV (NC1) Part Import](https://kineticusa.com/PrimecutHelp/dstv_part_import.html)

### STEP

- [Capvidia — Best STEP File: AP203 vs AP214 vs AP242](https://www.capvidia.com/blog/best-step-file-to-use-ap203-vs-ap214-vs-ap242)
- [RayPCB — STEP AP203 vs AP214 vs AP242](https://www.raypcb.com/step-ap203-vs-ap214-vs-ap242/)
- [MechProfessor — STEP AP comparison](https://mechprofessor.com/step-ap203-vs-ap214-vs-ap242/)

### Библиотеки

- [pythonocc-core (PyPI)](https://pypi.org/project/pythonocc-core/)
- [Open Cascade IGES Translator User Guide](https://dev.opencascade.org/doc/overview/html/occt_user_guides__iges.html)
- [Open Cascade IGESControl_Writer reference](https://dev.opencascade.org/doc/refman/html/class_i_g_e_s_control___writer.html)
- [OCCT IGES Wiki (read/write notes)](https://github.com/Open-Cascade-SAS/OCCT/wiki/iges)
- [roseengineering/igeswrite](https://github.com/roseengineering/igeswrite)
- [pyvista/pyiges](https://github.com/pyvista/pyiges)
- [pyiges docs — Trimmed Parametric Surface](https://pyiges.readthedocs.io/en/latest/examples/benchmarks/144_0/144-000.html)
- [cfinch/IGES-File-Reader](https://github.com/cfinch/IGES-File-Reader)

### Форумы и практический опыт

- [Practical Machinist — Tube laser cutting](https://www.practicalmachinist.com/forum/threads/cnc-laser-cutter-mitsubishi-vs-whitney-vs-mazak-vs.434399/)
- [CNCZone — Mazak/Amada/Trumpf tube laser](https://www.cnczone.com/forums/laser-engraving-cutting-machine-general-topics/125711-mazak.html)
- [The Fabricator — Tube and pipe laser cutting update](https://www.thefabricator.com/tubepipejournal/article/tubepipefabrication/laser-cutting-update-tube-and-pipe)
- [OSH Cut — How to Order Laser-Cut Tube](https://www.oshcut.com/design-guide/how-to-order-laser-cut-tube)
- [OSH Cut — Tube cutting basics](https://www.oshcut.com/design-guide/tube-cutting-basics)
- [Houston Laser — Tube quoting requirements](https://oceanfabricators.com/tube-laser-cutting-quoting-requirements/)
- [247TailorSteel — Tube cutting guidelines](https://247tailorsteel.com/en/submission-guidelines/guidelines-for-tube-laser-cutting)
- [Wikipedia Talk:IGES — discussion of MSBO ambiguity](https://en.wikipedia.org/wiki/Talk:IGES)
- [Autodesk forum — Tube laser cutting (notching)](https://forums.autodesk.com/t5/inventor-forum/tube-amp-pipe-cnc-laser-cutting-notching/td-p/9032707)
- [FreeCAD forum — IGES 5.3](https://forum.freecad.org/viewtopic.php?t=9851)
- [Autodesk forum — Bodor laser cutting](https://forums.autodesk.com/t5/fusion-manufacture-forum/bodor-laser-cutting/td-p/9389884)

### Validation viewers

- [Open Cascade CAD Assistant](https://www.opencascade.com/products/cad-assistant/)
- [FreeCAD](https://www.freecad.org/)
- [sharecad.org online viewer](https://sharecad.org/)
- [HilPCB Online 3D Viewer](https://hilpcb.com/en/blog/3d-viewer/)

---

## 8. Рекомендации для нашего конвертёра

### 8.1. Что мы хотим экспортировать (LOD-1 прямая профильная труба)

Геометрия:
- Прямоугольная труба (`width × height × wall`, скруглённый радиус
  `r_outer`).
- Длина `L` вдоль оси Z.
- Профиль outer + inner, скруглённые углы — Type 100 arcs.
- Прямые рёбра — Type 110 lines.
- Боковая поверхность outer — Type 122 (tabulated cylinder с composite
  curve как directrix).
- Боковая поверхность inner — Type 122 аналогично.
- Торцы (z=0 и z=L) — Type 144 trimmed surface (plane + outer + inner).

Метаданные (опционально, в G-section):
- Имя детали (typesize, ГОСТ).
- Длина в `max_coordinate`.
- Marka стали — в P-section как Type 406 (Property) form 15 (имя/значение).

### 8.2. Минимальный entity set достаточный для feature recognition

| # | Entity | Назначение |
|---|---|---|
| 1-4 | 4 × Type 110 | прямые outer контура z=0 |
| 5-8 | 4 × Type 100 | дуги outer контура z=0 |
| 9 | Type 102 | composite outer @ z=0 |
| 10-13 | 4 × Type 110 | прямые inner @ z=0 |
| 14-17 | 4 × Type 100 | дуги inner @ z=0 |
| 18 | Type 102 | composite inner @ z=0 |
| 19-22 | 4 × Type 110 | прямые outer @ z=L |
| 23-26 | 4 × Type 100 | дуги outer @ z=L |
| 27 | Type 102 | composite outer @ z=L |
| 28-31 | 4 × Type 110 | прямые inner @ z=L |
| 32-35 | 4 × Type 100 | дуги inner @ z=L |
| 36 | Type 102 | composite inner @ z=L |
| 37 | Type 122 | side surface outer (directrix=#9, vector=(0,0,L)) |
| 38 | Type 122 | side surface inner (directrix=#18, vector=(0,0,L)) |
| 39 | Type 190 | end plane z=0 (point=(0,0,0), normal=(0,0,-1)) |
| 40 | Type 190 | end plane z=L (point=(0,0,L), normal=(0,0,1)) |
| 41 | Type 142 | curve-on-surface: composite #9 on plane #39 |
| 42 | Type 142 | curve-on-surface: composite #18 on plane #39 |
| 43 | Type 142 | curve-on-surface: composite #27 on plane #40 |
| 44 | Type 142 | curve-on-surface: composite #36 on plane #40 |
| 45 | Type 144 | trimmed: plane #39, outer=#41, inner=#42 |
| 46 | Type 144 | trimmed: plane #40, outer=#43, inner=#44 |
| 47 | Type 144 | trimmed: side outer #37 (без inner) |
| 48 | Type 144 | trimmed: side inner #38 (без inner) |

**Итого: 48 entities** (без BREP-топологии).

При желании можно добавить:
- Type 124 (Transformation Matrix) если детали в сборке — но в MVP мы
  выгружаем по одной трубе, не assembly.
- Type 314 (Color) — для визуальной маркировки сторон.
- Type 406 form 15 (Property) — для метаданных (typesize, ГОСТ, марка
  стали).

### 8.3. Рекомендация по языку standalone

**Кандидаты:**

| # | Стек | Time-to-MVP | Bundle size | Долгосрочная цена |
|---|---|---|---|---|
| 1 | Python + custom writer + PyInstaller | 1-2 недели | ~50 MB | средняя (нужно maintenance) |
| 2 | Python + pythonocc-core + PyInstaller | 2-3 дня | ~200 MB | низкая (вся сложность в OCCT) |
| 3 | Rust + custom writer | 3-4 недели | ~5 MB | средняя |
| 4 | C++ + OCCT | 1-2 месяца | ~150 MB | высокая (build complexity) |

**Рекомендация — Python с собственным writer'ом**, опционально с
pyiges для валидации.

Аргументы:
1. Скорость MVP — главный приоритет, заказчик ждёт реальные NC-файлы.
2. 50 MB bundle — приемлемо для desktop tool.
3. Если позже окажется нужен полный BREP / fish-mouth / mitered cuts —
   переход на pythonocc-core делается за 2-3 дня (просто заменить writer
   на `IGESControl_Writer`).
4. Rust slowдольше для MVP без значимого выигрыша на этом этапе.

### 8.4. Координаты, единицы, DP — конкретные значения

```python
# Конфигурация writer'а NN FabKit
UNIT_FLAG          = 2          # millimeters
UNIT_NAME          = "MM"
IGES_VERSION_FLAG  = 11         # IGES 5.3
DRAFTING_FLAG      = 0          # no drafting standard
MIN_RESOLUTION     = 0.001      # 1 micron (real)
MAX_COORDINATE     = 13000.0    # достаточно для 12 м труб
MAX_LINES_PER_PAGE = 32         # стандартное для современных IGES
MODEL_SCALE        = 1.0        # без масштабирования
INT_BITS           = 32
SP_MAX_POWER       = 38         # single precision
SP_SIG_DIGITS      = 6
DP_MAX_POWER       = 308        # double precision
DP_SIG_DIGITS      = 15
FLOAT_FORMAT       = "%.6f"     # 6 знаков после точки = 1 нм точность
NEWLINE            = "\r\n"     # Windows-friendly; станки часто требуют
```

### 8.5. Stub IGES для нашего LOD-1

См. раздел 4.2 — stub-структура с правильным именованием параметров.
Реальный writer должен:

1. Сначала пройтись по всем сущностям и **зарезервировать** D-pointers
   (нечётные числа: 1, 3, 5, ...).
2. Сборка снизу вверх: сначала линии и дуги (они никуда не указывают),
   потом composite curves (указывают на curves), потом surfaces, потом
   curves-on-surface, потом trimmed surfaces.
3. Каждая P-line должна иметь корректный **back-pointer** (col 66-72) —
   sequence number первой DE-line этой entity.
4. T-section считает счётчики строк всех 4 секций (S/G/D/P).

Pseudocode для writer'а:

```python
class IgesWriter:
    def __init__(self):
        self.entities = []         # list of dicts with type, params
        self.start_lines = []
        self.global_params = []

    def add_line(self, p1, p2):
        idx = len(self.entities)
        self.entities.append({"type": 110, "p": [*p1, *p2]})
        return idx

    def add_arc(self, zt, center, start, end):
        idx = len(self.entities)
        self.entities.append({"type": 100, "p": [zt, *center, *start, *end]})
        return idx

    def add_composite(self, curve_indices):
        idx = len(self.entities)
        # +1 because IGES is 1-based; *2-1 because each entity has odd DE seq
        de_pointers = [(i*2 + 1) for i in curve_indices]
        self.entities.append({
            "type": 102,
            "p": [len(de_pointers), *de_pointers]
        })
        return idx

    def add_tabulated_cylinder(self, directrix_idx, terminate_pt):
        idx = len(self.entities)
        de_ptr = directrix_idx * 2 + 1
        self.entities.append({
            "type": 122,
            "p": [de_ptr, *terminate_pt]
        })
        return idx

    # ... аналогично add_plane, add_curve_on_surface, add_trimmed_surface

    def write(self, path):
        # 1. Render P-section и собрать back-pointers
        # 2. Render D-section на основе сущностей и P-lines counts
        # 3. Render G-section
        # 4. Render S-section (произвольный комментарий)
        # 5. Render T-section
        # 6. Записать всё в файл с col 73-80 sequence-padding
        ...
```

Полный код — задача spec-04 в `docs/specs/`. На основе этого справочника
оценочно ~600-800 строк Python.

### 8.6. Дальнейшие шаги исследования (что нужно проверить эмпирически)

1. **Тест на реальном станке заказчика-0.** Сгенерить наш минимальный
   IGES surface (Type 144) для 40×20×2 L=600, отнести заказчику, открыть
   в TubesT, посмотреть что получается. Это критическая валидация.
   Возможные исходы:
   - TubesT распознаёт деталь как «Tube 40×20×2, L=600» — успех.
   - TubesT видит «surface body, manual setup» — частичный успех (NC
     можно сделать вручную, но feature recognition не сработал).
   - TubesT не открывает — refactoring writer'а.

2. **Проверка composite curves.** TubesT по слухам не любит Type 102.
   Если выяснится, что не работает — переписать на «много отдельных
   trim curves» вместо одного composite. Это 4-кратное увеличение
   количества Type 142, но проще для импортёра.

3. **Проверка ориентации.** Inner contour — CW relative outer? Если
   ambiguity ([§1.2](#12-surface-сущности)) сработает в плохую сторону
   — endcap получится как «инвертированная маска» (cut inside instead of
   outside). Тестировать на реальном станке.

4. **Validation pipeline.** Настроить `pyiges` в качестве unit-test
   layer: после каждого generate — re-read и проверять, что сущности
   и их параметры — то, что мы ожидали.

5. **STEP-альтернатива.** Через 1-2 месяца после MVP — попробовать
   написать STEP AP242-writer (или использовать pythonocc-core
   напрямую). Сравнить на реальных станках, какой результат лучше.

6. **DSTV NC1 для случаев, где выгодно.** Если/когда у заказчика
   появятся стальные конструкции (балки, не трубы), DSTV-writer
   значительно проще IGES surface (это 2D ASCII с командами).
   Roadmap-item.

7. **IGES BREP (Type 186 + 514 + 510 + ...).** Если surface-only окажется
   недостаточным для feature recognition в TubesT — пробуем добавить
   полную BREP-топологию. Объём кода удваивается, но детектируемость
   деталей в премиум-САМ улучшается.

8. **Сборки (multiple tubes в одном файле).** Когда понадобятся «куча
   деталей в одном NC-файле» — добавить Type 124 (Transformation
   Matrix) и Type 308 (Subfigure Definition) / Type 408 (Subfigure
   Instance). До тех пор — один файл = одна труба.

9. **Метаданные для PMI.** Type 406 form 15 (User Property) — проверить,
   читает ли его TubesT. Если да — можно записывать ГОСТ, типоразмер,
   марку прямо в IGES, и заказчик в TubesT увидит «эта деталь — труба
   ГОСТ 30245-2003 40×20×2 Ст3сп».

### 8.7. Чек-лист «Ready for first machine test»

- [ ] Writer выдаёт IGES, который **открывается** в FreeCAD без ошибок.
- [ ] Writer выдаёт IGES, который **открывается** в CAD Assistant без
  ошибок.
- [ ] Координаты в IGES совпадают с моделью SketchUp (в мм, ось длины
  по Z, центр трубы — origin).
- [ ] Outer и inner contour видны как два разных ringed контура.
- [ ] Endcap — закрытый, не «дырка».
- [ ] Размер файла — не более 50 KB для одной трубы 40×20×2 L=600.
- [ ] Ни одной строки длиннее 80 chars.
- [ ] Все строки заканчиваются `\r\n`.
- [ ] Кодировка ASCII (no UTF-8 BOM).
- [ ] T-section счётчики совпадают с реальным числом строк в S/G/D/P.
- [ ] **Тест на станке заказчика-0** — деталь распознана как tube
  40×20×2 L=600.

После успеха пункта 11 — конвертёр готов для production beta.

---

## Связь с другими документами

- [ADR-017](09-architecture-decisions.md) — решение писать собственный
  IGES-конвертёр в составе MVP.
- [ADR-014](09-architecture-decisions.md) — бюджет геометрии и LOD-уровни.
- [ADR-013](09-architecture-decisions.md) — гибридный форм-фактор
  (плагин + standalone).
- [06-sortament-ontology.md](06-sortament-ontology.md) — каталог
  типоразмеров профильной трубы.
- [08-reference-components-analysis.md](08-reference-components-analysis.md) —
  что есть у заказчика-0 в существующих DC.
- [docs/specs/spec-01-dc-rework-for-iges.md](../specs/spec-01-dc-rework-for-iges.md) —
  доработка DC под IGES-конвертёр.
- [plugin-sketchup/src/nn_fabkit/metalfab/iges_exporter/wireframe.rb](../../plugin-sketchup/src/nn_fabkit/metalfab/iges_exporter/wireframe.rb) —
  текущий MVP wireframe (Type 110 + Type 100).
