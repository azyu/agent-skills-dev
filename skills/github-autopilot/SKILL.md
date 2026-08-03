---
name: github-autopilot
description: Use in Claude Code to pick one actionable GitHub issue and execute it autonomously through a gated pipeline (Fable 5 planning and review, Opus 5 implementation, evidence-backed verification, PR). Triggers include "다음 일감", "일감 하나 가져와서 진행", "이슈에서 하나 집어서 해줘", "next task", "github autopilot", and "autopilot". For Jira-tracked projects use jira-autopilot. If human judgment becomes necessary, record the decision needed on the issue and hold.
---

# GitHub Autopilot — Claude Code

Pick **one** actionable issue from the current repo's GitHub Issues and drive it to completion through a gated pipeline. When a judgment fork appears, record it on the issue and hold.

Preferred Claude Code role routing: planning, architecture, orchestration, runtime verification, adversarial review, and integration use fresh `Fable 5` contexts; one frozen implementation uses `Opus 5`. Preserve fresh-context separation and the single-writer boundary even when an exact model assignment is temporarily unavailable, and always report the actual routing.

All issue operations use the `gh` CLI against the current repo context. Issue bodies and comments must never reference local machine paths or session-local artifacts — the issue must stand alone for the next session or a human.

Herdr is an optional external-process control plane, not a prerequisite for this workflow. Claude Code's native Agent orchestration is the default when it can preserve the model routing, fresh contexts, and single-writer boundary above. Use Herdr only when the user or repository explicitly requests it, or when persistent coordination across independent interactive agent processes, lifecycle/approval-state control, or cross-runtime relaying is concretely required. `HERDR_ENV=1` indicates availability only and MUST NOT activate Herdr by itself. When Herdr is selected, read and follow `skill://herdr-orchestration`.

## State model (labels replace JIRA workflow states)

GitHub issues are only open/closed, so workflow states are modeled with labels:

| State | Representation | Meaning |
|---|---|---|
| To Do | open, no state label | in the pool |
| In Progress | open + `in-progress` + self-assigned | **mutex** — an active session is working now |
| Awaiting review | open + `awaiting-review` | PR is up, waiting for human review/merge |
| Done | closed | merge auto-closes via `Closes #N`, or explicit close with evidence |

Hold labels: `needs-decision` (user decision required), `blocked` (objective external precondition unmet). **Bootstrap once per repo**: check `gh label list` and create any missing state/hold labels with `gh label create` before the first pick.

If the repo marks actionable deferred items with a dedicated label (e.g. `backlog`), scope all pool queries to it and treat unlabeled issues as out of pool.

## Preconditions

If any is missing, stop at that stage — do not work around it.

| Required | When missing |
|---|---|
| `gh auth status` OK + repo issue write access | Cannot operate issues → report and exit |
| One bounded implementation context | Cannot isolate implementation → report and exit |
| One fresh read-only review context | Review gate impossible → Hold per §6 |

## 0. Sweep (clean up my residual issues — once, before Pick)

- Open issues with `awaiting-review`: check the PR recorded on the issue with `gh pr view`:
  - **MERGED** → `Closes #N` should have auto-closed the issue; if it is still open (missing keyword, non-default target branch), close it with an evidence comment.
  - **CLOSED without merge** → a human declined the work; remove `awaiting-review`, add `needs-decision` + comment (link the declined PR). An agent must not retry human-declined work.
  - **OPEN** → leave as is.
- Open issues with `in-progress`: owned by another session in principle — hands off. Two exceptions:
  - A PR is recorded on the issue → handle like `awaiting-review` above; if the PR is OPEN, swap the label to `awaiting-review`.
  - The start comment is 3+ days old with no PR/branch traces → dead session residue; comment the evidence, remove `in-progress`, unassign, return to pool.
- Open issues with `needs-decision`: if a user decision comment exists **after** the hold comment, remove the label (back to pool). Otherwise leave.
- If the previous session's plan file has a `## Unposted issue updates` section (see "GitHub write failure" below), post it to the issue and remove the section.

## 1. Pick (candidate selection)

```bash
gh issue list --state open \
  --search "-label:in-progress -label:awaiting-review -label:needs-decision -label:blocked sort:created-asc" \
  --limit 10
```

GitHub has no priority field — if the repo uses priority labels (`priority:high` etc.), triage those first; otherwise oldest first.

Read the bodies of the top ~5 and **triage for executability** — pick the first item satisfying all of:

- [ ] Preconditions hold (the "current state" described in the body is true now)
- [ ] Locally verifiable (repo's test/build commands — skip if VPN, prod access, or infra changes are required)
- [ ] Scope is clear from the issue body alone (design decisions already made in the body)
- [ ] No destructive work (shared DB migration execution, infra changes, data deletion)

Unfit handling:

- **Objective external precondition unmet** (e.g. "after TypeScript 7.1 ships", stated in the body) → `blocked` label + reason comment, removing it from the pool — avoids re-triaging the same issue every session.
- **Subjectively unfit** (unclear scope, not locally verifiable, etc.) → leave a skip comment: `⏭️ agent skip (YYYY-MM-DD): <unmet checklist item + 1-2 line reason>`. No label — code reality can change, so it stays in the pool.
  - In the next session's triage, an existing skip comment is **a reference, not a verdict** — instead of full re-analysis, quickly recheck whether the reason still holds; if resolved, proceed normally.
  - **If a skip comment with the same reason already exists**, do not stack a duplicate — add `needs-decision` (ask the user to concretize the issue). Two independent sessions failing to pick an issue for the same reason means it needs a human decision.

If nothing qualifies, report "no executable work + reasons" and exit.

## 2. Claim (take the mutex)

1. Re-read the issue and comments. If `in-progress` is already present, another session owns it — move to the next candidate.
2. Claim: `gh issue edit <n> --add-label in-progress --add-assignee @me`.
3. Post the repository-defined claim comment; default: `Claimed by Claude Code: <one-line plan>`.
4. Re-read comments after posting. The earliest valid active claim wins. If another claim won, comment that this later claim is withdrawn and move on. Do not remove the shared label or assignee; they now protect the winner.

## 3. Verify premise (re-validate before working)

An issue is a point-in-time record. Re-confirm the body's file:line references and code claims **against current code** before starting. If the description and current code diverge, split by **whether you can point to evidence for the cause** — never invalidate on speculation:

- **Premise gone**: the goal is already achieved or moot, and you can **point to the specific commit/PR/doc** that caused it. Close with `gh issue close <n> --comment "Invalidated (premise gone): <evidence commit/PR>"` — the prefix distinguishes invalidation from resolution, and the cited evidence makes a wrongly-closed issue refutable later; include both.
- **Mismatch**: you only observe that code differs from the description and cannot name the cause (issue error? direction changed midway?). An agent cannot close this — comment the observed difference, remove `in-progress`, unassign, add `needs-decision`.

In both cases no work context has been consumed yet, so **only at this stage** pick one new candidate.

## 4. Plan

1. Collect related code, docs, tests, and adjacent callers based on the issue body.
2. Write a self-contained plan artifact in the active harness's native plan storage, including a copy of the issue body (requirements + current state): implementation and verification must be able to proceed without re-fetching the issue if the network drops mid-work. Also **post a plan summary as an issue comment** — the next session/human must be able to take over from the issue alone.
3. Review plan validity, gaps, and alternatives in a fresh read-only `Fable 5` context. If that exact model is unavailable, use the strongest fresh native reviewer and report the fallback.
4. Re-validate each feedback item on its merits and **accept selectively** (never wholesale), update the plan, proceed.

## 5. Implement

- Run exactly one bounded `Opus 5` implementation Agent. If that exact model is unavailable, use the strongest bounded implementation Agent, preserve the single-writer boundary, and report the fallback.
- Prompt = **frozen spec**: full updated plan + issue requirements + verification commands + the applicable repository rules. The implementation context has no session history — put everything it needs in the prompt.
- When the implementation context is an interactive managed process, use the adapter's required approval mode and preserve that same context across restarts or remediation. Herdr-specific lifecycle handling applies only when Herdr was explicitly selected; follow `skill://herdr-orchestration` in that case.
- An approval mode that suppresses prompts changes interaction only, not scope or authority. An Implementer's frozen prompt must prohibit issue/PR writes, commits, pushes, branch/history changes, destructive or external writes, nested subagents, and self-review; only scoped worktree edits and bounded implementation checks are allowed.
- Every implementation or test change, including remediation after verification or adversarial review, returns to the same implementation context. The orchestrator, Verifier, and Reviewer never edit issue implementation files. If the Implementer cannot be resumed, Hold instead of creating a second writer or patching directly.
- After implementation settles, obtain fresh raw verification evidence. Deterministic tests, lint, builds, and static checks run as supervised processes; a runtime scenario requiring judgment may run in a fresh read-only Verifier. Agent summaries alone do not count: the orchestrator must inspect exact commands, exit codes, raw output, runtime observations, and pre/post tracked state.
- If the working tree is dirty, use a worktree — run the repo's install step right after creating it (e.g. `CI=true pnpm install --frozen-lockfile` for pnpm repos), and note that npm-script wrappers may fail in worktrees; invoke the underlying runner directly if needed.
- Branch: follow the repo's branch conventions; default `<type>/issue-<n>-<slug>` where `<type>` matches the repo's allowed prefixes. **Always branch from the up-to-date default branch**:
  - Before branching, check `git rev-list --count origin/main..main` (after `git fetch`). If the local default branch is **ahead of origin**, those unpushed commits would ride into the PR diff — and pushing the default branch is in the forbidden column, so this is one of the few points where the skill stops to ask: present the unpushed commits and let the user choose (push main first / branch from local main anyway / branch from origin/main). Do not pick silently — if the pending work touches the same files as the issue, the base choice changes what you implement.
  - Normal: `git checkout main && git pull && git checkout -b <branch>`.
  - Worktree: main checkout may be dirty and unable to pull, so `git fetch origin` then `git worktree add --no-track -b <branch> <path> origin/main`. Omitting `--no-track` sets upstream to `origin/main`, which pollutes later pushes.

## 6. DoD + adversarial review gate

1. Run the repo's Definition of Done (if none defined: tests + build + lint green), inspect the raw evidence, complete any required runtime verification, and confirm no verification role changed tracked files; then commit.
2. Run adversarial review in a fresh read-only `Fable 5` context. If that exact model is unavailable, use a fresh native reviewer and report the fallback.
3. BLOCKING findings → re-validate each on its merits, return confirmed implementation/test changes to the same Implementer, rerun every affected automated and runtime gate, commit, and re-review. **Max 2 re-reviews** — if still unresolved, Hold (treat as a design fork).
4. If a required verification or review gate cannot run, Hold. Never create an autonomous PR without both fresh verification evidence and independent review.

## 7. Hold (when human judgment is needed)

Stop immediately and hold when any of these appears — do not advance on speculation:

- Design fork (2+ approaches materially change the outcome and the issue records no decision / BLOCKING unresolved after 2 adversarial re-reviews)
- Policy/product decision (spec interpretation, team consensus needed)
- Unverifiable (no test infrastructure to produce GREEN evidence)
- Scope explosion (actual scope turns out 2x+ the issue after starting)
- Review gate infrastructure failure (Codex cannot run)

Hold procedure:

1. Comment on the issue: **what decision is needed, the options, my recommendation + rationale, progress so far** (including branch name).
2. Release the mutex: remove `in-progress`, unassign. Labels: `needs-decision` if a user decision is needed; **infra failures get no label the first time** (allow next-session retry) — if the same infra-failure comment already exists, add `needs-decision` (ask the user to restore the infra).
3. If there is progress, push the branch to preserve it (no PR).
4. Report the session and **exit** — do not pick a new candidate (unlike §3's re-pick allowance: work context has already been consumed here).

**GitHub write failure (mid-work)**: if an issue write (comment/label/close) fails, retry once, then save the full intended content in the plan file under `## Unposted issue updates` and state it in the user report — the next session's Sweep (§0) posts it. Preserving the trace is the top priority; never discard local results (branch, plan) just because the issue could not be updated.

## 8. Report (completion)

1. Secure verification evidence (actual test/build output — declare "done" only with fresh evidence).
2. Push, then create the PR with `gh pr create` — conventional title per repo convention; **PR body must contain `Closes #<n>`** so the merge auto-closes the issue (this replaces a manual done-transition), plus a note that the adversarial review passed.
3. Comment on the issue: result summary + PR link + verification evidence. Swap labels: remove `in-progress`, add `awaiting-review` — the mutex is released the moment the PR is up. The close happens on merge (auto via `Closes #N`, or the next session's Sweep as fallback).
4. Report to the user: issue number, what/why/how, verification results, review gate results, PR link, what remains.

## Autonomy boundaries

All repo CLAUDE.md/AGENTS.md rules apply (plus personal instruction files if present). Within this skill the user is considered to have pre-approved autonomous execution:

| Allowed (proceed without asking) | Forbidden (never) |
|---|---|
| Local edits, tests, builds, lint | Direct commit/push to the default branch |
| Feature branch creation, commits, push | **Merging** PRs |
| PR creation (body contains `Closes #N`) | Deploys, releases, version tag changes |
| Issue label/assignee/comment/close-with-evidence | Executing shared DB migrations |
| One isolated implementation agent, optional fresh runtime Verifier, and fresh review agents | rebase/force-push/history rewrites |
| | Changes outside the selected issue scope or creation/update of unrelated GitHub Issues |

## Principles

- **One invocation = one work item.** Never chain multiple items (§3's single re-pick after premise-gone/mismatch is the only exception).
- If the issue lacks the basis for a judgment, do not invent one — Hold. Autonomy is for speed, not unilateralism.
- Separation of powers: one agent writes, supervised process panes produce deterministic evidence, an optional fresh Verifier exercises runtime acceptance, fresh Reviewers refute, and the orchestrator adjudicates raw evidence.
- Every issue-related trace (plan, hold reasons, review results, outcomes) goes on the selected issue so the next session or human can take over from it.
- During an Autopilot invocation, do not create or update GitHub Issues for changes that are not directly part of the selected work item, including agent instructions, orchestration guidance, and shared skills. Keep those changes out of the selected issue and PR, and report them separately.
