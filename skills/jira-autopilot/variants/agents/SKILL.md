---
name: jira-autopilot
description: Use in OMP to pick one actionable Jira work item and execute it autonomously through a gated pipeline (plan, Luna implementation worker, direct verification, Sol adversarial reviewers, PR). Triggers include "다음 Jira 일감", "Jira에서 하나 진행", "jira autopilot", and "next Jira task". If human judgment becomes necessary, record the decision on the Jira work item and hold.
---

# Jira Autopilot — OMP

Pick exactly one actionable Jira work item for the current repository and drive it to a verified PR. Jira is the durable task record; OMP session artifacts are not.

## Runtime contract

| Role | OMP selector | Responsibility |
|---|---|---|
| Main planning and orchestration | `openai-codex/gpt-5.6-sol:high` | scope, state, evidence, final ruling |
| Implementation `task` agent | `openai-codex/gpt-5.6-luna:xhigh` | one bounded writable change |
| `reviewer` agent and integration | `openai-codex/gpt-5.6-sol:high` | read-only adversarial review; main integrates |

Required routing:

```yaml
modelRoles:
  default: openai-codex/gpt-5.6-sol:high
  plan: openai-codex/gpt-5.6-sol:high
  task: openai-codex/gpt-5.6-luna:xhigh
  advisor: openai-codex/gpt-5.6-sol:high

task:
  agentModelOverrides:
    task: openai-codex/gpt-5.6-luna:xhigh
    reviewer: openai-codex/gpt-5.6-sol:high
```

Keep OMP Advisor disabled for routine runs because the explicit review phase covers the same gate. Escalate review above high only for security, tenant isolation, irreversible data, or corruption risk.

OMP subagents start without conversation history. Every task prompt carries its complete bounded contract. The main orchestrator owns Jira transitions, planning decisions, verification, commits, and PR creation. Implementation and review agents never self-certify completion.

## Adapters

- Resolve a repository-defined Jira project key and queue JQL. Accept explicit user or repository configuration. Without either, hold instead of searching all visible Jira projects.
- Prefer official Atlassian `acli`; an equivalent repository Jira MCP/wrapper is acceptable.
- Inspect the exact installed Jira command help before every write. Workflows and transition names are tenant-specific; discover valid transitions instead of inventing names or IDs.
- Use JSON output for automation. The default queue JQL is `project = <KEY> AND statusCategory = "To Do" ORDER BY priority DESC, created ASC`.
- For Bitbucket Cloud, invoke `bb-cli` and use `bb` for PR operations. For GitHub, use `gh`. Detect the Git remote first.
- Jira descriptions/comments never reference local paths, `local://`, `agent://`, or transcripts.

## Preconditions

Stop at the failing stage:

- Jira adapter can read, comment, assign, and transition work items.
- The repository maps to one Jira project and has local verification commands.
- The Git host CLI can create a PR.
- OMP `task` and `reviewer` agents resolve to the runtime contract.
- One worktree can safely hold one implementation writer.

## 0. Sweep

Inspect this account's unresolved work in the repository project:

- Review-state item with merged PR: transition through an existing Done-category transition if automation did not.
- Review-state item with closed, unmerged PR: comment the PR and use an existing decision/blocked state when available; otherwise leave it for a human.
- In-progress item with open PR: use the existing review transition when available.
- In-progress item claimed at least three days ago with no branch or PR: comment evidence, unassign, and return it through an existing To Do transition.

Never administer Jira workflows from this skill.

## 1. Pick

Query at most ten queue candidates and inspect up to five. Pick the first that is true against current code, locally verifiable, sufficiently specified, non-destructive, and free of external prerequisites.

Use read-only `scout` or `librarian` agents only when code or external APIs are genuinely unclear; the main owns selection and scope. For an objective blocker, comment evidence and use an existing blocked transition/flag. For ambiguity, leave one dated skip comment; do not duplicate it. If no candidate qualifies, report concrete reasons and stop.

## 2. Claim

1. Re-read the item, comments, assignee, and status.
2. Assign it to the current Jira user and use an existing In Progress-category transition.
3. Comment `Claimed by OMP: <one-line plan>`.
4. Re-read. The earliest valid active claim wins. Withdraw a later claim without disturbing the winner and choose the next candidate.

## 3. Verify premise

Re-confirm every material code claim and file reference.

- Already achieved or moot with a specific commit/PR/doc: comment `Invalidated (premise gone): <evidence>` and use an existing cancellation/resolution transition. One replacement pick is allowed.
- Current code differs but the cause is unknown: comment the mismatch, release the claim safely, and hold.

After planning starts, hold instead of taking another item.

## 4. Plan

On Sol/high, gather only the relevant code, callers, tests, rules, and documentation. Freeze a self-contained plan with Jira requirements, current state, affected symbols, invariants, ordered steps, exact smoke/verification commands, hold triggers, and non-goals. Post a durable summary to Jira.

At most three independent read-only mapping agents may run in one batch for complex work. Validate their evidence directly; agents do not decide product scope or edit during planning.

## 5. Implement

Spawn exactly one OMP `task` agent on Luna/xhigh. Give it exact files/symbols, frozen steps, acceptance criteria, repository rules, and non-goals. It skips formatter, lint, tests, and project-wide validation; the main runs those once after edits settle. It does not update Jira, commit, push, create a PR, or review itself.

Use isolation when the checkout is dirty. Branch from the fetched remote default branch using repository conventions, otherwise `<type>/<JIRA-KEY>-<slug>`. If local default is ahead of remote, present the commits and hold for the base choice.

The main inspects the result and directly runs the changed path, relevant tests, build, and lint. Agent output is not evidence.

## 6. Adversarial review

After verification passes, batch three fresh read-only `reviewer` agents on Sol/high for non-trivial changes:

1. Correctness and regressions.
2. Security and operations.
3. Contract and observable test coverage.

They receive only Jira requirements, the frozen plan, base branch, diff, changed code, and verification evidence. Each finding includes severity, evidence, file/line, plausible failure, and verification method. The main rejects speculation, confirms findings, sends fixes to one Luna/xhigh agent, reruns verification, and repeats review at most twice.

A trivial mechanical change may use one reviewer and must report that reduced shape.

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

Allowed: Jira metadata for the selected project, feature branches, scoped edits, local checks, commits, branch push, PR creation, and bounded OMP delegation.

Forbidden: default-branch push, PR merge, deploy/release/tag, shared migration execution, destructive data changes, force-push/history rewrite, Jira workflow administration, or unrelated cleanup.

One invocation owns one Jira work item. Every durable handoff belongs on it. Autonomy never authorizes inventing missing policy.
