#!/bin/bash
# Run `codex exec review` inside a dedicated Herdr pane, print the report, close the pane.
#
# The pane exists for live visibility: the reviewer's progress is watchable while the
# calling agent stays free. The report itself is read from the -o file, not scraped from
# the terminal, so a long review cannot be truncated by pane scrollback.
set -uo pipefail

MODE=review
SCOPE_KIND=""
SCOPE_REF=""
FOCUS=""
KEEP_PANE=0
TIMEOUT_MS=900000
MODEL=""

usage() {
  cat <<'USAGE'
Usage: codex-pane-review.sh [options]

Scope (default --uncommitted):
  --uncommitted           staged + unstaged + untracked
  --base <ref>            changes against a base branch
  --commit <sha>          changes introduced by one commit

Options:
  --mode review|adversarial   review framing (default: review)
  --focus "<text>"            extra reviewer instructions
  --model <name>              codex model override
  --timeout-ms <n>            pane wait timeout (default: 900000)
  --keep-pane                 leave the pane open even on success
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:?--mode needs a value}"; shift 2 ;;
    --uncommitted) SCOPE_KIND=uncommitted; shift ;;
    --base) SCOPE_KIND=base; SCOPE_REF="${2:?--base needs a ref}"; shift 2 ;;
    --commit) SCOPE_KIND=commit; SCOPE_REF="${2:?--commit needs a sha}"; shift 2 ;;
    --focus) FOCUS="${2:?--focus needs text}"; shift 2 ;;
    --model) MODEL="${2:?--model needs a name}"; shift 2 ;;
    --timeout-ms) TIMEOUT_MS="${2:?--timeout-ms needs a number}"; shift 2 ;;
    --keep-pane) KEEP_PANE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in
  review|adversarial) ;;
  *) echo "--mode must be review or adversarial" >&2; exit 2 ;;
esac
[ -n "$SCOPE_KIND" ] || SCOPE_KIND=uncommitted

die() { echo "$*" >&2; exit 1; }
[ "${HERDR_ENV:-}" = "1" ] || die "not running inside Herdr (HERDR_ENV != 1); run 'codex exec review' directly instead"
[ -n "${HERDR_PANE_ID:-}" ] || die "HERDR_PANE_ID is unset; cannot split a sibling pane"
command -v herdr >/dev/null 2>&1 || die "herdr not found in PATH"
command -v codex >/dev/null 2>&1 || die "codex not found in PATH"
git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$SCOPE_KIND" in
  uncommitted)
    SCOPE_ARGS=(--uncommitted)
    SCOPE_PROSE='the uncommitted changes in this repository: inspect `git status --short --untracked-files=all`, `git diff`, `git diff --cached`, and read any untracked files in full'
    ;;
  base)
    SCOPE_ARGS=(--base "$SCOPE_REF")
    SCOPE_PROSE="the changes this branch introduces against \`$SCOPE_REF\`: \`git diff $SCOPE_REF...HEAD\`"
    ;;
  commit)
    SCOPE_ARGS=(--commit "$SCOPE_REF")
    SCOPE_PROSE="the changes introduced by commit \`$SCOPE_REF\`: \`git show $SCOPE_REF\`"
    ;;
esac

PROMPT=""
if [ "$MODE" = adversarial ]; then
  PROMPT="$(cat "$SKILL_DIR/references/adversarial-prompt.md")"
fi
if [ -n "$FOCUS" ]; then
  PROMPT="${PROMPT:+$PROMPT

}## Reviewer focus

$FOCUS"
fi

# `codex exec review` rejects a PROMPT argument alongside EVERY scope flag — --uncommitted,
# --base and --commit alike (verified against codex-cli 0.147.0). So a run that carries
# custom framing cannot use the built-in reviewer at all: it goes to plain `codex exec`,
# with the scope restated in prose so the agent reads the same diff. Scoping stays explicit
# either way; only the harness differs.
if [ -n "$PROMPT" ]; then
  PROMPT="Review $SCOPE_PROSE.

$PROMPT"
fi

OUT_DIR="${TMPDIR:-/tmp}/codex-pane-review"
mkdir -p "$OUT_DIR"
# Not mktemp: BSD mktemp only substitutes a template ending in X, so "report-XXXXXX.md"
# is taken literally and concurrent runs would overwrite one shared file.
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
OUT_FILE="$OUT_DIR/report-$RUN_ID.md"
: >"$OUT_FILE"
PROMPT_FILE=""
if [ -n "$PROMPT" ]; then
  PROMPT_FILE="$OUT_DIR/prompt-$RUN_ID.md"
  printf '%s\n' "$PROMPT" >"$PROMPT_FILE"
fi

jget() { python3 -c 'import json,sys;
d = json.load(sys.stdin).get("result") or {}
for k in sys.argv[1].split("."):
    d = (d or {}).get(k) or {}
print(d if isinstance(d, str) else "")' "$1"; }

PANE_ID="$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | jget pane.pane_id)"
[ -n "$PANE_ID" ] || die "herdr pane split returned no pane id"

# The label must match ^[a-z]+-[a-z]+$ so the herdr auto-name SessionStart hook
# (~/.codex/hooks/herdr-auto-name.sh) takes its reuse branch. `codex exec` fires that
# hook, and against any other label it overwrites the label with a minted $color-$animal.
LABEL="codex-review"
[ "$MODE" = adversarial ] && LABEL="codex-adversarial"
herdr pane rename "$PANE_ID" "$LABEL" >/dev/null

cleanup_pane() {
  if [ "$KEEP_PANE" = 0 ]; then
    herdr pane close "$PANE_ID" >/dev/null 2>&1
  else
    echo "(pane $PANE_ID left open)" >&2
  fi
}

if [ -n "$PROMPT_FILE" ]; then
  # -s read-only enforces the review-only contract: plain `codex exec` otherwise inherits
  # this machine's danger-full-access default, letting a "reviewer" mutate the worktree.
  # It constrains model-generated shell commands only; the CLI still writes -o itself.
  CMD=(codex exec -s read-only -o "$OUT_FILE")
else
  CMD=(codex exec review "${SCOPE_ARGS[@]}" -o "$OUT_FILE")
fi
[ -n "$MODEL" ] && CMD+=(-m "$MODEL")
[ -n "$PROMPT_FILE" ] && CMD+=(-)  # `codex exec -` reads the prompt from stdin

RUN_LINE="$(printf '%q ' "${CMD[@]}")"
[ -n "$PROMPT_FILE" ] && RUN_LINE="$RUN_LINE < $(printf '%q' "$PROMPT_FILE")"
# Split the sentinel literal: `herdr pane wait-output` also searches the echoed command
# line, so an intact marker in the command text matches before the review even starts.
RUN_LINE="$RUN_LINE; echo \"CODEX\"\"_PANE_DONE rc=\$?\""

herdr pane run "$PANE_ID" "$RUN_LINE" >/dev/null || { cleanup_pane; die "herdr pane run failed"; }

MATCHED="$(herdr pane wait-output "$PANE_ID" --match "CODEX_PANE_DONE" --timeout "$TIMEOUT_MS" | jget matched_line)"
if [ -z "$MATCHED" ]; then
  KEEP_PANE=1
  cleanup_pane
  die "review did not finish within ${TIMEOUT_MS}ms; pane $PANE_ID kept open for inspection"
fi

RC="${MATCHED##*rc=}"
RC="${RC%%[![:digit:]]*}"
[ -n "$RC" ] || RC=1

if [ -s "$OUT_FILE" ]; then
  cat "$OUT_FILE"
else
  echo "codex produced no report (exit $RC). Last pane output:" >&2
  herdr pane read "$PANE_ID" --source recent-unwrapped --lines 60 >&2
fi

[ "$RC" = 0 ] || KEEP_PANE=1
cleanup_pane
echo >&2 "report: $OUT_FILE (codex exit $RC)"
exit "$RC"
