# Workbench and Operational Readiness

Human in the loop, runbooks, and what to do in the first hour after a
release. Part of the Summer '26 maintenance focus alongside Agentforce
Voice and Workbench.

---

## 1. Human in the loop

Approval is the simplest governance control and the easiest to get wrong,
because a badly placed approval makes the agent useless.

| Decision | Needs approval? | Why |
| --- | --- | --- |
| Answer a question from records | No | Low risk, easily verified |
| Draft a reply a human sends | Yes | Reputation and accuracy |
| Issue a refund under £50 | Rarely | Low value, reversible, policy-bounded |
| Issue a refund over £500 | **Always** | Material value |
| Change a customer's permissions | **Always** | Security boundary |
| Delete or bulk update data | **Always** | Irreversible |

### The test

> **What is the worst outcome if this is wrong, and can it be reversed?**

If the answer is material and irreversible, it needs a person. A judgement
about a threshold changes depending on who reads it, so where a threshold
is involved, write the number down.

### Three placement mistakes

| Mistake | Consequence |
| --- | --- |
| Approve everything | The agent is slower than a human and less useful |
| Approve nothing | Approval is theatre; the control does not exist |
| Approve by model confidence | Confidence is not a risk measure. A confident wrong answer needs approval more than an unconfident one |

The third is the subtle one. Using confidence as the approval trigger
approves exactly the cases where the model is sure, which is where
confident errors live.

---

## 2. The runbook

A runbook is written for someone who has never seen the system, at 3am,
with no time to investigate.

### Structure that works

```text
Agent: <name>
Owner: <team>
Escalation: <role, then role>

For each failure:
  ALERT       what fires, and at what threshold
  DIAGNOSE    the first three steps, in order
  MITIGATE    how to stop the bleeding, fast
  ESCALATE    to whom, and when
  ROLLBACK    what to revert, and the command
```

The "first three steps" constraint is what makes it usable. A diagnostic
guide with twelve steps is not a first-response document.

---

## 3. A worked runbook

**Agent:** Acme Refund Agent
**Owner:** Platform team
**Escalation:** Payments on-call, then Duty Manager

### Failure 1 — Escalation rate spikes above 3x baseline

**Alert:** `Agent_Escaped_Session__c` volume, 15-minute window

**Diagnose (first three steps)**
1. Command Center: confirm the spike and identify the affected agent.
2. Session Tracing: open three escalated sessions, read the reasoning
   steps. Are they the same failure or three?
3. Compare against the previous release: is the input distribution
   different, or is the same input now failing?

**Mitigate**
- Roll back to the previous version. Do not debug in production.
- If the cause is upstream data, disable the agent and leave the escalation
  path open for humans.

**Escalate** if the rollback does not restore the baseline within 15
minutes.

### Failure 2 — Grounding returns nothing useful

**Alert:** `Grounding_Miss_Rate__c` above 20%

**Diagnose**
1. Check `Grounding_Source__c` is active and the filters are unchanged.
2. Confirm the knowledge articles are `Published`.
3. Retrieve the same scope manually and see what returns.

**Mitigate**
- Revert the scope change if there was one.
- If content is missing, republish rather than widening the scope. A wider
  scope causes the precision failures that follow.

**Escalate** to the knowledge owner, not to engineering. This is usually a
content problem wearing an engineering costume.

### Failure 3 — Credit consumption jumps with no code change

**Alert:** `Flex_Credit_Ledger__c` daily total, +50% day over day

**Diagnose**
1. Sort the ledger by agent, then by step type. Find the dominant step.
2. Open the most expensive session and read its trace.
3. Check whether retrieval volume changed before assuming logic did.

**Mitigate**
- Apply the per-agent budget and turn on the iteration bound.
- If one subagent is responsible, disable it and keep the main agent
  running. Partial availability beats none.

### The switch to disable the agent

Non-negotiable, and reachable in under a minute without a deploy:

```bash
sf data update record --sobject Agentforce_Agent__c \
  --record-id a0X5b00000AgentK \
  --values "Status='Inactive'" --target-org prod --wait 10
```

Everything else in this runbook is diagnosis. This is response.

---

## 4. The first hour after a release

Most agent incidents are caught in the first hour, and almost none are
caught by the deployment pipeline alone.

```text
1. Run the batch suite in production-like conditions before promoting.
2. After promoting, watch Command Center for error and escalation rates.
3. Sample five real sessions and read their traces end to end.
4. Check credit consumption against the previous release, per agent.
5. Have the runbook open on a second screen, and name the on-call person.
6. Roll back quickly if the numbers move the wrong way.
```

### Why each step is there

| Step | What it catches |
| --- | --- |
| Batch suite in production-like conditions | Volume and data-shape problems |
| Error and escalation rates | Anything broadly broken |
| Five sampled sessions | What tests could not predict |
| Credits vs previous release | Retrieval or looping changes |
| Runbook open | Avoids diagnosis from scratch |
| Rollback readily available | Limits the blast radius |

Step 3 is the one that earns its keep. A prompt change can deploy cleanly,
pass every test, and still produce badly wrong answers — because tests use
your phrasing and customers do not.

Step 4 catches a class nothing else does. A change that doubles retrieval
volume produces correct answers, no errors and no escalations, and a much
larger bill.

---

## 5. Roll back, do not debug in production

```text
Escalation rate doubled an hour after a release.
```

**Correct:** roll back to the previous version, then diagnose from the
traces of the escalated sessions.

**Incorrect:** start debugging. Debugging in production with a doubled
escalation rate extends the incident from one hour to an afternoon, and the
customer impact is real while you work.

The discipline is uncomfortable because it feels like losing information.
You do not: the traces survive the rollback, and the previous version is
still available to compare against.

---

## 6. The new operator's test

A runbook is only good if a newcomer can use it. Test it with a question:

> *The refund agent is escalating far more than usual. What do you do?*

**Good answer:** Check Command Center to confirm it is real, read three
escalated session traces to find whether it is one failure or several,
then roll back to the previous version and diagnose off-production. If the
rollback does not fix it within 15 minutes, escalate to the Duty Manager.

**Bad answer:** "Look at the instructions and see if something looks
wrong."

That is where diagnosis *starts*, not where a 3am response ends. If your
runbook produces the bad answer, the mitigation section is missing.

---

## 7. Ownership

| Item | Owner | Review cadence |
| --- | --- | --- |
| The agent definition | Platform team | Every change |
| The knowledge articles | Knowledge team | Monthly |
| The runbook | On-call team | Quarterly, and after every incident |
| The credit budget | Platform + FinOps | Monthly |
| The evaluation suite | Whoever changed the prompt | Every change |

The evaluation suite owner is the one teams get wrong. If the person who
changed the prompt does not run the suite, the change ships unmeasured,
and the next person to touch the agent inherits an unmeasured change with
no idea.

---

## 8. Anti-patterns

| Anti-pattern | Consequence |
| --- | --- |
| Approve on model confidence | Approves exactly the confident-error cases |
| Runbook with no mitigation section | Diagnosis without response |
| Debug in production | The incident outlasts its cause |
| Widening grounding to fix a miss | Trades a miss for a wrong answer |
| Escalating content problems to engineering | Wasted hours on the wrong team |
| No disable switch | No fast response option |
| Nobody owns the evaluation suite | Changes ship unmeasured |

---

## Check yourself

1. **Escalation rate doubled an hour after a release. What is the correct
   first action?**
   Roll back, then diagnose from the escalated sessions' traces. Debugging
   in production with a doubled escalation rate is how one bad release
   becomes an outage.

2. **Why is model confidence a bad approval trigger?**
   Because confidence is not a risk measure. Confident errors are exactly
   the cases that need a human, so triggering on confidence approves the
   wrong set. Use worst-case impact and reversibility.

3. **A grounding miss rate alert fires at 2am. Who do you call?**
   The knowledge owner, not engineering. A status change from `Published`
   to `In Review` with no code change is the most common cause, and no
   amount of engineering investigation will find it.

4. **Your runbook says "investigate the instructions". What is wrong?**
   It has no mitigation. A first-response document needs "how do I stop
   this", not just "where might I look". That is why the disable switch
   and the rollback are separate sections.

5. **A release doubles credit consumption with no errors and no
   escalations. Which first-hour step catches it?**
   Step 4, comparing credits against the previous release per agent. Nothing
   else would surface it.

---

## Key takeaways

- Approve on worst-case impact and reversibility, never on model
  confidence.
- A runbook needs alert, three diagnostic steps, mitigation, escalation
  and rollback. Mitigation is the section people forget.
- The first hour after a release is where most incidents are caught.
  Sample real sessions and compare credits.
- Roll back first, diagnose second.
- Content problems go to the knowledge owner, not engineering.
- Every runbook is tested with a newcomer's question.
