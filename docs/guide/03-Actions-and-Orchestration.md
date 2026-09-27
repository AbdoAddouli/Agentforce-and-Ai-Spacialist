# Actions and Orchestration

An action is the only way an agent changes anything. Everything in this
phase follows from that: the action is a boundary between a probabilistic
caller and a deterministic system, and a boundary needs a contract.

---

## 1. The action contract

An action has an input schema and an output schema. Both matter, and the
output schema matters more than most teams expect.

### Input

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `orderId` | Id | Yes | Must be readable by the running user |
| `reason` | String | Yes | Non-blank, 10–500 characters |

Every parameter needs a description the model can act on. A parameter with
no description is a parameter the model will guess at.

### Output

| Field | Type | Purpose |
| --- | --- | --- |
| `success` | Boolean | Did it complete? |
| `disputeId` | Id | The created record |
| `caseNumber` | String | Human-quotable reference |
| `nextStep` | String | The sentence to say next |
| `needsHuman` | Boolean | Escalate rather than retry |

Three of those exist for reasons that are not obvious.

- **`nextStep` as data.** The agent *reads* it instead of inventing a
  customer-facing sentence and getting the timeframe wrong.
- **`needsHuman`.** Gives the caller an explicit escalate signal instead of
  making it infer one from a failure.
- **`success` separate from a null result.** Distinguishes "did nothing on
  purpose" from "failed".

---

## 2. Return, do not throw

This is the single most important implementation rule in the phase.

```apex
// Wrong: the model gets an opaque failure and will typically retry
if (orderId == null) {
    throw new CustomException('Invalid order');
}
```

```apex
// Right: the model gets a value it can read and act on
if (orderId == null) {
    r.success    = false;
    r.needsHuman = true;
    r.nextStep   = 'I could not open a dispute without an order reference.';
    return r;
}
```

Why it matters: an exception surfaces to the model as a failure with no
usable content. The model has nothing to branch on, so its default
behaviour is to try again. One bad call becomes three, and if the action
writes, that is three records.

| Failure | What the model sees | What it does |
| --- | --- | --- |
| Exception | "Action failed" | Retries, possibly repeatedly |
| `success: false` + reason | Readable reason | Adjusts or escalates |
| `needsHuman: true` | Explicit instruction to stop | Stops and hands off |

---

## 3. Idempotency, because agents retry

An agent may retry after a timeout that actually succeeded. If the action
is not idempotent, the retry duplicates the side effect.

```apex
List<Case> prior = [
    SELECT Id, CaseNumber
    FROM Case
    WHERE AccountId = :o.AccountId
      AND Origin    = 'Agentforce'
      AND IsClosed  = false
    ORDER BY CreatedDate DESC
    LIMIT 1
];
if (!prior.isEmpty()) {
    r.success    = true;                    // success, not failure
    r.disputeId  = prior[0].Id;
    r.caseNumber = prior[0].CaseNumber;
    r.nextStep   = 'Dispute ' + prior[0].CaseNumber + ' is already open.';
    return r;
}
```

Note that the duplicate case reports **success**. It is: the customer's
intent is satisfied.

### When you cannot make it idempotent

Some actions genuinely cannot be. Then you must declare the retry policy:

| Error class | Retryable | Why |
| --- | --- | --- |
| Timeout, 5xx | Yes, 1–2 attempts with backoff | Transient |
| `DUPLICATE_CASE` | **No** | The system is saying it already succeeded |
| Validation error | **No** | Retrying identical input fails identically |
| Permission error | **No** | Retrying will never succeed |

Retrying a duplicate is how one call became three in the cost exercise in
Phase 12.

---

## 4. Security: `with sharing` and least privilege

```apex
public with sharing class ActionOrchestrator {
```

`with sharing` means the action runs in the caller's context and inherits
their visibility. This is what stops the agent reading an order the user
cannot see — the single most valuable line in the whole class.

### Least privilege in the permission set

```xml
<PermissionSet>
    <objectPermissions>
        <object>Order</object>
        <allowRead>true</allowRead>
        <allowCreate>false</allowCreate>
        <allowEdit>false</allowEdit>
        <allowDelete>false</allowDelete>
    </objectPermissions>
    <objectPermissions>
        <object>Case</object>
        <allowRead>true</allowRead>
        <allowCreate>true</allowCreate>
        <allowEdit>false</allowEdit>
        <allowDelete>false</allowDelete>
    </objectPermissions>
</PermissionSet>
```

The agent can do exactly two things. Every additional permission is a
decision you should be able to justify out loud.

---

## 5. Parameter mapping

Mapping is the wiring between the conversation, the action parameters, and
the result. It is the most common source of *"the agent knew but could not
do it"*.

| Symptom | Likely cause |
| --- | --- |
| "I don't have access to that" | Parameter not mapped, or value not resolvable |
| "I need an order number" | Parameter exists but is not described to the model |
| Action called with the wrong record | Ambiguous parameter, no disambiguation |
| "I did it but it did not save" | Write succeeded, `nextStep` did not confirm it |

### Rules that keep mapping sane

1. **Name outputs after what they mean**, not what they are: `summary`, not
   `string1`.
2. **Always return a "what next" field** — `nextStep`, `needsHuman`.
3. **Describe every parameter.** The model reads descriptions, not your
   intentions.
4. **Return the human-quotable identifier**, not just the Id. The model
   will read a raw Id out loud to a customer.
5. **Prefer one action that does one thing.** An action that can do five
   things will be called for the wrong one.

---

## 6. Orchestration: the sequence of an action

```text
1. Intent      what the user wants
2. Parameters  extract and validate
3. Guard       is this action permitted for this user, right now?
4. Execute     the deterministic work
5. Interpret   what does the result mean for the next step?
6. Respond     using the returned text, not generated text
7. Audit       record it
```

Step 6 is the one that is skipped. If the agent generates the confirmation
sentence rather than using `nextStep`, it will state a timeframe nobody
authorised. Phase 12 shows a session where exactly this happened.

Step 7 is what makes the session reconstructable. If `Agent_Action_Audit__c`
is not written, the action effectively did not happen as far as debugging
is concerned.

---

## 7. Testing actions

```apex
@IsTest
private class ActionOrchestratorTest {

    @TestSetup
    static void makeData() {
        insert new Account(Name = 'Acme');
    }

    @IsTest
    static void blankReasonReturnsNeedsHuman() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        ActionOrchestrator.Result r =
            ActionOrchestrator.openDispute(a.Id, '');

        System.assertEquals(false, r.success);
        System.assertEquals(true, r.needsHuman,
            'A blank reason must escalate rather than retry');
    }

    @IsTest
    static void validDisputeCreatesCase() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        ActionOrchestrator.Result r =
            ActionOrchestrator.openDispute(a.Id, 'Charged twice for one order');

        System.assertEquals(true, r.success);
        System.assertNotEquals(null, r.caseNumber);
        System.assertEquals(1, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void secondCallDoesNotDuplicateCase() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        ActionOrchestrator.openDispute(a.Id, 'Charged twice for one order');
        ActionOrchestrator.Result second =
            ActionOrchestrator.openDispute(a.Id, 'Charged twice for one order');

        System.assertEquals(true, second.success, 'Duplicate is a success');
        System.assertEquals(1, [SELECT COUNT() FROM Case],
            'Idempotency: exactly one Case');
    }
}
```

The third test is the one that catches the retry bug. It is the test most
often missing.

---

## Check yourself

1. **An action throws a validation exception. What is the likely
   consequence in an agent session?**
   The model gets an opaque failure, cannot branch, and retries — so one
   bad call becomes several, and if the action writes, several records.

2. **Why is `nextStep` a returned field rather than something the agent
   writes?**
   Because a generated confirmation can state a timeframe or an outcome
   nobody authorised. Reading a returned value means the commitment was
   already checked by the code that made it.

3. **Your `issueRefund` action is not idempotent. What do you do?**
   Declare the retry policy: retry timeouts and 5xx, never retry
   `DUPLICATE_CASE`, validation or permission errors. If you can make it
   idempotent, do that instead — check for an existing refund first.

4. **What does `with sharing` actually prevent here?**
   The agent reading or writing an order belonging to a different customer.
   It runs in the caller's context, so the caller's visibility is the
   boundary — enforced by the platform, not by the prompt.

5. **The agent says "I have opened your dispute" but no Case exists. What
   is missing?**
   Either the action was never called and the agent narrated it, or the
   `nextStep` text was generated rather than returned, or the audit record
   was not written. Check `Agent_Action_Audit__c` — which is the reason it
   exists.

---

## Key takeaways

- The output schema matters more than the input schema. `nextStep` and
  `needsHuman` are what make the action safe to call from an agent.
- Return failures, never throw them. An exception is an invitation to
  retry.
- `with sharing` plus a least-privilege permission set is the enforcement
  layer for data access.
- Agents retry. Either be idempotent or declare exactly which errors are
  retryable.
- Return human-quotable identifiers. The model will read an Id out loud.
- Write the audit record, or the session is unreconstructable.
