// NN FabKit Inspector — Sprint B.
// Vanilla JS, без сборки. Загружает каталог через bootstrap-payload от Ruby
// (NN::FabKit::UI::Inspector#push_bootstrap), рисует:
//   * Top tabs Metal FAB / Дерево FAB.
//   * Metal pane: supplier label + Профильная труба (subgroup filters
//     Все / Квадратные / Прямоугольные + поиск + список) + форма create.
//   * Wood pane: stub «в разработке».
//
// Контракт с Ruby:
//   * sketchup.nn_inspector_ready()
//     JS → Ruby, страница готова. Ruby отвечает window.NNInspector.bootstrap(payload).
//   * sketchup.nn_create_rect_tube(typesize, grade, length_mm)
//     JS → Ruby, создать DC. Ruby отвечает window.NNInspector.createDone({ok, ...}).

(function () {
  "use strict";

  var state = {
    version:          null,
    catalog:          null,    // полный JSON из rect_tube
    grades:           [],
    defaultGrade:     null,
    selectedTypesize: null,
    filter:           "",
    subgroup:         "all",   // 'all' | 'square' | 'rect'
    activePane:       "metal"  // 'metal' | 'wood'
  };

  var els = {};

  function $(id) { return document.getElementById(id); }

  function init() {
    els.version       = $("nn-version");
    els.catalog       = $("nn-catalog");
    els.catalogMeta   = $("nn-catalog-meta");
    els.search        = $("nn-search");
    els.length        = $("nn-length");
    els.grade         = $("nn-grade");
    els.createBtn     = $("nn-create-btn");
    els.formHint      = $("nn-form-hint");
    els.supplierName  = $("nn-supplier-name");
    els.countAll      = $("nn-count-all");
    els.countSquare   = $("nn-count-square");
    els.countRect     = $("nn-count-rect");
    els.tabMetal      = $("nn-tab-metal");
    els.tabWood       = $("nn-tab-wood");
    els.paneMetal     = $("nn-pane-metal");
    els.paneWood      = $("nn-pane-wood");

    // Top tabs
    [els.tabMetal, els.tabWood].forEach(function (tab) {
      tab.addEventListener("click", function () {
        switchPane(tab.dataset.pane);
      });
    });

    // Search
    els.search.addEventListener("input", function (e) {
      state.filter = e.target.value.trim().toLowerCase();
      renderCatalog();
    });

    // Subgroup filter chips
    document.querySelectorAll(".nn-chip[data-subgroup]").forEach(function (chip) {
      chip.addEventListener("click", function () {
        state.subgroup = chip.dataset.subgroup;
        document.querySelectorAll(".nn-chip[data-subgroup]").forEach(function (c) {
          c.classList.toggle("is-active", c === chip);
        });
        renderCatalog();
      });
    });

    // Create button
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

  function switchPane(name) {
    state.activePane = name;
    els.tabMetal.classList.toggle("is-active", name === "metal");
    els.tabWood.classList.toggle("is-active", name === "wood");
    els.tabMetal.setAttribute("aria-selected", name === "metal" ? "true" : "false");
    els.tabWood.setAttribute("aria-selected", name === "wood" ? "true" : "false");
    els.paneMetal.classList.toggle("is-active", name === "metal");
    els.paneWood.classList.toggle("is-active", name === "wood");
    els.paneMetal.hidden = (name !== "metal");
    els.paneWood.hidden  = (name !== "wood");
  }

  function bootstrap(payload) {
    payload = payload || {};
    state.version      = payload.version || null;
    state.catalog      = payload.catalog || { items: [] };
    state.grades       = payload.grades || [];
    state.defaultGrade = payload.default_grade || null;

    els.version.textContent = state.version ? "v" + state.version : "v?";

    var supplier = state.catalog && state.catalog.supplier;
    if (supplier && supplier.name) {
      var line = supplier.name;
      if (supplier.city) line += " · " + supplier.city;
      els.supplierName.textContent = line;
    } else {
      els.supplierName.textContent = "Поставщик не указан";
    }

    renderGradeOptions();
    renderSubgroupCounts();
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

  function isSquare(item) {
    var p = item.params || {};
    return Number(p.width_mm) === Number(p.height_mm);
  }

  function renderSubgroupCounts() {
    var items = (state.catalog && state.catalog.items) || [];
    var sq = items.filter(isSquare).length;
    var rect = items.length - sq;
    els.countAll.textContent    = items.length;
    els.countSquare.textContent = sq;
    els.countRect.textContent   = rect;
  }

  function renderCatalog() {
    var items = (state.catalog && state.catalog.items) || [];

    // 1. Subgroup filter (square/rect/all)
    var bySub = items.filter(function (it) {
      if (state.subgroup === "square") return isSquare(it);
      if (state.subgroup === "rect")   return !isSquare(it);
      return true;
    });

    // 2. Search filter
    var filtered = state.filter
      ? bySub.filter(function (it) {
          return (it.typesize || "").toLowerCase().indexOf(state.filter) !== -1;
        })
      : bySub;

    // Meta line
    var subLabel = state.subgroup === "square" ? "квадратных"
                 : state.subgroup === "rect"   ? "прямоугольных"
                 : "всего";
    if (filtered.length === bySub.length) {
      els.catalogMeta.textContent = "Показано " + bySub.length + " " + subLabel + ".";
    } else {
      els.catalogMeta.textContent =
        "Показано " + filtered.length + " из " + bySub.length + " " + subLabel + ".";
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
