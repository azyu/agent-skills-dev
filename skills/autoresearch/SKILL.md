---
name: autoresearch
description: >-
  Autonomous benchmark-driven experiment loop (port of oh-my-pi's autoresearch).
  Use when the user asks to iteratively optimize a measurable metric — performance,
  latency, memory, bundle size, test duration, accuracy — through repeated
  change→measure→keep/discard cycles. Triggers: "autoresearch", "실험 루프",
  "자율 실험", "벤치마크 돌면서 최적화", "성능 실험", "experiment loop",
  "optimize until", "keep iterating on the benchmark". Do NOT use for one-off
  profiling or a single benchmark run — reserve for multi-iteration optimization
  with an objective metric.
---

# Autoresearch — autonomous experiment loop

Run a disciplined optimization loop: build a deterministic benchmark harness once,
then iterate change → measure → log honestly, with git-backed keep/revert and a
state file that survives context compaction.

All session mechanics go through one script (referred to as `$AR` below):

```bash
AR=~/.claude/skills/autoresearch/scripts/ar-ctl.sh
```

Requirements: a git repository, `jq`. The script always operates on the repo root
of the current directory.

**Safety property**: `init` moves work onto a dedicated `autoresearch/*` branch and
commits a baseline snapshot. Non-keep logs run `git reset --hard` + `git clean -fd`
— this is why the dedicated branch is non-negotiable. Never run a session on a
branch with unrelated uncommitted work; never push `autoresearch/*` branches.

## Phase 1 — build the harness (no session yet)

Your job first is to **build the benchmark harness**, not to optimize anything.

1. Inspect the target. Read source, identify what to measure, decide on the workload.
2. Write `./autoresearch.sh` at the repo root. Contract:
   - exit 0 on success, non-zero on failure;
   - print the primary metric as a single line `METRIC <name>=<value>`;
   - print secondary metrics as additional `METRIC <name>=<value>` lines;
   - deterministic every run: no live network, no time-of-day dependence, fixed seeds.
3. Validate it yourself with plain Bash: `bash autoresearch.sh` must exit 0 and emit
   at least one `METRIC` line. Iterate on the harness until it does.
   A compile-only check is NOT a benchmark — the harness must execute the workload.
4. Open the session:

```bash
$AR init --goal "reduce cold-start latency of svc X" \
         --metric wall_ms --direction min \
         --scope apps/x/src --off-limits autoresearch.sh \
         --max-iter 15
```

`--metric` must match the `METRIC` name printed by the harness. `--direction`
declares whether bigger (`max`) or smaller (`min`) is better — best/baseline math
depends on it. If the user gave no explicit goal, infer it from their request and
record it via `--goal`.

5. Establish the baseline before touching code: `$AR run`, then
   `$AR log keep --desc "baseline"`.

## Phase 2 — the iteration loop

Repeat until the iteration cap is hit, the goal is met, or the user interrupts:

1. **Start every iteration with `$AR status`.** Its output — not your memory — is
   the source of truth for goal, scope, run history, and notes. This matters most
   after context compaction.
2. Design ONE coherent experiment. Change the code.
3. `$AR run` — executes `bash autoresearch.sh` (fixed command, default timeout
   600s, override with `--timeout N`), captures output to
   `.autoresearch/runs/<n>/output.log`, parses `METRIC`/`ASI` lines.
4. Log honestly with `$AR log <status> --desc "..."`:
   - `keep` — primary metric improved → modified files are auto-committed;
   - `discard` — regressed or flat → worktree reverted;
   - `crash` — the run failed → worktree reverted;
   - `checks_failed` — correctness validation failed → worktree reverted.
     You decide what validation means; run it through plain Bash before logging.
5. Record learnings in `.autoresearch/notes.md` (edit the file directly — playbook
   at the top, ideas backlog below). `status` prints it back every iteration.
6. When confidence is low, re-run a promising change before keeping it and compare
   the two values yourself — a delta smaller than run-to-run noise is not a win.

### ASI (auxiliary state injection)

Any `ASI key=value` line the harness prints is stored on the run and echoed back
by `status`. Use it freely to stash structured learnings (`hypothesis=...`,
`rollback_reason=...`, `next_action_hint=...`).

### Scope and accountability

- Edits are not blocked, but files outside `--scope` (or inside `--off-limits`)
  are recorded as scope deviations on the run.
- Keeping a deviating run requires `--justification "..."` — without it the run is
  marked UNJUSTIFIED and `status` nags until you justify, accept, or flag it.
- A run that later looks reward-hacked or measured wrong:
  `$AR flag <run_number> --reason "..."` — flagged runs are excluded from
  baseline/best calculations.

### Segments

`autoresearch.sh` is part of the baseline — NEVER edit it mid-segment, since that
makes metric values incomparable (`run` warns on checksum mismatch). To change the
harness intentionally: edit it, then `$AR init --new-segment`, then re-establish a
baseline run. Reconfigure goal/scope/cap without a segment bump via plain
`$AR init --goal ... / --scope ... / --max-iter ...`.

### Stopping

- The script refuses `run` past `--max-iter` per segment. When the cap is reached,
  stop and report; only raise it if the user asked for more.
- On stop (cap, goal met, or diminishing returns), report: baseline vs best metric,
  what was kept (commits are on the `autoresearch/*` branch), what was tried and
  discarded, and the surviving hypotheses from notes.
- The kept result stays on the experiment branch — the user decides what to
  cherry-pick or re-implement cleanly for a real PR. Never push the branch.
- `$AR clear` closes the session keeping the tree; `--reset-to-baseline` also
  discards kept commits.

## Guardrails

- NEVER game the benchmark. NEVER overfit to synthetic inputs when the real
  workload is broader. MUST preserve correctness.
- One experiment per iteration — no batched unrelated changes.
- Log every run, including embarrassing ones. `run` refuses to start while a
  pending run is unlogged.
- If the user sends a new message mid-loop, finish the current run+log cycle
  first, then address it.

## Command reference

| Command                                                                                           | Purpose                                              |
| ------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `$AR init --goal G --metric M --direction min\|max [--scope a,b] [--off-limits c] [--max-iter N]` | open session (branch + baseline snapshot)            |
| `$AR init [--goal/--scope/--max-iter ...]`                                                        | reconfigure without segment bump                     |
| `$AR init --new-segment`                                                                          | commit current tree as a new baseline segment        |
| `$AR run [--timeout N]`                                                                           | run `bash autoresearch.sh`, parse METRIC/ASI         |
| `$AR log keep\|discard\|crash\|checks_failed --desc "..." [--justification "..."]`                | record + commit/revert                               |
| `$AR flag <run#> --reason "..."`                                                                  | exclude a suspect run from the math                  |
| `$AR status`                                                                                      | snapshot block — run at the start of every iteration |
| `$AR clear [--reset-to-baseline]`                                                                 | close the session                                    |

State layout (repo root, kept out of git via `.git/info/exclude`):
`.autoresearch/session.json` (config), `runs.jsonl` (history),
`pending.json` (unlogged run), `notes.md` (playbook), `runs/<n>/output.log`.
