# Exam Preparation and Case Studies

How the questions are built, how to read them, and how to convert a bad
score into a revision plan that targets the right domain.

---

## 1. The exam facts

| Fact | Value |
| --- | --- |
| Exam | Agentforce Specialist (`AI-201`) |
| Questions | 60 scored, plus up to 5 unscored |
| Time | 105 minutes |
| Pass mark | 72% |
| Prerequisite | None |
| Format | Single-best-answer multiple choice |
| Registration | USD 200 |
| Retake | USD 100 |

### Your pace

105 minutes over 60 questions is **1 minute 45 seconds each**.

If you are averaging over two minutes, you are over-reading — almost
always re-reading four options before committing. If you are under a
minute, you are pattern-matching rather than reasoning.

---

## 2. Domain weights

| Domain | Weight | Questions (approx) |
| --- | --- | --- |
| AI Agents | 35% | 21 |
| Prompt Engineering | 20% | 12 |
| Data 360 Fundamentals | 20% | 12 |
| Testing / Deployment / Maintenance | 10% | 6 |
| Governance / Observability | 10% | 6 |
| Multi-Agent Orchestration | 5% | 3 |

**Revise by expected value, not by comfort.** If you are strongest in
Multi-Agent Orchestration, that is 3 questions. If you are weakest in
Prompt Engineering, that is 12. Time follows the weights.

---

## 3. The five question shapes

| Shape | Looks like | Approach |
| --- | --- | --- |
| **Definition** | "Which term means this?" | Know the current name |
| **Scenario** | "Given this situation, what should you do?" | Identify domain and priority |
| **Best practice** | "Which approach is correct?" | Know the enforced-layer distinction |
| **Terminology trap** | A legacy name offered beside a current one | Pick the current name |
| **Trade-off** | Two defensible options | One is better for the *stated* reason |

The trade-off shape is where the most points are lost, because both
options sound right and the discriminator is in the scenario text, not the
options.

---

## 4. The four classic traps

### Trap 1 — Legacy terminology

> "Which component selects the appropriate topic for a request?"
> Options include **Topic**, **Topic Selector**, **Agent Router**, ...

The current terms are subagents and Agent Router. Legacy names are never
the answer.

| Legacy | Current |
| --- | --- |
| Topic | Subagent |
| Topic Selector | Agent Router |
| Connected Agent | Connected Subagent |
| Data Cloud | Data 360 |
| Agentforce 3 | Agentforce 360 |
| Agent Builder | Agent Builder (unchanged) |

### Trap 2 — Request offered where a control belongs

> "The agent must never state a refund amount not in a record."
> - Add a constraint to the instructions
> - Enforce it in the action so only record values are returned
> - Both, labelled as request and control

The enforced control is the better answer. The instruction is worth adding
too, but it is not the control. This trap appears in several forms; the
pattern is always *request versus enforced*.

### Trap 3 — Right in general, wrong for the stated reason

> Scenario: "The agent must reduce cost without reducing accuracy."
> Option: "Use a larger model."
> Option: "Narrow the grounding scope."

Both can be right in general. The stated reason includes "without reducing
accuracy", and narrowing scope is the change that reduces cost while
*improving* accuracy. Read the stated reason, not the general principle.

### Trap 4 — Over-broad option that "works"

> "Which change makes the agent compliant?"
> - "Give the agent read access to all Orders so it always has context"

It works, and it fails the governance requirement. Over-broad options
usually make the control technically present and the risk unacceptable.

---

## 5. Working a case study

```text
1. Read the scenario fully before reading the options.
2. Identify the domain: architecture, prompt, data, testing, governance
   or orchestration.
3. Ask what the scenario is telling you to prioritise: cost, accuracy,
   safety, speed or reversibility.
4. Eliminate three options before reading the fourth carefully.
5. Check the last option for subtle over-reach.
6. If two survive, re-read for the constraint that separates them.
```

### Two heuristics that help

**Absolute wording.** An option saying "always" or "never" is usually
over-broad — check whether the scenario justifies it. "Always escalate" is
wrong; "always escalate refunds over £500" is right.

**Scope mismatch.** If two options both sound right, the difference is
scope, and one is broader than the job requires. The narrower one is
usually correct.

---

## 6. Worked example

> **Scenario:** A retail agent supports three areas: order status, returns,
> and product questions. It is missing constraints roughly once in twenty
> conversations. The business wants the number of specialists increased.
>
> - A. Add a fourth subagent for product questions
> - B. Increase the iteration bound to 12
> - C. Split the three areas into separate subagents, each with its own
>      actions and constraints
> - D. Add the missing constraints to the main instruction set

**Answer: C.**

Reasoning:

1. **Domain:** AI Agents — architecture and instruction design.
2. **Stated priority:** reduce missed constraints, *and* the business
   wants more specialists.
3. Missed constraints "once in twenty" is a dilution symptom, not a
   missing-content symptom. The instruction set has outgrown reliable
   following.
4. A is the business's proposed solution, not a diagnosis — a fourth
   subagent does not reduce dilution across the other three.
5. B increases the blast radius of a wrong turn and raises cost.
6. D addresses one instance of the symptom. The constraints that are
   currently followed may be the ones that break next month.
7. C fixes the cause and satisfies the business.

The option that is a *diagnosis* rather than a *symptom treatment* is the
answer, and C is the only one.

---

## 7. Building your evaluation set

Do not revise by re-reading. Build a set and measure.

```text
1. Assemble 60 questions across the six domains, using the weights.
2. Time yourself: 105 minutes, no notes, no pausing.
3. Mark every question you were unsure about.
4. For each, write the RULE you would test — not the option letter.
5. Re-do only the unsure questions after a break.
6. Write your three weakest domains and the phase numbers to re-read.
```

Step 4 is the whole exercise. "The answer was B" is useless six weeks
later. "I do not know that a timeout means *not known* rather than *no*" is
transferable to questions you have never seen.

---

## 8. Turning a score into a plan

Suppose you score 60% and overran by 13 minutes:

| Domain | Weight | Missed | Points lost |
| --- | --- | --- | --- |
| AI Agents | 35% | 4 | 3.5 |
| Prompt Engineering | 20% | 6 | 6.0 |
| Data 360 | 20% | 1 | 1.0 |
| Testing & Deployment | 10% | 2 | 2.0 |
| Governance | 10% | 2 | 2.0 |
| Orchestration | 5% | 1 | 0.5 |
| | | | **15.0** |

Two conclusions fall out of this table immediately:

**Prompt Engineering cost 40% of everything lost, from 20% of the
paper.** It is the single worst return on revision time — which means it
deserves the most hours.

**The time overrun was also in Prompt Engineering**: 1m49s per question
against 1m11s elsewhere. Slow *and* wrong on the same questions means the
*format* was unfamiliar, not just the content. That is a different fix.

### The revision plan that follows

| Priority | Target | Time |
| --- | --- | --- |
| 1 | Prompt, Agent Script | 3h |
| 2 | Instructions, architecture | 2h |
| 3 | Governance controls | 1.5h |
| 4 | Data 360, grounding | 2h |
| 5 | Full glossary, no filter | 45m |

Sorted by points lost per hour, not by syllabus order.

---

## 9. The pacing fix

```text
Read the scenario -> form the answer -> read the options ONCE.
If two survive, re-read for the stated constraint, not for reassurance.
Flag anything uncertain and move on.
```

The failure mode is re-reading four options trying to feel confident. With
60 questions there is no time for it, and feeling confident is not
evidence.

---

## 10. The day before

Review rules, not implementation details.

```text
[ ] The six domain weights
[ ] Every rename: topics, Topic Selector, connected agent, Data Cloud,
    Agent Builder, Agentforce 3
[ ] The exam facts: 60 questions, 105 minutes, 72%, no prerequisite
[ ] The maintenance release and its deadline
[ ] The five governance controls and which layer enforces each
[ ] The four observability questions and which tool answers each
[ ] The three grounding failure modes and their opposite fixes
[ ] The two termination paths: vagueness asks, ambiguity escalates
[ ] The full glossary, unfiltered
```

Not on this list, and not a good use of the evening: Apex trigger syntax,
permission set XML, the scratch org duration, or specific class names.

---

## Check yourself

1. **How long per question, and what does overrunning tell you?**
   1 minute 45 seconds. Overrunning means you are re-reading options before
   committing, which costs time and changes nothing.
2. **A question offers both "Topic" and "Subagent". Which do you pick?**
   Subagent. Current terminology is always the answer, and legacy names
   are a reliable distractor.
3. **Two options both look correct. What do you do?**
   Re-read the scenario for the constraint that separates them. The
   difference is almost always scope, and the narrower one is usually
   right.
4. **You scored 60% and Prompt Engineering cost 6 of your 15 lost points.
   What is the first thing to do?**
   Revise Prompt Engineering first — 40% of the loss from 20% of the
   paper is the best return on revision time. Then fix the pacing, which
   was also concentrated in that domain.
5. **Why write the rule rather than the answer when reviewing?**
   Because the answer does not transfer and the rule does. "The answer was
   B" helps for no future question. "A timeout means *not known*, not
   *no*" helps for every question about missing data.

---

## Key takeaways

- 60 questions, 105 minutes, 1m45s each, 72% to pass.
- Revise by expected value: Prompt Engineering is 20% of the paper and
  usually the biggest source of lost points.
- Four traps: legacy terminology, request versus control, right-in-general
  wrong-for-this-reason, and over-broad options.
- Read the scenario fully, identify the domain and the stated priority,
  then read the options once.
- Review with rules, not answers.
