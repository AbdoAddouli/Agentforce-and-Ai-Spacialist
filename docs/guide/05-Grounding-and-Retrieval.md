# Grounding and Retrieval

Grounding is the agent's input contract. This phase is about making it
narrow enough to be accurate and wide enough to be useful — and about
knowing which of those two you are failing.

---

## 1. The core idea

An agent has three possible sources for an answer:

| Source | You control it? | Risk |
| --- | --- | --- |
| Instructions | Yes | Too broad; the model fills gaps |
| Grounding | Yes | Too wide; the right record is crowded out |
| Model's parametric knowledge | No | **Fabrication** |

The instruction that matters most is the one that closes the third door:

```text
Answer only from the retrieved content. If the retrieved content does not
answer the question, say so and offer escalation. Do not answer from
general knowledge and do not guess.
```

Both halves are required. "Answer only from the retrieved content" without
a refusal path leaves the agent with no legal move, so it answers from
memory anyway.

---

## 2. Bounding the reference

```json
{
  "primary": [
    {
      "object": "Knowledge_Article__c",
      "filter": "Status__c = 'Published' AND Category__c IN ('Refunds','Billing','Orders')",
      "maxRecords": 5
    },
    {
      "object": "Order",
      "filter": "Id IN :orderIdsFromSession AND Status__c = 'Shipped'",
      "maxRecords": 3
    }
  ],
  "excluded": [
    { "reason": "unrelated tenants",    "filter": "AccountId != :currentAccountId" },
    { "reason": "draft content",        "filter": "Status__c = 'Draft'" },
    { "reason": "superseeded policy",   "filter": "Version__c < :currentVersion" },
    { "reason": "low relevance filler", "filter": "Category__c IN ('Marketing','Events')" }
  ],
  "maxTotalRecords": 8
}
```

### Why each exclusion earns its place

| Exclusion | Failure it prevents |
| --- | --- |
| Other tenants | Cross-customer data disclosure — the worst failure available |
| Draft articles | Citing unreviewed or wrong content |
| Superseded versions | Two versions in context; the model picks the retired one |
| Marketing content | Semantic neighbours crowding out the policy article |
| `maxTotalRecords` | Silent cost and latency growth as data grows |

The supersession exclusion is the subtle one. Two versions of a refund
policy in context is not a coin flip you can train away — the model has no
signal telling it which is current unless you remove the old one.

---

## 3. Why caps are the most important line

Consider a question that needs one order record. With no cap, retrieval
returns the 60 most semantically similar records in the tenant. The correct
order is now competing against 59 others, and it may not be in the final
context at all.

This is not a hypothetical. In Phase 12, a session retrieved 60 records
twice for a single-order question. The fix was `maxRecords: 3` — and the
agent's answers became *more* correct, not less. The instinct that a
wider scope is a safer scope is backwards for a bounded question.

Cap values are a judgement, not a constant. Articles: 3–5. Specific records
by id: 3. Anything scoped by category rather than by id: reconsider whether
the category is narrow enough to be the filter.

---

## 4. Measuring recall and precision

```text
For each evaluation question, log:
  retrieved ids and their rank
  the answer given
  whether the required article was in the retrieved set   <- recall
  the citations in the answer                            <- precision
```

| Metric | Question it answers | Fix |
| --- | --- | --- |
| **Recall** | Was the right document retrieved at all? | Widen, or fix a filter excluding it |
| **Precision** | Was the right document used in the answer? | Narrow, or improve ranking |
| **Rank of the correct hit** | Is it winning, or just present? | Narrow, or rerank |

Rank matters and is usually the missing metric. A correct document at rank
14 of 60 is technically a recall hit and practically a failure.

### Why this matters more than it sounds

A grounding problem diagnosed as "the model is bad at retrieval" is
usually a scope problem. Measuring tells you which knob to turn, and the
two knobs turn in opposite directions. Without the measurement you either
widen forever or narrow blindly.

---

## 5. Secure data retrieval

The trust-layer mechanism that answers a question the exam asks often:

> How do you use retrieved customer data to answer questions without
> sending that data to the model?

Secure data retrieval lets the retrieved records inform the answer without
being handed to the model as prompt text. This is the difference between
"the data was in the system" and "the data was in the prompt".

| Concern | Addressed by |
| --- | --- |
| PII reaching the model | Data masking |
| Provider retaining the data | Zero data retention |
| Cross-tenant exposure | Data Space isolation + scope |
| Retrieved records in the prompt | Secure data retrieval |

The four are distinct. Masking does not give you zero retention. Zero
retention does not stop cross-tenant retrieval. Secure data retrieval does
not mask what is in the action's own output.

---

## 6. Grounding for actions, not just answers

Grounding is not only about what the agent knows; it is about what it can
invoke.

| Layer | Grounded in | Failure if not |
| --- | --- | --- |
| Answers | Knowledge articles, records | Fabrication |
| Action parameters | Retrieved record values | Invented identifiers and amounts |
| Action invocation | Permission set | Acting beyond authorisation |

The second row is the one that changes behaviour. If the amount must come
from a retrieved record, the model has no value to invent:

```text
CONSTRAIN: the amount must equal a value present in the retrieved order.
IF the model proposes a value not present -> DECLINE.
```

Compare with asking for the amount and hoping. The difference between
"choose among these values" and "produce a number" is the difference
between a structural guarantee and a request.

---

## 7. Handling retrieval failure

Three distinct outcomes, and conflating them is a common bug:

| Outcome | Meaning | Correct response |
| --- | --- | --- |
| **No results above threshold** | Not known | Say so; offer escalation |
| **Results, none relevant** | Not known | Say so; offer escalation |
| **Timeout or error** | Not known | Say so; do **not** treat as a negative |

The third is the trap. A timeout is *missing information*. Treating it as
a negative answer means the agent tells a customer their refund was
declined when the system simply could not answer.

```text
A retrieval failure is never a negative answer. Report it as unknown.
```

---

## 8. Grounding anti-patterns

| Anti-pattern | Consequence |
| --- | --- |
| No `maxRecords` | Correct record crowded out; cost climbs silently |
| No status filter | Draft and retired content cited |
| Tenant filter in the prompt only | Request, not enforcement — rely on Data Spaces |
| Both versions of a policy in scope | Model picks the retired one |
| Category filter that is really a tenant filter | Scope leaks as content grows |
| Grounding described in instructions, not config | Unreviewable, unversioned |
| Treating a timeout as "no" | Confidently wrong negative answers |

---

## Check yourself

1. **A user asks "what is the refund policy for the Pro plan". The agent
   cites the Basic plan policy. Which failure is this, and what do you
   change?**
   A precision failure. The Pro article was probably retrieved too, at a
   lower rank, or not retrieved. Check rank before widening — if the Pro
   article is at rank 2 of 60, the fix is a cap and a tighter category
   filter, not more scope.

2. **Why does including both v3 and v4 of a policy in scope make things
   worse?**
   The model has no signal for which is current unless told, and "current"
   is a word in a prompt, not a field in a filter. Remove the superseded
   version from scope.

3. **A grounding call times out. What should the agent do?**
   Report unknown and offer escalation. It must not treat the timeout as a
   negative answer, and it must not retry indefinitely.

4. **Your action's `amount` parameter is described as "the refund amount".
   Why is that a problem?**
   It invites the model to produce a number from memory. Describe it as
   "an amount present on the retrieved order record" and validate the
   value against the record server-side.

5. **How would you distinguish a recall failure from a precision failure
   in production, without a labelled test set?**
   Sample real sessions, read the traces, and compare the retrieved ids
   against the record the customer was actually asking about. You do not
   need a full labelled set to learn whether the right record is being
   retrieved at all.

---

## Key takeaways

- Grounding is a contract. Bound it, version it, and cap it.
- `maxRecords` is the most consequential line in the scope, and omitting
  it makes answers *less* accurate.
- A timeout is missing information, never a negative answer.
- Secure data retrieval lets records inform answers without entering the
  prompt. It is distinct from masking and from zero retention.
- Ground the action parameters, not just the answers.
- Measure recall, precision and rank. The fixes are opposite directions.
