# nn-fabkit-nc-export

Standalone NC-конвертёр NN FabKit. Принимает BREP-структуру (профильная труба, в будущем — листовые детали) и пишет файлы для ЧПУ:

- **IGES** (труба) — для трубопрофилерезов (BLM, HGG, Trumpf, Friendess TubePro, Bochu/Bodor)
- **DXF** (лист) — для листовых станков (планируется)

Архитектура: ADR-017 (собственный IGES-конвертёр в составе MVP). Источник по форматам: [docs/knowledge-base/10-iges-for-tube-nc.md](../../docs/knowledge-base/10-iges-for-tube-nc.md).

## Статус

**v0.1.0** — каркас + минимальный IGES writer surface-модели.

| Шаг | Что | Статус |
|---|---|---|
| 1 | `hello-surface` — одна боковая грань трубы (Type 122) | ✅ v0.1.0 |
| 2 | `rect-tube --no-radius` — closed box LOD-1 (4 грани + 2 endcaps) | ✅ v0.1.0 |
| 3 | `rect-tube` со скруглёнными углами (Type 122 на цилиндры) | планируется |
| 4 | endcaps как Type 144 Trimmed Surface с inner+outer loops | планируется |
| 5 | TCP/JSON приёмник от Ruby-плагина | планируется |
| 6 | DXF writer для листа | планируется |

На каждом шаге — артефакт `.igs`, который заказчик/разработчик открывает в целевом CAM (Tube Pro, Lantek и т.п.) и подтверждает совместимость до перехода к следующему шагу.

## Установка и запуск

Зависимостей нет (stdlib-only). Python 3.10+.

```bash
cd app-desktop/nc-export
python -m venv .venv
# Windows:
.venv\Scripts\activate
# Linux/macOS:
source .venv/bin/activate

pip install -e .[dev]
```

Запуск без установки:

```bash
PYTHONPATH=src python -m nn_fabkit_nc_export hello-surface --width 40 --length 600 -o hello.igs
```

## CLI

```bash
nn-fabkit-nc-export hello-surface --width 40 --length 600 -o out.igs
nn-fabkit-nc-export rect-tube --width 40 --height 20 --wall 2 --length 600 --no-radius -o tube.igs
```

| Флаг | Значение |
|---|---|
| `--width` | внешняя ширина профиля, мм |
| `--height` | внешняя высота профиля, мм |
| `--wall` | толщина стенки, мм (используется в endcaps когда добавится Type 144) |
| `--length` | длина трубы по оси Z, мм |
| `--no-radius` | плоские углы (LOD-0/1 без скруглений) |
| `-o`, `--output` | путь сохранения `.igs` |

## Reference IGES от заказчика

В `examples/` могут лежать `.IGS` (uppercase) файлы — образцы рабочих IGES от заказчика, которые корректно читаются в CypTube. Используются как референс структуры (entity types, координатная система, формат G-section) при разработке writer'а.

**Не коммитятся в git** — G-section может содержать пути файловой системы с именами клиентов (`Yandex.Disk\Заказы \<клиент\>\...`). Шаблон в `.gitignore`: `app-desktop/nc-export/examples/*.IGS`. Наши собственные образцы пишутся в lowercase `.igs` и коммитятся.

Текущий reference:
- `60X10X992 21 шт.IGS` — труба 60×10×1.5 R=2.25 длиной 992 мм. SolidWorks 2025 export. CypTube распознаёт как `Rect 10 × 60 R2.25 X 992`. Используется как образец BREP-структуры (Type 144 + Type 128 + Type 102 + Type 142 + Type 110/100/126).

## Тесты

```bash
pytest
```

Тесты проверяют:
- 80-символьные строки (S/G/D/P/T секции)
- T-section счётчики совпадают с фактическим числом строк
- Hello-surface: 2 entities (Line + Tabulated Cylinder)
- Rect-tube box: 12 entities (4 directrix + 4 boundary + 4 boundary endcap + 2 endcap surfaces; точное число зависит от выбора writer'а — см. `tests/`)

## Структура

```
nc-export/
├── pyproject.toml
├── README.md
├── src/nn_fabkit_nc_export/
│   ├── __init__.py
│   ├── __main__.py        # python -m nn_fabkit_nc_export ...
│   ├── cli.py
│   ├── iges/
│   │   ├── __init__.py
│   │   ├── document.py    # IGESDocument: S/G/D/P/T, sequence, terminate
│   │   ├── entities.py    # Type 110, 100, 122, 128 factories
│   │   └── format.py      # 80-col line padding, Hollerith strings, fnum
│   └── tube/
│       ├── __init__.py
│       └── rect_tube.py   # rect-tube → entity list
└── tests/
    ├── test_format.py
    ├── test_document.py
    ├── test_hello_surface.py
    └── test_rect_tube.py
```
