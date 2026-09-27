# Routing and Subagents

Subagents — formerly topics — are the focused specialists within an agent.
Agent Router, formerly Topic Selector, decides which one handles a request.
This phase is about when to split, what a subagent must return, and why
routing failures are usually design failures.

---

## 1. Terminology, because the exam tests it

| Legacy | Current |
| --- | --- |
| Topic | Subagent |
| Topic Selector | Agent Router |
| Connected Agent | Connected Subagent |
| Agentforce 3 | Agentforce 360 |

If an option offers a legacy name, the legacy name is wrong. This costs
candidates several marks and is free to avoid — see `What Changed` on this
site for the full table.

---

## 2. When to split, and when not to

### Split on a real signal

| Signal | Why it matters |
| --- | --- |
| **Different** answers require different expertise | One instruction set cannot serve both |
| Combined instructions exceed reliable following length | Quality degrades before you notice |
| Specialisms have **different risk levels** | You want to govern them separately |
| Each specialism has its own action set | Least privilege per specialism |
| Different owners and release cadences | Independent testing and deployment |

### Do not split for these reasons

| Non-signal | Why it is not enough |
| --- | --- |
| The domain "feels big" | Size is not the criterion; differentiation is |
| Tidiness | Routing costs credits and adds a failure mode |
| Subagents sound sophisticated | A wrong specialist is worse than the main agent |
| Most requests are short | Short requests are the easy case anyway |

Routing is not free. It adds a turn, costs credits, increases latency, and
can send a confident question to the wrong specialist. Split only when a
real signal is present.

---

## 3. What a subagent must return

A subagent returns a **closed, enumerable result**, never prose.

```text
OUTPUT
Return exactly one of:
  APPROVED  — with an amount taken from the order record
  DECLINED  — with the rule that was applied
  UNCERTAIN — with what is missing
```

| Property | Why |
| --- | --- |
| Closed set | The caller can branch without parsing English |
| `UNCERTAIN` is first-class | Forcing a binary answer produces confident wrongness |
| No questions | A subagent has no channel to ask the user |
| Step bound present | Bounds cost and latency |
| Values come from records | The model never invents a number |

The `UNCERTAIN` outcome is the one most often missing, and it is the one
that matters. With only `YES` and `NO`, an unresolvable ambiguity must be
forced into one of them, and the model will pick the one that lets it
continue. That is how "your refund was declined" gets said when the real
situation was "I could not find your order".

---

## 4. The stopping rule

```text
STOP when one of these is true:
- You have returned APPROVED, DECLINED or UNCERTAIN.
- You have made 4 reasoning steps.
- You have made the same tool call twice with the same arguments.

You must not:
- Ask the customer a question. You have no channel to ask on.
- Call another subagent. If you need information, return UNCERTAIN.
```

The step bound exists because a subagent has no user to answer its
questions. Without it, an unresolvable ambiguity becomes a loop and the
caller waits.

The repeated-call guard is cheap and specific: a deterministic parameter
produces an identical result, so the second call bought nothing.

"No subagent calls" prevents chains. Phase 9 covers why chains are
trouble.

---

## 5. The router

```apex
public with sharing class AgentRouter {
    public class Route {
        @AuraEnabled public String subagent;   // null = main agent
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String reason;
    }

    private static final Set<String> SPECIALISTS = new Set<String>{
        'Billing', 'Orders', 'Technical', 'Account'
    };

    @AuraEnabled(cacheable=true)
    public static Route route(String userMessage, List<String> available) {
        Route r = new Route();
        r.subagent = null;
        r.confidence = 0;

        for (String s : available) {
            if (!SPECIALISTS.contains(s)) {
                continue;                       // never route to something not published
            }
            Decimal score = SubagentPlanner.score(userMessage, s);
            if (score > r.confidence) {
                r.confidence = score;
                r.subagent = s;
                r.reason = 'Best match for "' + s + '" at ' + score;
            }
        }

        if (r.confidence < 0.60) {              // below threshold: main agent
            r.subagent = null;
            r.reason = 'No specialist above threshold; main agent handles it';
        }
        return r;
    }
}
```

### The rules that make routing trustworthy

| Rule | Failure it prevents |
| --- | --- |
| Route only to published, active subagents | Routing to a retired agent |
| Read `available` at runtime | A hardcoded list drifting from reality |
| Below threshold, stay in the main agent | Forcing a bad specialist match |
| One hop, never a chain | Cycles and unbounded latency |
| Return a confidence, and log it | Opaque routing you cannot debug |
| Specialist gets the original message | Rewriting loses the user's actual words |

The one-hop rule matters more than it looks. Chained routing is how a
request ping-pongs until a step bound stops it — and the trace then shows
a loop rather than a failure.

---

## 6. Ambiguity is a routing outcome

```text
0.9  "where is my refund"            -> Orders
0.9  "the invoice is wrong"          -> Billing
0.85 "it will not connect to Wi-Fi"   -> Technical
0.2  "thanks, that helped"           -> none, main agent
0.2  "what are your opening hours"   -> none, main agent
0.55 "my order is late and I was
      charged twice"                -> below threshold
```

That last case is the interesting one. Two intents, no clear winner.
Routing it to either specialist produces a worse answer than the main
agent attempting it, and the confidence score says so.

**Ambiguity is a routing outcome, not a routing failure.** A router that
can decline is trustworthy. A router that always routes is not.

---

## 7. Measuring the router

Build 30–50 labelled utterances:

| Category | Count | Why |
| --- | --- | --- |
| Per specialist | 5 each | Phrased as customers actually phrase them |
| Must **not** route | 5 | Greetings, thanks, out-of-scope |
| Ambiguous | 5 | Correct answer is the main agent |
| Adversarial | 5 | Resembles a specialist that is not one |

Then measure two numbers, not one:

| Metric | Why separately |
| --- | --- |
| **Routing accuracy** | Did it pick the right specialist? |
| **Confident-but-wrong rate** | A wrong specialist is worse than no specialist |

A router can be 95% accurate on routing and still be a net negative if the
5% of misroutes produce confidently wrong answers. The second metric is
the one that tells you whether the router is actually helping.

---

## 8. Anti-patterns

| Anti-pattern | Consequence |
| --- | --- |
| Router that always routes | Forced bad matches on greetings and out-of-scope |
| Hardcoded specialist list | Routes to retired agents |
| Subagent that asks questions | Deadlock; it has no channel to the user |
| Only YES / NO returns | Ambiguity forced into a wrong answer |
| Chained subagent calls | Loops, unbounded latency, unclear traces |
| Rewriting the user message before routing | Loses the actual intent |
| Overlapping subagent scopes | Same request matches three specialists |
| No step bound in the subagent | Cost and latency you cannot cap |

---

## Check yourself

1. **A team has one agent for billing, technical support and account
   management, and constraints are missed occasionally. What is the cause
   and the fix?**
   Constraint dilution: the instruction set has outgrown reliable
   following. Fix by splitting into three subagents, each with its own
   action set, constraints and step bound, and route between them.

2. **A subagent must decide refund eligibility. Why does its return type
   need `UNCERTAIN`?**
   Because a subagent cannot ask a question or resolve missing data. With
   only a binary result it must pick one, and it will pick the one that
   lets it continue — producing a confident wrong answer.

3. **Your agent routes "my order is late and I was charged twice" to the
   Billing subagent with 0.7 confidence. What is wrong?**
   Two intents and no clear winner. The correct outcome is below threshold
   — the main agent, or an escalation with both facts collected. A 0.7
   confidence that is wrong in the way this one is wrong produces a
   confidently incorrect answer.

4. **Why must the subagent list be read at runtime rather than hardcoded?**
   Because a hardcoded list drifts from what is actually published, and
   the router will eventually route to a retired specialist. Read the
   active list and filter on status.

5. **Give one reason the router might be 95% accurate and still harmful.**
   The 5% of misroutes produce confidently wrong answers rather than
   graceful failures. Measure the confident-but-wrong rate separately from
   routing accuracy.

---

## Key takeaways

- Split only on a real signal: different expertise, different risk,
  different actions, different owners.
- A subagent returns a closed enum, including `UNCERTAIN`. Never prose.
- A subagent has no channel to the user, so it needs a step bound and a
  no-questioning rule.
- Below threshold, the main agent handles it. Ambiguity is a routing
  outcome.
- One hop, never a chain.
- Measure routing accuracy and confident-but-wrong rate separately.
