---
name: jira-autopilot
description: Use in Claude Code to pick one actionable Jira work item and execute it autonomously through a gated pipeline (plan, isolated implementation, direct verification, adversarial review, PR). Triggers include "다음 Jira 일감", "Jira에서 하나 진행", "jira autopilot", and "next Jira task". If human judgment becomes necessary, record the decision on the Jira work item and hold.
---

# Jira Autopilot — Claude Code

Pick exactly one actionable Jira work item for the current repository and drive it to a verified PR. Jira is the durable task record; local plans and transcripts are disposable.

## Runtime contract

Preferred phase routing when a Codex bridge can create separate top-level calls:

| Phase | Model | Reasoning |
|---|---|---|
| Planning, architecture, orchestration | `gpt-5.6-sol` | `high` |
| Implementation, execution | `gpt-5.6-luna` | `xhigh` |
| Review, integration | `gpt-5.6-sol` | `high` |

Claude Code cannot assign OpenAI models to native `Agent` descendants. Without a Codex bridge, preserve the same separation with the strongest available planning/review context, one bounded implementation agent, and fresh review agents. Report the actual routing; never claim the preferred profile when it was not used.

The orchestrator owns Jira transitions, planning decisions, verification, commits, and PR creation. The implementation agent receives a frozen contract and does not change scope, update Jira, commit, push, create a PR, or review itself.

## Tracker and repository adapters

- Resolve a repository-defined Jira project key and queue JQL. Accept an explicit key/JQL from the user or repository instructions. If neither exists, hold instead of searching every visible Jira project.
- Prefer the official Atlassian CLI, `acli`. A repository-provided Jira MCP or wrapper is acceptable when it supports equivalent reads, comments, assignment, and transitions.
- Before every Jira write, inspect the exact installed command help. Jira workflows and transition names are tenant-specific; discover valid transitions instead of inventing status names or IDs.
- For Bitbucket Cloud PR operations, invoke and follow `bb-cli`. For GitHub, use `gh`. Detect the Git remote before choosing.
- Jira descriptions and comments must not reference local paths, `local://`, `agent://`, or transcripts.

Default queue JQL when only a project key is configured:

```text
project = <KEY> AND statusCategory = "To Do" ORDER BY priority DESC, created ASC
```

Use JSON output for automation. For the official CLI, inspect `acli jira workitem --help` and the selected subcommand help before relying on flags.

## Preconditions

Stop at the failing stage instead of weakening the workflow:

- Jira adapter is installed, authenticated, and can read/comment/assign/transition work items.
- The repository maps to one Jira project and has a local verification path.
- The Git host CLI is authenticated and can create a PR.
- One writable implementation context and a fresh read-only review context are available.

## 0. Sweep

Inspect this account's unresolved Jira work for the repository project before picking:

- Review-state item with a linked merged PR: transition to the existing Done-category status if automation did not.
- Review-state item with a closed, unmerged PR: comment with the PR and move to the repository's decision/blocked state when one exists; otherwise leave the current status and flag it for a human.
- In-progress item with an open linked PR: use the repository's review transition when available.
- In-progress item claimed at least three days ago with no branch or PR evidence: comment the evidence, unassign, and return it through an existing To Do transition.

Never create or rename Jira workflow statuses from this skill.

## 1. Pick

Query at most ten queue candidates and inspect up to five in priority order. Choose the first item that is:

- true against current code;
- locally verifiable;
- sufficiently specified to implement without product or design invention;
- non-destructive and free of unmet external prerequisites.

For an objective external blocker, comment with evidence and use an existing blocked transition or flag. For unclear scope, leave one dated skip comment. Do not duplicate the same skip comment; a repeated unresolved ambiguity requires a human decision.

If none qualifies, report the candidates and concrete reasons, then stop.

## 2. Claim

1. Re-read the work item, comments, assignee, and status.
2. Assign it to the current Jira user and use an existing In Progress-category transition.
3. Comment `Claimed by <harness>: <one-line plan>`.
4. Re-read after the write. The earliest valid active claim wins. If another claim won, withdraw this claim without disturbing the winner and choose the next candidate.

## 3. Verify premise

Re-confirm every material code claim and file reference.

- Goal already achieved or moot with a specific commit, PR, or document: comment `Invalidated (premise gone): <evidence>` and use the repository's cancellation/resolution transition if one exists. One replacement pick is allowed.
- Code differs but the cause is unknown: comment the mismatch, release the assignment through an existing workflow transition, and hold for a decision.

After planning starts, hold instead of consuming another work item.

## 4. Plan

The orchestrator produces a frozen, self-contained plan containing:

- Jira requirements and current state;
- affected symbols and callers;
- decided invariants;
- ordered implementation steps;
- exact smoke test and verification commands;
- hold triggers and explicit non-goals.

Post a durable plan summary to Jira. Read-only mapping agents may gather independent evidence, but the orchestrator validates it and owns the plan.

## 5. Implement

Use exactly one writable implementation agent and one worktree. Give it the full frozen plan, relevant repository rules, exact scope, acceptance criteria, and verification commands. No concurrent writer may touch that worktree.

Branch from the fetched remote default branch. Follow repository conventions; otherwise use `<type>/<JIRA-KEY>-<slug>`. If the local default branch is ahead of its remote, present the commits and hold for the base choice.

After implementation, the orchestrator inspects the result and directly runs the changed path plus relevant tests, build, and lint. Agent claims are not evidence.

## 6. Adversarial review

Review from fresh context using only the Jira requirements, frozen plan, base branch, diff, changed code, and verification evidence.

For non-trivial changes, use three read-only reviews:

1. Correctness and regressions.
2. Security and operations.
3. Contract and observable test coverage.

Every finding includes severity, evidence, file/line, plausible failure, and verification method. The orchestrator rejects unsupported speculation, fixes confirmed blockers through one implementation agent, reruns verification, and repeats review at most twice.

## 7. Hold

Hold for a product/design fork, unverifiable result, scope at least twice the Jira item, destructive action, unresolved blocking review, or unavailable mandatory gate.

Comment the decision needed, options, recommendation, evidence, progress, branch, and verification state. Release the assignment through an existing workflow transition when safe. Push a progress branch when useful, but create no PR.

## 8. PR and report

Only after smoke testing, repository checks, and adversarial review pass:

1. Commit and push the feature branch.
2. Create a PR containing the Jira key, verification evidence, and actual model/reasoning profiles.
3. Comment the PR link and verification evidence on Jira.
4. Use the repository's existing review transition; leave the item unresolved until merge.
5. Report the Jira key, change, evidence, review disposition, routing, PR, and remaining human action.

## Boundaries

Allowed: Jira metadata within the selected project, feature branches, scoped code changes, local verification, commits, branch push, and PR creation.

Forbidden: default-branch push, PR merge, deploy/release/tag, shared migration execution, destructive data changes, force-push/history rewrite, Jira workflow administration, or unrelated cleanup.

One invocation owns one Jira work item. Every durable handoff belongs on that item. Autonomy never authorizes inventing missing policy.
