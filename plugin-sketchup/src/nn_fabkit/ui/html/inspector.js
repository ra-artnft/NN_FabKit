// NN FabKit Inspector — Sprint A.
// Vanilla JS, без сборки. Загружает каталог через bootstrap-payload от Ruby
// (NN::FabKit::UI::Inspector#push_bootstrap), рисует список с поиском.
//
// Контракт с Ruby:
//   * sketchup.nn_inspector_ready()  — JS → Ruby, сигнал «страница готова».
//   * window.NNInspector.bootstrap(payload) — Ruby → JS, заливает каталог.
//
// Sprint B добавит createRectTube callback; Sprint C — selection updates.

(function () {
  "use strict";

  var state = {
    version:        null,
    catalog:        null,    // полный JSON из rect_tube
    grades:         [],
    defaultGrade:   null,
    selectedTypesize: null,
    filter:         ""
  };

  var els = {};

  function $(id) { return document.getElementById(id); }

  function init() {
    els.version     = $("nn-version");
    els.catalog     = $("nn-catalog");
    els.catalogMeta = $("nn-catalog-meta");
    els.search      = $("nn-search");
    els.length      = $("nn-length");
    els.grade       = $("nn-grade");
    els.createBtn   = $("nn-create-btn");
    els.formHint    = $("nn-form-hint");

    els.search.addEventListener("input", function (e) {
      state.filter = e.target.value.trim().toLowerCase();
      renderCatalog();
    });

    els.createBtn.addEventListener("click", onCreateClick);

    // Стандартный мост HtmlDialog → Ruby. window.sketchup появляется только
    // когда страница открыта внутри SU; в обычном браузере её нет — это
    // защита от ошибок при offline-просмотре файла.
    if (window.sketchup && typeof window.sketchup.nn_inspector_ready === "function") {
      window.sketchup.nn_inspector_ready();
    } else {
      els.catalogMeta.textContent = "Inspector открыт вне SketchUp — данные не подгружены.";
    }
  }

  function bootstrap(payload) {
    payload = payload || {};
    state.version      = payload.version || null;
    state.catalog      = payload.catalog || { items: [] };
    state.grades       = payload.grades || [];
    state.defaultGrade = payload.default_grade || null;

    els.version.textContent = state.version ? "v" + state.version : "v?";
    renderGradeOptions();
    renderCatalog();
    updateCreateButton();
  }

  function renderGradeOptions() {
    els.grade.innerHTML = "";
    var grades = state.grades.length ? state.grades : [""];
    grades.forEach(function (g) {
      var opt = document.createElement("option");
      opt.value = g;
      opt.textContent = g.length ? g : "—";
      if (state.defaultGrade && g === state.defaultGrade) opt.selected = true;
      els.grade.appendChild(opt);
    });
  }

  function renderCatalog() {
    var items = (state.catalog && state.catalog.items) || [];
    var filtered = state.filter
      ? items.filter(function (it) {
          return (it.typesize || "").toLowerCase().indexOf(state.filter) !== -1;
        })
      : items;

    var gost = (state.catalog && state.catalog.gost) || "";
    if (filtered.length === items.length) {
      els.catalogMeta.textContent =
        "Типоразмеров: " + items.length +
        (gost ? ". Источник: ГОСТ " + gost + "." : ".");
    } else {
      els.catalogMeta.textContent =
        "Показано " + filtered.length + " из " + items.length + ".";
    }

    els.catalog.innerHTML = "";

    if (!filtered.length) {
      var empty = document.createElement("li");
      empty.className = "nn-catalog-empty";
      empty.textContent = items.length
        ? "Ничего не найдено."
        : "Каталог пуст.";
      els.catalog.appendChild(empty);
      return;
    }

    var frag = document.createDocumentFragment();
    filtered.forEach(function (item) {
      frag.appendChild(buildRow(item));
    });
    els.catalog.appendChild(frag);
  }

  function buildRow(item) {
    var params  = item.params  || {};
    var derived = item.derived || {};
    var w = Number(params.width_mm)  || 0;
    var h = Number(params.height_mm) || 0;
    var wall = params.wall_mm;
    var mass = derived.mass_per_m_kg;

    var li = document.createElement("li");
    li.className = "nn-catalog-item";
    if (state.selectedTypesize === item.typesize) {
      li.classList.add("is-selected");
    }
    li.dataset.typesize = item.typesize;
    li.setAttribute("role", "option");
    li.title = item.typesize +
               (wall != null ? "  стенка " + wall + " мм" : "") +
               (mass != null ? "  •  " + mass + " кг/м" : "");

    var thumbCell = document.createElement("span");
    thumbCell.className = "nn-thumb-cell";
    thumbCell.appendChild(buildThumb(w, h));

    var typesize = document.createElement("span");
    typesize.className = "nn-typesize";
    typesize.textContent = item.typesize;

    var massEl = document.createElement("span");
    massEl.className = "nn-mass";
    massEl.textContent = (mass != null ? mass : "—") + " кг/м";

    li.appendChild(thumbCell);
    li.appendChild(typesize);
    li.appendChild(massEl);

    li.addEventListener("click", function () {
      selectItem(item.typesize);
    });

    return li;
  }

  // Маленькая SVG-иконка сечения с реальным aspect ratio. Помогает глазу
  // быстро отличать квадрат от прямоугольника в длинном списке.
  function buildThumb(w, h) {
    var thumb = document.createElement("span");
    thumb.className = "nn-thumb";
    var maxSide = Math.max(w, h, 1);
    var size = 18;
    var pxW = Math.max(6, Math.round(size * (w / maxSide)));
    var pxH = Math.max(4, Math.round(size * (h / maxSide)));
    thumb.style.width  = pxW + "px";
    thumb.style.height = pxH + "px";
    return thumb;
  }

  function selectItem(typesize) {
    state.selectedTypesize = typesize;
    var rows = els.catalog.querySelectorAll(".nn-catalog-item");
    rows.forEach(function (el) {
      el.classList.toggle("is-selected", el.dataset.typesize === typesize);
    });
    updateCreateButton();
  }

  function updateCreateButton() {
    var hasSelection = !!state.selectedTypesize;
    els.createBtn.disabled = !hasSelection;
    if (hasSelection) {
      els.formHint.textContent = "Будет создан компонент «Труба " +
                                 state.selectedTypesize + "».";
    } else {
      els.formHint.textContent = "Выбери типоразмер из списка выше.";
    }
  }

  function onCreateClick() {
    if (!state.selectedTypesize) return;
    var lengthMm = Number(els.length.value);
    if (!isFinite(lengthMm) || lengthMm <= 0) {
      els.formHint.textContent = "Длина должна быть положительным числом.";
      els.length.focus();
      return;
    }
    var grade = els.grade.value || "";
    if (window.sketchup && typeof window.sketchup.nn_create_rect_tube === "function") {
      els.createBtn.disabled = true;
      els.formHint.textContent = "Создаём…";
      window.sketchup.nn_create_rect_tube(
        state.selectedTypesize, grade, lengthMm
      );
    } else {
      els.formHint.textContent = "Inspector открыт вне SketchUp — действие недоступно.";
    }
  }

  // Ruby уведомляет о завершении create — вернуть кнопку и подсказку в норму.
  function createDone(result) {
    els.createBtn.disabled = !state.selectedTypesize;
    if (result && result.ok) {
      els.formHint.textContent = "Создано: " + (result.name || "—");
    } else if (result && result.error) {
      els.formHint.textContent = "Ошибка: " + result.error;
    } else {
      updateCreateButton();
    }
  }

  // Глобальный экспорт для Ruby execute_script.
  window.NNInspector = {
    bootstrap:  bootstrap,
    createDone: createDone
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
