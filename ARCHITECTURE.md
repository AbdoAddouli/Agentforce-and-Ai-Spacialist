# Architecture

How the reference org is put together, and why. Written from the
implementation, then checked against it. If a section here disagrees with
`force-app`, the code is right and this document is wrong.

---

## 1. The layers

```text
                 +------------------------------+
                 |   Agent_Definition__c        |  instructions, subagents,
                 |   Action_Definition__c       |  declared capabilities
                 +---------------+--------------+
                                 |
                 +---------------v--------------+
                 |   AgentLifecycleService      |  entry point and invariants
                 |   Agent_DefinitionTrigger    |  thin, no logic
                 +---------------+--------------+
                                 |
        +-------------+----------+----------+------------+
        v             v          v          v            v
  SubagentPlanner  Grounding  AgentScript ActionOrch.  TokenUsage
   + AgentRouter   Service    Service     (+ Handler)   Service
        |             |          |          |            |
        +-------------+----------+----------+------------+
                                 |
              +------------------+------------------+
              |                  |                  |
   Agent_Interaction_Log__c  Agent_Action_Audit__c  Agent_Session_Trace__c
                                                     Flex_Credit_Ledger__c
                                                     Token_Usage__c
```

| Layer | Contains | Responsibility |
| --- | --- | --- |
| Data | 12 custom objects, 1 platform event | Configuration, evidence, cost |
| Logic | 12 service classes, 1 trigger | Behaviour, all of it testable |
| Automation | 6 flows | Routing fallback, budget, approval, notice, normalisation |
| Governance | Permission set, approval process, 2 assignment rules | Least privilege, human sign-off, triage routing |
| Insight | 5 reports, 1 dashboard | What escaped, what it cost, what failed |
| Tests | 12 test classes | One per service, plus structure tests |

---

## 2. Three decisions, and the reasoning

### Thin triggers

`Agent_DefinitionTrigger` is five lines. It calls
`AgentLifecycleService.validate` and exits.

Everything else — activation, retirement, versioning, step bounds — lives in
the service layer, where it is reachable from a unit test without DML.
A trigger that embeds logic can only be exercised by inserting a record, so
its bugs are only findable in production.

### The audit objects are the product

Four objects exist so that any session can be reconstructed: what was asked
(`Agent_Interaction_Log__c`), what was retrieved and in what order
(`Agent_Session_Trace__c`), what was called (`Agent_Action_Audit__c`), and
what it cost (`Flex_Credit_Ledger__c`, `Token_Usage__c`).

The agent is the easy part. Without these, an agent that "sometimes" behaves
badly is unfixable, because there is no evidence to reason about — only
anecdotes.

### A sanctioned failure path everywhere

Every service returns a value that says what to do next, including "I do not
know":

| Method | Decline signal |
| --- | --- |
| `SubagentPlanner.route` | `needsHuman = true`, `subagentName = null`, reason `BELOW_THRESHOLD` or `AMBIGUOUS_TIE` |
| `GroundingService.retrieve` | `recordsRetrieved = 0`, `missReason` set |
| `GroundingService.requireContext` | throws `GroundingMissException` |
| `ActionOrchestrator.executeStep` | `errorCode` of `APPROVAL_REQUIRED`, `ACTION_INACTIVE`, `UNKNOWN_ACTION`, `NO_HANDLER_REGISTERED`, `ACTION_THREW` |
| `AgentScriptService.run` | `terminationReason` of `CLARIFICATION_REQUIRED`, `STEP_BUDGET_EXHAUSTED`, `PLAN_EXHAUSTED_WITHOUT_END` |
| `AgentRouter.handleTurn` | `outcome` of `Escalated` / `Refused`, never throws |
| `Data360ModelSelector.select` | throws `NoApprovedEndpointException` |

A system with no sanctioned way to fail will fail unrecoverably.

---

## 3. The data model

### Configuration

| Object | Records | Notes |
| --- | --- | --- |
| `Agent_Definition__c` | One per agent | `Status__c` and `Version__c`; instructions changes bump the version and return the record to `In Review` |
| `Action_Definition__c` | One per capability | `Requires_Approval__c` is the approval gate; `Handler__c` names the implementation |
| `Grounding_Source__c` | One per retrieval target | Scope is fixed here and never widened at runtime |
| `Model_Endpoint_Config__c` | One per approved model | `Approved_By__c` and `Approved_On__c` are eligibility requirements, not documentation |

### Evidence

| Object | Grain | Written by |
| --- | --- | --- |
| `Agent_Interaction_Log__c` | One per turn | `AuditService.logInteraction` |
| `Agent_Session_Trace__c` | One per step | `AuditService.writeTrace` |
| `Agent_Action_Audit__c` | One per action attempt | `ActionOrchestrator`, including failures |
| `Flex_Credit_Ledger__c` | One per step, by cost center | `AuditService.recordCredits` |
| `Token_Usage__c` | One per session | `AuditService.recordTokens` |
| `Prompt_Template_Usage__c` | One per template use | `PromptTemplateService.logUsage` |
| `Agent_Test_Run__c` | One per evaluation case | `TestHarnessService` |

---

## 4. Failure paths

```text
Grounding miss      -> 0 records, missReason set, reason recorded.
                       requireContext() throws. Scope is NOT widened.
Routing below 0.60  -> needsHuman, no subagent, "BELOW_THRESHOLD".
Routing tie         -> needsHuman, no subagent, "AMBIGUOUS_TIE".
Vague request       -> "CLARIFICATION_REQUIRED", turn ends early.
No 'end' in plan    -> "PLAN_EXHAUSTED_WITHOUT_END" plus a fallback answer.
Budget exhausted    -> "STEP_BUDGET_EXHAUSTED", no answer is presented.
Approval required   -> "APPROVAL_REQUIRED", handler never runs, audit written.
Handler throws      -> "ACTION_THREW", audit written with the parameters.
Bad SOQL object     -> caught at build time by check-project.mjs, not at runtime.
```

`AgentRouter.handleTurn` catches everything and returns an `Escalated`
result. A failed session is still a logged session.

---

## 5. What deployment does and does not prove

| Claim | Proved by |
| --- | --- |
| Metadata is valid | Deploy report |
| Services compile | Apex test run |
| The agent runs | A real session completes |
| The agent is grounded | `Agent_Session_Trace__c` shows retrievals |
| The agent can act | `Agent_Action_Audit__c` has the action and parameters |
| The agent is observable | Log, trace, audit and ledger rows exist |
| The agent is affordable | `Flex_Credit_Ledger__c` totals the expected cost |

The last four are verified by **records**. A successful deploy with silent
observability objects means the agent did not run.

### What this repository has actually verified

```text
[done] 17 modules, 17 exercises, 17 guides, 17 model answers
[done] check-curriculum.mjs: 0 errors, 0 warnings
[done] check-project.mjs: 0 errors across 6 checks
[done] 45 XML files well-formed (structural check)
[done] 20 Node tests pass
[done] manifest regenerated from disk: 68 members, 11 types
[NOT done] Apex compilation        - requires an org
[NOT done] Apex test execution     - requires an org
[NOT done] Metadata API validation - requires sf project deploy validate
```

That list is the honest state. The metadata is structurally sound and
internally consistent; it has not been compiled by Salesforce.

---

## 6. Design rules encoded in the code

| Rule | Where it lives |
| --- | --- |
| Validate before activate: instructions, reviewer, review date, grounding, positive step bound | `AgentLifecycleService.validate` |
| Prompt changes are versioned and re-reviewed | `versionIfInstructionsChanged` |
| An undeclared action never runs | `ActionOrchestrator.lookupDefinition` |
| An approval-gated action never runs unapproved | `ActionOrchestrator.executeStep` |
| Every action attempt is audited, success or failure | `ActionOrchestrator.writeAudit` |
| A grounding miss is never fixed by widening scope | `GroundingService.retrieve` |
| Retrieval is bounded by `Max_Records__c` | `GroundingService.retrieve` |
| Routing is allowed to decline | `SubagentPlanner.route` |
| The step loop is hard-bounded | `AgentScriptService.run` |
| Observability never breaks the run it observes | every `catch` in `AuditService` |
| Only approved, active endpoints are selectable | `Data360ModelSelector.matches` |
| Evaluation never asserts on grounding success | `TestHarnessService` |
| Domain weights total 100 | `TestHarnessService.domainWeights` |

---

## 7. Known limitations

These are real and unresolved.

- **`RetrievalRelevance` is lexical, not semantic.** Term overlap, not
  embeddings. A semantically similar but wrong record can outrank the
  correct one. Mitigated by `Max_Records__c` and the status filter; not
  solved.
- **The routing threshold of 0.60 is uncalibrated.** It was set by
  judgement, not fitted. With a term-overlap scorer the score distribution
  is lumpy, so 0.60 is a guess that happens to be defensible. This is the
  first thing to revisit with a labelled set.
- **The 0.60 threshold and the subagent names are hard-coded in
  `AgentRouter`.** `ROUTING_THRESHOLD` is configuration; the candidate list
  is not. A real implementation would read the subagent inventory from
  `Agent_Definition__c`.
- **No per-tool cost attribution.** `Flex_Credit_Ledger__c` is per step
  type, so a slow integration is invisible in the ledger. A session with
  three `act` steps looks the same whether each took 20ms or 20s.
  `Duration_Ms__c` holds the answer but nothing aggregates it.
- **Action handlers are registered in memory.** `ActionOrchestrator.HANDLERS`
  is populated at runtime and is not durable. There is no `Handler__c`
  dispatcher, so a deploy does not wire handlers to actions automatically.
- **`Agent_ScriptService.run` does not execute steps.** It models the loop,
  the bound and the termination, and costs each step, but the `locate` and
  `act` branches do not call `GroundingService` or `ActionOrchestrator`.
  Wiring them is the next increment.
- **No Platform Event publisher in Apex.** `Agent_Session_Escaped__e` is
  published only by the `Agent_Routing_Fallback` flow, so an escalation
  raised in Apex does not reach subscribers.
- **Reports have no date filters per column** and the time range is
  hard-coded to a 2026-01-01 start.
- **Nothing is deployed.** No org has compiled this. Treat the metadata as
  unverified until `sf project deploy validate` says otherwise.
