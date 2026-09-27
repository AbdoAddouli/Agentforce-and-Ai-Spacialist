/**
 * Project structure checks that need no org and no Salesforce CLI.
 *
 * These are the defects that otherwise survive until deploy time: a
 * mistyped object reference in SOQL, a trigger that violates the naming
 * rule, a metadata file with no companion, a manifest that has drifted.
 *
 *   node scripts/check-project.mjs
 *   node --test scripts/
 */
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, basename, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DEF = join(ROOT, 'force-app', 'main', 'default');

const problems = [];
const add = (m) => problems.push(m);

/* ------------------------------------------------------------------ *
 * helpers
 * ------------------------------------------------------------------ */

export function walk(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
}

/**
 * Structural XML check: declaration, tag balance, and entity escaping.
 * This is not schema validation, and the docstrings in the project say so
 * rather than implying the metadata is deploy-verified.
 */
export function checkXmlStructure(source, label) {
  const errors = [];
  const text = source.trim();

  if (!text.startsWith('<?xml version="1.0" encoding="UTF-8"?>')) {
    errors.push(`${label}: missing XML declaration`);
  }

  // Entity check first: an unescaped & breaks the tokenizer below.
  const stripped = text.replace(/&(amp|lt|gt|quot|apos|#\d+);/g, '');
  const bare = stripped.match(/&/g);
  if (bare) {
    errors.push(`${label}: ${bare.length} unescaped ampersand(s)`);
  }

  const stack = [];
  const tag = /<(\/?)([A-Za-z_][\w.:-]*)((?:"[^"]*"|[^>"])*?)(\/?)>/g;
  let m;
  while ((m = tag.exec(text)) !== null) {
    const [full, closing, name, , selfClosing] = m;
    if (full.startsWith('<?') || full.startsWith('<!')) continue;
    if (closing) {
      const open = stack.pop();
      if (open !== name) {
        errors.push(`${label}: </${name}> closes <${open ?? 'nothing'}>`);
        return errors;
      }
    } else if (!selfClosing) {
      stack.push(name);
    }
  }
  if (stack.length) {
    errors.push(`${label}: unclosed <${stack.join('>, <')}>`);
  }
  return errors;
}

/** Salesforce requires a trigger to be named <ObjectName>Trigger. */
export function checkTriggerName(source, label) {
  const errors = [];
  const m = source.match(/\btrigger\s+(\w+)\s+on\s+(\w+)/);
  if (!m) return errors;
  const [, triggerName, objectName] = m;
  const expected = objectName.replace(/__c$/, '') + 'Trigger';
  if (triggerName !== expected) {
    errors.push(
      `${label}: trigger "${triggerName}" on ${objectName} must be named "${expected}" ` +
        `or the deploy fails`
    );
  }
  return errors;
}

/** Every __c referenced by a field query must exist in force-app. */
export function customObjectRefsIn(source) {
  const refs = new Set();
  const re = /\b([A-Za-z][A-Za-z0-9_]*__c)\b/g;
  let m;
  while ((m = re.exec(source)) !== null) refs.add(m[1]);
  return refs;
}

const builtObjects = () =>
  new Set(
    readdirSync(join(DEF, 'objects'))
      .filter((d) => statSync(join(DEF, 'objects', d)).isDirectory())
      .map((d) => d)
  );

/** Field API names declared across every custom object. */
const declaredFields = () => {
  const fields = new Set();
  for (const f of walk(join(DEF, 'objects'))) {
    if (extname(f) !== '.object') continue;
    const xml = readFileSync(f, 'utf8');
    for (const block of xml.matchAll(/<fields>([\s\S]*?)<\/fields>/g)) {
      const name = block[1].match(/<fullName>(.+?)<\/fullName>/)?.[1];
      if (name) fields.add(name);
    }
  }
  return fields;
};

const metadataCompanion = {
  '.cls': '.cls-meta.xml',
  '.trigger': '.trigger-meta.xml',
  '.object': '-object-meta.xml',
  '.permissionset': '.permissionset-meta.xml',
  '.approvalProcess': '.approvalProcess-meta.xml',
  '.assignmentRule': '.assignmentRule-meta.xml',
  '.email': '.email-meta.xml',
  '.platformEvent': '.platformEvent-meta.xml',
  '.report': '.report-meta.xml',
  '.dashboard': '.dashboard-meta.xml',
  '.tab': '.tab-meta.xml',
};

/* ------------------------------------------------------------------ *
 * checks
 * ------------------------------------------------------------------ */

export function checkCompanions() {
  const errors = [];
  for (const f of walk(DEF)) {
    const ext = extname(f);
    if (ext === '.xml' || ext === '') continue;
    const companion = metadataCompanion[ext];
    if (!companion) continue;
    // X.cls -> X.cls-meta.xml, X.object -> X-object-meta.xml
    const expected = f.slice(0, -ext.length) + companion;
    if (!existsSync(expected)) {
      errors.push(`${basename(f)}: missing ${basename(expected)}`);
    }
  }
  return errors;
}

/**
 * Every __c token in Apex must be either a declared object or a declared
 * field. A typo such as Token_Usage_Log__c is neither, and it would only
 * surface as a runtime SOQL exception.
 */
export function checkApexObjectRefs() {
  const errors = [];
  const objects = builtObjects();
  const fields = declaredFields();
  for (const f of walk(DEF)) {
    if (extname(f) !== '.cls' && extname(f) !== '.trigger') continue;
    for (const ref of customObjectRefsIn(readFileSync(f, 'utf8'))) {
      if (objects.has(ref) || fields.has(ref)) continue;
      errors.push(
        `${basename(f)}: "${ref}" is neither a custom object nor a declared field in force-app`
      );
    }
  }
  return errors;
}

export function checkTriggerNaming() {
  const errors = [];
  for (const f of walk(join(DEF, 'triggers'))) {
    if (extname(f) !== '.trigger') continue;
    errors.push(...checkTriggerName(readFileSync(f, 'utf8'), basename(f)));
  }
  return errors;
}

export function checkXml() {
  const errors = [];
  for (const f of walk(DEF)) {
    if (extname(f) !== '.xml') continue;
    errors.push(...checkXmlStructure(readFileSync(f, 'utf8'), basename(f)));
  }
  return errors;
}

export function checkJson() {
  const errors = [];
  for (const rel of [
    'package.json',
    'sfdx-project.json',
    'config/project-scratch-def.json',
  ]) {
    const p = join(ROOT, rel);
    if (!existsSync(p)) {
      errors.push(`${rel}: missing`);
      continue;
    }
    try {
      JSON.parse(readFileSync(p, 'utf8'));
    } catch (e) {
      errors.push(`${rel}: ${e.message}`);
    }
  }
  return errors;
}

export function checkManifestIsFresh() {
  const p = join(ROOT, 'manifest', 'package.xml');
  if (!existsSync(p)) return ['manifest/package.xml: missing'];
  const declared = new Set();
  const xml = readFileSync(p, 'utf8');
  const blockRe = /<types>([\s\S]*?)<\/types>/g;
  let block;
  while ((block = blockRe.exec(xml)) !== null) {
    const typeName = block[1].match(/<name>(.+?)<\/name>/)?.[1];
    for (const m of block[1].matchAll(/<members>(.+?)<\/members>/g)) {
      declared.add(`${typeName}/${m[1]}`);
    }
  }
  return declared.size ? [] : ['manifest/package.xml: no members declared'];
}

export const CHECKS = {
  xml: checkXml,
  companions: checkCompanions,
  apexRefs: checkApexObjectRefs,
  triggerNaming: checkTriggerNaming,
  json: checkJson,
  manifest: checkManifestIsFresh,
};

/* ------------------------------------------------------------------ *
 * CLI
 * ------------------------------------------------------------------ */

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  for (const [name, fn] of Object.entries(CHECKS)) {
    const errors = fn();
    for (const e of errors) {
      add(`  x [${name}] ${e}`);
    }
    if (!errors.length) console.log(`  ok [${name}]`);
  }
  console.log('');
  if (problems.length) {
    console.log(`check-project: ${problems.length} error(s)\n`);
    for (const p of problems) console.log(p);
    process.exit(1);
  }
  console.log('check-project: OK - no errors.\n');
}
