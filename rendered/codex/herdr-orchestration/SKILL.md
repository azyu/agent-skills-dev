---
name: herdr-orchestration
description: Use when HERDR_ENV=1 and an applicable repository instruction or workflow such as GitHub Autopilot routes implementation, verification, or review through Herdr. Defines user-level role, model, approval, verification, and single-writer policy across repositories.
---

# Herdr Orchestration

Apply this user-level policy when a workflow explicitly routes coding agents through Herdr. Matching this skill is the user's stored authorization for that workflow-directed use. Read `skill://herdr` only for the installed CLI mechanics; its generic activation gate does not override this narrower user policy, and this skill owns the user's orchestration policy rather than Herdr's upstream command reference.

## Preconditions

- Verify `HERDR_ENV=1` before issuing Herdr control commands.
- Follow the active repository's scope, issue, worktree, and verification rules. This skill does not weaken them.
- Use the workflow-created isolated worktree when one exists. Otherwise preserve the current working directory unless the user requested another location.
- Read pane IDs from Herdr JSON responses instead of predicting them, preserve the orchestrator pane focus with `--no-focus`, and create only the panes needed for the next settled stage.

## Roles

| Role | Runtime | Authority |
|---|---|---|
| Orchestrator | `gpt-5.6-sol`, `high` | scope, contracts, raw-evidence adjudication, integration |
| Implementer | `gpt-5.6-luna`, `xhigh`, `yolo` | the only implementation/test writer |
| Automated checks | process panes, no Agent | deterministic tests, lint, builds, static checks |
| Verifier | fresh `gpt-5.6-sol`, `high`, `yolo` | runtime/browser acceptance observations only |
| Reviewer | fresh `gpt-5.6-sol`, `high`, `yolo` | read-only adversarial review |

Immediately label every new pane by role before starting its agent or command:

```bash
herdr pane rename <implementer-pane-id> Implementer
herdr pane rename <frontend-checks-pane-id> "Frontend Checks"
herdr pane rename <backend-checks-pane-id> "Backend Checks"
herdr pane rename <verifier-pane-id> Verifier
herdr pane rename <reviewer-pane-id> Reviewer
```

## Deterministic Pane State

Pane labels, occupants, and agent lifecycle states are deterministic Herdr data. Query them with the bundled script instead of asking an Agent, inferring from prose, or repeatedly reading terminal screens:

```bash
python3 skill://herdr-orchestration/scripts/status.py
python3 skill://herdr-orchestration/scripts/status.py \
  --require Implementer=idle,done \
  --require Reviewer=idle,done
```

The script calls `herdr pane list` once, emits normalized JSON, and exits nonzero when a required role is missing or has a disallowed status. Use its output for orchestration branches and retain the JSON as evidence. `unknown` is an observed state, never proof of completion; inspect the specific agent only when the deterministic state requires diagnosis.

## Implementer

Start one bounded writer in the isolated task worktree:

```bash
herdr agent start implementer --kind omp --pane <pane-id> -- \
  --model gpt-5.6-luna --thinking xhigh --approval-mode yolo
```

The frozen prompt must forbid issue/PR operations, commits, pushes, branch/history changes, destructive or external writes, nested subagents, and self-review. It may edit only the frozen implementation and test scope and run bounded implementation checks.

Every implementation or test change, including remediation after verification or adversarial review, returns to this same Implementer context. The Orchestrator, Verifier, and Reviewer never edit implementation or test files. If the Implementer cannot be resumed, Hold instead of creating a second writer or patching directly.

If the Implementer starts with the wrong approval mode, preserve its context: obtain the session path with `herdr agent get`, dismiss approval UI with `Esc` twice, enter `/quit`, then restart the same pane/name/model/thinking with `--resume=<session-path> --approval-mode yolo`.

## Automated Verification

Deterministic tests, lint, builds, and static checks run in named Herdr process panes, not coding-agent sessions. The exact command, exit code, and raw output are the evidence; an Agent summary alone never counts.

- Start only after the Implementer settles.
- Record the implementation worktree's HEAD and tracked diff state before the checks and confirm the same state afterward.
- Generated or ignored build output is allowed. Any unexpected tracked mutation invalidates the result.
- Independent stacks may use separate process panes. Keep commands that share build directories or caches sequential unless the repository documents safe parallel execution.
- A confirmed implementation or test failure returns to the same Implementer. After a fix, rerun every affected check and every full repository gate required by the project.

Use `herdr pane run`, `herdr pane wait-output`, and `herdr pane read --source recent-unwrapped` as documented by `skill://herdr`.

## Runtime Verifier

Use a fresh Verifier only for runtime, browser, accessibility, or other acceptance scenarios that require judgment. The Orchestrator or a process pane starts the service and gives the Verifier its URL plus a frozen observable checklist.

```bash
herdr agent start verifier --kind omp --pane <pane-id> -- \
  --model gpt-5.6-sol --thinking high \
  --tools read,write --approval-mode yolo
```

The Verifier prompt must allow `write` only for the `xd://browser` device and forbid filesystem writes, source/test changes, issue/PR operations, commits, pushes, branch/history changes, fixes, and nested subagents. Because the device gateway does not technically sandbox `write` to browser operations, the Orchestrator records HEAD and tracked diff state before and after the turn. Any mutation invalidates verification and triggers Hold.

The Verifier reports exercised steps, direct observations, and reproduction details. It never fixes a finding; confirmed defects return to the same Implementer.

## Reviewer

Start the final Reviewer only after implementation and verification settle. A diagnosis or plan reviewer never satisfies the final fresh-review gate.

```bash
herdr agent start reviewer --kind omp --pane <pane-id> -- \
  --model gpt-5.6-sol --thinking high \
  --tools read,grep,glob,bash --approval-mode yolo
```

The Reviewer prompt must forbid file mutation, write-capable Bash actions, issue/PR operations, commits, pushes, branch/history changes, tests, builds, fixes, and nested subagents. `yolo` removes prompts but does not expand authority. Because `bash` is not technically read-only, the Orchestrator records HEAD and tracked diff state before and after every Reviewer turn. Any mutation invalidates the review and triggers Hold.

If the Reviewer starts with the wrong approval mode, use the same `/quit` and `--resume=<session-path> --approval-mode yolo` procedure as the Implementer while preserving the fresh review context.

## Ownership

- The Orchestrator owns scope and contract decisions, verification orchestration, raw-evidence adjudication, review-finding adjudication, and final integration. It does not edit implementation or test files.
- Automated process panes, the Verifier, and the Reviewer report evidence or findings. Only the same Implementer writes fixes.
- If the preferred Herdr route is unavailable, follow the active workflow's documented fallback and report the actual routing; never silently downgrade model or thinking level.
- During an issue-driven workflow, keep agent instructions, orchestration guidance, shared skills, and other changes unrelated to the selected work item out of that issue and PR. Do not create or update unrelated project issues for them; report them separately.
