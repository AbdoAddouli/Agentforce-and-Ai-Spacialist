import test from 'node:test';
import assert from 'node:assert/strict';
import {
  checkXmlStructure,
  checkTriggerName,
  customObjectRefsIn,
  topLevelDeclarations,
  checkGlobalCollisions,
  globalCollisions,
  CHECKS,
  walk,
} from './check-project.mjs';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT } from './check-project.mjs';

const DEF = join(ROOT, 'force-app', 'main', 'default');

/* ---------------------- checkXmlStructure ---------------------------- */

test('well-formed XML produces no errors', () => {
  const good =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n' +
    '    <fields>\n        <fullName>Status__c</fullName>\n    </fields>\n' +
    '</CustomObject>\n';
  assert.deepEqual(checkXmlStructure(good, 'x'), []);
});

test('missing XML declaration is reported', () => {
  const errors = checkXmlStructure('<A></A>', 'x');
  assert.equal(errors.length, 1);
  assert.match(errors[0], /declaration/);
});

test('unclosed tag is reported', () => {
  const errors = checkXmlStructure(
    '<?xml version="1.0" encoding="UTF-8"?>\n<A>\n  <B></B>\n',
    'x'
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /unclosed <A>/);
});

test('mismatched closing tag is reported', () => {
  const errors = checkXmlStructure(
    '<?xml version="1.0" encoding="UTF-8"?>\n<A><B></A></B>',
    'x'
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /closes/);
});

test('self-closing tags do not open a scope', () => {
  const good =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<A><fields><fullName>X__c</fullName></fields></A>\n';
  assert.deepEqual(checkXmlStructure(good, 'x'), []);
});

test('unescaped ampersand is reported', () => {
  const errors = checkXmlStructure(
    '<?xml version="1.0" encoding="UTF-8"?>\n<A><label>Trust & Safety</label></A>',
    'x'
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /ampersand/);
});

test('a properly escaped ampersand is accepted', () => {
  const good =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<A><label>Trust &amp; Safety</label></A>';
  assert.deepEqual(checkXmlStructure(good, 'x'), []);
});

/* ----------------------- checkTriggerName --------------------------- */

test('correctly named trigger passes', () => {
  const src = 'trigger AccountTrigger on Account (before insert) {}';
  assert.deepEqual(checkTriggerName(src, 'AccountTrigger'), []);
});

test('custom object trigger drops the __c suffix', () => {
  const src = 'trigger Agent_DefinitionTrigger on Agent_Definition__c (before insert) {}';
  assert.deepEqual(checkTriggerName(src, 'Agent_DefinitionTrigger'), []);
});

test('misnamed trigger is reported with the required name', () => {
  const src = 'trigger AgentLifecycleTrigger on Agent_Definition__c (before insert) {}';
  const errors = checkTriggerName(src, 'bad.trigger');
  assert.equal(errors.length, 1);
  assert.match(errors[0], /Agent_DefinitionTrigger/);
});

/* ---------------------- customObjectRefsIn --------------------------- */

test('collects every __c token including fields', () => {
  const refs = customObjectRefsIn('SELECT Id FROM Agent_Definition__c WHERE Status__c = null');
  assert.deepEqual([...refs].sort(), ['Agent_Definition__c', 'Status__c']);
});

/* ---------------- the checks against the real project ---------------- */

for (const [name, fn] of Object.entries(CHECKS)) {
  test(`check-project: ${name} is clean`, () => {
    const errors = fn();
    assert.deepEqual(
      errors,
      [],
      `${name} reported:\n  ${errors.join('\n  ')}`
    );
  });
}

test('every Apex class has a test class or is itself a test', () => {
  const classes = walk(join(DEF, 'classes'))
    .filter((f) => f.endsWith('.cls'))
    .map((f) => f.split('\\').pop().replace('.cls', ''));
  for (const c of classes) {
    if (c.endsWith('Test')) continue;
    assert.ok(
      classes.includes(`${c}Test`),
      `${c} has no ${c}Test class`
    );
  }
});

test('the curriculum validator is wired into package.json', () => {
  const pkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8'));
  assert.match(pkg.scripts.check, /check-curriculum/);
  assert.match(pkg.scripts.check, /check-project/);
});

test('no Apex references a custom object that does not exist', () => {
  // Guards the specific class of typo the ref check exists for.
  const objects = new Set(
    walk(join(DEF, 'objects'))
      .filter((f) => f.endsWith('.object'))
      .map((f) => f.split('\\').pop().replace('.object', ''))
  );
  for (const f of walk(DEF)) {
    if (!f.endsWith('.cls') && !f.endsWith('.trigger')) continue;
    for (const ref of customObjectRefsIn(readFileSync(f, 'utf8'))) {
      if (!objects.has(ref)) continue; // a field, not an object
      assert.ok(objects.has(ref));
    }
  }
  assert.equal(objects.size, 12, 'expected 12 custom objects');
});

/* ---------------- top-level global collisions ----------------------- */

test('topLevelDeclarations sees column-0 declarations only', () => {
  const src = [
    'const A = 1;',
    'let B = 2;',
    'function C() {',
    '  const indentedLocal = 3;',
    '  return indentedLocal;',
    '}',
    'class D {}',
  ].join('\n');
  assert.deepEqual(topLevelDeclarations(src), ['A', 'B', 'C', 'D']);
});

test('a name declared in two browser scripts is reported', () => {
  // This is the bug that shipped a blank site: REPO was declared in both
  // curriculum.js and app.js. Classic scripts share one global scope, so the
  // second declaration is a SyntaxError that aborts app.js entirely.
  const errors = globalCollisions({
    'curriculum.js': "const REPO = 'https://x';\nconst GUIDE = REPO;\n",
    'answers.js': "const TICK = '`';\n",
    'app.js': "const REPO = 'https://x';\nconst VIEW = 1;\n",
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /"REPO"/);
  assert.match(errors[0], /curriculum\.js, app\.js/);
  assert.match(errors[0], /SyntaxError/);
});

test('distinct top-level names across scripts are fine', () => {
  assert.deepEqual(
    globalCollisions({
      'curriculum.js': "const REPO = 'https://x';\n",
      'answers.js': "const TICK = '`';\n",
      'app.js': "const VIEW = 1;\n",
    }),
    []
  );
});

test('a name declared twice in one script is reported', () => {
  const errors = globalCollisions({ 'app.js': 'const A = 1;\nlet A = 2;\n' });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /twice at top level/);
});

test('the shipped browser scripts have no top-level collisions', () => {
  assert.deepEqual(checkGlobalCollisions(), []);
  for (const file of ['curriculum.js', 'answers.js', 'app.js']) {
    const p = join(ROOT, 'docs', 'assets', file);
    assert.ok(existsSync(p), `${file} should exist`);
    assert.ok(topLevelDeclarations(readFileSync(p, 'utf8')).length > 0, `${file} should declare globals`);
  }
});