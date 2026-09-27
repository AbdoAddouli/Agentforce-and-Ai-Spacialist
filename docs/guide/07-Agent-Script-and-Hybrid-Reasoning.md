# Agent Script and Hybrid Reasoning

Agent Script is one of the five named focus areas for the Summer '26
maintenance release. It is the declarative alternative to a free-form
instruction set: a reviewable sequence of steps that blends deterministic
operations with model reasoning.

---

## 1. Why it exists

A free-form instruction set asks the model to decide everything. An Agent
Script decides for it, in a structure you can read, review, diff and test.

| | Free-form instructions | Agent Script |
| --- | --- | --- |
| Who decides the order? | The model, per turn | You, at design time |
| Reviewable? | Only as prose | Yes, step by step |
| Testable? | Only end to end | Yes, per step |
| Cost predictability | Varies per session | Bounded by design |
| Handles novel input | Well | Only where you allow reasoning |
| Maintenance | Edit prose | Edit a structured document |

The trade is real: a script is less flexible. That is the point. Most
customer journeys are not novel, and a script makes the common cases
deterministic while spending model reasoning only where judgement is
actually required.

---

## 2. The step types

| Type | What it does | Needs the model? |
| --- | --- | --- |
| **Retrieve** | Fetch records or knowledge | No |
| **Act** | Invoke an action | No |
| **Reason** | Apply judgement to retrieved content | Yes |
| **Branch** | Route on a condition | No |
| **Guard** | Precondition checked before any work | No |
| **Escalate / Decline** | Terminal outcomes | No |

Only `Reason` steps consume model reasoning. Everything else is
deterministic, which is where the cost saving comes from.

---

## 3. A worked example

```text
SCRIPT: Standard refund
DESCRIPTION: Refund an order that qualifies under the published policy.

GUARD:
  Order.Status__c = 'Delivered'
  AND request within 45 days of delivery

STEP 1 — Retrieve
  retrieve Order WHERE Id = :orderId
  FAIL_IF missing         -> ESCALATE "order not found"
  FAIL_IF not Delivered   -> DECLINE  "order not delivered"

STEP 2 — Retrieve
  retrieve Knowledge_Article__c
    WHERE Category__c = 'Refunds' AND Status__c = 'Published'
  FAIL_IF no article      -> ESCALATE "no current refund policy"

STEP 3 — Reason
  Ask the model: given the delivered order and this policy, is the
  customer's stated reason covered?
  CONSTRAIN: answer from the retrieved policy only.
  IF not covered          -> DECLINE with the policy sentence quoted

STEP 4 — Reason
  Ask the model: propose a refund amount.
  CONSTRAIN: the amount must equal a value present in STEP 1.
  IF not a retrieved value -> DECLINE "amount could not be determined"

STEP 5 — Act
  issueRefund(orderId, amount)
  FAIL_ON error           -> ESCALATE with the error, do not retry

STEP 6 — Confirm
  Respond with the amount returned by STEP 5 and the published timeframe.
  The amount MUST be the value STEP 5 returned, not a regenerated one.
```

---

## 4. The two ideas that matter most

### The guard is a precondition

`GUARD` is evaluated **once, before any work**. Without it, the script
retrieves, calls a subagent, reasons about an undelivered order, and only
then discovers the problem — paying full cost and latency for a decision
that was already available in one field comparison.

A guard is a fail-fast, and fail-fast is the whole point of structuring.

### Constrained reasoning on the value

Step 4 is where implementations usually go wrong. Asking a model for a
number means asking it to produce a number it has no source for.

The correct construction:

```text
Ask the model: propose a refund amount.
CONSTRAIN: the amount must equal a value present in STEP 1.
IF the model proposes a value not present in STEP 1
   -> DECLINE "amount could not be determined from the record"
```

The judgement (which amount) is left to the model. The *value space* is
fixed by the data. And a proposal outside the space is a **failure**, not
something to clamp, round or accept.

The same reasoning applies to step 6, which reuses the value from step 5
rather than regenerating it. Two generations of the same number is two
chances to differ.

---

## 5. Why the hybrid framing is the point

Pure scripting does not scale: the world does not stay inside your
branches. Pure prompting does not verify: nothing checks the order of
operations.

Hybrid means:

```text
Deterministic for facts     -> retrieve, guard, branch, act
Reasoning for judgement     -> the smallest number of Reason steps
Structurally enforced values-> the thing the model must not invent
```

| Step | Type | Reason |
| --- | --- | --- |
| 1–2 | Deterministic | Fetching is not a judgement |
| 3 | Reasoning | Judgement against a policy genuinely needs a model |
| 4 | Constrained reasoning | Judgement is hard; the *value* must come from data |
| 5 | Deterministic | A write must not be improvised |
| 6 | Deterministic | Reporting a value that already exists |

Three of six steps never call a model. On the two cases the guard rejects,
nothing does.

---

## 6. Terminal outcomes

Every script needs a closed set of endings, and every one of them must be
reachable and testable.

| Outcome | When | What the agent does |
| --- | --- | --- |
| **Complete** | All steps succeeded | Report the value the action returned |
| **Decline** | Policy says no | Quote the policy sentence, offer no alternative |
| **Escalate** | Cannot proceed safely | Hand off with what was tried and what is missing |
| **Abort** | Input unusable | Say what is needed, ask one question |

The mistake is having only two of them. A script with success and failure
and nothing else forces every edge case into one of them, and the model
will improvise to pick the closer fit.

`Escalate` is the one most often omitted, and it is the one that prevents
the worst outcomes: a script with no escalation path has no safe response
to "the policy article is missing", so it will produce something.

---

## 7. Testing a script

| Case | Expected |
| --- | --- |
| Delivered, in window, reason covered | Refund issued, amount from record |
| Delivered, outside window | Declined at guard, **no model call** |
| Not delivered | Declined at guard, **no model call** |
| Policy article missing | Escalated at step 2 |
| Model proposes a new amount | Declined at step 4 |
| Action returns an error | Escalated, no automatic retry |
| Two distinct intents in one message | Escalated, nothing attempted |

The two "no model call" cases are the measurable payoff. On those inputs
the script is correct by construction, at zero reasoning cost, in constant
time. A free-form instruction set would reason, retrieve, and probably
arrive at the same answer — having paid for the privilege.

---

## 8. When to script and when not to

| Use a script | Use a free-form agent |
| --- | --- |
| The journey is known and repeatable | The request is genuinely open-ended |
| Steps have a required order | Order is an implementation detail |
| A wrong value is costly | Being wrong is cheap and correctable |
| You need predictable cost per session | Novelty is the product |
| Regulated, auditable steps | Exploration or discovery |
| You need per-step test coverage | End-to-end accuracy is enough |

A hybrid is common and healthy: script the risky, ordered, audited parts;
leave the conversational parts free-form. Most production agents should be
scripted at the action boundary and free-form in the dialogue.

---

## Check yourself

1. **Your script retrieves the order, calls a subagent, reasons about the
   refund, and only then discovers the order was never delivered. What
   should have happened, and what does it cost you?**
   The `GUARD` should have caught it before step 1. You paid retrieval, a
   subagent call and a reasoning step to rediscover a field value that a
   single comparison would have answered — in both credits and latency.

2. **A Reason step asks for a refund amount. The model returns a plausible
   figure that is not on the order. What is the correct response?**
   Decline. Do not clamp, round or accept. The value space must be fixed by
   the retrieved record, and a proposal outside it is a failure — because
   accepting it reintroduces exactly the fabrication the constraint
   existed to prevent.

3. **Name the four terminal outcomes of a script.**
   Complete, decline, escalate, abort. Every one must be reachable.

4. **Why does step 6 read the amount from step 5 rather than ask again?**
   Two generations of the same value is two chances to differ, and a
   discrepancy between what was refunded and what the customer was told is
   an incident.

5. **A maintenance-focused candidate is asked: "which part of a script is
   model reasoning and which is deterministic?"**
   `Reason` steps are model reasoning. Retrieve, Act, Branch, Guard and the
   terminal outcomes are deterministic. Being able to state that
   distinction is the core of the Agent Script focus area.

---

## Key takeaways

- A script decides order at design time, so it is reviewable, testable and
  cost-bounded.
- Guards are preconditions, evaluated before any work.
- Constrain the *value space* of a reasoning step; reject proposals
  outside it rather than adjusting them.
- Reuse returned values; never regenerate one.
- Every script needs complete, decline, escalate and abort.
- Script the risky ordered parts; leave dialogue free-form.
