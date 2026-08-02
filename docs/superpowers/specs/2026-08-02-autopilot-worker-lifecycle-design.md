# GitHub Autopilot Worker Lifecycle Design

## Problem

A completed Orca Dispatch records `worker_done` and preserves its Task result, but the worker terminal and agent TUI remain connected until explicitly stopped or closed. The 2026-08-02 TransNovel autopilot Run completed 32 Tasks yet retained 32 completed worker terminals across the main workspace and the merged feature worktree. The same Run also mixed 15 process-skill evaluation workers into feature delivery and used 13 review workers after one implementation worker.

## Goals

- Preserve orchestration Task results and Codex JSONL history.
- Remove completed worker processes, PTYs, and tabs when they no longer serve the active Run.
- Keep the coordinator and explicitly retained interactive terminals.
- Prevent process-skill experiments from expanding a feature Run.
- Bound adversarial re-review without weakening the review gate.
- Remove a merged, clean feature worktree at Run closure.

## Non-goals

- Deleting `~/.codex/sessions/*.jsonl`.
- Resetting Orca orchestration Task or message history.
- Automatically closing a worker before its result is durably recorded and consumed.
- Removing dirty, unmerged, blocked, or user-pinned worktrees.
- Changing TransNovel application behavior.

## Current Cleanup

The current cleanup keeps only the active Pi coordinator.

1. Confirm every targeted Dispatch is terminal (`completed` or `failed`) and has no pending question or follow-up.
2. Close the 18 completed worker terminals in the main TransNovel workspace.
3. Close the prior idle OMP terminal because the user explicitly selected full cleanup.
4. Confirm the Issue #31 worktree is clean and PR #61 is merged.
5. Remove the Issue #31 Orca worktree, which closes its 14 completed worker terminals and primary terminal.
6. Re-run `orca worktree ps --json` and `orca terminal list --worktree active --json`; the active TransNovel workspace must contain only the current Pi terminal and the Issue #31 worktree must be absent.

Historical JSONL and orchestration rows remain untouched.

## Future Lifecycle Policy

### Scope isolation

One autopilot invocation owns one GitHub issue. Process-skill experiments, benchmark cohorts, and control/baseline studies must use a separate Run after feature delivery. A discovered workflow defect may be recorded, but must not spawn unrelated workers inside the feature Run.

### Planning

Planning may use at most three bounded read-only workers. After their results are consumed and the frozen plan is written, stop their exact worker terminals unless a concrete follow-up in the same phase requires reuse.

### Implementation

Use one writable worker and one feature worktree. Keep that worker only while implementation or requested fixes remain. Once the implementation result is consumed and no follow-up edit is assigned, stop its exact worker terminal.

### Review

Use exactly three focused reviewers for the initial adversarial review. Confirmed findings are fixed in one consolidated implementation pass. Re-review targets the confirmed findings and affected paths; it does not automatically spawn another three full-diff reviewers. Permit one final integrated read-only review. Existing `at most twice` hold behavior remains the hard ceiling.

### Run closure

After PR creation or a hold handoff:

- Persist issue comments, verification, PR/branch links, and worker results first.
- Stop every terminal belonging to a terminal Dispatch with no pending follow-up.
- Preserve the coordinator and explicitly retained interactive terminals.
- Remove only feature worktrees proven clean and landed; otherwise retain them and report why.
- Never use orchestration database reset as routine cleanup.

## Command Selection and Failure Handling

- Prefer `orca orchestration worker-stop --dispatch <id> --json` for a supervised worker because it targets the exact Dispatch terminal.
- Use `orca terminal close --terminal <handle> --json` only for retained idle terminals that are not active Dispatches, such as the prior OMP terminal.
- Use `orca worktree rm --worktree <full-id> --force --json` only after merge and clean-state checks.
- If a target is no longer present, treat the operation as already clean after re-listing runtime state.
- If a target is active, dirty, has pending mail, or cannot be correlated to a terminal Dispatch, skip it and report the exact blocker instead of broad stopping or resetting.

## Verification

### Current cleanup

- `orca worktree ps --json` reports no Issue #31 worktree.
- `orca terminal list --worktree active --json` reports only the current Pi terminal.
- Current coordinator remains connected and writable.
- GitHub Issue #31 remains closed and PR #61 remains merged.
- No JSONL or orchestration history is deleted.

### Skill change

- Inspect the rendered Codex `github-autopilot` skill for explicit scope isolation, targeted review reuse, and terminal/worktree cleanup rules.
- Run the skill repository's supported validation workflow from the `writing-skills` instructions.
- Run `skillctl plan`; it must not propose an unexpected reversion of the edited rendered skill.
- Review the final diff without including pre-existing unrelated configuration changes.
