/* =============================================================================
 * Agentforce Specialist Academy — app
 * Client-side learning app: hash routing, lesson renderer, quiz engine,
 * progress persistence (localStorage), search, keyboard shortcuts.
 *
 * Additions over the Dev I & II engine this was derived from:
 *   - exam blueprint page      (#/exam)
 *   - glossary page            (#/glossary)
 *   - "what changed" deltas    (#/whats-new)
 *   - Summer '26 maintenance track toggle (re-baselines overall progress)
 *   - search across the glossary and the rendered guides
 *   - progress export / import as JSON, print, per-module reset
 *
 * Data model is unchanged: ACADEMY is a flat array of 17 modules, each with
 *   { id, n, title, icon, color, tagline, domain, maint, guide, art[],
 *     objectives[], lessons[{ title, mins, blocks[] }], quiz { title, mins,
 *     questions[{ q, opts[], a, why }] } }
 * Extra optional globals: EXAM, GLOSSARY, DELTA, GUIDE (blob base URL).
 * ============================================================================= */

/* ------------------------- theme ------------------------- */

function getTheme() {
  return document.documentElement.getAttribute('data-theme') || 'dark';
}
function setTheme(t) {
  document.documentElement.setAttribute('data-theme', t);
  localStorage.setItem('afacademy-theme', t);
  const btn = document.getElementById('themeToggle');
  if (btn) btn.textContent = t === 'dark' ? '🌙' : '☀️';
}

/* ------------------------- small helpers ------------------------- */

const $  = (s, c) => (c || document).querySelector(s);
const $$ = (s, c) => Array.from((c || document).querySelectorAll(s));

const esc = (s = '') => s.replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
const cyrb53 = s => { let h = 9; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 2654435761); return (h ^ h >>> 9) >>> 0; };

const MODULES = ACADEMY;
// REPO is declared once, in curriculum.js, and shared like GUIDE/EXAM/GLOSSARY.
// Redeclaring it here is a SyntaxError: these are classic scripts sharing one
// global scope, so a duplicate top-level const/let aborts this whole file and
// the site renders blank. check-project.mjs asserts there are no such clashes.
const REPO_BLOB = REPO + '/blob/main/';
const MAINT_MODULES = MODULES.filter(m => m.maint);

/* ------------------------- progress store ------------------------- */

const KEY = 'afacademy-v1';
let store = load();

function load() {
  try { return JSON.parse(localStorage.getItem(KEY)) || defaultStore(); }
  catch (e) { return defaultStore(); }
}
function defaultStore() {
  return { done: {}, quiz: {}, best: {}, stars: {}, guide: {}, lastOpen: null, track: false };
}
function trackOn() { return !!store.track; }
function activeModules() { return trackOn() && MAINT_MODULES.length ? MAINT_MODULES : MODULES; }
function save() {
  try { localStorage.setItem(KEY, JSON.stringify(store)); } catch (e) {}
}
function lessonDone(mid, li)  { return !!store.done[mid + ':' + li]; }
function markDone(mid, li, v) { store.done[mid + ':' + li] = v; save(); }
function guideRead(mid)       { return !!(store.guide && store.guide[mid]); }
function markGuideRead(mid, v) { if (!store.guide) store.guide = {}; store.guide[mid] = v; save(); }
function moduleProgress(mid) {
  const m = byId(mid);
  if (!m) return { done: 0, total: 0, pct: 0, quizPct: 0, complete: 0, totalUnits: 0 };
  const lessons = m.lessons.length;
  let done = 0;
  if (guideRead(mid)) {
    done = lessons;                       // reading the full guide = all lessons
  } else {
    m.lessons.forEach((_, i) => { if (lessonDone(mid, i)) done++; });
  }
  // lessons are worth 2 units, quiz worth 1
  const units = lessons * 2 + 1;
  const earned = done * 2 + (store.quiz[mid] ? 1 : 0);
  const pct = Math.round((earned / units) * 100);
  const complete = earned >= units;
  return { done, total: lessons, pct, quizPct: quizPctOf(mid), complete, earned, units };
}
function quizPctOf(mid) {
  const m = byId(mid);
  if (!m || !store.best[mid]) return 0;
  return Math.round((store.best[mid] / m.quiz.questions.length) * 100);
}
function overallPct() {
  const rows = activeModules().map(m => {
    const p = moduleProgress(m.id);
    return p.units ? p.earned / p.units * 100 : 0;
  });
  return rows.length ? Math.round(rows.reduce((a, b) => a + b, 0) / rows.length) : 0;
}

function byId(id) { return MODULES.find(m => m.id === id); }

/* ------------------------- routing ------------------------- */

let route = { view: 'home', mid: null, li: null };

function navigate(view, mid, li) {
  route = { view, mid, li: li != null ? li : null };
  history.replaceState(null, '', '#' + hashFor());
  render();
}
function hashFor() {
  if (route.view === 'phase') return '/phase/' + route.mid;
  if (route.view === 'lesson') return '/lesson/' + route.mid + '/' + route.li;
  if (route.view === 'quiz')  return '/quiz/' + route.mid;
  if (route.view === 'guide') return '/guide/' + route.mid + (route.anchor ? '/' + route.anchor : '');
  if (route.view === 'exam') return '/exam';
  if (route.view === 'whats-new') return '/whats-new';
  if (route.view === 'glossary') return '/glossary' + (route.q ? '/' + route.q : '');
  return '/';
}
function parseHash() {
  const h = decodeURIComponent((location.hash || '#/').replace(/^#/, ''));
  const parts = h.split('/').filter(Boolean);
  if (parts[0] === 'phase') return { view: 'phase', mid: parts[1] };
  if (parts[0] === 'lesson') return { view: 'lesson', mid: parts[1], li: Number(parts[2]) };
  if (parts[0] === 'quiz')   return { view: 'quiz', mid: parts[1] };
  if (parts[0] === 'guide')  return { view: 'guide', mid: parts[1], anchor: parts[2] || null };
  if (parts[0] === 'exam')   return { view: 'exam' };
  if (parts[0] === 'whats-new') return { view: 'whats-new' };
  if (parts[0] === 'glossary') return { view: 'glossary', q: parts.slice(1).join(' ') || '' };
  return { view: 'home' };
}

/* ------------------------- renderer ------------------------- */

const view = $('#view');

function render() {
  const mod = route.mid ? byId(route.mid) : null;
  const r = parseHash(); // keep in sync with friendly URLs

  // These views dereference `mod` unconditionally. A hand-edited or stale URL
  // breaks that in two ways: #/guide/01-Agentforce-Fundamentals.md passes a
  // filename where a module id is expected, and #/phase/ passes nothing at all.
  // byId() then yields undefined or null and the renderer throws on mod.id,
  // leaving a half-rendered page. Send those routes home instead.
  // parseHash() reads location.hash, so the hash has to be rewritten too, not
  // just `route` - otherwise the next render() sees the same bad hash and loops.
  const NEEDS_MODULE = { phase: 1, lesson: 1, quiz: 1, guide: 1 };
  if (NEEDS_MODULE[r.view] && !mod) {
    history.replaceState(null, '', '#/');
    route = { view: 'home' };
    return render();
  }

  const pageName = r.view === 'exam' ? 'Exam blueprint'
    : r.view === 'whats-new' ? 'What changed'
    : r.view === 'glossary' ? 'Glossary'
    : mod ? mod.title : '';
  document.title = 'Agentforce Specialist Academy' + (pageName ? ' · ' + pageName : '');

  // sidebar
  renderSidebar();
  document.body.classList.toggle('track-on', trackOn());
  const tt = $('#trackToggle');
  if (tt) {
    tt.classList.toggle('on', trackOn());
    const lbl = $('#trackLabel');
    if (lbl) lbl.textContent = trackOn() ? 'Maintenance ON' : 'Maintenance track';
  }

  // topbar progress
  const tp = $('#topPct');
  if (tp) tp.textContent = overallPct() + '%';
  const tbar = $('#topBar');
  if (tbar) tbar.style.width = overallPct() + '%';
  bindTopSearch();

  if (r.view === 'phase')  return renderModule(mod);
  if (r.view === 'lesson') return renderLesson(mod, Math.min(Number(r.li) || 0, mod.lessons.length - 1));
  if (r.view === 'quiz')   return renderQuiz(mod);
  if (r.view === 'guide')  return renderGuide(mod);
  if (r.view === 'exam')   return renderExam();
  if (r.view === 'whats-new') return renderDelta();
  if (r.view === 'glossary') return renderGlossary(r.q);
  renderHome();
}

/* ------------------------- sidebar ------------------------- */

function renderSidebar() {
  const aside = $('aside.sidebar');
  aside.innerHTML = `
    <div class="side-brand">
      <div class="logo">🤖</div>
      <div><b>Agentforce Specialist Academy</b><span>17-phase roadmap · ${esc(EXAM.code)}</span></div>
    </div>`;

  const nav = document.createElement('nav');
  nav.className = 'side-nav';

  const home = document.createElement('a');
  home.href = '#/';
  home.className = 'side-link' + (route.view === 'home' ? ' active' : '');
  home.innerHTML = `<span class="sli">🏠</span> Dashboard`;
  nav.appendChild(home);

  const exam = document.createElement('a');
  exam.href = '#/exam';
  exam.className = 'side-link' + (route.view === 'exam' ? ' active' : '');
  exam.innerHTML = `<span class="sli">📘</span> Exam blueprint <span class="sr-go">${EXAM.release}</span>`;
  nav.appendChild(exam);

  const delta = document.createElement('a');
  delta.href = '#/whats-new';
  delta.className = 'side-link' + (route.view === 'whats-new' ? ' active' : '');
  delta.innerHTML = `<span class="sli">🔄</span> What changed`;
  nav.appendChild(delta);

  const gloss = document.createElement('a');
  gloss.href = '#/glossary';
  gloss.className = 'side-link' + (route.view === 'glossary' ? ' active' : '');
  gloss.innerHTML = `<span class="sli">📚</span> Glossary`;
  nav.appendChild(gloss);

  const tools = document.createElement('a');
  tools.href = '#';
  tools.className = 'side-link';
  tools.id = 'sideTrack';
  tools.innerHTML = `<span class="sli">${trackOn() ? '🟢' : '⚪'}</span> ${trackOn() ? 'Maintenance track: on' : 'Maintenance track: off'}`;
  nav.appendChild(tools);

  MODULES.forEach(m => {
    const p = moduleProgress(m.id);
    const a = document.createElement('a');
    a.href = '#/phase/' + m.id;
    a.className = 'side-phase' + (m.maint ? ' m-maint' : '') + (route.mid === m.id ? ' active' : '');
    a.innerHTML = `
      <span class="sp-n" style="border-color:${m.color}">${String(m.n).padStart(2, '0')}</span>
      <span class="sp-body">
        <span class="sp-title">${esc(m.title)}${m.maint ? ' <em class="sh-flag">upd</em>' : ''}</span>
        <span class="sp-bar"><i style="width:${p.pct}%;background:${m.color}"></i></span>
      </span>
      <span class="sp-pct">${p.pct}%</span>
      ${p.complete ? '<span class="sp-ok">✓</span>' : ''}`;
    nav.appendChild(a);
  });

  aside.appendChild(nav);

  const progWrap = document.createElement('div');
  progWrap.className = 'side-progress';
  const op = overallPct();
  const scope = trackOn() ? MAINT_MODULES : MODULES;
  progWrap.innerHTML = `<div class="sp-bar big"><i style="width:${op}%"></i></div>
    <div class="side-prog-label"><b>${op}%</b> of ${trackOn() ? 'maintenance track' : 'roadmap'} complete
      <button class="btn ghost sm" id="sideExport" style="margin-top:8px;width:100%">⬇ Export progress</button>
      <button class="btn ghost sm" id="sideImport" style="margin-top:6px;width:100%">⬆ Import progress</button>
    </div>`;
  aside.appendChild(progWrap);

  const foot = document.createElement('div');
  foot.className = 'sb-foot';
  foot.innerHTML = `<a class="l" target="_blank" rel="noopener" href="${REPO}">GitHub repo</a>`;
  aside.appendChild(foot);
  void scope;
}

/* ------------------------- home ------------------------- */

function renderHome() {
  const op = overallPct();
  const scope = activeModules();
  const totalLessons = scope.reduce((a, m) => a + m.lessons.length, 0);
  const totalMin = scope.reduce((a, m) => a + m.lessons.reduce((x, l) => x + l.mins, 0) + m.quiz.mins, 0);
  const totalDone = scope.reduce((a, m) => a + moduleProgress(m.id).earned, 0);
  const totalUnits = scope.reduce((a, m) => a + moduleProgress(m.id).units, 0);

  // continue card
  let next = null;
  for (const m of scope) {
    for (let i = 0; i < m.lessons.length; i++) {
      if (!lessonDone(m.id, i)) { next = { m, i }; break; }
    }
    if (next) break;
  }
  if (!next) next = { m: scope[0], i: 0 };
  let resume = null;
  if (store.lastOpen && byId(store.lastOpen.mid)) {
    const lm = byId(store.lastOpen.mid);
    resume = { m: lm, li: Math.max(0, Math.min(store.lastOpen.li, lm.lessons.length - 1)) };
  }
  if (!resume) resume = { m: next.m, li: next.i };
  const rm = resume.m;
  const rli = resume.li != null && resume.li < rm.lessons.length ? resume.li : 0;

  view.innerHTML = `
    <div class="home-hero reveal">
      <div>
        <div class="hero-kicker">Salesforce AI · ${esc(EXAM.code)} · ${esc(EXAM.release)} blueprint</div>
        <h1 class="hero-title">Become <span class="grad">Agentforce certified</span>, phase by phase.</h1>
        <p class="hero-sub">${scope.length} guided phases, ${totalLessons} lessons, ${scope.length} quizzes — with real Agentforce metadata in the repo to deploy, wire and practise on.</p>
        ${renderExamStrip()}
        ${renderExamFacts()}
        <div class="hero-actions">
          <button class="btn primary" id="startBtn">▶ Continue learning</button>
          <button class="btn ghost" id="phasesBtn">Browse all phases</button>
          <button class="btn ghost" id="examBtn">📘 Exam blueprint</button>
          <span class="hero-meta">📅 ${MODULES.length} phases · self-paced</span>
        </div>
      </div>
      <div class="ring-wrap">
        <div class="ring" style="--p:${op}"><span>${op}<small>%</small></span></div>
        <div class="ring-caption">${trackOn() ? 'maintenance progress' : 'roadmap progress'}</div>
      </div>
    </div>

    ${trackOn() ? `
    <div class="maint-bar reveal">
      <b>Maintenance track on</b>
      <span>${esc(EXAM.maintenance.release)} · recertification due <span class="mb-deadline">${esc(EXAM.maintenance.deadline)}</span></span>
      <span>${MAINT_MODULES.length} phases in scope</span>
      <a class="l" href="#/exam#maintenance">What to revise →</a>
    </div>` : ''}

    <div class="stats reveal">
      <div class="stat"><div class="st-n">${totalDone}<small>/${totalUnits}</small></div><div class="st-l">units completed</div></div>
      <div class="stat"><div class="st-n">${scope.filter(m => moduleProgress(m.id).complete).length}<small>/</small></div><div class="st-l">phases mastered</div></div>
      <div class="stat"><div class="st-n">${scope.filter(m => (store.best[m.id] || 0) >= m.quiz.questions.length).length}<small>/</small></div><div class="st-l">quizzes passed</div></div>
      <div class="stat"><div class="st-n">${totalMin}<small> min</small></div><div class="st-l">~ total study time</div></div>
    </div>

    <div class="home-cards">
      <div class="card continue-card" style="--c:${rm.color}">
        <div class="cc-top"><span class="cc-label">Continue where you left off</span><span class="pill">Phase ${String(rm.n).padStart(2, '0')}</span></div>
        <h3>${esc(rm.lessons[rli].title)}</h3>
        <div class="cc-sub">${esc(rm.title)}</div>
        <div class="sp-bar"><i style="width:${moduleProgress(rm.id).pct}%;background:${rm.color}"></i></div>
        <button class="btn primary sm" id="resumeBtn">Resume →</button>
      </div>
      <div class="card next-card" style="--c:${next.m.color}">
        <div class="cc-top"><span class="cc-label">Next up</span><span class="pill">Phase ${String(next.m.n).padStart(2, '0')}</span></div>
        <h3>${esc(next.m.lessons[next.i].title)}</h3>
        <div class="cc-sub">${esc(next.m.tagline)} · ${next.m.lessons[next.i].mins} min · ${next.m.quiz.questions.length}-question quiz</div>
        <button class="btn sm" id="nextBtn">Open →</button>
      </div>
      <div class="card next-card" style="--c:#7f9cf5">
        <div class="cc-top"><span class="cc-label">Reference</span><span class="pill">${GLOSSARY.length} terms</span></div>
        <h3>Glossary &amp; terminology</h3>
        <div class="cc-sub">Old <b>topics</b> are now <b>subagents</b>. Every legacy alias is listed so your old notes still make sense.</div>
        <a class="btn sm" href="#/glossary">Open →</a>
      </div>
      <div class="card streak-card" style="--c:#e8b93d">
        <div class="cc-top"><span class="cc-label">Learning tips</span></div>
        <h3>3 wins today</h3>
        <ul class="tips">
          <li>Finish <b>one lesson</b> then take its phase quiz.</li>
          <li>Build the <b>agent</b> in your own scratch org, then test it.</li>
          <li>Use <kbd>/</kbd> to search anything, <kbd>t</kbd> for the maintenance track.</li>
        </ul>
      </div>
    </div>

    <div class="grid-head reveal"><h2>Your roadmap</h2><span>${MODULES.length} phases · study in order or jump anywhere${trackOn() ? ' · non-maintenance phases dimmed' : ''}</span></div>
    <div class="module-grid reveal" id="modGrid"></div>`;

  $('#startBtn').addEventListener('click', () => navigate('lesson', rm.id, rli));
  $('#resumeBtn').addEventListener('click', () => navigate('lesson', rm.id, rli));
  $('#nextBtn').addEventListener('click', () => navigate('lesson', next.m.id, next.i));
  $('#phasesBtn').addEventListener('click', () => navigate('phase', scope[0].id));
  $('#examBtn').addEventListener('click', () => navigate('exam'));

  const grid = $('#modGrid');
  MODULES.forEach(m => {
    const p = moduleProgress(m.id);
    const card = document.createElement('a');
    card.href = '#/phase/' + m.id;
    card.className = 'mod-card' + (m.maint ? ' m-maint' : '');
    card.style.setProperty('--c', m.color);
    card.innerHTML = `
      <div class="mc-top">
        <span class="mc-num">${String(m.n).padStart(2, '0')}</span>
        <span class="mc-ico">${esc(m.icon)}</span>
        ${p.complete ? '<span class="mc-done">✓ completed</span>' : ''}
      </div>
      <h3>${esc(m.title)}</h3>
      ${m.maint ? '<div class="mc-tag maint-tag">maintenance track</div>' : ''}
      <div class="mc-tag">${esc(m.tagline)}</div>
      <div class="mc-prog">
        <div class="sp-bar"><i style="width:${p.pct}%;background:${m.color}"></i></div>
        <div class="mc-sub">${p.done}/${p.total} lessons · ${p.quizPct}% quiz</div>
      </div>
      <div class="mc-foot">
        <span>${m.lessons.length} lessons · ${m.quiz.questions.length} quiz</span>
        <span class="mc-arrow">→</span>
      </div>`;
    grid.appendChild(card);
  });
}

/* ------------------------- module/phase page ------------------------- */

function renderModule(mod) {
  const p = moduleProgress(mod.id);
  const quizScore = store.best[mod.id];
  view.innerHTML = `
    <div class="crumb reveal"><a href="#/">Dashboard</a> <span>›</span> <b>${mod.title}</b></div>

    <div class="phase-hero reveal" style="--c:${mod.color}">
      <div class="ph-ico">${esc(mod.icon)}</div>
      <div class="ph-body">
        <div class="ph-kicker">Phase ${String(mod.n).padStart(2, '0')} · ${esc(mod.tagline)}</div>
        <h1>${esc(mod.title)}</h1>
        ${mod.domain ? `<div class="ph-dom">Exam domain <b>${esc(mod.domain)}</b></div>` : ''}
        ${mod.maint ? `<div class="callout warn"><div class="co-ico">⚠️</div><div>${esc(mod.maintNote || 'This phase is part of the ' + EXAM.maintenance.release + ' maintenance track.')}</div></div>` : ''}
        <div class="ph-obj"><span>By the end you can:</span>
          <ul>${mod.objectives.map(o => `<li>${esc(o)}</li>`).join('')}</ul>
        </div>
      </div>
      <div class="ph-side">
        <div class="ring sm" style="--p:${p.pct};--c:${mod.color}"><span>${p.pct}<small>%</small></span></div>
        <div class="ph-stats">
          <span>${p.done}/${p.total} lessons</span>
          <span>${store.quiz[mod.id] ? '✓ quiz taken' : 'quiz pending'}</span>
        </div>
        <a class="btn primary sm" href="#/guide/${mod.id}">📖 Read the full guide</a>
        <a class="btn ghost sm" target="_blank" rel="noopener"
           href="${GUIDE}${mod.guide}">📄 raw</a>
        <button class="btn ghost sm" id="resetMod">↺ Reset phase</button>
      </div>
    </div>

    <div class="lessons reveal">
      <a class="lesson-row guide-row" href="#/guide/${mod.id}" style="--c:${mod.color}">
        <span class="lr-state guide">📖</span>
        <span class="lr-info">
          <b>Full module guide</b>
          <span class="lr-meta">complete walkthrough · sections, tables, code & checklists${guideRead(mod.id) ? ' · read ✓' : ''}</span>
        </span>
        <span class="lr-arrow">→</span>
      </a>
      ${mod.lessons.map((l, i) => `
        <a class="lesson-row" href="#/lesson/${mod.id}/${i}" style="--c:${mod.color}">
          <span class="lr-state">${lessonDone(mod.id, i) ? '<span class="lr-done">✓</span>' : String(i + 1).padStart(2, '0')}</span>
          <span class="lr-info">
            <b>${l.title}</b>
            <span class="lr-meta">${l.mins} min</span>
          </span>
          <span class="lr-arrow">→</span>
        </a>`).join('')}
    </div>

    <div class="quiz-card reveal" style="--c:${mod.color}">
      <div class="qc-left">
        <div class="qc-ico">🧠</div>
        <div>
          <h3>Module quiz · check your understanding</h3>
          <p>${mod.quiz.questions.length} questions · ${mod.quiz.mins} min.
             ${quizScore != null ? `Your best: <b>${quizScore}/${mod.quiz.questions.length}</b> (${Math.round(quizScore / mod.quiz.questions.length * 100)}%).` : 'Not attempted yet.'}
          </p>
        </div>
      </div>
      <div class="qc-right">
        ${quizScore != null && quizScore === mod.quiz.questions.length ? '<span class="qc-perfect">★ perfect</span>' : ''}
        <a class="btn primary" href="#/quiz/${mod.id}">${quizScore != null ? 'Retake quiz' : 'Take quiz →'}</a>
      </div>
    </div>

    <div class="artifacts reveal">
      <h3>📦 Real artifacts in this repo</h3>
      <div class="artifacts-grid">
        ${mod.art.map(a => `
          <a class="artifact" target="_blank" rel="noopener"
             href="${REPO_BLOB}${a.href}" style="--c:${mod.color}">
            <span class="a-ico">🗂️</span> <span>${esc(a.label)}</span>
          </a>`).join('')}
      </div>
    </div>

    <div class="phase-nav reveal">
      ${mod.n > 1 ? `<a class="btn ghost" href="#/phase/${MODULES[mod.n - 2].id}">← ${esc(MODULES[mod.n - 2].title)}</a>` : '<span></span>'}
      ${mod.n < MODULES.length
        ? `<a class="btn primary" href="#/phase/${MODULES[mod.n].id}">${esc(MODULES[mod.n].title)} →</a>`
        : `<a class="btn primary" href="#/quiz/${mod.id}">🎯 Take the final quiz</a>`}
    </div>`;

  const rm2 = $('#resetMod');
  if (rm2) rm2.addEventListener('click', () => {
    if (!confirm(`Reset all progress for "${mod.title}"?`)) return;
    mod.lessons.forEach((_, i) => delete store.done[mod.id + ':' + i]);
    delete store.quiz[mod.id];
    delete store.best[mod.id];
    delete store.guide[mod.id];
    save();
    toast('Phase reset');
    render();
  });
}

/* ------------------------- lesson page ------------------------- */

function renderLesson(mod, li) {
  const lesson = mod.lessons[li];
  const prevI = li > 0 ? li - 1 : null;
  const nextI = li < mod.lessons.length - 1 ? li + 1 : null;
  const done = lessonDone(mod.id, li);

  view.innerHTML = `
    <div class="crumb reveal"><a href="#/">Dashboard</a> <span>›</span> <a href="#/phase/${mod.id}">${esc(mod.title)}</a> <span>›</span> <b>${esc(lesson.title)}</b></div>

    <div class="lesson-wrap reveal">
      <aside class="lesson-toc">
        <div class="toc-title">${esc(mod.title)}</div>
        ${mod.lessons.map((l, i) => `
          <a href="#/lesson/${mod.id}/${i}" class="toc-item ${i === li ? 'active' : ''}">
            <span class="toc-state">${lessonDone(mod.id, i) ? '✓' : i + 1}</span>
            <span>${esc(l.title)}<span class="toc-min">${l.mins}′</span></span>
          </a>`).join('')}
        <a href="#/guide/${mod.id}" class="toc-item toc-guide" style="--c:${mod.color}">
          <span class="toc-state">📖</span><span>Full module guide</span>
        </a>
        <a href="#/quiz/${mod.id}" class="toc-item toc-quiz" style="--c:${mod.color}">
          <span class="toc-state">🧠</span><span>Module quiz</span>
        </a>
        <button class="toc-item toc-guide" id="printLesson">🖨 Print / save PDF</button>
      </aside>

      <article class="lesson article" style="--c:${mod.color}">
        <div class="lesson-head" style="--c:${mod.color}">
          <div class="lh-meta">Phase ${String(mod.n).padStart(2, '0')} · Lesson ${li + 1} of ${mod.lessons.length} · ${lesson.mins} min${mod.domain ? ' · ' + esc(mod.domain) : ''}</div>
          <h1>${esc(lesson.title)}</h1>
        </div>
        <div class="chips">
          ${mod.objectives.map((o, i) => `<span class="chip-o">${esc(o)}</span>`).join('')}
        </div>

        <div class="blocks">${lesson.blocks.map(renderBlock).join('')}</div>

        <div class="lesson-foot">
          <div class="lf-left">
            ${done
              ? '<button class="btn ghost sm" id="unbtn">↩ Mark as unlearned</button>'
              : `<button class="btn primary" id="doneBtn">✓ Mark lesson complete</button>`}
          </div>
          <div class="lf-right">
            ${prevI != null ? `<a class="btn ghost sm" href="#/lesson/${mod.id}/${prevI}">← Prev</a>` : ''}
            ${nextI != null
              ? `<a class="btn primary sm" href="#/lesson/${mod.id}/${nextI}">Next →</a>`
              : `<a class="btn primary sm" href="#/quiz/${mod.id}">Take the quiz →</a>`}
          </div>
        </div>
      </article>
    </div>`;

  const b = $('#doneBtn'); const u = $('#unbtn');
  if (b) b.addEventListener('click', () => { markDone(mod.id, li, true); store.lastOpen = { mid: mod.id, li }; save(); toast('Lesson complete! 🎉'); render(); });
  if (u) u.addEventListener('click', () => { markDone(mod.id, li, false); render(); });
  const pr = $('#printLesson');
  if (pr) pr.addEventListener('click', () => window.print());
  store.lastOpen = { mid: mod.id, li }; save();
  requestAnimationFrame(() => window.scrollTo(0, 0));
}

/* Minimal markdown renderer for the exercise answer blocks + full guides */
let mdToc = [];            // filled on every md() call: { lvl, slug, label }

function slugify(txt) {
  return String(txt || '')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/[^a-z0-9]+/gi, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase() || 'section';
}

function mdInline(t) {
  return String(t)
    .replace(/`([^`]+)`/g, (m, c) => '\u0001' + c + '\u0002')       // protect inline code
    .replace(/\*\*([^*\n]+)\*\*/g, '<b>$1</b>')
    .replace(/(^|[^*\u0001\u0002])\*([^*\n\u0001\u0002]+?)\*(?!\*)/g, '$1<i>$2</i>')
    .replace(/\u0001([^\u0002]*)\u0002/g, '<code class="inline">$1</code>');
}

function md(src, opts) {
  opts = opts || {};
  const lines = String(src || '').split(/\r?\n/);
  const html = [];
  const seen = new Set();
  mdToc = [];
  let i = 0, inFence = false, fenceBuf = [], fenceLang = '';

  while (i < lines.length) {
    const line = lines[i];

    if (!inFence && /^```/.test(line)) {
      inFence = true; fenceLang = (line.match(/^```(\w*)/) || [])[1] || 'text'; fenceBuf = []; i++; continue;
    }
    if (inFence) {
      if (/^```/.test(line)) {
        html.push(renderCode(fenceLang, fenceBuf));
        inFence = false; fenceBuf = []; fenceLang = ''; i++; continue;
      }
      fenceBuf.push(line); i++; continue;
    }
    if (/^\s*---\s*$/.test(line)) { i++; continue; }

    const head = line.match(/^(#{1,4})\s+(.*)/);
    if (head) {
      const hl = head[1].length;
      if (opts.skipH1 && hl === 1 && !seen.has('h1')) { seen.add('h1'); i++; continue; }
      const lvl = hl + (opts.shift || 0);
      const txt = esc(head[2]);
      const label = mdInline(txt).replace(/<[^>]+>/g, '');
      let slug = slugify(label), base = slug, n = 2;
      while (seen.has(slug)) { slug = base + '-' + n; n++; }
      seen.add(slug);
      if (lvl <= 4) mdToc.push({ lvl, slug, label });
      html.push(`<h${lvl} id="${slug}">${mdInline(txt)}</h${lvl}>`);
      i++; continue;
    }

    if (/^\|/.test(line)) {
      const rows = [];
      while (i < lines.length && /^\|/.test(lines[i])) { rows.push(lines[i]); i++; }
      html.push(mdTable(rows));
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      const items = [];
      const isTask = /^\s*[-*]\s+\[[ xX]\]/.test(line);
      while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) { items.push(lines[i]); i++; }
      if (isTask) {
        html.push('<ul class="task-list">' + items.map(x => {
          const m = x.match(/^\s*[-*]\s+\[([ xX])\]\s+(.*)/);
          if (!m) return `<li>${mdInline(esc(x.replace(/^\s*[-*]\s+/, '')))}</li>`;
          const done = m[1] === 'x' || m[1] === 'X';
          return `<li class="task ${done ? 'done' : ''}"><span class="t-box">${done ? '✓' : ''}</span><span class="t-text">${mdInline(esc(m[2]))}</span></li>`;
        }).join('') + '</ul>');
      } else {
        html.push(`<ul class="tick-list">${items.map(x => `<li>${mdInline(esc(x.replace(/^\s*[-*]\s+/, '')))}</li>`).join('')}</ul>`);
      }
      continue;
    }
    if (/^\s*\d+\.\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) { items.push(lines[i].replace(/^\s*\d+\.\s+/, '')); i++; }
      html.push(`<ol>${items.map(x => `<li>${mdInline(esc(x))}</li>`).join('')}</ol>`);
      continue;
    }
    if (/^\s*$/.test(line)) { i++; continue; }

    const para = [];
    while (i < lines.length) {
      const l = lines[i];
      if (/^\s*$/.test(l) || /^```/.test(l) || /^\|/.test(l) || /^\s*[-*]\s+/.test(l) || /^\s*\d+\.\s+/.test(l) || /^(#{1,4})\s+/.test(l) || /^\s*---\s*$/.test(l)) break;
      para.push(l); i++;
    }
    if (para.length) html.push(`<p>${mdInline(esc(para.join(' ')))}</p>`);
  }

  if (inFence && fenceBuf.length) html.push(renderCode(fenceLang, fenceBuf));
  return html.join('');
}

function renderCode(lang, buf) {
  return `<div class="codeblock"><div class="cb-head"><span class="cb-lang">${esc(lang || 'text')}</span></div><pre><code>${buf.map(esc).join('\n')}</code></pre></div>`;
}

function mdTable(rows) {
  const parseRow = r => r.replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());
  let head = [], body = [], sep = false;
  for (let idx = 0; idx < rows.length; idx++) {
    const r = rows[idx];
    if (idx === 1 && /^[\s|:-]+$/.test(r.replace(/^\|/, '').replace(/\|$/, ''))) { sep = true; head = parseRow(rows[0]); continue; }
    if (sep) body.push(parseRow(r)); else head = parseRow(r);
  }
  if (!sep) { body = rows.map(parseRow); head = []; }
  const thead = head.length ? `<thead><tr>${head.map(h => `<th>${mdInline(esc(h))}</th>`).join('')}</tr></thead>` : '';
  const tbody = `<tbody>${body.map(r => `<tr>${r.map(c => `<td>${mdInline(esc(c))}</td>`).join('')}</tr>`).join('')}</tbody>`;
  return `<div class="tbl"><table>${thead}${tbody}</table></div>`;
}

/* Block renderer for the curriculum blocks */
const LANG_LABEL = {
  apex: 'Apex', soql: 'SOQL', sosl: 'SOSL', xml: 'XML', json: 'JSON',
  yaml: 'YAML', md: 'Markdown', text: 'Text', bash: 'CLI', shell: 'CLI',
  agentscript: 'Agent Script', textfile: 'Flow', flow: 'Flow',
  agent: 'Agent definition', mdt: 'Custom metadata', report: 'Report'
};
function renderBlock(b) {
  switch (b.t) {
    case 'p': return `<p>${esc(b.x)}</p>`;
    case 'h': return `<h2>${esc(b.x)}</h2>`;
    case 'list': return `<ul class="tick-list">${b.items.map(i => `<li>${esc(i)}</li>`).join('')}</ul>`;
    case 'num': return `<ol>${b.items.map(i => `<li>${esc(i)}</li>`).join('')}</ol>`;
    case 'table': return `
      <div class="tbl"><table>
        <thead><tr>${b.head.map(h => `<th>${esc(h)}</th>`).join('')}</tr></thead>
        <tbody>${b.rows.map(r => `<tr>${r.map(c => `<td>${esc(c)}</td>`).join('')}</tr>`).join('')}</tbody>
      </table></div>`;
    case 'code': {
      const cid = 'c' + cyrb53(b.x);
      const bT = b.lang || 'text';
      const nice = LANG_LABEL[bT.toLowerCase()] || bT;
      return `<div class="codeblock">
        <div class="cb-head"><span class="cb-lang lang-${esc(bT.toLowerCase())}">${esc(nice)}</span>${b.name ? `<span class="cb-file">${esc(b.name)}</span>` : ''}<button class="cb-copy" data-copy="${cid}" title="Copy">⧉ Copy</button></div>
        <pre id="${cid}" class="lang-${esc(bT.toLowerCase())}"><code>${esc(b.x)}</code></pre>
      </div>`;
    }
    case 'term': return `
      <div class="tbl term-table"><table>
        <thead><tr><th>Legacy term</th><th>Current term</th><th>Notes</th></tr></thead>
        <tbody>${b.rows.map(r => `<tr><td class="term-old">${esc(r[0])}</td><td class="term-new">${esc(r[1])}</td><td>${esc(r[2] || '')}</td></tr>`).join('')}</tbody>
      </table></div>`;
    case 'delta': return `
      <div class="delta">${b.items.map(d => `
        <div class="delta-item">
          <div class="delta-when">${esc(d.kind)}</div>
          <div class="delta-body">
            <b>${esc(d.title)}</b>
            ${d.from ? `<p><span class="term-old">${esc(d.from)}</span><span class="term-arrow">&rarr;</span><span class="term-new">${esc(d.to)}</span></p>` : ''}
            <p>${esc(d.what)}</p>
          </div>
        </div>`).join('')}</div>`;
    case 'cli': return `<div class="cli-strip">${b.items.map(c => `<span class="cli-cmd">${esc(c)}</span>`).join('')}</div>`;
    case 'bp': return `<div class="bp">${b.rows.map(r => `
        <div class="bp-row">
          <div class="bp-name">${esc(r[0])}</div>
          <div class="bp-track"><i class="bp-fill" style="width:${r[1]}%;background:${r[2] || 'var(--accent)'}"></i></div>
          <div class="bp-pct">${esc(r[1])}%</div>
        </div>`).join('')}</div>`;
    case 'facts': return `<div class="exam-facts">${b.items.map(f => `<span>${esc(f[0])} <b>${esc(f[1])}</b></span>`).join('')}</div>`;
    case 'callout': {
      const icons = { tip: '💡', warn: '⚠️' };
      return `<div class="callout ${esc(b.kind)}"><div class="co-ico">${icons[b.kind] || '💡'}</div><div>${esc(b.x)}</div></div>`;
    }
    case 'selfcheck': return `
      <div class="selfcheck">
        <div class="sc-head"><span class="sc-qmark">?</span> <span>Check yourself</span></div>
        <div class="sc-q">${esc(b.q)}</div>
        <div class="sc-actions"><button class="btn sm ghost showA">Show answer</button></div>
        <div class="sc-a" hidden>${esc(b.a)}</div>
      </div>`;
    case 'ex':
    case 'proj': {
      const isProject = b.t === 'proj';
      const items = b.steps || b.reqs || [];
      const lis = items.map(i =>
        typeof i === 'string'
          ? `<li>${esc(i)}</li>`
          : `<li class="ex-group"><b>${esc(i.h)}</b><ul>${i.items.map(x => `<li>${esc(x)}</li>`).join('')}</ul></li>`
      ).join('');
      const stars = '★'.repeat(b.stars) + '☆'.repeat(Math.max(0, 4 - b.stars));
      const code = b.code ? renderBlock({ t: 'code', ...b.code }) : '';
      const footer = isProject
        ? `<div class="ex-verify">🎯 Success — ${esc(b.success)}</div>`
        : `<div class="ex-verify">✅ Verify — ${esc(b.verify)}</div>`;
      const hasAnswer = typeof EXERCISE_ANSWERS !== 'undefined' && EXERCISE_ANSWERS[b.id];
      const answer = hasAnswer
        ? `<details class="ex-answer"><summary><span class="ea-ico">💡</span><span>Show answer</span><span class="ea-caret">▾</span></summary><div class="ex-answer-body">${md(EXERCISE_ANSWERS[b.id])}</div></details>`
        : '';
      return `
        <div class="ex-card ${isProject ? 'proj' : ''}" data-stars="${b.stars}">
          <div class="ex-head">
            <span class="ex-id">${esc(b.id)}</span>
            <span class="ex-stars">${stars}</span>
          </div>
          <h3 class="ex-title">${esc(b.title)}</h3>
          <p class="ex-obj">${esc(b.obj)}</p>
          ${code}
          <div class="ex-label">${isProject ? '📋 Requirements' : '🧭 Instructions'}</div>
          <ol class="ex-list">${lis}</ol>
          ${footer}
          ${answer}
        </div>`;
    }
    default: return '';
  }
}

/* ------------------------- full guide page ------------------------- */

const GUIDE_DIR = 'guide/';
const guideCache = {};

function fetchGuide(mod) {
  const key = mod.guide;
  if (guideCache[key]) return Promise.resolve(guideCache[key]);
  if (!window.fetch) return Promise.reject(new Error('fetch unavailable'));
  return fetch(GUIDE_DIR + key)
    .then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })
    .then(t => { guideCache[key] = t; return t; });
}

function renderGuide(mod) {
  const p = moduleProgress(mod.id);
  const read = guideRead(mod.id);

  view.innerHTML = `
    <div class="crumb reveal"><a href="#/">Dashboard</a> <span>›</span> <a href="#/phase/${mod.id}">${mod.title}</a> <span>›</span> <b>Full guide</b></div>

    <div class="guide-hero reveal" style="--c:${mod.color}">
      <div class="ph-ico">${mod.icon}</div>
      <div class="ph-body">
        <div class="ph-kicker">Phase ${String(mod.n).padStart(2, '0')} · complete guide</div>
        <h1>${mod.title}</h1>
        <p class="qc-sub">The full roadmap guide is rendered right here — every section, table, code sample and checklist from ${esc(mod.guide)}. ${read ? '<b>You marked this guide as read.</b>' : 'Read it end-to-end, then mark it as read to complete the module.'}</p>
        <div class="guide-meta">
          ${mod.art.map(a => `<a class="artifact" target="_blank" rel="noopener" href="${REPO_BLOB}${a.href}" style="--c:${mod.color}"><span class="a-ico">🗂️</span> <span>${esc(a.label)}</span></a>`).join('')}
        </div>
      </div>
      <div class="ph-side">
        <div class="ring sm" style="--p:${p.pct};--c:${mod.color}"><span>${p.pct}<small>%</small></span></div>
        <div class="ph-stats"><span>${read ? '✓ guide read' : 'guide unread'}</span></div>
        <a class="btn ghost sm" target="_blank" rel="noopener" href="${GUIDE}${mod.guide}">📄 raw on GitHub</a>
      </div>
    </div>

    <div class="guide-wrap reveal">
      <aside class="guide-toc" aria-label="Table of contents">
        <div class="toc-title">On this guide</div>
        <div id="guideToc"><div class="gt-loading">…</div></div>
      </aside>
      <article class="article guide-article" style="--c:${mod.color}">
        <div class="guide-loading"><span class="spinner"></span> Loading the full guide…</div>
      </article>
    </div>

    <div class="lesson-foot reveal">
      <div class="lf-left">
        <button class="btn primary" id="greadBtn">${read ? '✓ Guide read — toggle' : '✔ Mark guide as read'}</button>
      </div>
      <div class="lf-right">
        ${mod.n > 1 ? `<a class="btn ghost sm" href="#/guide/${MODULES[mod.n - 2].id}">← ${MODULES[mod.n - 2].title}</a>` : ''}
        ${mod.n < MODULES.length
          ? `<a class="btn primary sm" href="#/guide/${MODULES[mod.n].id}">${MODULES[mod.n].title} →</a>`
          : `<a class="btn primary sm" href="#/quiz/${mod.id}">🎯 Take the final quiz →</a>`}
      </div>
    </div>`;

  fetchGuide(mod).then(src => {
    const article = $('.guide-article');
    article.innerHTML = md(src, { skipH1: true });
    buildGuideToc();
    if (route.anchor) {
      const el = document.getElementById(route.anchor);
      if (el) requestAnimationFrame(() => el.scrollIntoView({ block: 'start' }));
    }
    const fail = $('.guide-loading', article);
    if (fail) fail.remove();
  }).catch(() => {
    const article = $('.guide-article');
    article.innerHTML = `
      <div class="guide-fail">
        <div class="gf-ico">⚠️</div>
        <h3>Could not load the guide file</h3>
        <p>The full guide is served from <code class="inline">docs/guide/${esc(mod.guide)}</code> in this repo. If you are viewing a local file (not through GitHub Pages), the fetch may be blocked.</p>
        <a class="btn" target="_blank" rel="noopener" href="${GUIDE}${mod.guide}">📄 Open the guide on GitHub</a>
      </div>`;
  });

  const rb = $('#greadBtn');
  if (rb) rb.addEventListener('click', () => { markGuideRead(mod.id, !guideRead(mod.id)); toast(guideRead(mod.id) ? 'Guide marked as read — module complete! 🎉' : 'Guide marked as unread'); render(); });

  store.lastOpen = { mid: mod.id, li: 0 }; save();
  requestAnimationFrame(() => window.scrollTo(0, 0));
}

function buildGuideToc() {
  const toc = $('#guideToc');
  if (!toc) return;
  toc.innerHTML = '';
  if (!mdToc.length) { toc.innerHTML = '<div class="gt-empty">Smooth reading — no section headings in this file.</div>'; return; }
  mdToc.forEach(t => {
    const a = document.createElement('a');
    a.className = 'gt-item lvl' + t.lvl;
    a.textContent = t.label;
    a.href = '#/guide/' + route.mid + '/' + t.slug;
    a.addEventListener('click', e => {
      e.preventDefault();
      const el = document.getElementById(t.slug);
      if (el) {
        route.anchor = t.slug;
        history.replaceState(null, '', '#' + hashFor());
        el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
    toc.appendChild(a);
  });
}

/* ------------------------- quiz page ------------------------- */

function renderQuiz(mod) {
  const qs = mod.quiz.questions;
  const prevBest = store.quiz[mod.id]; // fractional 0..1
  view.innerHTML = `
    <div class="crumb reveal"><a href="#/">Dashboard</a> <span>›</span> <a href="#/phase/${mod.id}">${mod.title}</a> <span>›</span> <b>Quiz</b></div>

    <div class="quiz-top reveal" style="--c:${mod.color}">
      <div>
        <div class="ph-kicker">Phase ${String(mod.n).padStart(2, '0')} · ${mod.quiz.title}</div>
        <h1>${mod.icon} ${mod.title} — Quiz</h1>
        <p class="qc-sub">${qs.length} questions. Answer all, get instant feedback + explanations, then save your score.</p>
      </div>
      <div class="quiz-best">
        ${prevBest != null
          ? `Best: <b>${Math.round(prevBest * qs.length)}/${qs.length}</b> · ${Math.round(prevBest * 100)}%`
          : 'No score yet'}
      </div>
    </div>

    <div class="quiz-list reveal" id="quizList"></div>
    <div class="lesson-foot reveal" id="quizFoot"></div>`;

  const list = $('#quizList');
  qs.forEach((q, qi) => {
    const item = document.createElement('div');
    item.className = 'q-item';
    item.dataset.qi = qi;
    item.innerHTML = `
      <div class="q-head"><span class="q-num">Q${qi + 1}</span><span class="q-prog"></span></div>
      <div class="q-text">${esc(q.q)}</div>
      <div class="q-opts">
        ${q.opts.map((o, oi) => `
          <button class="q-opt" data-oi="${oi}">
            <span class="q-letter">${String.fromCharCode(65 + oi)}</span>
            <span class="q-otext">${esc(o)}</span>
            <span class="q-mark"></span>
          </button>`).join('')}
      </div>
      <div class="q-why" hidden><div class="qw-label"></div><div class="qw-text">${esc(q.why)}</div></div>`;
    list.appendChild(item);
  });

  // footer buttons
  const foot = $('#quizFoot');
  foot.innerHTML = `
    <div class="lf-left"><button class="btn ghost sm" id="resetQuiz">↺ Reset</button></div>
    <div class="lf-right">
      <button class="btn primary" id="saveScore" disabled>✓ Save my score</button>
      <a class="btn ghost sm" href="#/phase/${mod.id}">Back to module</a>
    </div>`;

  $('#resetQuiz').addEventListener('click', () => renderQuiz(mod));

  const saveBtn = $('#saveScore');
  let answered = 0, score = 0;
  const reset = () => { answered = 0; score = 0; saveBtn.disabled = true; };

  $$('.q-item', list).forEach(item => {
    const qi = +item.dataset.qi;
    const prog = $('.q-prog', item);

    $$('.q-opt', item).forEach(btn => {
      btn.addEventListener('click', () => {
        if (item.dataset.state) return; // already answered
        const oi = +btn.dataset.oi;
        const correct = oi === qs[qi].a;
        item.dataset.state = correct ? 'right' : 'wrong';
        prog.textContent = item.dataset.state === 'right' ? '✓ correct' : '✗';
        prog.classList.add(item.dataset.state === 'right' ? 'ok' : 'bad');

        $$('.q-opt', item).forEach(o => {
          const t = +o.dataset.oi;
          o.classList.add(t === qs[qi].a ? 'right' : 'dim');
          if (t === oi && !correct) o.classList.add('wrong');
          o.disabled = true;
        });
        const why = $('.q-why', item);
        why.hidden = false;
        $('.qw-label', why).textContent = item.dataset.state === 'right' ? '🎉 That\u2019s right' : '🙈 Not quite';
        why.classList.add(item.dataset.state === 'right' ? 'ok' : 'bad');

        answered++; if (correct) score++;
        saveBtn.disabled = answered < qs.length;
        if (answered === qs.length) {
          const pct = Math.round(score / qs.length * 100);
          toast(`Quiz complete: ${score}/${qs.length} (${pct}%)`);
          if (pct === 100) confetti();
        }
      });
    });
  });

  saveBtn.addEventListener('click', () => {
    const pct = score / qs.length;
    if (prevBest == null || pct > prevBest) {
      store.quiz[mod.id] = pct;
      store.best[mod.id] = Math.round(pct * qs.length);
      save();
      toast('Score saved — keep it up! 🏆');
      saveBtn.textContent = '✓ Saved — nice work!';
      saveBtn.disabled = true;
    }
    renderSidebar();
  });
}

/* ------------------------- exam blueprint page ------------------------- */

const DOMAIN_COLORS = ['#00a1e0', '#7f9cf5', '#3ddc97', '#f5b13d', '#f56a6a', '#b98cf0'];

function renderExamFacts() {
  return `<div class="exam-facts">${EXAM.facts.map(f => `<span>${esc(f.label)} <b>${esc(f.value)}</b></span>`).join('')}</div>`;
}
function renderExamStrip() {
  return `<div class="exam-strip">${EXAM.domains.map((d, i) => `
    <a class="exam-chip" href="#/exam"><i class="ec-dot" style="background:${DOMAIN_COLORS[i % DOMAIN_COLORS.length]}"></i>${esc(d.name)} <b>${d.weight}%</b></a>`).join('')}</div>`;
}
function renderBlueprint() {
  return `<div class="bp">${EXAM.domains.map((d, i) => `
    <div class="bp-row">
      <div class="bp-name">${esc(d.name)}</div>
      <div class="bp-track"><i class="bp-fill" style="width:${d.weight}%;background:${DOMAIN_COLORS[i % DOMAIN_COLORS.length]}"></i></div>
      <div class="bp-pct">${d.weight}%</div>
    </div>`).join('')}</div>`;
}

function renderExam() {
  view.innerHTML = `
    <div class="crumb reveal"><a href="#/">Dashboard</a> <span>›</span> <b>Exam blueprint</b></div>

    <div class="home-hero reveal" style="--c:#00a1e0">
      <div>
        <div class="hero-kicker">${esc(EXAM.code)} · ${esc(EXAM.release)}</div>
        <h1 class="hero-title">${esc(EXAM.title)}</h1>
        <p class="hero-sub">${esc(EXAM.summary)}</p>
        ${renderExamFacts()}
        <div class="hero-actions">
          <a class="btn primary" href="#/phase/${MODULES[0].id}">Start the roadmap →</a>
          <a class="btn ghost" href="#/whats-new">🔄 What changed</a>
          <a class="btn ghost" href="#/glossary">📚 Glossary</a>
        </div>
      </div>
    </div>

    <div class="article reveal">
      <h2>Domain weighting</h2>
      ${renderBlueprint()}
      <p class="bp-note">${esc(EXAM.weightNote)}</p>

      <h2>What each domain expects</h2>
      ${EXAM.domains.map(d => `
        <h3>${esc(d.name)} · ${d.weight}%</h3>
        <p>${esc(d.blurb)}</p>
        <ul class="tick-list">${d.coverage.map(c => `<li>${esc(c)}</li>`).join('')}</ul>
        <p><b>Covered by:</b> ${d.modules.map(mid => {
          const m = byId(mid);
          return m ? `<a class="l" href="#/phase/${m.id}">Phase ${String(m.n).padStart(2, '0')}</a>` : '';
        }).filter(Boolean).join(' · ') || '<i>cross-phase</i>'}</p>`).join('')}

      <h2>Scoring</h2>
      <ul class="tick-list">${EXAM.scoring.map(s => `<li>${esc(s)}</li>`).join('')}</ul>

      <h2 id="maintenance">Maintenance &amp; recertification</h2>
      <div class="maint-bar">
        <b>${esc(EXAM.maintenance.release)}</b>
        <span>Recertification due <span class="mb-deadline">${esc(EXAM.maintenance.deadline)}</span></span>
        <span>${MAINT_MODULES.length} phases in this roadmap</span>
      </div>
      <p>${esc(EXAM.maintenance.summary)}</p>
      <ul class="tick-list">${EXAM.maintenance.focus.map(f => `<li><b>${esc(f.name)}</b> — ${esc(f.detail)}</li>`).join('')}</ul>
      <p>Press <kbd>t</kbd> (or use the top-bar switch) to grey out everything outside the maintenance track and re-baseline your progress against it.</p>

      <h2>Day-one readiness checklist</h2>
      <ul class="task-list">${EXAM.checklist.map(c => `<li class="task"><span class="t-box"></span><span class="t-text">${esc(c)}</span></li>`).join('')}</ul>

      <h2>Registration</h2>
      <p>${esc(EXAM.registration)}</p>
    </div>`;
  requestAnimationFrame(() => window.scrollTo(0, 0));
}

/* ------------------------- what changed page ------------------------- */

function renderDelta() {
  const groups = [];
  DELTA.forEach(d => {
    let g = groups.find(x => x.release === d.release);
    if (!g) { g = { release: d.release, items: [] }; groups.push(g); }
    g.items.push(d);
  });
  view.innerHTML = `
    <div class="crumb reveal"><a href="#/">Dashboard</a> <span>›</span> <b>What changed</b></div>
    <div class="home-hero reveal" style="--c:#7f9cf5">
      <div>
        <div class="hero-kicker">Terminology &amp; release deltas</div>
        <h1 class="hero-title">What changed</h1>
        <p class="hero-sub">Renames, renoancements and newly launched capabilities, newest first. Use this page to retire old notes and re-point them at the current name.</p>
        <div class="hero-actions">
          <a class="btn primary" href="#/glossary">📚 Open the glossary</a>
          <a class="btn ghost" href="#/exam">📘 Exam blueprint</a>
        </div>
      </div>
    </div>
    ${groups.map(g => `
      <div class="article reveal">
        <h2>${esc(g.release)}</h2>
        <div class="delta">${g.items.map(d => `
          <div class="delta-item">
            <div class="delta-when">${esc(d.kind)}</div>
            <div class="delta-body">
              <b>${esc(d.title)}</b>
              ${d.from ? `<p><span class="term-old">${esc(d.from)}</span><span class="term-arrow">&rarr;</span><span class="term-new">${esc(d.to)}</span></p>` : ''}
              <p>${esc(d.what)}</p>
              ${d.modules && d.modules.length ? `<p><b>Study:</b> ${d.modules.map(mid => {
                const m = byId(mid);
                return m ? `<a class="l" href="#/phase/${m.id}">Phase ${String(m.n).padStart(2, '0')}</a>` : '';
              }).filter(Boolean).join(' · ')}</p>` : ''}
            </div>
          </div>`).join('')}</div>
      </div>`).join('')}`;
  requestAnimationFrame(() => window.scrollTo(0, 0));
}

/* ------------------------- glossary page ------------------------- */

let glossTimer;
function renderGlossary(q) {
  const term = (q || '').trim().toLowerCase();
  const rows = GLOSSARY
    .filter(g => !term || g.term.toLowerCase().includes(term)
      || (g.alias || '').toLowerCase().includes(term)
      || g.def.toLowerCase().includes(term))
    .sort((a, b) => a.term.localeCompare(b.term));

  view.innerHTML = `
    <div class="crumb reveal"><a href="#/">Dashboard</a> <span>›</span> <b>Glossary</b></div>
    <div class="home-hero reveal" style="--c:#3ddc97">
      <div>
        <div class="hero-kicker">Exam reference</div>
        <h1 class="hero-title">Glossary</h1>
        <p class="hero-sub">${GLOSSARY.length} exam terms. Where a term was renamed, the legacy alias is shown so older study material still makes sense.</p>
        <div class="search-wrap" style="margin-top:14px;max-width:520px">
          <input id="glossQ" type="search" placeholder="Filter terms or legacy aliases…" value="${esc(q || '')}" autocomplete="off" />
        </div>
      </div>
    </div>
    <div class="article reveal">
      <p class="muted">${rows.length} of ${GLOSSARY.length} terms</p>
      <div class="gloss-grid">${rows.map(g => `
        <div class="gloss-card">
          <h4>${esc(g.term)}</h4>
          <p>${esc(g.def)}</p>
          ${g.alias ? `<span class="gloss-alias">legacy: ${esc(g.alias)}</span>` : ''}
          ${g.modules && g.modules.length ? `<span class="gloss-alias">${g.modules.map(mid => {
            const m = byId(mid);
            return m ? `<a class="l" href="#/phase/${m.id}">Phase ${String(m.n).padStart(2, '0')}</a>` : '';
          }).filter(Boolean).join(' · ')}</span>` : ''}
        </div>`).join('')}</div>
      ${rows.length ? '' : '<div class="sr-empty">Nothing matched that term.</div>'}
    </div>`;

  const input = $('#glossQ');
  if (input) {
    input.addEventListener('input', () => {
      clearTimeout(glossTimer);
      const v = input.value;
      glossTimer = setTimeout(() => {
        route = { view: 'glossary', q: v };
        history.replaceState(null, '', '#' + hashFor());
        render();
        focusGloss(v);
      }, 200);
    });
    input.focus();
  }
  requestAnimationFrame(() => window.scrollTo(0, 0));
}
function focusGloss(v) {
  const i = $('#glossQ');
  if (i) { i.value = v; i.focus(); i.setSelectionRange(v.length, v.length); }
}

/* ------------------------- toast ------------------------- */

let toastTimer;
function toast(msg) {
  let t = $('#toast');
  if (!t) { t = document.createElement('div'); t.id = 'toast'; document.body.appendChild(t); }
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 2600);
}

/* ------------------------- confetti ------------------------- */

function confetti() {
  const colors = ['#00A1E0', '#10B981', '#F59E0B', '#EC4899', '#8B5CF6', '#e8b93d'];
  for (let i = 0; i < 90; i++) {
    const p = document.createElement('i');
    p.className = 'confetti';
    const x = Math.random() * 100;
    const d = Math.random() * 2.4 + 1.2;
    const s = 8 + Math.random() * 8;
    p.style.left = x + '%';
    p.style.background = colors[i % colors.length];
    p.style.animationDuration = d + 's';
    p.style.width = p.style.height = s + 'px';
    p.style.setProperty('--tx', (Math.random() * 160 - 80) + 'px');
    document.body.appendChild(p);
    setTimeout(() => p.remove(), d * 1000 + 400);
  }
}

/* ------------------------- events wiring ------------------------- */

document.addEventListener('click', e => {
  const sc = e.target.closest('.selfcheck');
  if (sc) {
    const a = $('.sc-a', sc); const btn = $('.showA', sc);
    if (a.hidden) { a.hidden = false; btn.textContent = 'Hide answer'; }
    else { a.hidden = true; btn.textContent = 'Show answer'; }
    return;
  }
  const copy = e.target.closest('.cb-copy');
  if (copy) {
    const pre = document.getElementById(copy.dataset.copy);
    if (pre) {
      const txt = pre.innerText;
      (navigator.clipboard ? navigator.clipboard.writeText(txt) : Promise.reject())
        .then(() => { copy.textContent = '✓ Copied'; setTimeout(() => copy.textContent = '⧉ Copy', 1400); })
        .catch(() => { /* fallback select */ const r = document.createRange(); r.selectNodeContents(pre); const s = window.getSelection(); s.removeAllRanges(); s.addRange(r); document.execCommand('copy'); copy.textContent = '✓ Copied'; setTimeout(() => copy.textContent = '⧉ Copy', 1400); });
    }
  }
});

/* search */
let searchBox = null;
function ensureSearch() {
  if (searchBox) return searchBox;
  searchBox = document.createElement('div');
  searchBox.className = 'search-wrap';
  searchBox.innerHTML = `<input id="globalQ" type="search" placeholder="Search lessons, subagents, prompts, guides…" autocomplete="off" />
    <div class="search-results" id="searchRes"></div>`;
  document.body.appendChild(searchBox);

  const input = $('#globalQ', searchBox);
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') {
      const first = $('.sr-item', wrap);
      if (first) { location.hash = first.getAttribute('href'); closeSearch(); }
    }
    if (e.key === 'Escape') closeSearch();
  });

  const wrap = $('#searchRes', searchBox);
  input.addEventListener('input', runSearch);
  input.addEventListener('focus', () => { if (input.value.trim().length >= 2) searchBox.classList.add('open'); });
  return searchBox;
}

/* guide text index — built lazily the first time a search runs */
let guideIndex = null, guideIndexing = false;
function buildGuideIndex() {
  if (guideIndex || guideIndexing) return;
  if (!window.fetch) return;
  guideIndexing = true;
  Promise.all(MODULES.map(m => fetchGuide(m)
    .then(txt => {
      const secs = [];
      let head = m.title;
      const push = (h, extra) => {
        const last = secs[secs.length - 1];
        if (last && last.head === h) last.text += ' ' + extra;
        else secs.push({ head: h, text: h + ' ' + extra, mod: m });
      };
      txt.split(/\r?\n/).forEach(ln => {
        if (/^#{2,4}\s/.test(ln)) { head = ln.replace(/^#+\s*/, '').replace(/[`*]/g, '').trim(); }
        else if (ln.trim()) push(head, ln.replace(/[`*|#]/g, ' '));
      });
      return secs;
    })
    .catch(() => [])))
    .then(chunks => {
      guideIndex = chunks.flat();
      guideIndexing = false;
      if (searchBox && searchBox.classList.contains('open')) runSearch();
    });
}

function runSearch() {
  const sb = searchBox || ensureSearch();
  const input = $('#globalQ', sb);
  const wrap = $('#searchRes', sb);
  const q = input.value.trim().toLowerCase();
  wrap.innerHTML = '';
  if (q.length < 2) { sb.classList.remove('open'); return; }
  buildGuideIndex();

  const results = [];
  MODULES.forEach(m => {
    m.lessons.forEach((l, i) => {
      const hay = (m.title + ' ' + m.tagline + ' ' + l.title + ' ' + m.objectives.join(' ') + ' ' + l.blocks.map(bd => bd.x || (bd.items || []).join(' ')).join(' ')).toLowerCase();
      if (hay.includes(q) || m.title.toLowerCase().includes(q)) {
        results.push({ mod: m, li: i, label: m.title + ' → ' + l.title });
      }
    });
    m.quiz.questions.forEach(qq => {
      if ((qq.q + ' ' + qq.why).toLowerCase().includes(q)) {
        results.push({ mod: m, quiz: true, label: `Quiz · ${m.title}: "${qq.q.slice(0, 60)}…"` });
      }
    });
  });
  GLOSSARY.forEach(g => {
    if ((g.term + ' ' + (g.alias || '') + ' ' + g.def).toLowerCase().includes(q)) {
      results.push({ href: '#/glossary/' + encodeURIComponent(g.term), ico: '📚', label: `Glossary · ${g.term}${g.alias ? ' (was ' + g.alias + ')' : ''}` });
    }
  });
  (guideIndex || []).forEach(s => {
    if (s.text.toLowerCase().includes(q)) {
      results.push({ mod: s.mod, anchor: slugify(s.head), ico: '📖', label: `Guide · ${s.mod.title} → ${s.head}` });
    }
  });

  const seen = new Set(); const uniq = [];
  results.forEach(r => {
    const k = r.href ? r.href : (r.quiz ? 'q' + r.label : (r.mod.id + ':' + (r.li != null ? r.li : r.anchor)));
    if (!seen.has(k)) { seen.add(k); uniq.push(r); }
  });
  if (!uniq.length) { wrap.innerHTML = '<div class="sr-empty">No results — try "subagent", "grounding", "Agent Script", "flex credits", "MCP"…</div>'; }
  else {
    uniq.slice(0, 12).forEach(r => {
      const a = document.createElement('a');
      a.className = 'sr-item';
      a.href = r.href || (r.quiz ? '#/quiz/' + r.mod.id : (r.anchor ? '#/guide/' + r.mod.id + '/' + r.anchor : '#/lesson/' + r.mod.id + '/' + r.li));
      a.innerHTML = `<span class="sr-ico">${r.ico || (r.quiz ? '🧠' : r.mod.icon)}</span><span>${esc(r.label)}</span><span class="sr-go">→</span>`;
      a.addEventListener('click', closeSearch);
      wrap.appendChild(a);
    });
    if (guideIndexing) {
      const n = document.createElement('div');
      n.className = 'sr-empty';
      n.textContent = 'indexing guides…';
      wrap.appendChild(n);
    }
  }
  sb.classList.add('open');
}

function openSearch() {
  const sb = ensureSearch();
  sb.classList.add('open');
  const inp = $('#globalQ', sb);
  inp.focus();
  const top = $('#topSearch');
  if (top) { inp.value = top.value; }
  runSearch();
}
function closeSearch() {
  if (searchBox) { searchBox.classList.remove('open'); const inp = $('#globalQ', searchBox); inp.value = ''; }
}

/* hotkey */
window.addEventListener('keydown', e => {
  const ae = document.activeElement;
  const typing = ae && (ae.tagName === 'INPUT' || ae.tagName === 'TEXTAREA');
  if ((e.key === '/' || e.key === 'f') && !e.ctrlKey && !e.metaKey) {
    if (!typing) { e.preventDefault(); openSearch(); }
    return;
  }
  if (e.key === 'Escape') {
    if (searchBox && searchBox.classList.contains('open')) { closeSearch(); e.preventDefault(); return; }
  }
  if (e.key === 'ArrowLeft' && !typing && route.view === 'lesson') {
    const mod = byId(route.mid);
    if (route.li > 0) navigate('lesson', route.mid, route.li - 1);
  }
  if (e.key === 'ArrowRight' && !typing && route.view === 'lesson') {
    const mod = byId(route.mid);
    if (route.li < mod.lessons.length - 1) navigate('lesson', route.mid, route.li + 1);
  }
  if (!typing && !e.ctrlKey && !e.metaKey && !e.altKey) {
    const k = e.key.toLowerCase();
    if (k === 't') { e.preventDefault(); toggleTrack(); }
    else if (k === 'e') { e.preventDefault(); navigate('exam'); }
    else if (k === 'w') { e.preventDefault(); route = { view: 'whats-new' }; history.replaceState(null, '', '#/whats-new'); render(); }
    else if (k === 'g') { e.preventDefault(); route = { view: 'glossary', q: '' }; history.replaceState(null, '', '#/glossary'); render(); }
  }
});

function bindTopSearch() {
  const topQ = $('#topSearch');
  if (!topQ || topQ.dataset.bound) return;
  topQ.dataset.bound = '1';
  topQ.addEventListener('focus', () => {
    const sb = ensureSearch();
    sb.classList.add('open');
    $('#globalQ', sb).value = topQ.value;
    runSearch();
  });
  topQ.addEventListener('input', () => {
    const sb = ensureSearch();
    sb.classList.add('open');
    $('#globalQ', sb).value = topQ.value;
    runSearch();
  });
}

/* ------------------------- progress export / import ------------------------- */

function exportProgress() {
  const payload = {
    app: 'afacademy',
    version: 1,
    exported: new Date().toISOString(),
    exam: EXAM.code,
    release: EXAM.release,
    track: !!store.track,
    done: store.done,
    quiz: store.quiz,
    best: store.best,
    guide: store.guide
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'agentforce-academy-progress-' + new Date().toISOString().slice(0, 10) + '.json';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
  toast('Progress exported ⬇');
}

function importProgress() {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'application/json,.json';
  input.addEventListener('change', () => {
    const f = input.files && input.files[0];
    if (!f) return;
    const reader = new FileReader();
    reader.onload = () => {
      let p;
      try { p = JSON.parse(String(reader.result)); }
      catch (err) { toast('That file is not valid JSON'); return; }
      if (!p || p.app !== 'afacademy' || typeof p.done !== 'object') { toast('Not an academy progress file'); return; }
      if (!confirm('Replace your current progress with the imported file?')) return;
      store.done = p.done || {};
      store.quiz = p.quiz || {};
      store.best = p.best || {};
      store.guide = p.guide || {};
      if (typeof p.track === 'boolean') store.track = p.track;
      save();
      toast('Progress imported ⬆');
      render();
    };
    reader.readAsText(f);
  });
  input.click();
}

function toggleTrack() {
  store.track = !store.track;
  save();
  render();
  toast(trackOn()
    ? `Maintenance track on — ${MAINT_MODULES.length} phases in scope`
    : 'Full roadmap view restored');
}

/* ------------------------- lazy event (hashchange) ------------------------- */
window.addEventListener('hashchange', () => { route = parseHash(); render(); });

/* ------------------------- boot ------------------------- */
route = parseHash();
render();

/* mobile menu */
const menuBtn = $('#menuBtn');
if (menuBtn) {
  menuBtn.addEventListener('click', () => {
    document.body.classList.toggle('sb-open');
    if (document.body.classList.contains('sb-open')) {
      const first = $('.side-phase');
      if (first) first.scrollIntoView({ block: 'start', behavior: 'smooth' });
    }
  });
}
document.addEventListener('click', e => {
  if (document.body.classList.contains('sb-open') && !e.target.closest('.sidebar') && !e.target.closest('#menuBtn')) {
    document.body.classList.remove('sb-open');
  }
});

/* theme toggle */
const themeBtn = $('#themeToggle');
if (themeBtn) {
  themeBtn.textContent = getTheme() === 'dark' ? '🌙' : '☀️';
  themeBtn.addEventListener('click', () => {
    setTheme(getTheme() === 'dark' ? 'light' : 'dark');
  });
}

/* maintenance track — top bar */
const trackBtn = $('#trackToggle');
if (trackBtn) trackBtn.addEventListener('click', toggleTrack);

/* delegated handlers for sidebar controls (sidebar is re-rendered often) */
document.addEventListener('click', e => {
  if (e.target.closest('#sideTrack')) { e.preventDefault(); toggleTrack(); return; }
  if (e.target.closest('#sideExport')) { e.preventDefault(); exportProgress(); return; }
  if (e.target.closest('#sideImport')) { e.preventDefault(); importProgress(); return; }
});