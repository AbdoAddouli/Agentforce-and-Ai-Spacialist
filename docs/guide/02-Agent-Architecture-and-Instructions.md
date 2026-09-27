# Agent Architecture and Instructions

The agent lifecycle, instruction design, and how to decide what belongs in
one agent versus several. This phase carries the heaviest exam weight of any
single topic in the blueprint, because everything else is a variation on it.

---

## 1. The agent lifecycle

Five stages. Each has a distinct failure mode, and knowing which stage is
broken tells you where to look.

| Stage | What happens | Failure mode |
| --- | --- | --- |
| **Define** | Scope, role, success criteria | Vague scope, no definition of done |
| **Design** | Instructions, actions, grounding, subagents | Everything bolted onto one agent |
| **Build** | Configure in Agent Builder, wire actions | Action parameters not mapped |
| **Test** | Behavioural, safety, regression | Only happy paths tested |
| **Deploy & Monitor** | Promote, observe, iterate | No observability, no rollback path |

Two stages are skipped most often, and they are **Define** and **Monitor**.

Skipping Define is why agents have vague scope. Skipping Monitor is why a
regression is discovered by a customer rather than an alert.

---

## 2. Decide the shape before you write a word

The single highest-leverage decision: one agent, or several?

### Split into subagents when

| Signal | Why it matters |
| --- | --- |
| **Different** answers require different expertise | One instruction set cannot serve both well |
| Combined instructions exceed reliable following length | Quality degrades before you notice |
| Specialisms have **different risk levels** | You want to govern them separately |
| Each specialism has its own action set | Least privilege per specialism |
| Each specialism is owned by a different team | Independent release cadence |

### Keep it as one agent when

- The subagents would need the same grounding anyway.
- Routing decisions are ambiguous often enough to frustrate users.
- The total instruction set still fits comfortably.
- The specialisms are not independently testable.

Routing is not free. It adds a turn, costs credits, and can send a
confident question to the wrong specialist — which is worse than a
mediocre answer from the main agent. Split only on a real signal.

---

## 3. The instruction set, properly written

### The five sections

```text
ROLE
One or two sentences. Who the agent is and what domain it covers.

SCOPE
In scope: explicit list.
Out of scope: explicit list. This section is the one most often omitted
and it is the one that prevents scope drift.

GROUNDING
What the agent may answer from, and what to do when the answer is not
in the retrieved content. Never leave this implied.

PROCESS
The ordered steps. Numbered. Include what to do on ambiguity.

CONSTRAINTS
Hard limits. Each one testable.

TONE
One or two lines. Not a paragraph.
```

### A worked example

```text
ROLE
You are Acme Billing Support. You answer questions about a single
authenticated customer's orders, invoices and eligible refunds.

SCOPE
In scope: order status, invoices, refund eligibility and next steps.
Out of scope: discounts, tax advice, product recommendations, and any
other customer's account.

GROUNDING
Answer only from the retrieved Acme knowledge articles and the customer's
own account records. If the retrieved content does not answer the
question, say so and offer escalation. Do not answer from general
knowledge.

PROCESS
1. Identify the order or invoice the question is about. If it is not
   clear which, ask one clarifying question before looking anything up.
2. Retrieve, then answer in one short paragraph.
3. State the next step, with a timeframe only if a retrieved source
   states one.

CONSTRAINTS
- Never state a refund amount that is not in a retrieved record.
- Never predict an outcome. Report the policy and let the customer decide.
- Never discuss an account other than the authenticated one.
- Maximum 6 reasoning steps. If the task is not resolved, escalate.

TONE
Plain, factual, short sentences. No exclamation marks. No apology filler.
```

### Why each section earns its place

| Section | What breaks without it |
| --- | --- |
| ROLE | Identity drifts on long conversations |
| SCOPE | Adjacent requests get improvised answers |
| GROUNDING | Confident fabrication from model knowledge |
| PROCESS | Inconsistent handling; no defined ambiguity path |
| CONSTRAINTS | The model picks its own boundaries |
| TONE | Cosmetic, but it compounds over a long session |

---

## 4. Writing constraints that work

The distinction the exam cares about most: **a request versus a control**.

| Written as | It is | Enforceable? |
| --- | --- | --- |
| "Never state an amount not in a record" | Request | No — and add an action contract that makes it structural |
| "Be accurate" | Wish | No |
| "Be concise" | Wish | No |
| "Maximum 6 reasoning steps, then escalate" | Request with a number | Partially — enforce it in the runtime too |
| "Only return amounts present in the retrieved order" | Action schema | **Yes** |
| "Customer A's orders are not visible to this user" | Permission set | **Yes** |

Write the constraint anyway — it shapes behaviour and it is cheap. But
never claim it is a security control, and never stop there.

### A test for every constraint

Ask: *what input makes this fail?* If you cannot write that input, it is a
wish. If you can, it is a constraint, and it is a test case.

---

## 5. The two termination paths

An agent must always have both of these defined. An agent without them will
invent a resolution.

| Situation | Correct behaviour | Wrong behaviour |
| --- | --- | --- |
| **Vagueness** — the request is unclear | Ask exactly one clarifying question, then proceed | Retrieve for all interpretations and answer all of them |
| **Ambiguity** — the data is missing or contradictory | Escalate with what you tried and what is missing | Pick the most likely interpretation and answer confidently |

The distinction is real and it is examined. Vagueness is fixable with a
question. Ambiguity is not fixable by asking, because the information does
not exist yet — escalating gets a human who can supply it.

---

## 6. Structured, reviewable instructions

Instructions that only exist inside a UI field cannot be code-reviewed,
diffed, or rolled back. Keep them as metadata in the repository.

```text
Agentforce_Agent__c
  Name              Acme Billing Support
  Instructions__c   <the text above, version controlled>
  Status__c         Draft | In Review | Active | Retired
  Version__c        7
  Owner__c          Platform team
  Reviewed_By__c    <user>
  Reviewed_On__c    <date>
```

This gives you three things a browser edit does not:

1. **Review** — a pull request shows exactly what changed in the prompt.
2. **History** — when behaviour regressed, you can diff v6 against v7.
3. **Rollback** — `git revert` and redeploy. A browser edit has no rollback.

The `Status__c` lifecycle is what stops an unreviewed prompt reaching
production.

---

## 7. Anti-patterns

| Anti-pattern | What goes wrong | Instead |
| --- | --- | --- |
| One agent for everything | Context dilutes; nothing follows reliably | Split on a real signal |
| Constraints as adjectives | Not testable, not enforceable | Specific, falsifiable statements |
| No grounding instruction | Fabrication | "Answer only from retrieved content" |
| No refusal path | Guessing is the only option available | Define escalate explicitly |
| Hardcoding subagent lists | Drifts from reality | Read the published list at runtime |
| Instructions only in the UI | No review, no rollback | Metadata in the repository |
| Adjectives in `ROLE` | Not actionable | Plain domain statement |

---

## Check yourself

1. **A team has one agent handling billing, technical support and account
   management. It misses constraints occasionally. What is the most likely
   cause, and what is the fix?**
   Constraint dilution — the instruction set has grown past the point
   where the model follows it reliably. Fix: split into subagents on the
   three domains, each with its own action set and constraints, and route
   between them.

2. **A user asks "my order is late and I was charged twice". What should
   the agent do?**
   Ambiguity, not vagueness: the request is clear, the data is not. Do not
   route it to either subagent. Keep it in the main agent, or escalate
   with both facts collected.

3. **Write a constraint and the input that breaks it.**
   "Never state a refund amount that is not in a retrieved record" breaks
   when the retrieved order has no recorded amount and the user says
   "I was told it was fifty pounds". That input is your test case.

4. **Why keep instructions in metadata rather than the Agent Builder UI?**
   Code review, version history, and rollback. Also testability: the
   instruction text is an input you can assert on.

5. **An agent handles one job perfectly. Is it under-designed?**
   No. If one agent covers the job within reliable instruction limits, one
   agent is the correct design. Adding subagents to look sophisticated
   adds cost, latency and a routing failure mode for no benefit.

---

## Key takeaways

- Decide the shape first: one agent or several. Split on real signals, not
  on tidiness.
- Five sections, always: role, scope, grounding, process, constraints.
- A constraint is a falsifiable statement, not an adjective. If you cannot
  write the input that breaks it, it is a wish.
- Requests shape behaviour; controls enforce it. Write both, and never
  claim the request is the control.
- Vagueness gets one clarifying question. Ambiguity gets an escalation.
- Instructions belong in version control.
