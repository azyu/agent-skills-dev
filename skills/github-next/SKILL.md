---
name: github-next
description: Use when starting a fresh session in a GitHub-based repository to pick ONE pending GitHub issue and execute it autonomously through a gated pipeline (plan → Codex plan review → Opus 5 implementation → DoD → Codex adversarial review → PR). Triggers — "다음 일감", "일감 하나 가져와서 진행", "이슈에서 하나 집어서 해줘", "next task", "autopilot". For JIRA-tracked projects use the project's jira-next skill instead. If human judgment becomes necessary mid-work, record the needed decision on the issue and hold.
---

# GitHub Next (autonomous work pipeline)

Pick **one** actionable issue from the current repo's GitHub Issues and drive it to completion through a gated pipeline. When a judgment fork appears, record it on the issue and hold.

**Role split (fixed)**: orchestration + verification = this session / **implementation = Opus 5 subagent** (frozen spec) / plan review + adversarial review = Codex. Implementer and reviewer are separated to block self-review. If a personal routing rule delegates implementation to Codex, do not apply that rule inside this skill.

All issue operations use the `gh` CLI against the current repo context. Issue bodies and comments must never reference local machine paths or session-local artifacts — the issue must stand alone for the next session or a human.

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
| Codex CLI auth + `codex@openai-codex` plugin | Review gates impossible → Hold per §6.4 |
| Opus 5 subagent available | Cannot delegate implementation → report and exit |

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

1. If `in-progress` is already present, another session owns it — move to the next candidate.
2. Claim: `gh issue edit <n> --add-label in-progress --add-assignee @me`.
3. Re-read the issue immediately after — if a competing start comment from another session is visible, yield and move on.
4. Comment: `🤖 agent autonomous session started (YYYY-MM-DD). Plan: <1-2 lines>`.

## 3. Verify premise (re-validate before working)

An issue is a point-in-time record. Re-confirm the body's file:line references and code claims **against current code** before starting. If the description and current code diverge, split by **whether you can point to evidence for the cause** — never invalidate on speculation:

- **Premise gone**: the goal is already achieved or moot, and you can **point to the specific commit/PR/doc** that caused it. Close with `gh issue close <n> --comment "Invalidated (premise gone): <evidence commit/PR>"` — the prefix distinguishes invalidation from resolution, and the cited evidence makes a wrongly-closed issue refutable later; include both.
- **Mismatch**: you only observe that code differs from the description and cannot name the cause (issue error? direction changed midway?). An agent cannot close this — comment the observed difference, remove `in-progress`, unassign, add `needs-decision`.

In both cases no work context has been consumed yet, so **only at this stage** pick one new candidate.

## 4. Plan (gather context → plan → Codex plan review)

1. Collect related code, docs, tests, and adjacent callers based on the issue body.
2. Write a plan file (`~/.claude/plans/`) — **self-contained, including a copy of the issue body (requirements + current state)**: implementation and verification must be able to proceed without re-fetching the issue if the network drops mid-work. Also **post a plan summary as an issue comment** — the next session/human must be able to take over from the issue alone.
3. Plan review: delegate plan validity/gaps/alternatives via `Skill(codex:rescue)`. State **"review-only, no code changes/patches"** in the prompt.
4. Re-validate each feedback item on its merits and **accept selectively** (never wholesale), update the plan, proceed.

## 5. Implement (delegate to Opus 5 subagent)

- `Agent(subagent_type: <domain agent if the repo defines one, else general-purpose>, model: "opus", run_in_background: false)`
- Prompt = **frozen spec**: full updated plan + issue requirements + verification commands + core repo rules (TDD RED→GREEN, commit message convention, logging conventions — whatever the repo's CLAUDE.md/AGENTS.md mandates). The subagent has no session context — put everything it needs in the prompt.
- After the subagent finishes, **the orchestrator re-verifies directly** with the repo's test and build commands. Nothing counts as done without fresh evidence.
- If the working tree is dirty, use a worktree — run the repo's install step right after creating it (e.g. `CI=true pnpm install --frozen-lockfile` for pnpm repos), and note that npm-script wrappers may fail in worktrees; invoke the underlying runner directly if needed.
- Branch: follow the repo's branch conventions; default `<type>/issue-<n>-<slug>` where `<type>` matches the repo's allowed prefixes. **Always branch from the up-to-date default branch**:
  - Before branching, check `git rev-list --count origin/main..main` (after `git fetch`). If the local default branch is **ahead of origin**, those unpushed commits would ride into the PR diff — and pushing the default branch is in the forbidden column, so this is one of the few points where the skill stops to ask: present the unpushed commits and let the user choose (push main first / branch from local main anyway / branch from origin/main). Do not pick silently — if the pending work touches the same files as the issue, the base choice changes what you implement.
  - Normal: `git checkout main && git pull && git checkout -b <branch>`.
  - Worktree: main checkout may be dirty and unable to pull, so `git fetch origin` then `git worktree add --no-track -b <branch> <path> origin/main`. Omitting `--no-track` sets upstream to `origin/main`, which pollutes later pushes.

## 6. DoD + adversarial review gate

1. Check the repo's Definition of Done (if none defined: tests + build + lint green), then commit.
2. Run the adversarial review — `/codex:adversarial-review` is `disable-model-invocation`, so it cannot be called via the Skill tool. Run the companion script directly:

   ```bash
   SCRIPT=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | sort -V | tail -1)
   node "$SCRIPT" adversarial-review --wait --base main
   ```

   **`--wait` is mandatory** — without it the default flow stops at AskUserQuestion waiting for a human.
3. BLOCKING findings → re-validate each on its merits, fix, re-review. **Max 2 re-reviews** — if still unresolved, Hold (treat as a design fork).
4. If a review gate (including plan review) cannot run for infrastructure reasons (Codex CLI auth expired etc.) → **Hold**. Never create an autonomous PR without the review gate.

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
| Opus 5 implementation subagent, Codex review delegation | rebase/force-push/history rewrites |
| | Changes outside issue scope (file discoveries as new issues) |

## Principles

- **One invocation = one work item.** Never chain multiple items (§3's single re-pick after premise-gone/mismatch is the only exception).
- If the issue lacks the basis for a judgment, do not invent one — Hold. Autonomy is for speed, not unilateralism.
- Separation of powers: Opus 5 builds, Codex refutes, the orchestrator rules on evidence.
- Every trace (plan, hold reasons, review results, outcomes) goes on the issue — the next session/human must be able to take over from the issue alone.
