#!/usr/bin/env node
/**
 * Static consistency checks for the learning site data.
 *
 *   node scripts/check-curriculum.mjs
 *
 * Verifies that curriculum.js, answers.js and the guide files agree with each
 * other and with the block contract implemented by docs/assets/app.js.
 * Exits non-zero on any error, so it can gate a commit.
 */

import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import vm from 'node:vm';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DOCS = join(ROOT, 'docs');
const ASSETS = join(DOCS, 'assets');
const GUIDES = join(DOCS, 'guide');

const errors = [];
const warnings = [];
const err = m => errors.push(m);
const warn = m => warnings.push(m);

/** Block types implemented by renderBlock() in docs/assets/app.js. */
const BLOCK_TYPES = [
  'bp', 'callout', 'cli', 'code', 'delta', 'ex', 'facts',
  'h', 'list', 'num', 'p', 'proj', 'selfcheck', 'table', 'term'
];

/** Required non-empty string field for a given block type. */
const BLOCK_TEXT = {
  p: 'x', h: 'x', code: 'x'
};

/** Required array field for a given block type. */
const BLOCK_ARRAY = {
  list: 'items', num: 'items', cli: 'items',
  table: 'rows', term: 'rows', facts: 'items'
};

/** Types whose array items are themselves arrays (rows) rather than strings. */
const ROW_TYPES = new Set(['table', 'term']);

/**
 * Backtick stand-in used by answers.js, since markdown fences cannot appear
 * unescaped inside a JS template literal. Resolved by tick() at load time.
 */
const TICK_PLACEHOLDER = '§';

function load(file) {
  const path = join(ASSETS, file);
  if (!existsSync(path)) {
    err(`missing ${path}`);
    return null;
  }
  const src = readFileSync(path, 'utf8');
  const ctx = vm.createContext({});
  // Each asset file declares only some of these globals, so probe with typeof.
  const probe = name => `(typeof ${name} === 'undefined' ? undefined : ${name})`;
  const wanted = ['ACADEMY', 'EXAM', 'DELTA', 'GLOSSARY', 'EXERCISE_ANSWERS'];
  try {
    vm.runInContext(
      `${src}\nglobalThis.__exports = { ${wanted.map(n => `${n}: ${probe(n)}`).join(', ')} };`,
      ctx,
      { filename: path }
    );
  } catch (e) {
    err(`${file} failed to evaluate: ${e.message}`);
    return null;
  }
  return ctx.__exports;
}

const isText = v => typeof v === 'string' && v.trim().length > 0;

function checkBlock(b, where) {
  if (!b || typeof b !== 'object') return err(`${where}: block is not an object`);
  const t = b.t;
  if (!BLOCK_TYPES.includes(t)) return err(`${where}: unsupported block type "${t}"`);
  if (t === 'ex') return;

  const textField = BLOCK_TEXT[t];
  if (textField && !isText(b[textField])) {
    err(`${where}: block "${t}" needs a non-empty "${textField}" (got ${typeof b[textField]})`);
  }

  const arrField = BLOCK_ARRAY[t];
  if (arrField) {
    const arr = b[arrField];
    if (!Array.isArray(arr) || arr.length === 0) {
      err(`${where}: block "${t}" needs a non-empty "${arrField}" array`);
    } else {
      arr.forEach((item, i) => {
        if (ROW_TYPES.has(t)) {
          if (!Array.isArray(item) || item.length === 0) {
            err(`${where}: ${t} row ${i} is not a non-empty array`);
            return;
          }
          item.forEach((cell, ci) => {
            if (!isText(cell)) err(`${where}: ${t} row ${i} cell ${ci} is not non-empty text`);
          });
          if (t === 'term' && item.length < 2) {
            err(`${where}: term row ${i} needs at least [legacy, current]`);
          }
          if (t === 'table' && b.head && Array.isArray(b.head) && item.length !== b.head.length) {
            err(`${where}: table row ${i} has ${item.length} cells but head has ${b.head.length}`);
          }
          return;
        }
        if (t === 'facts') {
          if (!Array.isArray(item) || item.length !== 2) {
            err(`${where}: facts item ${i} must be a [label, value] pair`);
          } else if (!isText(item[0]) || !isText(item[1])) {
            err(`${where}: facts item ${i} has an empty label or value`);
          }
          return;
        }
        if (!isText(item)) err(`${where}: ${t}[${i}] is not non-empty text`);
      });
    }
  }

  if (t === 'callout' && !isText(b.x)) {
    err(`${where}: callout needs a non-empty "x"`);
  }
  if (t === 'selfcheck' && (!isText(b.q) || !isText(b.a))) {
    err(`${where}: selfcheck needs non-empty "q" and "a"`);
  }
  if (t === 'table' && isText(b.head) === false && !Array.isArray(b.head)) {
    err(`${where}: table "head" must be an array when present`);
  }
}

function checkQuiz(quiz, where) {
  if (!quiz) return err(`${where}: missing quiz`);
  if (!isText(quiz.title)) err(`${where}: quiz needs a title`);
  if (!Array.isArray(quiz.questions) || quiz.questions.length === 0) {
    return err(`${where}: quiz has no questions`);
  }
  quiz.questions.forEach((q, i) => {
    const at = `${where}: quiz q${i + 1}`;
    if (!isText(q.q)) err(`${at}: missing question text`);
    if (!Array.isArray(q.opts) || q.opts.length < 2) err(`${at}: needs at least 2 options`);
    if (!Number.isInteger(q.a) || q.a < 0 || q.a >= (q.opts || []).length) {
      err(`${at}: answer index ${q.a} is out of range for ${(q.opts || []).length} options`);
    }
    if (!isText(q.why)) err(`${at}: missing "why"`);
    (q.opts || []).forEach((o, oi) => {
      if (!isText(o)) err(`${at}: option ${oi} is empty`);
    });
  });
}

const data = load('curriculum.js');
if (!data) {
  console.error('check-curriculum: could not load curriculum.js');
  if (warnings.length) warnings.forEach(w => console.error(`  ~ ${w}`));
  if (errors.length) errors.forEach(e => console.error(`  x ${e}`));
  process.exit(1);
}

const { ACADEMY, EXAM, DELTA, GLOSSARY } = data;
let moduleCount = 0;
const answersFile = join(ASSETS, 'answers.js');
const hasAnswers = existsSync(answersFile);
const answers = hasAnswers ? (load('answers.js') || {}).EXERCISE_ANSWERS || {} : {};

// ---------------------------------------------------------------- modules ---
if (!Array.isArray(ACADEMY)) {
  err('ACADEMY is not an array');
} else {
  moduleCount = ACADEMY.length;
  const seenIds = new Set();
  const seenNs = new Set();
  const exerciseIds = [];
  const guideFiles = existsSync(GUIDES)
    ? new Set(readdirSync(GUIDES).filter(f => f.toLowerCase().endsWith('.md')))
    : new Set();

  ACADEMY.forEach((m, i) => {
    const at = `module ${i + 1}`;
    if (!isText(m.id)) return err(`${at}: missing id`);
    if (seenIds.has(m.id)) err(`${at}: duplicate id "${m.id}"`);
    seenIds.add(m.id);
    if (m.n !== i + 1) err(`${at}: n should be ${i + 1}, got ${m.n}`);
    if (seenNs.has(m.n)) err(`${at}: duplicate n ${m.n}`);
    seenNs.add(m.n);

    ['title', 'icon', 'color', 'tagline', 'domain', 'guide'].forEach(f => {
      if (!isText(m[f])) err(`${at} (${m.id}): missing "${f}"`);
    });
    if (m.color && !/^#[0-9A-Fa-f]{6}$/.test(m.color)) {
      err(`${at} (${m.id}): color "${m.color}" is not a #rrggbb hex`);
    }
    if (Array.isArray(m.objectives) && m.objectives.length === 0) {
      err(`${at} (${m.id}): objectives is empty`);
    }
    (m.objectives || []).forEach((o, oi) => {
      if (!isText(o)) err(`${at} (${m.id}): objectives[${oi}] is empty`);
    });

    if (!isText(m.guide)) {
      // already reported
    } else if (!guideFiles.has(m.guide)) {
      err(`${at} (${m.id}): guide file docs/guide/${m.guide} does not exist`);
    }

    (m.art || []).forEach((a, ai) => {
      if (!isText(a.label)) err(`${at} (${m.id}): art[${ai}].label is empty`);
      if (!isText(a.href)) {
        err(`${at} (${m.id}): art[${ai}].href is empty`);
      } else if (a.href.startsWith('force-app/') && !existsSync(join(ROOT, a.href))) {
        warn(`${at} (${m.id}): art href not on disk yet: ${a.href}`);
      }
    });

    if (!Array.isArray(m.lessons) || m.lessons.length === 0) {
      err(`${at} (${m.id}): no lessons`);
    }
    (m.lessons || []).forEach((l, li) => {
      const lat = `${at} (${m.id}) lesson ${li + 1}`;
      if (!isText(l.title)) err(`${lat}: missing title`);
      if (!Number.isFinite(l.mins) || l.mins <= 0) warn(`${lat}: mins is ${l.mins}`);
      if (!Array.isArray(l.blocks) || l.blocks.length === 0) {
        return err(`${lat}: no blocks`);
      }
      l.blocks.forEach((b, bi) => {
        const at2 = `${lat} block ${bi + 1}`;
        checkBlock(b, at2);
        if (b && b.t === 'ex') {
          if (!isText(b.id)) err(`${at2}: exercise missing id`);
          else {
            exerciseIds.push({ id: b.id, mod: m.n, at: at2 });
            ['title', 'obj', 'verify'].forEach(f => {
              if (!isText(b[f])) err(`${at2}: exercise ${b.id} missing "${f}"`);
            });
            if (!Array.isArray(b.steps) || b.steps.length === 0) {
              err(`${at2}: exercise ${b.id} has no steps`);
            }
            (b.steps || []).forEach((s, si) => {
              if (!isText(s)) err(`${at2}: exercise ${b.id} step ${si + 1} is empty`);
            });
            if (!Number.isFinite(b.stars) || b.stars < 1 || b.stars > 5) {
              err(`${at2}: exercise ${b.id} stars should be 1-5, got ${b.stars}`);
            }
          }
        }
      });
    });

    checkQuiz(m.quiz, `${at} (${m.id})`);
  });

  // exercise ids: unique, N.M, N matching the module
  const seenEx = new Set();
  exerciseIds.forEach(e => {
    if (seenEx.has(e.id)) err(`duplicate exercise id "${e.id}" (at ${e.at})`);
    seenEx.add(e.id);
    if (!/^\d+\.\d+$/.test(e.id)) err(`exercise id "${e.id}" is not N.M`);
    else if (Number(e.id.split('.')[0]) !== e.mod) {
      err(`exercise id "${e.id}" does not match its module number ${e.mod} (at ${e.at})`);
    }
  });

  if (!hasAnswers) {
    err('docs/assets/answers.js does not exist yet');
  } else {
    exerciseIds.forEach(e => {
      if (!(e.id in answers)) err(`no answer for exercise "${e.id}" (at ${e.at})`);
      else {
        const a = answers[e.id];
        if (!isText(a)) err(`answer for exercise "${e.id}" is empty`);
        else {
          // Answers are markdown fed to md(); unclosed fences break the page.
          const fences = (a.match(/^```/gm) || []).length;
          if (fences % 2 !== 0) {
            err(`answer for exercise "${e.id}" has an unbalanced code fence (${fences})`);
          }
          if (a.includes(TICK_PLACEHOLDER)) {
            err(`answer for exercise "${e.id}" still contains the raw "${TICK_PLACEHOLDER}" placeholder`);
          }
        }
      }
    });
    Object.keys(answers).forEach(k => {
      if (!seenEx.has(k)) warn(`answers.js has "${k}" with no matching exercise`);
    });
  }

  // orphan guide files
  const referenced = new Set(ACADEMY.map(m => m.guide));
  guideFiles.forEach(f => {
    if (!referenced.has(f)) warn(`docs/guide/${f} is not referenced by any module`);
  });
  if (guideFiles.size < ACADEMY.length) {
    warn(`${guideFiles.size} guide file(s) for ${ACADEMY.length} modules`);
  }

  // ------------------------------------------------------------------ exam ---
  if (EXAM) {
    if (!isText(EXAM.title)) warn('EXAM: missing title');
    const sum = (EXAM.domains || []).reduce((s, d) => s + (d.weight || 0), 0);
    if (sum !== 100) err(`EXAM: domain weights sum to ${sum}, expected 100`);
    (EXAM.domains || []).forEach(d => {
      if (!isText(d.name)) err('EXAM: domain without a name');
      (d.modules || []).forEach(id => {
        if (!seenIds.has(id)) err(`EXAM: domain "${d.name}" references unknown module "${id}"`);
      });
    });
    const referencedMods = new Set((EXAM.domains || []).flatMap(d => d.modules || []));
    ACADEMY.forEach(m => {
      if (!referencedMods.has(m.id)) warn(`module "${m.id}" is not mapped to an exam domain`);
    });
    if (EXAM.maintenance) {
      (EXAM.maintenance.focus || []).forEach((f, i) => {
        if (!isText(f.name)) err(`EXAM.maintenance.focus[${i}] missing name`);
        if (!isText(f.detail)) err(`EXAM.maintenance.focus[${i}] missing detail`);
      });
    }
  }

  // --------------------------------------------------------- delta/glossary ---
  if (DELTA) {
    (DELTA.items || []).forEach((it, i) => {
      if (!isText(it.term) && !isText(it.legacy) && !isText(it.from)) {
        err(`DELTA.items[${i}] has no term/legacy/from label`);
      }
      if (!isText(it.was) && !isText(it.to) && !isText(it.now)) {
        err(`DELTA.items[${i}] has no "was" or "to" value`);
      }
      if (!isText(it.why)) err(`DELTA.items[${i}] is missing "why"`);
    });
  }
  if (GLOSSARY) {
    if (!Array.isArray(GLOSSARY) || GLOSSARY.length === 0) err('GLOSSARY is empty');
    (GLOSSARY || []).forEach((g, i) => {
      if (!isText(g.term)) err(`GLOSSARY[${i}] missing term`);
      if (!isText(g.def)) err(`GLOSSARY[${i}] (${g.term}) missing def`);
    });
  }
}

function report() {
  console.log(`check-curriculum: ${moduleCount} module(s)`);
  if (warnings.length) {
    console.log(`\n${warnings.length} warning(s):`);
    warnings.forEach(w => console.log(`  ~ ${w}`));
  }
  if (errors.length) {
    console.error(`\n${errors.length} error(s):`);
    errors.forEach(e => console.error(`  x ${e}`));
    process.exit(1);
  }
  console.log('\nOK - no errors.');
}

report();
