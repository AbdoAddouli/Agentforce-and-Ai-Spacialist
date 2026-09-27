# Data 360 Fundamentals

Data 360 is the current name for what was Data Cloud. This phase covers
what you need to model, retrieve and trust the data an agent reasons over.
It carries 20% of the exam.

---

## 1. Why data modelling decides agent quality

An agent can only be as good as the data it can reach. Two failures account
for most bad agent answers:

| Failure | Cause | Symptom |
| --- | --- | --- |
| **Recall failure** | The correct document was out of scope | "I don't have that information" on something you published |
| **Precision failure** | Too much in scope, the right one crowded out | A confident answer citing the wrong policy |

These have **opposite fixes**. Widening the scope helps recall and hurts
precision. Guessing which one you have is why you measure rather than
iterate blindly. Phase 5 covers the measurement.

---

## 2. The model

| Object | Key fields | Why it exists |
| --- | --- | --- |
| `Knowledge_Article__c` | Title, Body__c, Status__c, Category__c, Version__c, Effective_From__c, Reviewed_By__c, Reviewed_On__c | One fact, one row, one owner |
| `Knowledge_Review__c` | Article__c, Reviewer__c, Outcome__c, Notes__c | The audit trail behind "reviewed" |
| `Grounding_Source__c` | Name, Type__c, Object_Api_Name__c, Scope_Json__c, Is_Active__c | The agent's declared retrieval boundary |

### Why articles, not a document blob

A knowledge article is reviewable, versioned and permissionable **on its
own**. A shared long text field in a settings object is none of those, and
it is the single most common modelling mistake in agent projects.

| Requirement | Article | Shared text field |
| --- | --- | --- |
| Reviewed by a named person | Yes | No |
| Version history | Yes | No — you overwrite and lose it |
| Permissionable separately | Yes | No |
| Citable in an answer | Yes | Awkwardly |
| Effective-dated | Yes | No |

### Why status, not a boolean

```text
Draft  ->  In Review  ->  Published  ->  Retired
```

With a boolean `Is_Active__c` you cannot distinguish "not written yet" from
"under review" from "deliberately withdrawn". All three get retrieved, and
a draft policy is a live liability. A status makes the retrieval filter a
truth value.

### Why version, not overwrite

Policy changes. An answer citing version 3 when 4 is live is a defect you
cannot investigate without history. `Version__c` plus `Effective_From__c`
tells you what was true when the agent answered.

---

## 3. The question a schema must answer

A data model is only justified if it answers a question you could have asked
before building it. For agent grounding, five matter:

| Question | Answered by |
| --- | --- |
| Which facts can the agent cite? | `Knowledge_Article__c` where Status = Published |
| What is the single source of truth? | One article per topic, enforced by a unique key on Title |
| How is accuracy maintained? | `Knowledge_Review__c` plus Reviewed_By / Reviewed_On |
| How is a policy change handled? | `Version__c` and `Effective_From__c` |
| What is the agent's retrieval boundary? | `Grounding_Source__c` |

If you cannot answer all five by naming a field, the model is not finished.

---

## 4. Grounding sources

`Grounding_Source__c` declares what the agent may retrieve, in one
reviewable record:

```text
Name              Acme Support KB
Type__c           LightningKnowledge
Scope_Json__c     {
                    "objects":    ["Knowledge_Article__c", "Case", "Order"],
                    "statuses":   ["Published"],
                    "scope":      "current account + public policy",
                    "maxRecords": 25
                  }
Is_Active__c      true
```

### The fields that matter most

| Field | What it controls | Failure if omitted |
| --- | --- | --- |
| `objects` | Which records are reachable | Everything is reachable |
| `statuses` | Only published content | Drafts get cited |
| `scope` | Tenant and user boundaries | Cross-customer disclosure |
| `maxRecords` | Result volume | The right record is crowded out; cost grows |

`maxRecords` is the one most projects omit, and it is the one that causes
both precision failures and unexpected cost. Relevance ranking, not human
judgement, decides what the model sees once you stop capping.

---

## 5. Data 360 concepts you need to name

| Concept | What it is | Why it matters here |
| --- | --- | --- |
| **Data Space** | An isolated tenant boundary | The hard limit on who can see whose data |
| **Data Space Sharings** | Controlled sharing between spaces | How two domains share without merging |
| **Data Model** | The relationships between objects | Determines what can be joined in a query |
| **Data Stream** | Incoming data from a source | How records arrive |
| **Data Related List / Data Recipe** | Derived, enriched data sets | Where computed fields belong |
| **Zero Copy** | Reference data without copying it | Live CRM data in Data 360, no duplication |
| **Identity Resolution** | Matching records to one person | Without it, the same person has two profiles |

### Zero Copy, specifically

With Zero Copy, Data 360 references Salesforce data rather than copying it.
For agent grounding this matters because the agent reads current CRM data
with no synchronisation delay and no duplicated copy to keep in step. The
trade-off is that the data is only as available as the source system.

### Data Space isolation

A Data Space is a hard boundary. If customer data must not cross tenants, a
Data Space is the control — not a filter in the grounding scope, and not an
instruction. A filter is a request; a Data Space is a boundary.

---

## 6. Identity resolution and why agents break without it

If the same customer exists as three profiles, then:

- The agent retrieves one order and misses the other two.
- Credit cost rises because more records compete for the same slots.
- The answer looks wrong to a customer who is looking at a different screen.

Identity resolution is not a Data 360 feature you enable later. It is
part of getting the model right.

---

## 7. Data policies: the enforcement layer

A data policy on an action defines what the action may return. It is
enforced by the platform and cannot be talked around.

| Policy type | What it controls |
| --- | --- |
| Field-level | Which fields leave the action at all |
| Record-level | Which records the action may touch |
| Data masking | Which fields are masked before the model sees them |
| Data masking on a model | Applies to all prompts, including ad hoc |
| Zero data retention | Instructs the provider not to store what it receives |
| Secure data retrieval | Retrieved data informs the answer without entering the prompt |
| Residency | Where processing happens |

The exam distinction that matters most:

| | Enforcement |
| --- | --- |
| "Never discuss another customer's data" | A request. Model-dependent. |
| Data Space isolation | Enforced. Model-independent. |

Both are worth having. Only one is a control.

---

## 8. Keeping the data correct

| Control | Owner | Cadence |
| --- | --- | --- |
| `Reviewed_On__c` staleness alert | Knowledge team | Monthly |
| `Knowledge_Review__c` on every change | Reviewer | Per change |
| Draft content excluded from retrieval | Platform | Continuous |
| Duplicate-topic check on Title | Platform | Continuous |
| Grounding coverage report | Platform | Weekly |

The failure mode to avoid is the one from Phase 15: a knowledge article
moves from `Published` to `In Review`, retrieval silently stops returning
it, and the agent's grounding miss rate climbs. Nobody changed the code.
The runbook's first diagnostic step is to check the status field, because
it is the most common cause and the least obvious.

---

## Check yourself

1. **A customer asks about an order, and the agent says it has no record
   of it. The record exists and is visible in Salesforce. What are the
   three most likely causes?**
   The order is out of the grounding scope. The article or record is not in
   `Published` status. Identity resolution has split the customer's records
   so the agent retrieved a different profile. In that order of likelihood.

2. **Why is `Status__c` better than `Is_Active__c = true`?**
   Because a boolean cannot distinguish draft from in-review from
   deliberately retired, so all three are retrieved and a draft policy
   becomes citable.

3. **You need to expand grounding to fix a recall failure. What are you
   risking?**
   A precision failure: more irrelevant records competing for the same
   limited slots, so the correct record now ranks lower. Add a measured
   case first, and confirm the fix with recall *and* precision metrics.

4. **Name the control that prevents an agent reading another tenant's
   data.**
   Data Space isolation. A grounding scope filter is a request the model
   could work around; a Data Space is enforced by the platform.

5. **A record needs a computed field the agent will read. Where does it
   belong?**
   A Data Related List or Data Recipe in Data 360, or a formula field on the
   record — not inside the prompt. Computed values belong in data so the
   model reads them rather than deriving them.

---

## Key takeaways

- Model one fact per row, with status, version and review fields.
- A schema is finished when it answers the five questions on source of
  truth, currency and retrieval boundary.
- Always cap `maxRecords`. Relevance ranking, not judgement, decides what
  the model sees without a cap.
- Recall and precision failures have opposite fixes. Measure which you have.
- Data Space isolation is a control; a grounding filter is a request.
- Data correctness is an operational process. A status change with no code
  change is a real incident mode.
