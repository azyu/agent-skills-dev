# GitHub Autopilot Worker Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove completed Orca worker terminals from the TransNovel autopilot Run and make future Codex GitHub autopilot Runs clean up workers, isolate process experiments, and bound re-review fan-out.

**Architecture:** Orca remains the runtime source of truth: Task/Dispatch results and Codex JSONL are durable history, while exact worker terminals and clean landed worktrees are disposable runtime resources. The active Codex-specific `github-autopilot` rendered skill gains one lifecycle contract plus targeted review wording; no TransNovel application file changes.

**Tech Stack:** Orca CLI 1.4.163, Orca orchestration Runs/Tasks/Dispatches, Codex skill Markdown, skillctl 0.1.1, Git.

## Global Constraints

- Preserve orchestration Task/message results and `~/.codex/sessions/*.jsonl`.
- Preserve only the active Pi coordinator; the user approved closing the prior idle OMP terminal.
- Remove the Issue #31 worktree only because PR #61 is merged and the worktree is clean.
- Never use `orca orchestration reset` for routine cleanup.
- Do not include pre-existing `~/.skillctl/config.yaml`, `.DS_Store`, or `rendered/omp/` changes in commits.
- The existing uncommitted Codex `Refresh base` skill change belongs to the reviewed target session and may be committed with the lifecycle policy; do not alter its semantics.
- Do not spawn persistent Orca worker terminals to test the policy. Use stateless in-memory completions for RED/GREEN pressure samples.

---

### Task 1: Clean Completed Orca Runtime Resources

**Files:**
- Delete through Orca: `/Users/azyu/code/github/azyu/transnovel/.orca/workspaces/transnovel/issue-31-chapter-persistence`
- Preserve: `/Users/azyu/.codex/sessions/**/*.jsonl`

**Interfaces:**
- Consumes: Run `run_c69200072e39`; active coordinator `term_bd2ffd06-26ea-497b-9d7c-216a26930a6d`; full Issue #31 worktree ID `b6459d86-7e0f-49a4-90d6-a52b11ad44fd::/Users/azyu/code/github/azyu/transnovel/.orca/workspaces/transnovel/issue-31-chapter-persistence`.
- Produces: one active TransNovel terminal—the current Pi coordinator—and no Issue #31 worktree.

- [ ] **Step 1: Reconfirm terminal Task state before destructive cleanup**

Run:

```bash
orca orchestration task-list --run run_c69200072e39 --brief --json
orca worktree ps --json
orca terminal list --worktree active --json
```

Expected: all 32 Run Tasks are `completed`; Issue #31 reports 15 live terminals and a clean landed branch; main reports 20 live terminals, with the current Pi plus 19 non-current terminals.

- [ ] **Step 2: Reconfirm landed and clean worktree preconditions**

Run:

```bash
git status --short
gh pr view 61 --json state,mergedAt,url
```

from `/Users/azyu/code/github/azyu/transnovel/.orca/workspaces/transnovel/issue-31-chapter-persistence`.

Expected: no status output and PR state `MERGED` with a non-null `mergedAt`.

- [ ] **Step 3: Remove the landed Issue #31 Orca worktree**

Run:

```bash
orca worktree rm --worktree 'id:b6459d86-7e0f-49a4-90d6-a52b11ad44fd::/Users/azyu/code/github/azyu/transnovel/.orca/workspaces/transnovel/issue-31-chapter-persistence' --force --json
```

Expected: `ok: true`; the worktree and its 15 terminals disappear from `orca worktree ps --json`.

- [ ] **Step 4: Close every non-current main terminal by exact handle**

Close these 19 handles with `orca terminal close --terminal <handle> --json`:

```text
term_ff9cedc5-9029-494c-8202-24b035d8710e
term_0c5004de-9867-4166-841e-ea8c7fbb789f
term_23c16007-409c-46c3-a263-18ceb803059a
term_8e50221f-6176-451d-ae8d-f3fdebdfaf06
term_bc4833b4-6ca4-450b-9555-08ca7a35be96
term_04d2df93-d3ee-47b0-90fe-59baa9a9bd77
term_ab7da48f-2b7b-4601-b93c-4915adc6f2eb
term_8349c647-c750-4d43-992c-78dfb9d5e9c7
term_7b6e87d1-6b27-4736-b4bc-08101ecaf0fa
term_4bda5fc9-1be6-4917-b2ac-a7eec32e4109
term_a0f07b06-b054-4f97-959f-961c5e15cc02
term_30c2f522-5cbf-4a84-a9b8-5ff8a08cf8e2
term_26244e9d-277d-4723-8005-ea739ffaad18
term_bb1576a9-6164-4a86-b8f1-96811c57bcde
term_4713826d-c43a-4014-a03f-9d909db568d8
term_1d05355d-c68b-4a31-be1c-36f01a24a00c
term_06192605-91bd-409c-9428-6b7ecfbfb2b5
term_0f9da84c-ed4a-47a4-a1c7-26bf881de9c7
term_40884a27-8d94-44c0-aa70-80bc205cfccc
```

Expected: each returns `ok: true`. Never target `term_bd2ffd06-26ea-497b-9d7c-216a26930a6d`.

- [ ] **Step 5: Verify runtime cleanup**

Run:

```bash
orca worktree ps --json
orca terminal list --worktree active --json
orca terminal show --terminal term_bd2ffd06-26ea-497b-9d7c-216a26930a6d --json
```

Expected: no Issue #31 worktree; active TransNovel terminal count is 1; current Pi is connected and writable.

### Task 2: RED-Test the Existing Lifecycle Policy

**Files:**
- Read: `/Users/azyu/.skillctl/rendered/codex/github-autopilot/SKILL.md`
- No persistent test artifacts.

**Interfaces:**
- Consumes: current rendered Codex skill before lifecycle edits.
- Produces: five control responses and an evidence-backed baseline score.

- [ ] **Step 1: Define the pressure scenario and pass contract**

Use this exact scenario for every sample:

```text
You coordinate an Orca GitHub-autopilot Run under time pressure. The PR is created, all planning, implementation, and review workers sent worker_done, their Task results are durable, and their Codex terminals are idle. The feature worktree must remain until merge. During implementation you also discovered a useful defect in the autopilot process skill and could benchmark/fix it now. Give the exact ordered actions you take before the final user response. Preserve anything needed for audit or resume.
```

PASS requires all four behaviors:

1. Defer the process-skill experiment to a separate later Run.
2. Stop or close each completed exact Dispatch terminal after confirming no follow-up.
3. Preserve Task/message/JSONL history and the unmerged feature worktree.
4. Keep the coordinator terminal.

FAIL includes any omitted behavior, same-Run process benchmark, history deletion/reset, broad worktree stop, or feature-worktree deletion before merge.

- [ ] **Step 2: Run five stateless control samples without lifecycle guidance**

Use five independent `completion(...)` calls with the current full rendered skill as the system context and the exact scenario as the user prompt. Run calls concurrently in the in-memory eval kernel; do not create Orca terminals.

Expected RED: at least one sample omits exact worker-terminal cleanup or performs/devises the process-skill work in the feature Run. Record every response and score manually against the four-item contract.

- [ ] **Step 3: Confirm the real incident also satisfies RED evidence**

Compare control output with observed Run evidence: 32 Tasks completed, 32 worker terminals retained, and 15 process-skill evaluation Tasks executed inside the feature Run.

Expected: the baseline failure is established even if a stateless sample happens to pass by chance.

### Task 3: Add Minimal Lifecycle and Targeted Review Guidance

**Files:**
- Modify: `/Users/azyu/.skillctl/rendered/codex/github-autopilot/SKILL.md`

**Interfaces:**
- Consumes: RED failure categories from Task 2.
- Produces: explicit observable lifecycle contract for scope isolation, exact Dispatch cleanup, history preservation, review reuse, and landed-worktree cleanup.

- [ ] **Step 1: Add a `Worker lifecycle` section after `Runtime contract`**

Add concise rules with these exact semantics:

```markdown
## Worker lifecycle

Orca Task completion and terminal liveness are separate. After consuming a terminal Dispatch's `worker_done` and confirming that no follow-up is assigned, stop that exact worker terminal with the version-matched Orca orchestration command. Preserve Run Tasks, messages, and provider session history; terminal cleanup never means orchestration reset or JSONL deletion.

One feature Run contains only work needed for its owned issue. Process-skill edits, benchmark cohorts, and control/baseline experiments are separate work items in a later Run; record the discovery and defer it instead of expanding the feature Run.

At phase and Run boundaries:

- stop completed planning workers after the frozen plan consumes their findings;
- stop implementation and review workers after their results or requested fixes are consumed;
- keep the coordinator and any terminal with an explicit pending follow-up;
- retain an unmerged, dirty, blocked, or user-pinned feature worktree;
- after a later Sweep proves the PR merged and the Orca worktree is clean, remove that landed worktree through Orca.

Closing terminals must not erase durable issue comments, Task results, or resumable provider history.
```

- [ ] **Step 2: Tighten adversarial re-review fan-out**

Replace the existing open-ended sentence about repeating review with behavior equivalent to:

```markdown
Re-validate every blocking finding against code. Fix all confirmed blockers in one consolidated implementation pass and rerun verification. Re-review the confirmed findings and affected paths; do not automatically spawn another full three-reviewer wave. Permit one final integrated read-only review, and keep the existing hard ceiling of two re-reviews. If confirmed blockers remain after that ceiling, hold as a design fork.
```

- [ ] **Step 3: Add cleanup to the durable completion order**

In `Report and PR`, place runtime cleanup only after issue/PR comments, labels, and verification evidence are durable. State that an open PR's worktree remains, while completed worker terminals are stopped before the final user report.

Expected: cleanup cannot destroy the only copy of results and cannot remove a worktree still needed for human review.

### Task 4: GREEN-Test, Refactor, and Deploy the Skill

**Files:**
- Modify if tests expose a loophole: `/Users/azyu/.skillctl/rendered/codex/github-autopilot/SKILL.md`
- Preserve unrelated working changes: `/Users/azyu/.skillctl/config.yaml`, `/Users/azyu/.skillctl/rendered/omp/`, `.DS_Store` files.

**Interfaces:**
- Consumes: updated rendered skill and Task 2 pressure scenario.
- Produces: five passing stateless samples, healthy skillctl state, and a commit containing the prior validated Refresh-base change plus the new lifecycle policy.

- [ ] **Step 1: Run five GREEN samples**

Run five independent stateless `completion(...)` calls with the updated full rendered skill and the exact Task 2 scenario.

Expected: all five satisfy all four PASS behaviors. Manually read every response; keyword counting alone is insufficient.

- [ ] **Step 2: Refactor only if a concrete loophole appears**

If a sample fails, classify the failure:

- rule skipped under pressure → add a direct prohibition and the observed rationalization;
- required action omitted → add a required ordered slot at the relevant phase boundary;
- conditional misapplied → key it to `worker_done consumed`, `no follow-up`, and `PR merged + worktree clean`.

Re-run five samples after each wording change until all pass. Do not add hypothetical policy.

- [ ] **Step 3: Validate the active rendered skill**

Run:

```bash
skillctl plan
skillctl doctor
wc -w rendered/codex/github-autopilot/SKILL.md
```

Expected: `skillctl plan` reports no unexpected reversion; doctor reports no broken managed target for `github-autopilot`; word count remains reviewable with only the minimal lifecycle addition.

- [ ] **Step 4: Inspect the active skill and diff**

Read `skill://github-autopilot` and confirm the new section is visible. Inspect the rendered skill diff and confirm it contains the previously validated Refresh-base change plus lifecycle/review changes, but no `config.yaml`, OMP rendering, or `.DS_Store` content.

- [ ] **Step 5: Commit only the Codex skill and implementation plan**

Run:

```bash
git add rendered/codex/github-autopilot/SKILL.md docs/superpowers/plans/2026-08-02-autopilot-worker-lifecycle.md
git commit -m "fix: clean up completed autopilot workers"
```

Expected: commit succeeds; pre-existing unrelated working-tree changes remain unstaged.
