# Deployment, Packaging and CI

An agent in a browser is an agent you cannot review, roll back or test
twice. Everything in this phase exists to move agent configuration into
version control and get it to an org repeatably.

---

## 1. Why metadata beats the UI

| | Browser configuration | Metadata in git |
| --- | --- | --- |
| Review | None | Pull request shows the diff |
| History | Overwritten | Every version retained |
| Rollback | Impossible | `git revert` and redeploy |
| Test twice | Manual | Automated on every change |
| Destructive merge | Silent | Caught in review |
| Environments | Manual re-entry | Deploy the same artefact |

The practical argument is the last row. Two people both editing an agent
in the browser means the second save silently overwrites the first. With
metadata, that is a merge conflict you can see.

---

## 2. The package manifest

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>AgentLifecycleService</members>
        <members>AgentLifecycleServiceTest</members>
        <members>ActionOrchestrator</members>
        <members>ActionOrchestratorTest</members>
        <members>TokenUsageService</members>
        <members>Agent_DefinitionTrigger</members>
        <members>Agent_Definition__c</members>
        <members>Action_Definition__c</members>
        <members>AgentforceSpecialist</members>
    </types>
    <version>68.0</version>
</Package>
```

The file is not the point. **The list must be derived from the diff.** A
hand-maintained manifest drifts, and the failure mode is deploying a
partial change where old code calls something you removed.

### Deriving it

```bash
sf project retrieve start \
    --metadata Agent_Definition__c:Agent_Definition__c-Portal \
    --output-dir ./out --target-org source-org

git diff --name-only HEAD~1 -- out | sed 's#out/##'
```

Then review it. The automation makes the list trustworthy; the review is
the decision.

---

## 3. Deployment strategies

| Strategy | Command | Use |
| --- | --- | --- |
| Source deploy | `sf project deploy start --source-dir force-app` | Full project, scratch and dev |
| Manifest deploy | `sf project deploy start --manifest manifest/package.xml` | Promotions, narrow changes |
| Targeted | `sf project deploy start --metadata Agent_Definition__c` | One component, quick iteration |
| Validate first | `--dry-run` | Check without committing |

```bash
sf project deploy start --source-dir force-app --target-org afs --wait 20
sf project deploy report --target-org afs
```

`--wait 20` matters. A synchronous deploy gives you a result you can act
on; an asynchronous one gives you a job id and a reason to go and look
later.

---

## 4. Environments and promotion

```text
Development  ->  Integration  ->  UAT  ->  Production
   scratch       scratch        real    real
```

| Environment | Contains | Purpose |
| --- | --- | --- |
| Scratch | Seed data, one agent | Per-PR validation |
| Integration | Realistic volume, all integrations | Cross-component behaviour |
| UAT | Real data shapes, business users | Acceptance, prompt tuning |
| Production | Live | Only after gates pass |

### What must not be promoted directly

| Item | Why |
| --- | --- |
| Production data | Privacy; and integration tests need synthetic data |
| Seeder scripts | They are for dev and integration only |
| Debug flags | They will disable safety in production |
| Hardcoded org ids | Break on the next environment |

Promote the **artefact**, never the environment. A rebuild is a different
artefact.

---

## 5. The CI pipeline

```yaml
name: salesforce
on:
  pull_request:
    paths:
      - 'force-app/**'
      - 'manifest/**'
      - 'sfdx-project.json'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run check
      - run: npx prettier --check .
      - name: Deploy to a scratch org
        uses: forcedotcom/sfdx-github-action@v2
        with:
          command: run
          args: |
            apex run test
            --target-org devhub@scratch
            --wait 20
            --code-coverage
            --result-format human
            --test-level RunLocalTests
      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with: { name: coverage, path: ./ }
```

### The rules that matter

| Rule | Why |
| --- | --- |
| Run on **pull requests**, not only on main | Feedback before merge |
| Gate on **tests**, not deploy success | A deploy can succeed with failing tests |
| **Never auto-deploy production** | Deployment is a decision |
| Report the **coverage number** | Make the result visible and arguable |
| **No secrets in the workflow** | Use an org connection, never credentials |
| Fail on a **partial** deploy | A half-applied change is worse than none |

Run on pull requests is the one most pipelines get wrong. Feedback after
merge means five people have built on a broken change.

---

## 6. Pre-deployment and post-deployment

### Before

```text
[ ] Tests pass, coverage at or above the gate
[ ] Manifest derived from the diff, and reviewed
[ ] No debug flags, no hardcoded org ids
[ ] Permission set reviewed for least privilege
[ ] Rollback plan written, and it is one command
[ ] Someone other than the author approved the prompt change
```

### After

```text
[ ] Deploy report shows success for every component
[ ] Agent activated, not just deployed
[ ] Five real sessions sampled and their traces read
[ ] Command Center: error and escalation rates vs previous release
[ ] Credit consumption vs previous release, per agent
[ ] Rollback still available for the first hour
```

The last two are the ones that catch a regression. A prompt change can
deploy cleanly, pass every test, and still double the escalation rate —
because tests use your phrasing and production does not.

---

## 7. Rollback

```bash
git log --oneline -5
git revert --no-commit <sha>
sf project deploy start --manifest package.xml --target-org prod --wait 20
sf apex run test --target-org prod --test-level RunLocalTests --wait 30
```

The precondition is that the previous version is in version control. **An
agent edited directly in a browser has no rollback**, which is the
practical argument for metadata-first changes even when the UI is faster.

### The switch to disable an agent

Reach this in under a minute, without a deploy:

```bash
sf data update record --sobject Agentforce_Agent__c \
  --record-id a0X5b00000AgentK \
  --values "Status='Inactive'" --target-org prod --wait 10
```

Disabling is not the same as rolling back: the definition is still wrong
and will come back on the next deploy. Disable to stop the bleeding, roll
back to fix it.

---

## 8. The destructive merge

The classic failure in a metadata-first project:

```text
Branch A:  edit the agent instructions
Branch B:  deploy a change to the same agent
Merge:     takes A's version of the agent
Result:    B's change is silently gone
```

Nobody is notified, because git resolved it as a valid merge. This is why
the agent definition lives in the repository, why prompts get reviewed like
code, and why the first hour after a release includes checking the traces.

---

## Check yourself

1. **Why must the manifest be derived from the diff rather than
   maintained by hand?**
   A hand-maintained list drifts from reality, and the failure is a partial
   deploy where old code calls something you removed — which surfaces
   later as a runtime error in an unrelated feature.

2. **Your pipeline is green on `main` and a developer pushed a broken
   change. What is wrong with the pipeline?**
   It runs on push to main, not on pull requests. Feedback arrived after
   merge, so five people may have built on a broken change. Move the run to
   `pull_request`.

3. **A deploy succeeded. Is the agent working?**
   No. A successful deploy proves the metadata is valid. To know the agent
   works: activate it, run a real session, and confirm the interaction,
   action and credit records were written.

4. **You need to stop an agent costing too much right now. Rollback or
   disable?**
   Disable, immediately, without a deploy. Then roll back, because the
   definition is still wrong and will return on the next deploy.

5. **Name something that must never be promoted to production.**
   Production data, seeder scripts, debug flags, hardcoded org ids. All
   four, and each for a specific reason.

---

## Key takeaways

- Metadata, not browser configuration. Review, history, rollback.
- Derive the manifest from the diff, then review it.
- Deploy synchronously with `--wait`, and always read the deploy report.
- Run CI on pull requests and gate on tests, not on deploy success.
- A successful deploy is not a working agent. Sample real sessions.
- Know two responses: disable (fast) and revert (correct).
