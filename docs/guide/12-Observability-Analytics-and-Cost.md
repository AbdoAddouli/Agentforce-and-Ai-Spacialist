# Observability, Analytics and Cost

Observability is how you prove what an agent did and where the credits
went. It shares the Governance and Observability domain with Phase 13, and
it is the domain where the Summer '26 maintenance focus lands hardest.

---

## 1. Three tools, three questions

| Tool | Question it answers | Granularity |
| --- | --- | --- |
| **Command Center** | Is the agent healthy right now? | Org and agent level |
| **Agent Analytics** | How is it doing over time? | Aggregated trends |
| **Session Tracing** | Why did this one session go wrong? | Single session, every step |

The most common operational mistake is starting at the dashboard when the
question is "why". The dashboard tells you it is up; the trace tells you
which step did it.

### What a session trace contains

```text
Session
 ├─ Step 1  reason
 ├─ Step 2  ground            retrieved 60 records
 ├─ Step 3  reason
 ├─ Step 4  subagent Billing
 ├─ Step 5  subagent Billing  identical arguments to step 4
 ├─ Step 6  ground            retrieved 60 records again
 ├─ Step 7  act openDispute
 └─ Step 8  act openDispute   ERROR: DUPLICATE_CASE
```

Every reasoning step in order, every subagent call and result, every
retrieval with its source, every action with parameters and duration, and
the credits consumed at each step. The credits per step are what make the
expensive step visible.

---

## 2. Reading a trace: a worked example

A session that cost 14 credits against a normal 3:

| Step | Type | Credits | Note |
| --- | --- | --- | --- |
| 1 | reason | 0.4 | |
| 2 | ground | 0.6 | 60 records |
| 3 | reason | 0.5 | |
| 4 | subagent Billing | 0.4 | |
| 5 | subagent Billing | 0.4 | **identical to step 4** |
| 6 | ground | 0.6 | **60 records again** |
| 7 | reason | 0.5 | |
| 8 | act openDispute | 0.5 | |
| 9 | act openDispute | 0.5 | **DUPLICATE_CASE** |
| 10 | reason | 0.5 | retrying |
| 11 | act openDispute | 0.5 | **DUPLICATE_CASE** |
| 12 | escalate | 0.6 | |

Three causes, and they are not equally important.

**1. Unbounded retrieval.** 60 records twice, for a question needing one
order. The grounding reference has no cap, and 60 results crowd out the
record the answer depends on.

**2. A repeated subagent call.** Steps 4 and 5 are identical. Nothing
changed between them, so step 5 bought nothing. The model looped because
nothing told it the answer was already obtained.

**3. A retried non-idempotent write.** Steps 9 and 11 retried after
`DUPLICATE_CASE` — which is the system saying *it already succeeded*. The
agent treated an idempotency signal as a failure.

---

## 3. The fixes

### Cap the retrieval

```json
{ "object": "Order", "filter": "Id IN :orderIds", "maxRecords": 3 }
```

Plus relevance thresholding, so an irrelevant match returns nothing rather
than 60 weak ones.

### Stop conditions

```text
- Do not call the same subagent twice with the same arguments.
- Once a subagent returns a result, use it.
- Maximum 8 reasoning steps per turn, then escalate.
```

### Idempotency in the action

```apex
List<Case> prior = [
    SELECT Id, CaseNumber FROM Case
    WHERE AccountId = :o.AccountId AND Origin = 'Agentforce' AND IsClosed = false
    ORDER BY CreatedDate DESC LIMIT 1
];
if (!prior.isEmpty()) {
    r.success = true;                    // success, not failure
    r.caseNumber = prior[0].CaseNumber;
    r.nextStep = 'Dispute ' + prior[0].CaseNumber + ' is already open.';
    return r;
}
```

### Do not retry a class of error

| Error class | Retryable | Why |
| --- | --- | --- |
| Timeout, 5xx | Yes, 1–2 with backoff | Transient |
| `DUPLICATE_CASE` | **No** | It already succeeded |
| Validation error | **No** | Identical input fails identically |
| Permission error | **No** | Retrying will never succeed |

Retrying a duplicate is how one call became three.

---

## 4. Before and after

| Metric | Before | After |
| --- | --- | --- |
| Records retrieved per turn | 60 | 3 |
| Subagent calls | 2 | 1 |
| `openDispute` calls | 3 | 1 |
| Reasoning steps | 12 | 6 |
| **Credits per session** | **14.2** | **3.6** |

A 75% reduction — and, more importantly, the answer no longer depended on
one record surviving 60 competitors. **The cost fix improved accuracy.**
That is the usual relationship, not a coincidence: wasted steps are
usually the result of the agent not finding what it needed.

---

## 5. Flex Credits

Flex Credits are the unit Agentforce consumption is metered in. Consumption
is driven by the work each turn does: tokens processed, data retrieved, and
actions invoked.

That makes a credit budget a **governance** control, not just a finance
one.

### A budget that holds

```text
1. Org-level budget and a per-agent budget.
2. Alert at 60% and 85% consumed.
3. Bound the loop: a maximum iteration count per turn.
4. Cap expensive actions per turn, and rate-limit retries.
5. Review top consumers by agent and by subagent monthly.
6. Narrow the grounding reference of the worst offender.
```

### A credit spike is always one of three things

| Cause | Signature in the trace |
| --- | --- |
| Grounding reference got too wide | High retrieval volume per turn |
| Agent loops after a successful action | Repeated identical calls |
| A subagent fans out without a limit | Many subagent calls, one turn |

Look for the signature before touching the budget. Raising the limit makes
the invoice arrive and the problem remain.

---

## 6. Alerting

| Alert | Threshold | Why |
| --- | --- | --- |
| Credit burn | +50% day over day | Cheapest early signal |
| Grounding miss rate | > 20% | Content or scope problem |
| Escalation rate | > 3x baseline | Something regressed |
| Action error rate | > 5% | Integration or permission failure |
| Session p95 latency | > 2x baseline | Loop or slow dependency |
| Duplicate action rate | > 1% | Idempotency defect |

Every alert needs an owner and a first diagnostic step. An alert with
neither is noise, and noise trains people to ignore alerts.

---

## 7. OpenTelemetry

Exporting session telemetry into your own tooling, rather than only reading
it in Salesforce, gives you:

- Dashboards in whatever BI tool the business already uses
- Alerting into Slack or PagerDuty
- Long-term retention beyond Salesforce's window
- Correlation with your own service telemetry

It does not replace session tracing — it moves the *numbers* out. The step
detail stays where it is.

---

## 8. Anti-patterns

| Anti-pattern | Consequence |
| --- | --- |
| Starting at the dashboard for a "why" question | Days lost; the answer is in the trace |
| Raising the budget when credits spike | The invoice arrives; the problem remains |
| No per-step credit attribution | The expensive step stays invisible |
| Alerting with no owner | Trained-away alerts |
| Retrying all errors uniformly | Duplicate side effects |
| No grounding miss rate | Content rot is invisible until a complaint |
| OpenTelemetry treated as a replacement for traces | Step detail is lost |

---

## Check yourself

1. **Credits tripled overnight, no code change. What is the first thing
   you do?**
   Read the session traces of the expensive sessions, looking for
   retrieval volume, repeated actions, or an unbounded loop. Not the
   budget, and not the code — the trace is where the cause is.

2. **The trace shows `openDispute` called twice, the second returning
   `DUPLICATE_CASE`. What is the correct interpretation?**
   The first call succeeded; the system is reporting that the dispute
   already exists. The agent treated an idempotency signal as a failure
   and retried. Fix: the action returns success for an existing dispute.

3. **Name the three causes of a credit spike.**
   A grounding reference that got too wide; an agent looping after a
   successful action; a subagent fanning out without a limit.

4. **You capped retrieval from 60 records to 3 and credits fell 75%. Why
   did accuracy improve too?**
   The correct record was competing against 59 others and was frequently
   outside the final context. Wasted steps are usually the result of the
   agent not finding what it needed.

5. **What does an alert need that a threshold does not provide?**
   An owner and a first diagnostic step. Without both it is noise, and
   noise gets ignored.

---

## Key takeaways

- Three tools: Command Center for now, Analytics for trends, Tracing for
  why.
- For a "why" question, go to the trace. Always.
- A credit spike is one of three things, and each has a signature in the
  trace.
- Cost fixes usually improve accuracy. Wasted steps mean the agent did
  not find what it needed.
- Never raise a budget to resolve an unexplained spike.
- Every alert needs an owner and a first diagnostic step.
