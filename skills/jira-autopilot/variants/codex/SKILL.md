---
name: jira-autopilot
description: Use in Codex to pick one actionable Jira work item and execute it autonomously through a gated pipeline (plan, isolated implementation, direct verification, adversarial review, PR). Triggers include "다음 Jira 일감", "Jira에서 하나 진행", "jira autopilot", and "next Jira task". If human judgment becomes necessary, record the decision on the Jira work item and hold.
---

# Jira Autopilot — Codex

Pick exactly one actionable Jira work item for the current repository and drive it to a verified PR. Jira is the durable task record; local session context is disposable.

## Runtime contract

Preferred phase-isolated profiles when the controller can create separate top-level Responses calls:

| Phase | Model | Reasoning | Shape |
|---|---|---|---|
| Planning, architecture, orchestration | `gpt-5.6-sol` | `high` | root; bounded read-only research |
| Implementation, execution | `gpt-5.6-luna` | `xhigh` | separate top-level worker; one worktree |
| Review, integration | `gpt-5.6-sol` | `high` | fresh read-only root; root integrates |

A normal Codex hosted tree gives the root and descendants the same request model and reasoning. When phase-specific top-level calls are unavailable, use Sol/high for the tree, preserve role separation with fresh bounded contexts, and report the fallback. Never claim Luna/xhigh implementation when it did not run.

Plan, implementation, and review are sequential. Multi-agent is only for independent bounded research or review. Never let concurrent agents edit one worktree.

## Adapters

- Resolve a repository-defined Jira project key and queue JQL. Accept explicit user or repository configuration. Without either, hold instead of searching all visible Jira projects.
- Prefer official Atlassian `acli`; an equivalent repository Jira MCP/wrapper is acceptable.
- Inspect the exact installed Jira command help before every write. Workflows and transition names are tenant-specific; discover valid transitions instead of inventing names or IDs.
- Use JSON output. Default queue JQL: `project = <KEY> AND statusCategory = "To Do" ORDER BY priority DESC, created ASC`.
- For Bitbucket Cloud, invoke `bb-cli` and use `bb` for PR operations. For GitHub, use `gh`. Detect the remote before choosing.
- Jira descriptions/comments never reference local paths or session artifacts.

## Preconditions

Stop at the failing stage:

- Jira adapter can read, comment, assign, and transition work items.
- The repository maps to one Jira project and has local verification commands.
- The Git host CLI can create a PR.
- Fresh implementation and review contexts are available.
- The active model profile satisfies the runtime contract or its disclosed Sol/high fallback.

## 0. Sweep

Inspect this account's unresolved Jira work in the repository project:

- Review-state item with merged PR: use an existing Done-category transition if automation did not.
- Review-state item with closed, unmerged PR: comment the PR and use an existing decision/blocked state when available; otherwise leave it for a human.
- In-progress item with open PR: use the existing review transition when available.
- In-progress item claimed at least three days ago with no branch or PR: comment evidence, unassign, and return it through an existing To Do transition.

Never administer Jira workflows from this skill.

## 1. Pick

Query at most ten queue candidates and inspect up to five. Pick the first that is true against current code, locally verifiable, sufficiently specified, non-destructive, and free of unmet external prerequisites.

For an objective blocker, comment evidence and use an existing blocked transition/flag. For ambiguity, leave one dated skip comment; never duplicate it. If none qualifies, report candidates and concrete reasons, then stop.

## 2. Claim

1. Re-read the item, comments, assignee, and status.
2. Assign it to the current Jira user and use an existing In Progress-category transition.
3. Comment `Claimed by Codex: <one-line plan>`.
4. Re-read. The earliest valid active claim wins. Withdraw a later claim without disturbing the winner and choose the next candidate.

## 3. Verify premise

Re-confirm every material code claim and file reference.

- Already achieved or moot with a specific commit/PR/doc: comment `Invalidated (premise gone): <evidence>` and use an existing cancellation/resolution transition. One replacement pick is allowed.
- Current code differs but the cause is unknown: comment the mismatch, release the claim safely, and hold.

After planning starts, hold instead of taking another item.

## 4. Plan

Keep orchestration on Sol/high. Gather only relevant code, callers, tests, rules, and documentation. Freeze a self-contained plan with Jira requirements, current state, affected symbols, invariants, ordered steps, exact smoke/verification commands, hold triggers, and non-goals. Post a durable plan summary to Jira.

For complex work, use at most three bounded read-only agents for independent code mapping, test mapping, or plan criticism. The root validates evidence and owns scope.

## 5. Implement

Preferred: run a separate top-level Luna/xhigh implementation phase. Fallback inside one hosted tree: one implementation worker on the shared Sol/high profile, explicitly reported.

The prompt is a frozen contract containing exact targets, Jira requirements, repository rules, allowed scope, acceptance criteria, verification commands, and non-goals. Use one writer and one worktree. The worker does not update Jira, commit, push, create a PR, or review itself.

Branch from the fetched remote default branch using repository conventions, otherwise `<type>/<JIRA-KEY>-<slug>`. If local default is ahead of remote, present the commits and hold for the base choice.

After implementation, the root directly runs the changed path and relevant tests, build, and lint. Worker claims are not evidence.

## 6. Adversarial review

Use a fresh Sol/high context that receives only the Jira requirements, frozen plan, base branch, diff, changed code, and verification evidence.

For non-trivial changes, run three read-only reviewers:

1. Correctness and regressions.
2. Security and operations.
3. Contract and observable test coverage.

Every finding includes severity, evidence, file/line, plausible failure, and verification method. The review root deduplicates findings and rejects speculation. Re-validate blockers, fix confirmed findings through one implementation worker, rerun verification, and re-review at most twice.

A trivial mechanical change may use one reviewer and must report that reduced shape. Escalate review above high only for security, tenant isolation, irreversible data, or corruption risk.

## 7. Hold

Hold for a product/design fork, unverifiable result, scope at least twice the Jira item, destructive action, unresolved blocking review, or unavailable gate. Comment the decision, options, recommendation, evidence, progress, branch, and verification state. Release the assignment through the existing workflow when safe. Push progress when useful; create no PR.

## 8. PR and report

Only after smoke testing, repository checks, and review pass:

1. Commit and push the feature branch.
2. Create a PR containing the Jira key, verification evidence, and actual model/reasoning profiles.
3. Comment the PR and evidence on Jira.
4. Use the existing review transition; leave the item unresolved until merge.
5. Report the Jira key, change, evidence, review disposition, routing, PR, and remaining action.

## Boundaries

Allowed: Jira metadata for the selected project, feature branches, scoped edits, local checks, commits, branch push, and PR creation.

Forbidden: default-branch push, PR merge, deploy/release/tag, shared migration execution, destructive data changes, force-push/history rewrite, Jira workflow administration, or unrelated cleanup.

One invocation owns one Jira work item. Every durable handoff belongs on it. Autonomy never authorizes inventing missing policy.
