# Agentforce Fundamentals

Everything else in this roadmap is a detail on top of four questions: what is
an agent, when should you build one, what can it do, and how do you keep it
under control. If you can answer those four, the rest is detail.

---

## 1. What an agent actually is

An agent is a configured generative AI capability inside Salesforce that can
reason over a conversation, decide what to do, and take action.

Three components, and every exam question about agent design is really a
question about one of them:

| Component | What it is | Where it fails |
| --- | --- | --- |
| **Instructions** | Natural language that defines role, scope, process and constraints | Vague prose the model cannot follow or test |
| **Actions** | Typed operations the agent may invoke | Unmapped parameters; no failure signal |
| **Topics / Subagents** | Focused specialists handling part of the job | Overlapping scopes; routing loops |

An agent without actions is a chatbot. An agent without grounding is a
confident fiction. An agent without constraints is a liability.

---

## 2. Agent types, and when you need one

Salesforce ships several agent types. The distinction that matters on the
exam is **autonomy**.

| Type | Who configures it | Autonomy | Use when |
| --- | --- | --- | --- |
| **Agentforce 360 platform agent** | Admin / developer via metadata | Configurable | You own the design and the governance |
| **Agent Builder (Agent Builder)** | Admin in a guided UI | Configurable | Non-developers need to create and change agents |
| **Specialist agent (subject matter expert)** | Pre-built, Salesforce-maintained | Fixed | The domain is already covered well |
| **Agentforce Service Agent** | Configurable | Guardrailed | Support deflection with a controlled action set |
| **Einstein GPT / ask Agentforce** | Minimal, retrieval-only | Low | Users need answers over data, not actions |

### The decision rule

Ask whether the process needs **judgement over unstructured input**. If it
does not, build a flow.

| Situation | Build |
| --- | --- |
| Known steps, known order, no interpretation | Flow |
| Unstructured input, judgement needed, novel paths | Agent |
| One data question, no action | Retrieval-only agent |
| High value, high risk | Agent **with** human approval on the risky steps |

A flow is cheaper, faster, deterministic, and testable by asserting
outcomes. An agent is probabilistic, slower and more expensive. Reach for
the agent only when the decision genuinely requires interpretation — and
put the deterministic parts back into flows, where they belong.

---

## 3. The Agentforce 360 platform surface

You need the vocabulary, not the clicks.

| Term | Meaning |
| --- | --- |
| **Agentforce 360** | The current platform name (formerly Agentforce 3) |
| **Agent Builder** | The current builder name (formerly Agent Builder) |
| **Data 360** | The current data platform name (formerly Data Cloud) |
| **Subagent** | A focused specialist within an agent (formerly a topic) |
| **Agent Router** | Routes a request to the right subagent (formerly Topic Selector) |
| **Connected Subagent** | A subagent that hands off to an external agent (formerly Connected Agent) |
| **Agent Script** | A declarative, reviewable script blending deterministic steps with reasoning |
| **Agentforce Grid** | Coordinated specialists working one case on shared context |
| **Flex Credits** | The unit Agentforce consumption is metered in |

If a question offers a legacy name as the answer, the legacy name is the
wrong answer. See `What Changed` on this site for the full rename table.

---

## 4. Instructions: the four sections that matter

Every instruction set needs these, in this order.

| Section | Purpose | Failure if missing |
| --- | --- | --- |
| **Role** | Who the agent is and what domain it covers | Scope drift; the agent helps with everything |
| **Scope** | In scope / out of scope, explicitly | It improvises adjacent topics |
| **Process** | The ordered steps to follow | Inconsistent handling of the same request |
| **Constraints** | Hard limits — never do X, maximum N steps | The model chooses its own boundaries |
| **Tone** | Output style, briefly | Not fatal, but inconsistent |

The most common mistake is writing constraints as adjectives. "Be
accurate" is not a constraint. "Never state a refund amount that is not in
a retrieved record" is.

Phase 2 covers this properly.

---

## 5. Grounding: the input contract

An agent answers from three sources, and you control all three.

| Source | What it is | Risk if unmanaged |
| --- | --- | --- |
| **Instructions** | What you wrote | Too broad, the model fills gaps |
| **Grounding** | Records and knowledge you expose | Too wide, irrelevant records crowd out the right one |
| **Model knowledge** | The model's parametric memory | **Fabrication** — it will answer from here if you allow it |

The rule: instruct the agent to answer **only** from grounding, and give it
a sanctioned way to say it does not know. An agent that must always answer
will answer. An agent allowed to refuse will refuse correctly.

Phase 4 and 5 cover data and grounding in depth.

---

## 6. Actions: the boundary to the deterministic world

An action is a typed operation with an input schema and an output schema.
It is the only place an agent can change anything.

```text
Input   { orderId: Id, reason: String }
Output  { success: Boolean, caseNumber: String, nextStep: String, needsHuman: Boolean }
```

Three properties of a good action contract:

1. **Validate and return, do not throw.** The model needs a readable value.
   An exception surfaces as an opaque failure and invites a retry.
2. **Return `needsHuman`.** Give the caller an explicit escalate signal
   rather than making it infer one from a failure.
3. **Be idempotent, or declare that it is not.** Agents retry. An action
   that is neither will eventually duplicate something.

Phase 3 covers action design and orchestration.

---

## 7. The cost and safety baseline

| Control | What it does |
| --- | --- |
| **Flex Credits** | Meters consumption, so it can be budgeted and alerted on |
| **Iteration bound** | Caps reasoning steps per turn, preventing runaway cost |
| **Safety configuration** | What the agent may do without a human |
| **Data masking** | Removes sensitive fields before the model sees them |
| **Zero data retention** | Instructs the provider not to store what it receives |
| **Secure data retrieval** | Uses retrieved data without passing it as prompt text |

None of these are optional in production. The most commonly forgotten is
the iteration bound, and it is the one that turns a bad day into a large
invoice.

---

## 8. How the exam uses these ideas

| Domain | Weight | What it tests |
| --- | --- | --- |
| AI Agents | 35% | Lifecycle, instructions, actions, subagents, routing |
| Prompt Engineering | 20% | Instruction structure, grounding, iteration |
| Data 360 Fundamentals | 20% | Data model, grounding sources, relevance |
| Testing / Deployment / Maintenance | 10% | Test layers, packaging, observability |
| Governance / Observability | 10% | Trust layer, controls, analytics |
| Multi-Agent Orchestration | 5% | MCP, A2A, the grid |

The heaviest domain is agent design, and it is the one where the
foundational vocabulary above does the most work.

---

## Check yourself

1. **A process has five known steps in a fixed order with no interpretation
   anywhere. Agent or flow?**
   Flow. There is no judgement, so a flow is cheaper, faster and
   deterministic. Reach for an agent only when the decision needs
   interpretation.

2. **Your agent says "I was unable to find that in our knowledge base,
   but generally speaking…" What went wrong, and what fixes it?**
   The agent is answering from parametric memory because nothing stopped
   it. The instruction must say answer only from retrieved content, and
   there must be a defined refusal path.

3. **Name the current term for each legacy name.**
   Topics → subagents. Topic Selector → Agent Router. Connected Agent →
   Connected Subagent. Data Cloud → Data 360. Agent Builder → Agent
   Builder. Agentforce 3 → Agentforce 360.

4. **An action throws a validation exception. Why is this worse than
   returning `success: false`?**
   The model receives an opaque failure, has nothing to branch on, and
   will typically retry — turning one bad call into several. A returned
   result is a value the model can read and act on.

5. **Which control do teams most often forget, and what does it cost?**
   The per-turn iteration bound. Without it, a looping agent consumes
   credits until you notice.

---

## Key takeaways

- An agent is instructions plus actions plus grounding. Every design
  question maps to one of them.
- Build a flow unless the process genuinely needs judgement. A flow is
  strictly better when it fits.
- Grounding is an input contract. Bound it, and let the agent refuse.
- Every action needs a typed contract, a defined failure value, and an
  idempotency story.
- Legacy terminology is a trap. Current names are always the answer.
- Budget consumption with Flex Credits and an iteration bound, or you are
  choosing to be surprised.
