<script>
(function () {
  const STORAGE_KEY = 'exercise-skip:v1';

  function loadState() {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}'); }
    catch { return {}; }
  }

  function saveState(state) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  function pageKeyPrefix() {
    return location.pathname + '::';
  }

  function isSkipped(state, exId) {
    return !!state[pageKeyPrefix() + exId];
  }

  function setSkipped(state, exId, skipped) {
    const key = pageKeyPrefix() + exId;
    if (skipped) state[key] = true; else delete state[key];
    saveState(state);
  }

  function isGraded(exId) {
    return !!document.querySelector('[data-exercise="' + exId + '"] .exercise-grade.alert-success');
  }

  function applySkipAttr(el, skipped, graded) {
    if (skipped) {
      el.setAttribute('data-skip', 'true');
      el.setAttribute('data-complete', 'true');
    } else {
      el.removeAttribute('data-skip');
      if (!graded) el.removeAttribute('data-complete');
    }
  }

  function applyToExerciseCells(exId, fn) {
    document
      .querySelectorAll('.cell.wait[data-check="true"][data-exercise="' + exId + '"]')
      .forEach(fn);
  }

  function buildButton(state, exId) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'btn btn-sm btn-outline-secondary skip-exercise-btn';
    btn.dataset.exercise = exId;
    const skipped = isSkipped(state, exId);
    btn.textContent = skipped ? 'Undo skip' : 'Skip exercise';
    btn.setAttribute('aria-pressed', skipped ? 'true' : 'false');
    btn.style.margin = '0.5rem 0';

    btn.addEventListener('click', function () {
      const nowSkipped = btn.getAttribute('aria-pressed') !== 'true';
      const graded = isGraded(exId);
      applyToExerciseCells(exId, function (cell) { applySkipAttr(cell, nowSkipped, graded); });
      setSkipped(state, exId, nowSkipped);
      btn.textContent = nowSkipped ? 'Undo skip' : 'Skip exercise';
      btn.setAttribute('aria-pressed', nowSkipped ? 'true' : 'false');
    });
    return btn;
  }

  document.addEventListener('DOMContentLoaded', function () {
    const state = loadState();
    const cells = Array.from(document.querySelectorAll('.cell.wait[data-check="true"][data-exercise]'));

    // Group cells by exercise id. Some exercises end up with nested .cell nodes that
    // both match the selector; we only want one skip button per exercise.
    const byExercise = new Map();
    cells.forEach(function (cell) {
      const exId = cell.getAttribute('data-exercise');
      if (!exId) return;
      if (!byExercise.has(exId)) byExercise.set(exId, []);
      byExercise.get(exId).push(cell);
    });

    byExercise.forEach(function (exCells, exId) {
      // Reapply stored skip state to all matching cells
      const skipped = isSkipped(state, exId);
      const graded = isGraded(exId);
      exCells.forEach(function (cell) { applySkipAttr(cell, skipped, graded); });

      // If the button already exists (e.g., script included twice), do nothing
      if (document.querySelector('.skip-exercise-btn[data-exercise="' + exId + '"]')) return;

      // Choose the outer-most matching cell to insert the button before
      const targetCell = exCells.find(function (candidate) {
        return !exCells.some(function (other) { return other !== candidate && other.contains(candidate); });
      }) || exCells[0];

      const btn = buildButton(state, exId);
      const parent = targetCell.parentElement || targetCell;
      parent.insertBefore(btn, targetCell);
    });
  });
})();
</script>
