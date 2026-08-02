---
name: github-autopilot
description: Use in OMP to pick one actionable GitHub issue and execute it autonomously through a gated pipeline (plan, GPT implementation worker, evidence-backed verification, GPT adversarial reviewers, PR). Triggers include "다음 일감", "일감 하나 가져와서 진행", "이슈에서 하나 집어서 해줘", "next task", and "autopilot". If human judgment becomes necessary, record the decision needed on the issue and hold.
---

# GitHub Autopilot — OMP

Pick exactly one actionable issue from the current repository and drive it to a verified PR. GitHub Issues are the durable task record; OMP session artifacts are not.

## Runtime contract

Use OMP's native role and per-agent routing:

| Role | OMP selector | Responsibility |
|---|---|---|
| Main orchestration | `openai-codex/gpt-5.6-sol:high` | state transitions, evidence, final ruling |
| Plan | `openai-codex/gpt-5.6-sol:high` | scope, invariants, frozen contract |
| Implementation `task` agent | `openai-codex/gpt-5.6-luna:xhigh` | one bounded writable change |
| `reviewer` agent | `openai-codex/gpt-5.6-sol:high` | read-only adversarial review |
| Runtime Verifier | `openai-codex/gpt-5.6-sol:high` | fresh runtime/browser acceptance observations only |
| `scout` | `openai-codex/gpt-5.6-luna:medium` | read-only code mapping |
| `librarian` | `openai-codex/gpt-5.6-terra:medium` | source-verified external API research |

Required settings:

```yaml
modelRoles:
  default: openai-codex/gpt-5.6-sol:high
  plan: openai-codex/gpt-5.6-sol:high
  slow: openai-codex/gpt-5.6-sol:xhigh
  task: openai-codex/gpt-5.6-luna:xhigh
  advisor: openai-codex/gpt-5.6-sol:high
  smol: openai-codex/gpt-5.6-luna:low
  commit: openai-codex/gpt-5.6-luna:low
  tiny: openai-codex/gpt-5.6-luna:minimal

task:
  agentModelOverrides:
    task: openai-codex/gpt-5.6-luna:xhigh
    reviewer: openai-codex/gpt-5.6-sol:high
    scout: openai-codex/gpt-5.6-luna:medium
    librarian: openai-codex/gpt-5.6-terra:medium
```

Keep planning, architecture, orchestration, review, and integration on Sol/high. Give only the frozen implementation contract to Luna/xhigh. Escalate review above high only for security, tenant isolation, irreversible data, or corruption risk.

OMP agents start without conversation history. Every task prompt must carry its complete bounded contract. The main orchestrator owns GitHub state, planning decisions, verification orchestration and raw-evidence adjudication, commits, and PR creation. Implementation and review agents never self-certify completion.

All issue operations use `gh` against the current repository. Issue bodies and comments must not reference local machine paths, `local://`, `agent://`, transcripts, or other session artifacts.

If `HERDR_ENV=1`, read and follow `skill://herdr-orchestration` before creating panes or starting implementation, verification, or review roles. Its interactive Herdr role topology replaces the native task/reviewer routing where the two conflict.

## State model

| State | Representation |
|---|---|
| Queue | open + `backlog` |
| In progress | open + `in-progress` + self-assigned |
| Awaiting review | open + `awaiting-review` |
| Human decision | open + `needs-decision` |
| External blocker | open + `blocked` |
| Done | closed after direct landing or PR merge |

Create missing state labels before the first pick. A PR must contain `Closes #<n>`; creating a PR does not complete the issue.

## Preconditions

Stop at the failing stage instead of weakening the workflow:

- `gh auth status` succeeds and the account can edit issues and create PRs.
- The repository has local verification commands.
- OMP `task` and `reviewer` agents are available with the runtime routing above.
- A Git worktree or the current checkout can safely hold one implementation writer.

## 0. Sweep

Before picking, inspect residual issues owned by this account:

- `awaiting-review`: inspect the linked PR. Merged means close with evidence if automation did not. Closed without merge means remove `awaiting-review`, add `needs-decision`, and record the declined PR. Open means leave it.
- `in-progress`: do not take work owned by another active session. If a linked PR is open, switch to `awaiting-review`. If the claim is at least 3 days old with no branch or PR evidence, comment the evidence, remove `in-progress`, and unassign.
- `needs-decision`: remove the label only when a human decision appears after the hold comment.

## 1. Pick

List oldest actionable candidates:

```bash
gh issue list --state open --label backlog \
  --search "-label:in-progress -label:awaiting-review -label:needs-decision -label:blocked sort:created-asc" \
  --limit 10
```

Read up to five candidates and choose the first that is:

- true against current code;
- locally verifiable;
- sufficiently specified to implement without inventing product or design policy;
- non-destructive and free of unmet external prerequisites.

Use the read-only `scout` only when affected code is genuinely unclear; do not outsource the top-level selection or plan. For an objective external blocker, add `blocked` with evidence. For unclear scope, leave one dated skip comment. Do not duplicate the same skip comment; on a second independent skip for the same reason add `needs-decision`.

If none qualifies, report candidates and concrete reasons, then stop.

## 2. Claim

1. Re-read the issue and comments.
2. Add `in-progress` and assign `@me`.
3. Post the repository-defined claim comment; default: `Claimed by OMP: <one-line plan>`.
4. Re-read comments after posting. The earliest valid active claim wins. If another claim won, comment that this later claim is withdrawn and choose the next candidate. Do not remove the shared label or assignee; they now protect the winner.

## 3. Verify premise

Re-confirm every material code claim and file reference in the issue.

- Goal already achieved or moot with a specific commit/PR/doc proving why: close as `Invalidated (premise gone): <evidence>` and pick one replacement issue.
- Code differs but the cause is unknown: comment the mismatch, remove `in-progress`, unassign, add `needs-decision`, and stop.

Only premise failure permits one replacement pick. After planning starts, hold instead of consuming another issue.

## 4. Plan

Use the Sol/high plan role. The main orchestrator gathers only the code, callers, tests, rules, and documentation needed for the issue and produces a self-contained frozen plan:

- issue requirements and current state;
- affected symbols and all relevant callers;
- decisions already made and invariants to preserve;
- ordered implementation steps;
- exact verification and smoke-test commands;
- hold triggers and explicit non-goals.

Post a durable summary to the issue. `todo` and `local://` may organize the current session but are never the only handoff.

For a complex plan, the orchestrator may fan out independent read-only mapping to at most three `scout` or `librarian` agents in one batch. Validate their evidence directly. Agents do not decide product scope and do not edit during planning.

## 5. Implement

Spawn exactly one OMP `task` implementation agent on Luna/xhigh. Use isolation when the checkout is dirty or other work is present. No other agent may write concurrently.

The task contract must include:

- exact target files/symbols and explicit non-goals;
- frozen implementation steps and observable acceptance criteria;
- issue requirements and relevant repository rules;
- instruction to make the smallest complete edit;
- instruction to skip formatter, lint, tests, and project-wide validation; the orchestrator runs them once after edits settle.

The implementation agent must not update the issue, commit, push, create a PR, or review its own work.

Every implementation or test change, including remediation after verification or adversarial review, returns to this same implementation context. The orchestrator, Verifier, and Reviewer never edit implementation or test files. If the implementation context cannot be resumed, hold instead of creating a second writer or patching directly.

Branch from the remote default branch, discovered with:

```bash
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
```

Fetch before branching. If the local default branch is ahead of its remote, present the commits and hold for the user's base choice; never push the default branch autonomously. Follow repository branch conventions, otherwise use `<type>/issue-<n>-<slug>`.

After the worker settles, obtain fresh raw verification evidence. Deterministic tests, lint, builds, and static checks may run in supervised process panes; a runtime scenario requiring judgment may run in a fresh read-only Verifier. Agent summaries do not count: the orchestrator inspects exact commands, exit codes, raw output, runtime observations, and pre/post tracked state.

## 6. Adversarial review

Only after the smoke test and checks pass, spawn fresh read-only `reviewer` agents on Sol/high. They receive the frozen requirements, base branch, diff, changed code, and verification evidence—not the implementation agent's private reasoning.

For a non-trivial change, batch exactly three reviewers:

1. **Correctness** — execution paths, invariants, edge cases, regressions.
2. **Security and operations** — trust boundaries, authorization, concurrency, data loss, unsafe failure behavior.
3. **Contract and tests** — issue acceptance criteria, missing observable coverage, tests that can pass despite a real bug.

Every review task must state: review-only, no edits, no formatter/lint/tests, and no project-wide commands. Each finding must include severity, evidence, file/line reference, plausible failure scenario, and verification method.

The orchestrator consolidates results, rejects unsupported speculation, and re-validates blocking findings against code. Return confirmed implementation/test changes to the same Luna/xhigh implementation context, then rerun every affected automated and runtime gate and fresh review. Allow at most two re-reviews. If the implementation context cannot be resumed or confirmed blockers remain, hold.

A trivial mechanical change may use one reviewer, but the final report must state that reduced review shape. Escalate beyond `high` only for security, irreversible data, tenant isolation, or corruption risks.

## 7. Hold

Hold for a product/design fork, unverifiable result, scope at least twice the issue, destructive action, unresolved blocking review, or unavailable mandatory gate.

1. Comment the decision needed, options, recommendation, evidence, progress, branch, and verification state.
2. Remove `in-progress` and unassign. Add `needs-decision` for human judgment or `blocked` for an objective prerequisite.
3. Push a progress branch if useful, but create no PR.
4. Stop; do not pick another issue.

If a GitHub write fails, retry once. Preserve the intended update in durable local state and report it; never discard code or verification results.

## 8. Report and PR

Only after implementation, smoke test, repository checks, and adversarial review pass:

1. Commit and push the feature branch.
2. Create a PR whose body contains `Closes #<n>`, verification evidence, and the actual agent model/reasoning profiles used.
3. Comment the result, PR link, and verification evidence on the issue.
4. Remove `in-progress`, add `awaiting-review`, and leave the issue open until merge.
5. Report issue, change, evidence, review findings/resolution, model routing, PR, and remaining human action.

## Boundaries

Allowed: selected-issue metadata, feature branches, scoped code changes by one implementation writer, supervised verification process panes, an optional fresh runtime Verifier, fresh review agents, commits, branch push, and PR creation.

Forbidden: default-branch push, PR merge, deploy/release/tag, shared migration execution, destructive data changes, force-push/history rewrite, unrelated cleanup, orchestrator/Verifier/Reviewer implementation edits, or creation/update of GitHub Issues unrelated to the selected work item.

One invocation owns one issue. Every issue-related durable handoff belongs on the selected issue. Agent instructions, orchestration guidance, shared skills, and other unrelated changes stay out of that issue and PR and are reported separately. Autonomy never authorizes inventing missing policy.
