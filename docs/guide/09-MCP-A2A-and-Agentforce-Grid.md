# MCP, A2A and the Agentforce Grid

Multi-agent orchestration is 5% of the exam — the smallest weight, and the
one most likely to be answered correctly by process of elimination. The
concepts are also the ones that distinguish an integrator from a
configurator.

---

## 1. Choosing between them

| Need | Use | Why |
| --- | --- | --- |
| Reach a tool or system Agentforce does not have | **MCP server** | One tool contract, standard discovery, no custom glue |
| Delegate a whole case to another agent | **A2A** | Task-level delegation with an agreed result contract |
| Several specialists work one case together | **Agentforce Grid** | Coordinated work on shared context, no handoff chain |

**MCP is about tools, A2A is about tasks, the grid is about
collaboration.**

Choosing wrongly usually means building custom integration code for
something one of these already solves — and then owning that code forever.

---

## 2. MCP: the tool contract

```json
{
  "name": "get_shipment",
  "description": "Retrieve shipment status and ETA for a single order. Requires the order id. Returns carrier, status and a delivery estimate the carrier has published. Does not return tracking events older than 30 days.",
  "inputSchema": {
    "type": "object",
    "required": ["order_id"],
    "properties": {
      "order_id":  { "type": "string", "description": "18-char Salesforce Order Id" },
      "include_events": { "type": "boolean", "default": false }
    }
  }
}
```

### Three things that make this contract usable

**The description says when *not* to call it.** "Does not return tracking
events older than 30 days" is not decoration — descriptions are the model's
only documentation, and a tool whose limits are undocumented gets called
for the wrong thing.

**Defaults are declared.** `include_events` defaults to false so the
common case stays cheap. An unconditional large payload is the usual cause
of an unexpectedly expensive integration.

**`required` is accurate.** Marking everything optional means the model
invents values for parameters that must come from a record.

---

## 3. MCP reliability rules

| Rule | Failure it prevents |
| --- | --- |
| Wrap every call in a timeout | A hung tool stalls the turn indefinitely |
| Treat a timeout as "not known", never "no" | A false negative gets acted on |
| Cap retries at 1–2, with backoff | Retry storms against a struggling system |
| Never blindly retry a non-idempotent write | Duplicate side effects |
| Return structured errors, not prose | The model cannot branch on a sentence |
| Log call, arguments, duration, outcome | A tool failure with no log is undebuggable |

The second row is the one teams get wrong. A timeout is **missing
information**. Treating it as a negative answer means the agent acts on an
absence of data as if it were data — and tells a customer their order
shipped when nobody checked.

### Structured errors

```json
{
  "ok": false,
  "error": {
    "code": "UPSTREAM_TIMEOUT",
    "message": "Carrier API did not respond within 10s",
    "retryable": true
  }
}
```

Not: `"We couldn't reach the carrier right now, please try again later."`
The model cannot branch on a sentence. It can branch on `retryable`.

---

## 4. A2A: delegating a task

```json
{
  "skill": "refund_eligibility",
  "input":  { "order_id": "string", "reason": "string" },
  "output": { "status": "APPROVED|DECLINED|UNCERTAIN", "amount": "decimal|null", "rule": "string" },
  "error":  { "code": "ORDER_NOT_FOUND|POLICY_UNAVAILABLE", "retryable": "boolean" }
}
```

The two fields that matter are `UNCERTAIN` and `retryable`.

Delegating agents are **independent**. Without `UNCERTAIN`, the caller
cannot distinguish "no" from "I could not find out", and it will
confidently tell a customer their refund was declined when the delegate
simply timed out. This is the single most important field in an A2A
contract.

### When to delegate versus when to chain

| Situation | Use |
| --- | --- |
| One clear task, a specialist owns it | A2A delegation |
| Several specialists on one case, shared context | The grid |
| Subagent inside one agent | A subagent, not A2A |
| Chained delegation, A routes to B routes to C | **Avoid** — cycles, unbounded latency, unclear traces |

Delegation is one hop. If you find yourself designing a chain, the shape
is wrong.

---

## 5. The Agentforce Grid

The coordinated-agent grid: specialised agents work one case **together**
on shared context, rather than handing off in a chain.

| | Handoff chain | Grid |
| --- | --- | --- |
| Context | Passed, and degraded at each hop | Shared and current |
| Work | Sequential, one owner at a time | Parallel where independent |
| Trace | Hard to follow | Per specialist, on one case |
| Failure | Retry the whole chain | Retry the failed specialist |
| Duplicated work | Common | Avoided by shared context |

For a case that genuinely needs three specialists — billing, orders and a
human approver — the chain re-summarises the case three times and loses
detail each time. The grid keeps one shared case context, so the third
specialist sees what the first two actually found.

This is one of the named Summer '26 maintenance focus areas, so expect a
question distinguishing it from a handoff chain.

---

## 6. Observing the interop path

```text
Session
 ├─ Agentforce_Agent__c
 ├─ Agentforce_Action__c        get_shipment (MCP)
 ├─ ExternalToolCall__c         status=ERROR, code=UPSTREAM_TIMEOUT
 └─ Agentforce_Action__c        fallback: read Order.Ship_Status__c
```

One session shows the call, the failure, and the fallback. Without it, an
agent that "sometimes knows the shipping status" is unfixable, because
there is no evidence of what happened.

### What to log per call

| Field | Why |
| --- | --- |
| Tool or skill name | Which integration |
| Arguments (masked) | Reproducibility |
| Duration | Latency budget |
| Outcome | Success / error code |
| Retry count | Whether retry policy is working |
| Credits consumed | Cost attribution per integration |

Credits per integration is the one that answers "why did the bill go up
after we added that tool".

---

## 7. Security considerations

| Concern | Control |
| --- | --- |
| External endpoint data handling | Trust-layer policies configured for it |
| Credential storage | Named credentials, never in the prompt or code |
| Over-broad tool access | One tool per capability, narrow parameters |
| Untrusted tool output | Treat as data; delimit and validate |
| Data residency | Confirm the provider's region |

Two of these catch teams out. A bring-your-own-model or third-party MCP
server extends your perimeter: its operator, hosting and retention become
your risk. And tool *output* is untrusted input — a compromised or
careless tool returning instruction-like text is an injection vector.

---

## Check yourself

1. **You need to check parcel status from a carrier that has no Salesforce
   integration. MCP, A2A or the grid?**
   MCP. You need a tool, not a task delegation or a collaborating agent.

2. **A user's order is not found by a delegated subagent. What is the
   correct result, and what is the failure mode of getting it wrong?**
   `UNCERTAIN` (or an error with `retryable: false`). Returning `DECLINED`
   makes the caller tell the customer the refund was refused, when the
   real situation is that the order was never found.

3. **Why is a handoff chain worse than a grid for a three-specialist case?**
   Context is passed and degrades at each hop, work is duplicated, and a
   single failure retries the whole chain. The grid shares case context,
   so each specialist sees the current state and only the failed part is
   retried.

4. **A tool call times out. What must the agent do, and what must it not
   do?**
   Report unknown and fall back or escalate. It must not treat the timeout
   as a negative answer, and must not retry more than once or twice.

5. **You enabled a third-party model endpoint for one subagent. What
   besides latency and cost do you need to review?**
   Data classes allowed to that endpoint, residency, retention, who
   operates it, and whether the trust-layer masking and zero-retention
   policies are configured for it.

---

## Key takeaways

- MCP for tools, A2A for task delegation, the grid for collaboration.
- Describe when *not* to call a tool, and declare defaults.
- A timeout is "not known", never "no". Structured errors, not prose.
- `UNCERTAIN` and `retryable` are the fields that make delegation safe.
- Avoid chains. One hop, or the grid.
- Trace every interop call with duration, outcome and credits — without
  it, integration problems are unfixable.
