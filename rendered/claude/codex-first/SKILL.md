---
name: codex-first
description: "Route implementation work to Codex CLI as the Executor; Claude (Fable) plans, specs, orchestrates, reviews, verifies. Use when about to write/modify code, implement a spec, fix a bug with known repro, write tests, or do mechanical refactors/migrations."
---

# Codex First (Codex = Executor)

Claude Code sessions only. Codex/other harnesses: skip; never self-delegate.

Rationale: Claude (Fable/Opus) tokens metered + expensive; Codex flat-rate. GPT-5.5+ is usually the better and faster model at writing/implementing code; Claude wins at ergonomics — judgment, design, spec-writing, review, orchestration. So Codex types, Claude thinks and verifies.

## Route

Delegate to Codex (default Executor for hands-on work):

- implementation from a frozen spec; refactors; mechanical migrations
- bug fixes with known repro; test writing; coverage fills
- CI fixes, dependency bumps, scripts/tooling
- bulk codebase exploration where raw reading ≫ the answer

Keep in Claude (Fable):

- design, API design, architecture, naming, UX judgment
- tasks where writing the spec IS the work (ambiguity = design)
- tiny edits (~<20 lines, single obvious change) — delegation overhead loses
- anything needing session tools: MCP, secrets, session-scoped credentials
- destructive/irreversible ops, releases, pushes, PR creation, GitHub/Bitbucket mutations
- review of Codex output — never delegated, never skipped

Subagent roles under this policy:

- `fast-worker` (Sonnet) is NOT an implementation executor anymore. Use it only for parallel subtasks that require live session context (e.g. task execution inside superpowers:subagent-driven-development).
- `/codex:rescue` stays for one-shot handoffs when Claude is stuck; `/codex:review` stays for independent second opinions on Claude-authored code.
- Review independence: code that Codex wrote must NOT be reviewed by `/codex:review` alone (self-review). Claude reviews the diff + run `/code-review:code-review`.

Mixed task: Claude designs first, freezes spec, delegates build-out.
Heuristic: prompt reads as a work order → delegate; writing it forces decisions → design, Claude.

## Invoke

Prompt via temp file, never inline quoting:

```bash
P=$(mktemp); cat >"$P" <<'EOF'
<goal, repo + key paths, constraints ("don't touch X"), non-goals, proof expected, output shape>
EOF
codex exec -s workspace-write -C <repo> \
  -c model_reasoning_effort="xhigh" \
  -o "$SCRATCHPAD/codex-last.md" - <"$P" 2>/dev/null
```

- `-s workspace-write` is the house default — repo writes + command/test runs allowed. Network is already enabled for this mode via `[sandbox_workspace_write] network_access = true` in `~/.codex/config.toml`, so `pnpm install` etc. work. Passing `-s` explicitly matters: the global config default is `danger-full-access`, and this flag tightens it per-run.
- `--dangerously-bypass-approvals-and-sandbox` (full bypass) only with explicit user approval.
- `$SCRATCHPAD` = the session scratchpad dir from the system prompt; one `-o` file per run.
- stderr suppressed (thinking noise bloats context); drop `2>/dev/null` only to debug a failing run
- read the `-o` file for the result; don't parse the JSONL stream
- long runs: Bash `run_in_background`, read the `-o` file on exit; don't kill quiet runs <30 min
- parallel independent tasks OK: separate repos/dirs, separate `-o` files
- outside a git repo add `--skip-git-repo-check`

Follow-up fixes — cheaper than fresh runs, keeps context. `resume` has no `-C`/`-s` flags: run from the repo dir, pass sandbox as a config override:

```bash
(cd <repo> && codex exec resume --last \
  -c sandbox_mode="workspace-write" \
  -c model_reasoning_effort="xhigh" \
  -o "$SCRATCHPAD/codex-last.md" - <"$P2" 2>/dev/null)
```

## Prompt contract

Codex starts with zero session context. Every prompt: goal, exact repo/paths, constraints, non-goals, proof expected (exact test command), output shape ("report files changed + test output"). Spec quality decides success. The `codex:gpt-5-4-prompting` skill has model-specific prompt guidance.

## Verify (Claude, always)

- `git status -sb` + read the full diff; judge like a contributor PR
- run focused tests yourself or demand proof output; Codex claims are advisory
- iterate via resume; after 2 failed rounds, take over and do it directly
- the project's own post-change verification order (e.g. "After Code Changes" in CLAUDE.local.md) still applies on top of this

## Economics

Win = generation + exploration tokens moved to Codex; Claude spends only on spec + diff review. Don't ping-pong trivia through delegation; don't re-read what Codex already summarized.
