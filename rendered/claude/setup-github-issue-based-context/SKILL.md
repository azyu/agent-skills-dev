---
name: setup-github-issue-based-context
description: This skill should be used when adopting, migrating, or refreshing GitHub Issues as a repository's actionable task layer for agent coordination, especially when replacing TASKS.md-style status boards, bootstrapping workflow labels, or adding agent instruction rules for issue-based ownership and status.
---

# Setup GitHub Issue-Based Context

## Overview

Make GitHub Issues the single source of truth for actionable work — backlog, ownership, status, blockers, follow-ups — while durable direction stays in files.

Sibling of `setup-file-based-context`: only the task/status layer (TASKS.md) moves to issues; project summary and steering stay file-based.

Core principle: an issue must stand alone — executable by the next session or a human with no access to local context.

## When to Use

Use when:

- Adopting GitHub Issues as the actionable backlog for a repo where multiple agents or sessions coordinate.
- Migrating a TASKS.md-style status board to issues.
- Bootstrapping or repairing the workflow label set.
- Adding or updating agent instruction rules for issue-based coordination.

Do not use for:

- Non-GitHub trackers (Bitbucket, GitLab, Jira) — this skill assumes the `gh` CLI.
- Durable constraints and decision logs — those belong in `.context/STEERING.md` (use `setup-file-based-context`).
- Executing work against an existing setup — that is a session-execution workflow (e.g. `github-autopilot`), not setup.

## Standard Structure

```text
.context/
└── STEERING.md        # durable direction, constraints, decision log (file-based)
GitHub Issues          # actionable work: open + `backlog` label = the queue
```

- TASKS.md is replaced by issues. Do not keep both — two sources drift.
- `STEERING.md` keeps a one-line pointer to the issue tracker (URL + queue label) instead of task lists.

## Label Set

Check `gh label list` and create missing labels with `gh label create`:

| Label | Meaning |
|---|---|
| `backlog` | in the actionable queue; open issues without it are out of pool |
| `in-progress` | mutex — an active session is working now |
| `awaiting-review` | PR is up, waiting for human review/merge |
| `needs-decision` | human decision required before work can continue |
| `blocked` | objective external precondition unmet |
| `archive` (optional) | historical record, not actionable |
| `priority:*` (optional) | triage order; without it, oldest-first |

Closed = done. PRs should carry `Closes #<n>` so merge closes the issue automatically.

## Issue-Writing Conventions

An issue an agent can pick up must contain:

- Current state with file:line references (verifiable against code, not memory).
- The goal, and how to verify it locally (test/build commands).
- Design decisions made in the body — or explicitly delegated ("pick one during implementation").
- No local machine paths, session artifacts, or "as discussed" references.
- Follow-ups cross-linked by number in both directions.

An issue missing these gets skipped by executors — the setup's value is exactly this quality bar.

## Agent Instruction Intake Rule

Merge a section like this into the repository's existing agent instruction file (`AGENTS.md`, `CLAUDE.md`, …). Do not create a parallel file; if a coordination section exists, merge instead of duplicating.

```md
## Task Coordination (GitHub Issues)

Open issues labeled `backlog` are the actionable queue. Before starting any task:

1. Read `.context/STEERING.md`.
2. Read the issue with `gh issue view <n> --comments`. If none was given, pick from
   `gh issue list --state open --label backlog`, or open a new issue first.

Claim before implementing:

1. `gh issue edit <n> --add-label in-progress --add-assignee @me`.
2. Comment `Claimed by <agent-name>: <one-line plan>`.
3. Re-read the comments after posting. The earliest active claim wins. If another
   claim landed first, comment that this later claim is withdrawn and move to
   another issue. Do not remove the shared label or assignee: that would erase the
   winner's mutex. The comment identifies the owner — agents may share one
   authenticated account, so the assignee alone does not.

On completion, comment the verification results and transition the issue:

- Directly landed work: remove `in-progress`, then close the issue.
- PR workflow: remove `in-progress`, add `awaiting-review`, and leave the issue
  open until merge. `Closes #<n>` in the PR performs the close.
- Hold: remove `in-progress`, unassign, and add `needs-decision` or `blocked`.

Open `backlog` issues are the queue; closing at PR creation drops unfinished work
out of it.

Open follow-up issues for remaining work and cross-link them and the closed issue by
number in both directions.
```

## Migration Workflow

1. Inventory existing task boards (TASKS.md, TODO sections, stale checklists).
2. Create one issue per pending item, meeting the issue-writing conventions. Do not retro-create issues for completed work — git history already records it.
3. Create the label set.
4. Merge the intake rule into the agent instruction file.
5. Slim `STEERING.md`: point tracking at the issue queue, delete executable task lists.
6. Verify: read back the changed files; `gh label list` and `gh issue list --label backlog` show the expected state.

## Update Rules

| Change | Update |
|---|---|
| Task starts / completes / blocks | the issue (labels + comments) |
| Durable design decision | `.context/STEERING.md` |
| New follow-up work discovered | new issue, cross-linked both ways |
| Agent behavior rule changes | the agent instruction file |

## Common Mistakes

| Mistake | Fix |
|---|---|
| Closing issues at PR creation | Close after merge; open issues are the queue |
| Keeping TASKS.md alongside issues | Delete the board; two sources drift |
| Issue bodies referencing local paths or sessions | Issues must stand alone |
| Treating the assignee as the ownership signal | Comment-based claim; accounts may be shared |
| Recording steering decisions in issues | Durable decisions go to `STEERING.md` |
| Multiple claim-comment formats in one repo | Define one format in the instruction file; execution workflows defer to it |
