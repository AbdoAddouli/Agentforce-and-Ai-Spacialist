# Model and Channel Governance

Choosing a model, onboarding a third-party one, and designing for the
constraints of a voice channel. Smaller in scope than Phase 13, but it
overlaps the same exam domain and the voice material is part of the Summer
'26 maintenance focus.

---

## 1. Model choice is a design decision

Model choice is not a quality ranking. It is a trade between capability,
cost, latency, and how much data you are willing to send.

| Situation | Reasonable choice | Why |
| --- | --- | --- |
| Grounded extraction from records | A smaller, cheaper model | The work is bounded; the data does the work |
| Multi-step reasoning across many conflicting sources | A larger model | Planning quality is the bottleneck |
| Regulated and must be reproducible | Scripted steps plus a small model for language | Remove variance from the risk-bearing path |
| Third-party model already approved by the business | BYO-LLM, with the same policies configured | Reuse the approval; do not skip the controls |

### The argument you will be offered, and why it is wrong

> "Let's use the largest model for everything, to be safe."

Three problems, in order of cost:

1. **Cost and latency** are paid on every job, including the 90% that were
   never hard.
2. **More data reaches the model** than a smaller, narrower job requires,
   which widens the exposure surface.
3. **It is not actually safer.** Safety comes from the enforced layer —
   permissions, policies, action contracts — not from model size.

The correct approach is to choose per job and **record the decision**,
including the reasoning. A model decision with no record cannot be
reviewed two years later.

---

## 2. Recording the decision

```text
Model_Endpoint_Config__c
  Endpoint_Name__c        Text
  Provider__c             Picklist (Salesforce, Partner, BYO)
  Model_Version__c        Text
  Residency__c            Text
  Zero_Retention__c       Checkbox
  Masking_Policy__c       Text
  Approved_By__c          Text
  Approved_On__c          Date
  Max_Tokens_Per_Call__c  Number
```

Every field answers a question someone will ask later:

| Field | Question it pre-answers |
| --- | --- |
| `Provider__c` | Is this ours or a third party's |
| `Model_Version__c` | What exactly was in use during the incident |
| `Residency__c` | Where was this processed |
| `Zero_Retention__c` | Was it stored |
| `Masking_Policy__c` | What was redacted |
| `Approved_By__c` / `On__c` | Who decided, and when |
| `Max_Tokens_Per_Call__c` | What bounds one call's cost |

Without `Model_Version__c`, a question about a session three months ago is
unanswerable. Models change; the record must too.

---

## 3. Onboarding a third-party endpoint

The order matters. Each step catches a class of problem the next cannot.

```text
1. Data classification   What may go to this endpoint, at all?
2. Residency             Where does it process?
3. Retention             Does it store anything? Can it be instructed not to?
4. Trust-layer policies  Masking and zero retention configured FOR THIS endpoint
5. Credentials           Named credentials, never in code or prompt
6. Approval              Named owner, dated record
7. Limits                Max tokens per call, rate limits
8. Test                  One call, verified, before any use
```

### Step 4 is the one that gets skipped

**Trust-layer policies are not inherited.** Masking configured for a
Salesforce endpoint does not automatically apply to a partner endpoint. If
you onboard a BYO model and do not explicitly configure masking and zero
retention for it, you have a live gap that nobody notices until an audit.

### What makes a third-party endpoint your risk

| Property | Why it matters |
| --- | --- |
| Operator | Who you are trusting, and with what recourse |
| Hosting | Where the data physically goes |
| Retention | Whether you can delete it |
| Training use | Whether your data becomes their training data |
| Change control | Whether the model changes under you |
| Logging | Whether they log prompts, and can you see it |

An endpoint is part of your data path. Its properties become your
properties.

---

## 4. Voice changes the design

A voice agent is not a chat agent with a different output format. It has
different constraints.

| Constraint | Consequence for design |
| --- | --- |
| No visual output | A written bullet list is a poor voice experience |
| Turn-taking | The agent must yield and detect silence |
| Interruption | It will be interrupted; it must recover |
| No highlighting | Identifiers must be confirmed back verbally |
| Less patience | Long answers lose the caller |
| Higher cost | Audio processing is metered differently |

### Design consequences

```text
VOICE
- Answers are spoken, so keep them to one or two short sentences.
- Confirm back any identifier before acting on it: "order 006B2, is that right?"
- Detect silence after a pause and offer to repeat or transfer.
- If interrupted, stop, acknowledge, and ask what they still need.
- Never read out a raw record id, URL or reference number without saying it slowly.
- Say numbers as words and currency with units: "forty two pounds", not "£42.00".
```

That last pair is not a detail. `£42.00` read as a character sequence is
the single most common voice-agent failure, and it is entirely avoidable
by returning a spoken form from the action rather than generating one.

### Returning spoken text

```apex
@AuraEnabled public String spokenNextStep;   // "forty two pounds"
@AuraEnabled public String displayNextStep;  // "£42.00"
```

The same reasoning as `nextStep` in Phase 3, extended: the agent *reads*
the spoken form instead of trying to pronounce a currency string.

---

## 5. Human handoff

### Escalation triggers

| Trigger | Condition | Why |
| --- | --- | --- |
| Amount over limit | Refund > £500 | Material, needs a person |
| Policy silent | No published article covers the case | Must not improvise policy |
| Data absent | Order not found after a retry | Absence is not a negative answer |
| Safety hit | Injection or cross-account attempt | Do not continue |
| Customer asks | "Let me speak to someone" | Explicit request |
| Repeated failure | Two failed actions on one intent | The agent is stuck |
| Low confidence | Router below threshold twice | It genuinely does not know |

The first is a hard number rather than a judgement, because a judgement
about a threshold changes depending on who reads it.

### The payload

```json
{
  "reason_code": "AMOUNT_OVER_LIMIT",
  "trigger_detail": "Requested £742.00, limit £500.00",
  "customer": { "account_id": "001A1", "name": "Ada Okafor" },
  "transcript": [ { "role": "customer", "text": "..." } ],
  "records": [
    { "object": "Order", "id": "006B2", "fields": { "TotalAmount": 742.00 } }
  ],
  "actions_attempted": [
    { "action": "getOrder", "outcome": "SUCCESS" },
    { "action": "openDispute", "outcome": "SKIPPED", "reason": "over limit" }
  ],
  "open_questions": ["Is this a first-time request for this order?"]
}
```

`actions_attempted` is the field teams omit, and it is the reason handoff
feels slow: without it the human re-asks what the customer already
answered.

### What the agent must not do after handoff

```text
- Not continue the case, including "just checking" follow-ups.
- Not promise an outcome.
- Not open a second dispute.
- Answer only factual, non-case questions.
```

### Testing the payload, not the handoff

```apex
@IsTest
static void overLimitHandoffIsComplete() {
    TestHandoffPayload p = HandoffService.build('ORDER_006B2', 742.00);
    System.assertEquals('AMOUNT_OVER_LIMIT', p.reasonCode);
    System.assert(p.actionsAttempted.size() > 0, 'must record attempts');
    System.assert(p.records.size() > 0, 'must carry retrieved records');
    System.assertNotEquals(null, p.customer.accountId);
}
```

Assert **completeness**, not that the handoff happened. Completeness is
what silently degrades when someone adds a field.

---

## 6. Measuring channels separately

| Metric | Chat | Voice |
| --- | --- | --- |
| Success rate | Task completed | Task completed |
| Turns to resolution | Low is good | Not meaningful — turns are not the unit |
| Duration | Seconds | Minutes |
| Interruption rate | n/a | High means the agent talks too long |
| Abandon rate | n/a | The voice-specific failure |
| Escalation rate | Meaningful | Meaningful |

Combining them produces a number that describes neither. Voice has a much
higher abandonment rate and a much higher cost per interaction, and
averaging hides both.

---

## Check yourself

1. **Which job most justifies a large model?**
   Multi-step reasoning across many conflicting sources. Everything else on
   the list is bounded work where the data, not the model, does the
   thinking.

2. **You onboard a partner model endpoint. What is the most commonly
   missed step?**
   Configuring the trust-layer masking and zero-retention policies *for
   that endpoint*. They are not inherited from a Salesforce endpoint, so
   skipping this leaves a live gap.

3. **Why does a voice agent need a `spokenNextStep` field?**
   Because a currency string read as characters is unintelligible, and
   because an agent that has to generate the spoken form will sometimes get
   it wrong. Returning it means the code that knows the value produced the
   pronunciation.

4. **A voice agent's interruption rate is high. What does that tell you?**
   Its answers are too long. Interruption is a length signal, and shortening
   the answers addresses both interruption and abandonment.

5. **Why must handoff payloads record `actions_attempted`?**
   Without it the human re-asks what the customer already answered, which
   is the main reason handoff feels slow and is the main complaint about
   agent handoff.

---

## Key takeaways

- Choose the model per job and record the decision, including the version.
- Trust-layer policies are not inherited by third-party endpoints.
  Configure them explicitly.
- Voice has different constraints: length, turn-taking, interruption, and
  spoken form.
- Return spoken text from actions; do not let the model generate it.
- Approve on worst-case impact and reversibility.
- Handoff payload completeness is the thing that degrades silently, so
  test for it.
- Measure channels separately.
