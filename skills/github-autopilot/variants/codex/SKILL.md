---
name: github-autopilot
description: Use in Codex to pick one actionable GitHub issue and execute it autonomously through a gated pipeline (plan, implementation, evidence-backed verification, adversarial review, PR). Triggers include "다음 일감", "일감 하나 가져와서 진행", "이슈에서 하나 집어서 해줘", "next task", and "autopilot". If human judgment becomes necessary, record the decision needed on the issue and hold.
---

# GitHub Autopilot — Codex

Pick exactly one actionable issue from the current repository and drive it to a verified PR. GitHub Issues are the durable task record; local session context is disposable.

## Runtime contract

Codex Responses Multi-agent gives the root and every descendant the same request model and tools. Do not claim that one hosted tree used different models or reasoning efforts.

Preferred phase-isolated profiles, when the controller can create separate top-level Responses calls:

| Phase | Model | Reasoning | Shape |
|---|---|---|---|
| Plan and orchestration | `gpt-5.6-sol` | `high` | root; at most 3 bounded research/critique agents |
| Implementation | `gpt-5.6-luna` | `xhigh` | separate top-level worker; one mutable worktree |
| Adversarial review and integration | `gpt-5.6-sol` | `high` | separate read-only root with 3 focused reviewers; root integrates |

A normal Codex invocation cannot change descendants to those per-role profiles. In that case use `gpt-5.6-sol` with `high` reasoning for the entire tree. Preserve role separation with fresh bounded subagent contexts; never misreport this fallback as Luna/xhigh implementation.

Use Multi-agent only for independent bounded work. Plan → implementation → review is an ordered pipeline and must remain sequential. Never let concurrent agents edit the same worktree.

All issue operations use `gh` against the current repository. Issue bodies and comments must not reference local machine paths or session artifacts.

Herdr is optional. Codex-native orchestration or separate top-level Responses calls remain the default when they preserve the phase isolation and single-writer boundary above. Use Herdr only when the user or repository explicitly requests it, or when persistent coordination across independent interactive agent processes, lifecycle/approval-state control, or cross-runtime relaying is concretely required. `HERDR_ENV=1` indicates availability only and MUST NOT activate Herdr by itself; when Herdr is selected, read and follow `skill://herdr-orchestration`.

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
- Codex Multi-agent is available for independent implementation/review contexts.
- The active model profile satisfies the runtime contract above. If phase-specific top-level calls are unavailable, explicitly record the Sol/high fallback in the final report.

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

For an objective external blocker, add `blocked` with evidence. For unclear or unverifiable scope, leave one dated skip comment. Do not duplicate the same skip comment; on a second independent skip for the same reason add `needs-decision`.

If none qualifies, report the candidates and concrete reasons, then stop.

## 2. Claim

1. Re-read the issue and comments.
2. Add `in-progress` and assign `@me`.
3. Post the repository-defined claim comment; default: `Claimed by Codex: <one-line plan>`.
4. Re-read comments after posting. The earliest valid active claim wins. If another claim won, comment that this later claim is withdrawn and choose the next candidate. Do not remove the shared label or assignee; they now protect the winner.

## 3. Verify premise

Re-confirm every material code claim and file reference in the issue.

- Goal already achieved or moot with a specific commit/PR/doc proving why: close as `Invalidated (premise gone): <evidence>` and pick one replacement issue.
- Code differs but the cause is unknown: comment the mismatch, remove `in-progress`, unassign, add `needs-decision`, and stop.

Only premise failure permits one replacement pick. After planning starts, hold instead of consuming another issue.

## 4. Plan

Keep orchestration on Sol/high. Gather only the code, callers, tests, rules, and documentation needed for the issue.

Create a self-contained frozen plan containing:

- issue requirements and current state;
- affected symbols and callers;
- decisions already made and invariants to preserve;
- ordered implementation steps;
- exact verification and smoke-test commands;
- hold triggers and explicit non-goals.

Post a durable summary to the issue. Local plan storage is optional; never make the issue depend on it.

For a complex plan, use at most three independent bounded agents for code-path mapping, test mapping, and plan criticism. They share the current request model and reasoning. The root validates findings and freezes one plan; subagents do not edit code.

## 5. Implement

Preferred: run a separate top-level implementation phase on Luna/xhigh. Fallback inside one hosted tree: spawn one implementation worker on the shared Sol/high profile and record the fallback.

The implementation prompt is a frozen contract: full plan, issue requirements, repository rules, allowed scope, and verification commands. Use one writable worker and one worktree. The orchestrator must not edit implementation or test files. Every implementation or test change, including remediation after verification or adversarial review, returns to this same implementation context; if it cannot be resumed, hold.

Branch from the remote default branch, discovered with:

```bash
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
```

Fetch before branching. If the local default branch is ahead of its remote, present the commits and hold for the user's base choice; never push the default branch autonomously. Follow repository branch conventions, otherwise use `<type>/issue-<n>-<slug>`.

After implementation settles, obtain fresh raw verification evidence. Deterministic tests, lint, builds, and static checks may run in supervised process panes; a runtime scenario requiring judgment may run in a fresh read-only Verifier. Agent summaries are not evidence: the orchestrator inspects exact commands, exit codes, raw output, runtime observations, and pre/post tracked state.

## 6. Adversarial review

Review must use a fresh context that receives only the frozen requirements, base branch, diff, changed code, and verification evidence. It must not receive the implementer's rationale except where recorded as a requirement.

Preferred: separate Sol/high Responses call with Multi-agent enabled and `max_concurrent_subagents: 3`. Fallback: fresh Sol/high review agents in the current tree, explicitly reported.

Spawn exactly three read-only reviewers when the change is non-trivial:

1. **Correctness** — execution paths, invariants, edge cases, regressions.
2. **Security and operations** — trust boundaries, authorization, concurrency, data loss, unsafe failure behavior.
3. **Contract and tests** — issue acceptance criteria, missing observable coverage, tests that can pass despite a real bug.

Each finding must include severity, evidence, file/line reference, plausible failure scenario, and verification method. The review root deduplicates findings and rejects unsupported speculation.

Re-validate every blocking finding against code. Return confirmed implementation/test changes to the same implementation context, rerun every affected automated and runtime gate, and repeat review at most twice. If the implementation context cannot be resumed or confirmed blockers remain after two re-reviews, hold. Escalate review above `high` only for security, irreversible data, tenant isolation, or corruption risk.

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
2. Create a PR whose body contains `Closes #<n>`, verification evidence, and the actual review profile used.
3. Comment the result, PR link, and verification evidence on the issue.
4. Remove `in-progress`, add `awaiting-review`, and leave the issue open until merge.
5. Report issue, change, evidence, review findings/resolution, model/reasoning profile, PR, and remaining human action.

## Boundaries

Allowed: selected-issue metadata, feature branches, scoped code changes by one implementation writer, supervised verification process panes, an optional fresh runtime Verifier, fresh review agents, commits, branch push, and PR creation.

Forbidden: default-branch push, PR merge, deploy/release/tag, shared migration execution, destructive data changes, force-push/history rewrite, unrelated cleanup, orchestrator/Verifier/Reviewer implementation edits, or creation/update of GitHub Issues unrelated to the selected work item.

One invocation owns one issue. Every issue-related durable handoff belongs on the selected issue. Agent instructions, orchestration guidance, shared skills, and other unrelated changes stay out of that issue and PR and are reported separately.
