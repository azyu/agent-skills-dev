---
name: codex-review
description: Use when the user asks for an independent Codex code review or adversarial review of local git changes while working inside a Herdr pane. Runs `codex exec review` in a dedicated sibling pane so the review is watchable live, returns the report, and closes the pane. Replaces the codex@openai-codex plugin's /codex:review and /codex:adversarial-review.
---

# Codex Review in a Herdr Pane

Runs Codex's built-in reviewer as a process in its own Herdr pane. The pane gives live
visibility while the review runs; the report is read from a file, so a long review is
never truncated by pane scrollback. The pane closes on success and stays open on failure.

This is review-only. Do not fix issues, apply patches, or announce upcoming changes.
Return the report verbatim.

## Preconditions

- `HERDR_ENV=1` and `HERDR_PANE_ID` set. Outside Herdr there is no pane to split — run
  `codex exec review --uncommitted` directly in the foreground instead and say that you
  fell back.
- `codex` and `herdr` on `PATH`, and the working directory inside a git repository.

## Run it

```bash
~/.claude/skills/codex-review/scripts/codex-pane-review.sh --uncommitted
```

That path is the skillctl-managed symlink; `skill://` URLs do not resolve in a shell.

The script splits a sibling pane, runs the review, prints the report to stdout, and
closes the pane. Return its stdout verbatim.

Scope — pick one, default `--uncommitted`:

| Flag             | Reviews                                 |
| ---------------- | --------------------------------------- |
| `--uncommitted`  | staged + unstaged + untracked           |
| `--base <ref>`   | changes against a base branch, PR-style |
| `--commit <sha>` | changes introduced by one commit        |

Options: `--mode adversarial` swaps in the challenge-the-design framing from
`references/adversarial-prompt.md`; `--focus "<text>"` appends reviewer instructions;
`--model <name>` overrides the Codex model; `--keep-pane` leaves the pane open;
`--timeout-ms <n>` raises the 15-minute default.

Exit code is Codex's own. On a nonzero exit the script keeps the pane open and prints the
report path on stderr — hand both to the user rather than retrying blindly.

## Three behaviors this script works around

All three were observed directly on 2026-08-11 against codex-cli 0.147.0 and herdr 0.8.0;
none is documented upstream, and code that ignores any of them fails silently or
misleadingly rather than loudly.

**`codex exec review` refuses a PROMPT argument alongside every scope flag** —
`--uncommitted`, `--base` and `--commit` alike, each with
`error: the argument '<flag>' cannot be used with '[PROMPT]'`. So the built-in reviewer
cannot take custom framing at all. A run carrying `--mode adversarial` or `--focus`
therefore goes to plain `codex exec` instead, with the scope restated in prose
(`git show <sha>`, `git diff <base>...HEAD`, or the working-tree commands) so the agent
reads the same diff. Native `--mode review` keeps using `codex exec review`.

**`codex exec` fires SessionStart hooks**, so anything registered there runs against the
review pane. `~/.codex/hooks/herdr-auto-name.sh` used to mint a `$color-$animal` label for
it — a pane labeled `hooktest` came back as `crimson-tapir` after one `codex exec` run.
That hook has since been fixed to claim nothing unless herdr reports an agent occupying the
pane, which a one-shot `codex exec` never is. The script still labels its pane
`codex-review` (or `codex-adversarial`) for readability, and any other SessionStart hook
added later inherits the same exposure.

**`herdr pane wait-output --match` also searches the echoed command line.** A completion
sentinel written intact into the command text matches the moment the command is typed,
before the review starts. The script emits `echo "CODEX""_PANE_DONE rc=$?"`, so the marker
exists only in the output, never in the echoed command.

## Relationship to the codex plugin

Supersedes `/codex:review` and `/codex:adversarial-review` from the `codex@openai-codex`
plugin, which run `codex-companion.mjs` headlessly and track background runs through their
own broker. The pane replaces that job tracking — there is no `/codex:status` equivalent
here, because the run is visible in the pane and the call is synchronous.

Reviewing code that Codex itself wrote with this skill alone is self-review; get a second
reviewer for that case.
