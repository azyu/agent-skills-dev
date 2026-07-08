---
name: setup-file-based-context
description: Use when setting up, adopting, migrating, or refreshing a lightweight .context directory for project/session continuity, especially when the user mentions file-based context, context management, PROJECT.md, STEERING.md, TASKS.md, or AGENTS.md intake rules.
---

# Setup File-Based Context

## Overview

Create a small `.context/` coordination layer that helps future sessions resume work without rereading full transcripts or duplicating README/spec content.

Core principle: `.context` is a state board, not a documentation dump.

## When to Use

Use when:

- Adding `.context` to a project.
- Porting context-management conventions from another repository.
- Updating project state after a phase change.
- Adding AGENTS.md instructions that tell future agents which context files to read.
- Splitting long-lived project knowledge into project summary, steering decisions, and task status.

Do not use for:

- One-off notes that belong in chat only.
- User-facing install/use documentation; put that in `README.md`.
- Full implementation plans or specs; link to those instead.
- Domain glossary work; use a domain-modeling workflow for that.

## Standard Structure

Create only these files unless the project has a clear need for more:

```text
.context/
├── PROJECT.md
├── STEERING.md
└── TASKS.md
```

### PROJECT.md

Purpose: current project summary and material state.

Include:

- Project name and one-sentence purpose.
- Current state.
- Major implemented capabilities.
- Major not-yet-implemented capabilities.
- Important related repositories or durable references.
- Verification commands.

Avoid:

- Full README content.
- Full architecture specs.
- Detailed task history.

### STEERING.md

Purpose: durable direction, constraints, and decision log.

Include:

- Current priority.
- Execution mode.
- Non-negotiable constraints.
- Target seams/interfaces if relevant.
- Decisions log with date, decision, rationale.
- Notes that should affect future sessions.

Avoid:

- Completed task lists.
- Step-by-step plans.
- Temporary thoughts.

### TASKS.md

Purpose: status board.

Include:

- Active phase/task table.
- Completed work with evidence.
- Verification results tied to task status.
- Pending tasks phrased as observable work.

Avoid:

- Full implementation plans.
- Long design discussions.
- Claims without evidence.

## AGENTS.md Intake Rule

Add or update a section like this:

```md
## Required Context Intake

Before starting any task, read these files in order:

1. `.context/PROJECT.md` — current project summary and active state.
2. `.context/STEERING.md` — active priorities, constraints, and decision log.
3. `.context/TASKS.md` — current status board.

The `.context` directory is the lightweight coordination layer for future sessions and agents. Keep it current when task status changes, but do not duplicate README, full specs, or implementation plans.
```

If the repository already has a context-intake section, merge instead of duplicating.

## Update Rules

Use these rules after adoption:

| Change | Update |
|---|---|
| Task starts/completes | `.context/TASKS.md` |
| Durable design decision | `.context/STEERING.md` |
| Active phase materially changes | `.context/PROJECT.md` and `.context/TASKS.md` |
| User-facing usage changes | `README.md` |
| Agent behavior rule changes | `AGENTS.md` |

## Workflow

1. Inspect current project docs and code surface enough to know actual state.
2. Create `.context/PROJECT.md`, `.context/STEERING.md`, and `.context/TASKS.md`.
3. Update `AGENTS.md` with required context intake.
4. Verify files by reading them back.
5. If edits are non-trivial, run the project’s focused verification command only if behavior changed; pure docs usually need read-back verification.

## Quality Bar

A good `.context` setup is:

- Short enough to read at session start.
- Specific enough to prevent wrong next steps.
- Honest about what is not implemented.
- Linked to durable docs instead of copying them.
- Evidence-based for completed work.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Copying README into PROJECT.md | Summarize state; link README. |
| Putting full plans in TASKS.md | Keep only task board and evidence. |
| Adding constraints only to chat | Put durable constraints in STEERING.md. |
| Forgetting AGENTS.md intake | Add required read order. |
| Marking future work as done | Keep future work pending and evidence-free until verified. |
