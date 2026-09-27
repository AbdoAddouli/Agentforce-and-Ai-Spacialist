# Salesforce Certified Agentforce Specialist — Learning Academy

A self-contained study academy for the **Agentforce Specialist (`AI-201`)**
exam, in two halves:

1. **`docs/`** — a static interactive study site. 17 modules, 17 guides, 17
   model answers, a mock exam, a glossary, and progress tracking. No build
   step, no framework, works from the filesystem.
2. **`force-app/`** — a complete SFDX metadata project: 12 custom objects, 12
   service classes with tests, 6 flows, 1 approval process, 5 reports and a
   dashboard. A reference implementation of the architecture the exam asks
   about.

Nothing here is deployed. See [Status](#status).

---

## Quick start

### Study site

No install required:

```bash
npm run site:serve
# then open http://localhost:8080
```

Or just open `docs/index.html` directly. The site is plain HTML, CSS and
JavaScript with no build step and no external runtime dependencies.

### Validate everything

```bash
npm install     # first time only
npm run check   # both validators, no org required
npm test        # 20 tests for the checkers themselves
```

### Deploy to a scratch org (optional)

```bash
npm run org:create
npm run deploy:validate     # dry run, no changes
npm run deploy
npm run test:apex           # Apex tests with coverage
npm run org:open
```

---

## What is in here

### The site

| Path | Purpose |
| --- | --- |
| `docs/index.html` | Application shell and script load order |
| `docs/assets/app.js` | Router, renderer, search, exam, progress, print |
| `docs/assets/curriculum.js` | 17 modules, 17 exercises, exam blueprint, glossary |
| `docs/assets/answers.js` | 17 model answers |
| `docs/assets/style.css` | Styling |
| `docs/guide/01..17-*.md` | The long-form guides |

**Module order:** fundamentals → architecture → actions → Data 360 →
grounding → prompts → Agent Script → routing → MCP/A2A/Grid → testing →
deployment → observability & cost → governance → models & channels →
Workbench → exam prep → build.

Four modules carry `maint: true` and are flagged for the Summer '26
maintenance release (deadline **2027-08-20**): Agent Script, interoperability,
cost, and Workbench.

### The metadata

| Layer | Count | Contents |
| --- | --- | --- |
| Apex | 12 classes + 1 trigger | Lifecycle, routing, grounding, script, actions, cost, audit, model selection, prompts, evaluation |
| Tests | 12 classes | One per service, asserting rules rather than coverage |
| Objects | 12 custom | Configuration (4), evidence (7), training (1) |
| Flows | 6 | Routing fallback, budget alert, grounding notice, approval request, session close, normalisation |
| Governance | 1 permission set, 1 approval process, 2 assignment rules, 4 email templates | Least privilege, human sign-off, triage routing |
| Insight | 5 reports, 1 dashboard | What escaped, what it cost, what failed |
| Events | 1 platform event | `Agent_Session_Escaped__e` |
| Manifest | 68 members, 11 types | Generated from disk, never hand-edited |

Read [`ARCHITECTURE.md`](ARCHITECTURE.md) before changing the Apex. It
explains the three design decisions and lists the known limitations.

---

## Validation

Two checkers, both runnable with no org and no Salesforce CLI.

```bash
npm run check
```

**`scripts/check-curriculum.mjs`** loads the curriculum and answers in a
`vm` sandbox and verifies:

- module IDs are unique and sequential
- every field the renderer reads exists
- every block type the renderer understands is used correctly
- quiz answer indices are in range
- exercise IDs are `N.M` and match their module
- every exercise has a substantive answer
- every guide file exists
- exam domain weights total 100 and every module maps to a domain
- the Delta and glossary data is well-formed

**`scripts/check-project.mjs`** catches the defects that otherwise survive
until deploy time:

- XML structure: declaration, tag balance, entity escaping
- every metadata file has its `-meta.xml` companion
- **every `__c` token in Apex is either a declared object or a declared
  field** — this catches typos like `Token_Usage_Log__c`
- trigger names follow the `<ObjectName>Trigger` rule Salesforce enforces
- `package.json`, `sfdx-project.json` and the scratch definition parse
- the manifest is non-empty

Both must be clean before a change is considered done. Neither replaces
`sf project deploy validate`.

### Regenerating the manifest

`manifest/package.xml` is generated from `force-app`, so it cannot drift:

```bash
npm run manifest:generate
```

Run this after adding or removing metadata.

---

## Exam facts encoded in the curriculum

| | |
| --- | --- |
| Exam | `AI-201`, Agentforce Specialist |
| Questions | 60 scored + up to 5 unscored |
| Time | 105 minutes (1m45s each) |
| Pass | 72% |
| Prerequisite | None |
| Registration | USD 200 / USD 100 retake |

**Domain weights:** AI Agents 35% · Prompt Engineering 20% · Data 360
Fundamentals 20% · Testing/Deployment/Maintenance 10% ·
Governance/Observability 10% · Multi-Agent Orchestration 5%.

Current terminology is enforced throughout: **subagents** (not topics),
**Agent Router** (not Topic Selector), **connected subagent** (not connected
agent), **Data 360** (not Data Cloud), **Agentforce 360** (not Agentforce
3). The exam offers legacy names as distractors.

---

## Conventions

- **No comments in code unless they explain a non-obvious decision.** The
  Apex explains *why* a decline path exists; it does not narrate what the
  next line does.
- **Every service returns something**, including an explicit failure. No
  `void` returns on a decision path.
- **Requests and controls are distinguished.** An instruction asks; the
  action, trigger or flow enforces.
- **Assertions state the rule.** `System.assertEquals(true, ok, 'Delivered
  1 March, claimed same day')` beats a bare `assert(true, 'works')`.
- **Plain Markdown guides**, no front matter. Rendered with
  `md(src, { skipH1: true })`.
- **`answers.js` encodes Markdown backticks** with `§` placeholders and the
  `tick` tag. Preserve that convention or properly escape any backticks you
  add.

---

## Status

```text
Complete    Site, 17 modules, 17 guides, 17 answers, both validators,
            20 tests, all metadata written
Verified    XML structure, internal reference consistency, manifest
            freshness, curriculum/answer/guide integrity
NOT done    Apex compilation, Apex test execution, Metadata API
            validation, any deploy, any publishing
```

`ARCHITECTURE.md` §5 lists the same table in full. The metadata is
structurally sound and internally consistent; Salesforce has not compiled
it. Run `npm run deploy:validate` before trusting it.

## Licence

MIT.
