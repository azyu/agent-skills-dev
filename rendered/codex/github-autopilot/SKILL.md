---
name: github-autopilot
description: Use in Codex to pick one actionable GitHub issue and execute it autonomously through a gated pipeline (plan, implementation, verification, adversarial review, PR). Triggers include "다음 일감", "일감 하나 가져와서 진행", "이슈에서 하나 집어서 해줘", "next task", and "autopilot". If human judgment becomes necessary, record the decision needed on the issue and hold.
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

## Worker lifecycle

Orca Task completion and terminal liveness are separate: `worker_done` does not close a terminal. After consuming a terminal Dispatch's result and confirming that no follow-up is assigned, stop that exact worker terminal with the version-matched Orca orchestration command. Preserve Run Tasks, messages, and provider session history; terminal cleanup never means orchestration reset or JSONL deletion.

One feature Run contains only work needed for its owned issue. Process-skill edits, benchmark cohorts, and control/baseline experiments are separate work items in a later Run. Record the discovery and defer it instead of expanding the feature Run.

At phase and Run boundaries:

- Stop completed planning workers after the frozen plan consumes their findings.
- Stop implementation and review workers after their results or requested fixes are consumed.
- Keep the coordinator and any terminal with an explicit pending follow-up.
- Retain an unmerged, dirty, blocked, or user-pinned feature worktree.
- After a later Sweep proves the PR merged and the Orca worktree is clean, remove that landed worktree through Orca.

Closing terminals must not erase durable issue comments, Task results, or resumable provider history.

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

## 0. Refresh base

Before Sweep, Pick, Claim, or any issue mutation, refresh the repository's actual remote default branch:

```bash
default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
git fetch origin "$default_branch"
git rev-parse "origin/$default_branch"
```

Record the fetched remote commit as the planning base. If a local branch with that name exists, compare it with the refreshed remote:

```bash
git rev-list --left-right --count "$default_branch...origin/$default_branch"
git log --oneline "origin/$default_branch..$default_branch"
```

- No local-only commits: continue. A behind local branch is not the implementation base; use the refreshed remote branch.
- Any local-only commits or divergence: show the commits and hold for the user's base choice before sweeping or changing issue state. Never rewrite or push the default branch.
- Fetch, authentication, or default-branch discovery failure: stop at this preflight gate.

Do not reuse a fetch from an earlier session. The frozen plan must name the fetched remote commit it was validated against.

## 1. Sweep

Before picking, inspect residual issues owned by this account:

- `awaiting-review`: inspect the linked PR. Merged means close with evidence if automation did not. Closed without merge means remove `awaiting-review`, add `needs-decision`, and record the declined PR. Open means leave it.
- `in-progress`: do not take work owned by another active session. If a linked PR is open, switch to `awaiting-review`. If the claim is at least 3 days old with no branch or PR evidence, comment the evidence, remove `in-progress`, and unassign.
- `needs-decision`: remove the label only when a human decision appears after the hold comment.

## 2. Pick

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

## 3. Claim

1. Re-read the issue and comments.
2. Add `in-progress` and assign `@me`.
3. Post the repository-defined claim comment; default: `Claimed by Codex: <one-line plan>`.
4. Re-read comments after posting. The earliest valid active claim wins. If another claim won, comment that this later claim is withdrawn and choose the next candidate. Do not remove the shared label or assignee; they now protect the winner.

## 4. Verify premise

Re-confirm every material code claim and file reference in the issue.

- Goal already achieved or moot with a specific commit/PR/doc proving why: close as `Invalidated (premise gone): <evidence>` and pick one replacement issue.
- Code differs but the cause is unknown: comment the mismatch, remove `in-progress`, unassign, add `needs-decision`, and stop.

Only premise failure permits one replacement pick. After planning starts, hold instead of consuming another issue.

## 5. Plan

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

## 6. Implement

Preferred: run a separate top-level implementation phase on Luna/xhigh. Fallback inside one hosted tree: spawn one implementation worker on the shared Sol/high profile and record the fallback.

The implementation prompt is a frozen contract: full plan, issue requirements, repository rules, allowed scope, and verification commands. Use one writable worker and one worktree. The orchestrator must not edit concurrently.

Immediately before creating the feature branch, fetch the default branch again and compare its remote commit with the planning base:

```bash
default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
git fetch origin "$default_branch"
git rev-parse "origin/$default_branch"
```

If the remote commit changed after planning, re-verify the issue premise and every affected plan reference against the refreshed remote before branching. If it did not change, branch from the exact refreshed remote commit. Follow repository branch conventions, otherwise use `<type>/issue-<n>-<slug>`.

After implementation, the orchestrator directly runs the changed path and the repository's relevant verification commands. Agent claims are not evidence.

## 7. Adversarial review

Review must use a fresh context that receives only the frozen requirements, base branch, diff, changed code, and verification evidence. It must not receive the implementer's rationale except where recorded as a requirement.

Preferred: separate Sol/high Responses call with Multi-agent enabled and `max_concurrent_subagents: 3`. Fallback: fresh Sol/high review agents in the current tree, explicitly reported.

Spawn exactly three read-only reviewers when the change is non-trivial:

1. **Correctness** — execution paths, invariants, edge cases, regressions.
2. **Security and operations** — trust boundaries, authorization, concurrency, data loss, unsafe failure behavior.
3. **Contract and tests** — issue acceptance criteria, missing observable coverage, tests that can pass despite a real bug.

Each finding must include severity, evidence, file/line reference, plausible failure scenario, and verification method. The review root deduplicates findings and rejects unsupported speculation.

Re-validate every blocking finding against code. Fix all confirmed blockers in one consolidated implementation pass and rerun verification. Re-review the confirmed findings and affected paths; do not automatically spawn another full three-reviewer wave. Permit one final integrated read-only review, and keep the hard ceiling of two re-reviews. If confirmed blockers remain after that ceiling, hold as a design fork. Escalate review above `high` only for security, irreversible data, tenant isolation, or corruption risk.

## 8. Hold

Hold for a product/design fork, unverifiable result, scope at least twice the issue, destructive action, unresolved blocking review, or unavailable mandatory gate.

1. Comment the decision needed, options, recommendation, evidence, progress, branch, and verification state.
2. Remove `in-progress` and unassign. Add `needs-decision` for human judgment or `blocked` for an objective prerequisite.
3. Push a progress branch if useful, but create no PR.
4. Stop; do not pick another issue.

If a GitHub write fails, retry once. Preserve the intended update in durable local state and report it; never discard code or verification results.

## 9. Report and PR

Only after implementation, smoke test, repository checks, and adversarial review pass:

1. Commit and push the feature branch.
2. Create a PR whose body contains `Closes #<n>`, verification evidence, and the actual review profile used.
3. Comment the result, PR link, and verification evidence on the issue.
4. Remove `in-progress`, add `awaiting-review`, and leave the issue open until merge.
5. After those durable writes succeed, stop every completed worker terminal whose result was consumed and which has no pending follow-up. Keep the coordinator and retain the open PR's feature worktree.
6. Report issue, change, evidence, review findings/resolution, model/reasoning profile, PR, worker cleanup, and remaining human action.

## Boundaries

Allowed: issue metadata, feature branches, scoped code changes, tests/build/lint, commits, branch push, PR creation.

Forbidden: default-branch push, PR merge, deploy/release/tag, shared migration execution, destructive data changes, force-push/history rewrite, or unrelated cleanup.

One invocation owns one issue. Every durable handoff belongs on the issue. Autonomy never authorizes inventing missing policy.
