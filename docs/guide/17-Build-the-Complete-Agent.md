# Build the Complete Agent

The final phase assembles everything into one deployable project. This is
also the phase where the architecture becomes something you can explain
rather than something you copied.

---

## 1. What the project contains

| Layer | Contents |
| --- | --- |
| **Data** | Agent definition, action definition, grounding source, interaction log, action audit, prompt usage, token usage, session trace, flex credit ledger, test run, model endpoint config, training question |
| **Logic** | Thin triggers over a service layer: lifecycle, action orchestration, grounding, script, planner, subagents, token usage, audit, agent router |
| **Automation** | Flows for escalation, credit alert, grounding refresh, router fallback, approval request, session close |
| **Governance** | Permission set, approval process, assignment rules, email templates, platform event |
| **Insight** | Dashboard plus reports on agent performance, credit burn and grounding coverage |
| **Tests** | One test class per service class, plus data and negative-path coverage |

---

## 2. The architecture

```text
                 +-----------------------------+
                 |   Agentforce_Agent__c       |  instructions, subagents
                 |   Agentforce_Action__c      |  declared capabilities
                 +-------------+---------------+
                               |
                 +-------------v---------------+
                 |   AgentLifecycleService     |  entry point, single place
                 +-------------+---------------+
                               |
        +------------+------------+-----------+--------------+
        v            v            v           v              v
  SubagentPlanner  Grounding   AgentScript  ActionOrch.   TokenUsage
   (routing)      Service      Service      (writes)      Service
        |            |           |           |              |
        +------------+-----------+-----------+--------------+
                               |
                 +-------------v---------------+
                 |  Agent_Interaction_Log__c    |  every turn
                 |  Agent_Action_Audit__c       |  every action
                 |  Agent_Session_Trace__c      |  every step
                 |  Flex_Credit_Ledger__c       |  every credit
                 +-----------------------------+
```

---

## 3. The three decisions that matter

### Thin triggers over a service layer

```apex
trigger Agent_DefinitionTrigger on Agent_Definition__c (before insert, before update) {
    AgentLifecycleService.validate(Trigger.new);
}
```

Five lines. All the logic is in `AgentLifecycleService`, which is testable
without DML and without trigger context.

Every real bug in a trigger-heavy codebase is logic that could only be
reached by inserting a record. The service layer is what makes the
behaviour reachable from a unit test.

### The audit objects are the product

The agent is the easy part. The value of the project is that **any session
can be reconstructed afterwards**: what was asked, what was retrieved,
what was called, what it cost.

Without `Agent_Session_Trace__c`, an agent that "sometimes" behaves badly
is unfixable, because there is no evidence. That is the whole argument for
these four objects existing.

### A declared failure path everywhere

```apex
r.needsHuman = true;         // openDispute
r.subagent   = null;         // route() below threshold
// grounding miss -> no records returned
// executeStep() -> stepError()
```

An agent with no sanctioned way to fail will fail unrecoverably. Every
service method returns a value that says what to do next, including
"escalate" and "I do not know".

---

## 4. Deploy and verify

```bash
sf org create scratch -f config/project-scratch-def.json -a afs -d 7
sf project deploy start --source-dir force-app --target-org afs --wait 20
sf apex run test --target-org afs --test-level RunLocalTests --code-coverage --wait 30
sf project deploy report --target-org afs
sf org open --target-org afs
```

`--wait` matters. A synchronous deploy gives you a result you can act on.

---

## 5. What deployment proves, and what it does not

A successful deploy proves **the metadata is valid**. It does not prove the
agent works.

| Claim | Proved by |
| --- | --- |
| Metadata is valid | Deploy report shows success |
| The agent runs | A real session completes |
| The agent is grounded | The trace shows retrievals |
| The agent can act | `Agent_Action_Audit__c` has the action |
| The agent is observable | Trace, log and ledger records exist |
| The agent is affordable | `Flex_Credit_Ledger__c` shows expected cost |

The last four are verified by **records**, not by the deploy. If they are
silent, the agent did not run, whatever the deploy said.

### The end-to-end check

```text
1. Create an Agent_Definition__c, set Status = Active.
2. Run a real session through the agent.
3. Confirm Agent_Interaction_Log__c has the turn.
4. Confirm Agent_Action_Audit__c has the action and its parameters.
5. Confirm Agent_Session_Trace__c shows the steps in the expected order.
6. Confirm Flex_Credit_Ledger__c has the consumption.
```

---

## 6. Coverage

| Layer | Target | Why |
| --- | --- | --- |
| Service classes | 90%+ | This is where the logic lives |
| Triggers | 90%+ | Thin, but still must be exercised |
| Data policies | 100% of declared actions | An unexercised policy is a guess |
| Overall | 75%+ | A floor, not a goal |

The number matters less than the assertion:

```apex
System.assertEquals(true, ok, 'Delivered 1 March, claimed same day');
```

That documents a rule. A covered line with no assertion documents nothing,
and coverage percentage is a proxy for having tried, not for being correct.

---

## 7. Files worth reading first

| File | What it teaches |
| --- | --- |
| `AgentLifecycleService.cls` | The entry point and the shape of every service |
| `ActionOrchestrator.cls` | The action contract, including `needsHuman` |
| `GroundingService.cls` | Bounded retrieval and the miss path |
| `AgentScriptService.cls` | Hybrid deterministic/reasoning execution |
| `SubagentPlanner.cls` | Routing with a threshold and a decline path |
| `TokenUsageService.cls` | Per-step credit attribution |
| `Agent_DefinitionTrigger.trigger` | How thin a trigger should be |

Read them in that order. Together they are the architecture.

---

## 8. Writing ARCHITECTURE.md

Write it from your own understanding, then check it against the metadata.
Not the other way round.

It should contain:

```text
1. The layer diagram, and what each layer is responsible for
2. The three decisions above, with the reasoning
3. The data model: what each object records and why it exists
4. The failure paths: every service method and how it declines
5. What the deployment does not prove, and how you verify it
6. Known limitations, stated honestly
```

### Point 6 is the one that proves the rest

A document with no limitations section reads as marketing. The useful
statement is specific:

```text
KNOWN LIMITATIONS
- Grounding relevance is lexical; a semantically similar but wrong article
  can outrank the correct one. Mitigated by maxRecords and the status
  filter, not solved.
- The router threshold of 0.60 was tuned on 40 utterances. It is not
  calibrated, and it is the first thing to revisit.
- Session trace credit figures are per step, but there is no per-tool
  attribution, so a slow integration is not yet visible in the ledger.
```

Naming three real limitations is what makes the other five sections
credible.

---

## 9. Anti-patterns in the assembled project

| Anti-pattern | Consequence |
| --- | --- |
| Logic in triggers | Untestable without DML; bugs only findable in production |
| Service methods returning void | The caller cannot know what happened |
| No `needsHuman` on any action | Escalation is inferred from failures |
| Audit objects optional | Sessions become unreconstructable |
| Coverage without assertions | A number, not evidence |
| Architecture doc written from the metadata | Describes the code, not the design |
| A guide with no limitations | Marketing, not engineering |

---

## Check yourself

1. **The deploy succeeded. What do you do next to prove the agent
   works?**
   Activate it, run a real session, then confirm the interaction, action,
   trace and credit records were written. The deploy proved validity, not
   behaviour.

2. **Why are the triggers thin?**
   So all business logic lives in service classes that can be unit tested
   without DML or trigger context. Bugs in trigger-embedded logic are only
   findable by inserting a record.

3. **Coverage is 80% overall. Is that acceptable?**
   It is a floor. The real question is whether the assertions are
   meaningful. 80% with `System.assertEquals(true, ok, 'a rule')` in the
   service classes beats 95% of empty tests.

4. **What is the most important property of the audit objects?**
   That any session can be reconstructed afterwards — asked, retrieved,
   called, cost. Without it, an intermittently misbehaving agent is
   unfixable, because there is no evidence to reason about.

5. **Why write ARCHITECTURE.md before checking it against the metadata?**
   Writing from the metadata produces a description of the code. Writing
   from your understanding and then checking produces a design document
   with the reasoning exposed, and it finds the places where you had the
   code wrong.

---

## Key takeaways

- Thin triggers, all logic in testable services.
- The audit objects are the product, not an afterthought.
- Every service method returns something, including "I do not know".
- Deployment proves validity; records prove behaviour.
- Coverage is a proxy for trying. Assertions are the evidence.
- An architecture document with a limitations section is worth more than
  one without.
