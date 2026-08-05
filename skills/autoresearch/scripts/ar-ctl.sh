#!/usr/bin/env bash
# ar-ctl.sh — autoresearch session state machine (port of oh-my-pi autoresearch).
#
# Subcommands:
#   init    open/reconfigure a session (baseline snapshot, dedicated branch)
#   run     execute `bash autoresearch.sh`, capture output, parse METRIC/ASI lines
#   log     record the pending run: keep => commit, discard/crash/checks_failed => revert
#   flag    mark a logged run as suspect (excluded from baseline/best math)
#   status  print the session snapshot block (re-read this every iteration)
#   clear   close the session (keeps tree by default)
#
# State lives in .autoresearch/ at the repo root (kept out of git via .git/info/exclude).
set -euo pipefail

AR_DIR=".autoresearch"
SESSION="$AR_DIR/session.json"
PENDING="$AR_DIR/pending.json"
RUNS="$AR_DIR/runs.jsonl"
NOTES="$AR_DIR/notes.md"
HARNESS="autoresearch.sh"
DEFAULT_TIMEOUT=600
DEFAULT_MAX_ITER=15

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

need_jq() { command -v jq >/dev/null 2>&1 || die "jq is required"; }

enter_repo_root() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
  cd "$root"
}

need_session() {
  [ -f "$SESSION" ] || die "no active autoresearch session — run: ar-ctl.sh init --goal '...' --metric <name> --direction min|max"
}

session_get() { jq -r "$1" "$SESSION"; }

# session_update '<jq filter>' [jq args...]
session_update() {
  local filter="$1"; shift
  local tmp; tmp=$(mktemp)
  jq "$@" "$filter" "$SESSION" > "$tmp" && mv "$tmp" "$SESSION"
}

ensure_exclude() {
  local ex=".git/info/exclude"
  mkdir -p .git/info
  grep -qxF "$AR_DIR/" "$ex" 2>/dev/null || echo "$AR_DIR/" >> "$ex"
}

harness_hash() { shasum -a 256 "$HARNESS" | awk '{print $1}'; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# run_with_timeout <seconds> <cmd...>  (macOS has no `timeout`)
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "$secs" && kill -TERM "$pid" 2>/dev/null && sleep 5 && kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  local rc=0
  wait "$pid" || rc=$?
  kill "$watcher" >/dev/null 2>&1 || true
  return "$rc"
}

# parse_kv_lines <prefix> <logfile> -> JSON object on stdout
# Matches lines like: "METRIC wall_ms=123.4" / "ASI hypothesis=cache misses"
parse_kv_lines() {
  local prefix="$1" log="$2"
  { grep -E "^${prefix} +[A-Za-z0-9_.:-]+ *=" "$log" 2>/dev/null || true; } |
    sed -E "s/^${prefix} +//" |
    jq -Rn '[inputs | capture("^(?<k>[A-Za-z0-9_.:-]+) *= *(?<v>.*)$") | {(.k): (.v | (tonumber? // .))}] | add // {}'
}

# modified_paths -> newline-separated worktree changes (porcelain, rename target)
modified_paths() {
  git status --porcelain | sed -E 's/^.{3}//; s/^.* -> //; s/^"(.*)"$/\1/'
}

csv_to_json_array() {
  jq -Rn --arg s "${1:-}" '$s | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))'
}

runs_json() {  # all logged runs as a JSON array
  if [ -f "$RUNS" ]; then jq -s '.' "$RUNS"; else echo '[]'; fi
}

segment_summary() {  # prints baseline/best lines for the current segment
  local seg dir metric
  seg=$(session_get '.segment'); dir=$(session_get '.direction'); metric=$(session_get '.metric')
  runs_json | jq -r --argjson seg "$seg" --arg dir "$dir" --arg metric "$metric" '
    [ .[] | select(.segment == $seg) ] as $all
    | ($all | map(select(.flagged | not))) as $ok
    | ($ok | map(select(.metric != null)) | first) as $base
    | ($ok | map(select(.status == "keep" and .metric != null))) as $kept
    | (if ($kept | length) == 0 then null
       elif $dir == "max" then ($kept | max_by(.metric))
       else ($kept | min_by(.metric)) end) as $best
    | "runs logged this segment: \($all | length) (counts toward the iteration cap; \(($all | length) - ($ok | length)) flagged)",
      (if $base then "baseline \($metric): \($base.metric) (run #\($base.run))" else "baseline: not established yet" end),
      (if $best then
         "best kept \($metric): \($best.metric) (run #\($best.run))"
         + (if $base and $base.metric != 0 then
              " — \(( ($best.metric - $base.metric) / $base.metric * 10000 | round) / 100)% vs baseline"
            else "" end)
       else "best kept: none yet" end)
  '
}

# ---------------------------------------------------------------------------
cmd_init() {
  local goal="" metric="" direction="" scope="" off="" max_iter="" new_segment=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --goal) goal="$2"; shift 2 ;;
      --metric) metric="$2"; shift 2 ;;
      --direction) direction="$2"; shift 2 ;;
      --scope) scope="$2"; shift 2 ;;
      --off-limits) off="$2"; shift 2 ;;
      --max-iter) max_iter="$2"; shift 2 ;;
      --new-segment) new_segment=1; shift ;;
      *) die "init: unknown option: $1" ;;
    esac
  done

  [ -f "$PENDING" ] && die "a pending run is unlogged — finish it first: ar-ctl.sh log <keep|discard|crash|checks_failed> --desc '...'"

  if [ -f "$SESSION" ]; then
    # Reconfigure existing session in place.
    [ -n "$goal" ]   && session_update '.goal = $v'   --arg v "$goal"
    [ -n "$metric" ] && session_update '.metric = $v' --arg v "$metric"
    if [ -n "$direction" ]; then
      [ "$direction" = "min" ] || [ "$direction" = "max" ] || die "--direction must be min or max"
      session_update '.direction = $v' --arg v "$direction"
    fi
    [ -n "$scope" ]    && session_update '.scope_paths = $v' --argjson v "$(csv_to_json_array "$scope")"
    [ -n "$off" ]      && session_update '.off_limits = $v'  --argjson v "$(csv_to_json_array "$off")"
    [ -n "$max_iter" ] && session_update '.max_iterations = ($v | tonumber)' --arg v "$max_iter"

    if [ "$new_segment" -eq 1 ]; then
      [ -f "$HARNESS" ] || die "./$HARNESS not found — the harness must exist to start a segment"
      git add -A
      git diff --cached --quiet || git commit --no-verify -q -m "autoresearch: baseline (segment $(($(session_get '.segment') + 1)))"
      session_update '.segment += 1 | .baseline_commit = $c | .harness_sha256 = $h' \
        --arg c "$(git rev-parse HEAD)" --arg h "$(harness_hash)"
      echo "Started segment $(session_get '.segment') — new baseline commit $(git rev-parse --short HEAD)."
      echo "Establish the segment baseline: run + log the unmodified harness before changing code."
    else
      echo "Session reconfigured."
    fi
  else
    [ -n "$goal" ] || die "--goal is required for a new session"
    [ -n "$metric" ] || die "--metric is required (must match a METRIC <name>=<value> line printed by $HARNESS)"
    [ "$direction" = "min" ] || [ "$direction" = "max" ] || die "--direction min|max is required"
    [ -f "$HARNESS" ] || die "./$HARNESS not found — build and validate the harness first (Phase 1), then init"

    # Dedicated branch: experiment reverts run `git reset --hard` + `git clean -fd`.
    local current branch created=0
    current=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current" == autoresearch/* ]]; then
      branch="$current"
    else
      local slug
      slug=$(printf '%s' "$goal" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)
      branch="autoresearch/${slug:-session}-$(date +%y%m%d-%H%M)"
      git checkout -q -b "$branch"
      created=1
    fi

    mkdir -p "$AR_DIR"
    ensure_exclude

    # Baseline snapshot: everything in the worktree (harness included) is the segment-1 baseline.
    git add -A
    git diff --cached --quiet || git commit --no-verify -q -m "autoresearch: baseline (segment 1)"

    jq -n \
      --arg goal "$goal" --arg metric "$metric" --arg direction "$direction" \
      --argjson scope "$(csv_to_json_array "$scope")" \
      --argjson off "$(csv_to_json_array "$off")" \
      --arg branch "$branch" --arg baseline "$(git rev-parse HEAD)" \
      --arg harness_sha "$(harness_hash)" \
      --argjson max_iter "${max_iter:-$DEFAULT_MAX_ITER}" \
      --arg created "$(now_iso)" \
      '{version: 1, goal: $goal, metric: $metric, direction: $direction,
        scope_paths: $scope, off_limits: $off, segment: 1, branch: $branch,
        baseline_commit: $baseline, harness_sha256: $harness_sha,
        max_iterations: $max_iter, run_seq: 0, created_at: $created}' > "$SESSION"

    [ -f "$NOTES" ] || printf '# Autoresearch notes\n\n## Playbook\n\n(empty)\n\n## Ideas\n\n(empty)\n' > "$NOTES"

    echo "Session opened on branch $branch$( [ "$created" -eq 1 ] && echo ' (created)' )."
    echo "Baseline commit: $(git rev-parse --short HEAD)"
    echo "Next: establish the baseline metric — ar-ctl.sh run, then ar-ctl.sh log keep --desc 'baseline'."
  fi
}

# ---------------------------------------------------------------------------
cmd_run() {
  need_session
  local timeout="$DEFAULT_TIMEOUT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) timeout="$2"; shift 2 ;;
      *) die "run: unknown option: $1 (the command is fixed: bash $HARNESS)" ;;
    esac
  done

  [ -f "$PENDING" ] && die "run #$(jq -r '.run' "$PENDING") is unlogged — finish it first: ar-ctl.sh log <status> --desc '...'"
  [ -f "$HARNESS" ] || die "./$HARNESS is missing"

  local seg max_iter used
  seg=$(session_get '.segment'); max_iter=$(session_get '.max_iterations')
  used=$(runs_json | jq --argjson seg "$seg" '[ .[] | select(.segment == $seg) ] | length')
  if [ "$used" -ge "$max_iter" ]; then
    die "iteration cap reached ($used/$max_iter for segment $seg) — stop and report to the user, or raise it: ar-ctl.sh init --max-iter N"
  fi

  if [ "$(harness_hash)" != "$(session_get '.harness_sha256')" ]; then
    warn "$HARNESS changed since the segment baseline — results are NOT comparable. Run: ar-ctl.sh init --new-segment"
  fi

  local n rundir log
  n=$(( $(session_get '.run_seq') + 1 ))
  session_update '.run_seq = $n' --argjson n "$n"
  rundir="$AR_DIR/runs/$n"; mkdir -p "$rundir"; log="$rundir/output.log"

  echo "Run #$n: bash $HARNESS (timeout ${timeout}s)"
  local start rc=0 dur
  start=$(date +%s)
  run_with_timeout "$timeout" bash "$HARNESS" > "$log" 2>&1 || rc=$?
  dur=$(( $(date +%s) - start ))

  local metrics asi metric_name primary
  metrics=$(parse_kv_lines "METRIC" "$log")
  asi=$(parse_kv_lines "ASI" "$log")
  metric_name=$(session_get '.metric')
  primary=$(jq -n --argjson m "$metrics" --arg k "$metric_name" '$m[$k] // null')

  jq -n \
    --argjson run "$n" --argjson segment "$seg" --argjson exit_code "$rc" \
    --argjson duration_s "$dur" --argjson metrics "$metrics" --argjson asi "$asi" \
    --argjson metric "$primary" --arg log "$log" --arg started "$(now_iso)" \
    '{run: $run, segment: $segment, exit_code: $exit_code, duration_s: $duration_s,
      metric: $metric, metrics: $metrics, asi: $asi, log: $log, started_at: $started}' > "$PENDING"

  echo "exit code: $rc | duration: ${dur}s"
  echo "parsed metrics: $(jq -c '.' <<< "$metrics")"
  [ "$(jq 'length' <<< "$asi")" -gt 0 ] && echo "parsed ASI: $(jq -c '.' <<< "$asi")"
  if [ "$primary" = "null" ]; then
    warn "primary metric '$metric_name' was NOT found in the output — a keep decision is not possible without it"
  else
    echo "primary $metric_name = $primary"
  fi
  if [ "$rc" -ne 0 ]; then
    echo "--- last 30 output lines ($log) ---"
    tail -n 30 "$log"
  fi
  echo "Now record it: ar-ctl.sh log <keep|discard|crash|checks_failed> --desc '...'"
}

# ---------------------------------------------------------------------------
cmd_log() {
  need_session
  [ -f "$PENDING" ] || die "no pending run — ar-ctl.sh run first"

  local status="${1:-}"; shift || true
  case "$status" in keep|discard|crash|checks_failed) ;; *) die "log: first argument must be keep|discard|crash|checks_failed" ;; esac

  local desc="" justification=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --desc) desc="$2"; shift 2 ;;
      --justification) justification="$2"; shift 2 ;;
      *) die "log: unknown option: $1" ;;
    esac
  done
  [ -n "$desc" ] || die "--desc is required: one honest sentence about what this run changed and why"

  local modified deviations scope_json off_json
  modified=$(modified_paths)
  scope_json=$(session_get '.scope_paths' | jq -c '.')
  off_json=$(session_get '.off_limits' | jq -c '.')
  deviations=$(jq -n --arg paths "$modified" --argjson scope "$scope_json" --argjson off "$off_json" '
    ($paths | split("\n") | map(select(length > 0))) as $p
    | $p | map(. as $f
        | if ([$off[] | select(. as $o | $f | startswith($o))] | length) > 0 then $f
          elif ($scope | length) == 0 then empty
          elif ([$scope[] | select(. as $s | $f | startswith($s))] | length) > 0 then empty
          else $f end)')

  local n commit="null" git_note=""
  n=$(jq -r '.run' "$PENDING")

  if [ "$status" = "keep" ]; then
    git add -A
    if git diff --cached --quiet; then
      git_note="nothing to commit"
    else
      # --no-verify: throwaway experiment branch, never pushed; repo hooks
      # (commitlint format, lint-staged) would break the loop for no benefit.
      git commit --no-verify -q -m "autoresearch run #$n: $desc"
      git_note="committed"
    fi
    commit="\"$(git rev-parse HEAD)\""
  else
    git reset --hard -q HEAD
    git clean -fd -q          # respects .git/info/exclude, so .autoresearch/ survives
    git_note="worktree reverted"
  fi

  local unjustified=false
  if [ "$(jq 'length' <<< "$deviations")" -gt 0 ] && [ "$status" = "keep" ] && [ -z "$justification" ]; then
    unjustified=true
  fi

  local tmp; tmp=$(mktemp)
  jq -c \
    --arg status "$status" --arg desc "$desc" --arg just "$justification" \
    --argjson commit "$commit" --argjson deviations "$deviations" \
    --argjson unjustified "$unjustified" --arg modified "$modified" --arg logged "$(now_iso)" \
    '. + {status: $status, desc: $desc,
          justification: (if $just == "" then null else $just end),
          commit: $commit, deviations: $deviations, unjustified: $unjustified,
          modified: ($modified | split("\n") | map(select(length > 0))),
          flagged: false, flag_reason: null, logged_at: $logged}' "$PENDING" > "$tmp"
  cat "$tmp" >> "$RUNS"; rm -f "$tmp" "$PENDING"

  echo "run #$n logged as '$status' ($git_note)"
  if [ "$unjustified" = true ]; then
    warn "kept with UNJUSTIFIED scope deviations: $(jq -c '.' <<< "$deviations") — justify next time or flag this run"
  elif [ "$(jq 'length' <<< "$deviations")" -gt 0 ]; then
    echo "scope deviations (justified or non-keep): $(jq -c '.' <<< "$deviations")"
  fi
  segment_summary
}

# ---------------------------------------------------------------------------
cmd_flag() {
  need_session
  local run_no="${1:-}"; shift || true
  [[ "$run_no" =~ ^[0-9]+$ ]] || die "flag: first argument must be a run number"
  local reason=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      *) die "flag: unknown option: $1" ;;
    esac
  done
  [ -n "$reason" ] || die "--reason is required (why is this run suspect?)"
  [ -f "$RUNS" ] || die "no logged runs"
  runs_json | jq -e --argjson n "$run_no" 'any(.[]; .run == $n)' >/dev/null || die "run #$run_no not found"

  local tmp; tmp=$(mktemp)
  jq -c --argjson n "$run_no" --arg r "$reason" \
    'if .run == $n then .flagged = true | .flag_reason = $r else . end' "$RUNS" > "$tmp"
  mv "$tmp" "$RUNS"
  echo "run #$run_no flagged: $reason (excluded from baseline/best math)"
  segment_summary
}

# ---------------------------------------------------------------------------
cmd_status() {
  if [ ! -f "$SESSION" ]; then
    echo "No active autoresearch session in $(pwd)."
    echo "Phase 1: build ./$HARNESS (exit 0, print 'METRIC <name>=<value>', deterministic), validate it, then:"
    echo "  ar-ctl.sh init --goal '...' --metric <name> --direction min|max [--scope a,b] [--off-limits c] [--max-iter N]"
    return 0
  fi

  local seg max_iter used
  seg=$(session_get '.segment'); max_iter=$(session_get '.max_iterations')
  used=$(runs_json | jq --argjson seg "$seg" '[ .[] | select(.segment == $seg) ] | length')

  echo "=== AUTORESEARCH STATUS ==="
  echo "goal: $(session_get '.goal')"
  echo "branch: $(session_get '.branch') | segment: $seg | baseline commit: $(session_get '.baseline_commit' | cut -c1-10)"
  echo "primary metric: $(session_get '.metric') (direction: $(session_get '.direction'))"
  echo "scope: $(session_get '.scope_paths' | jq -c '.') | off-limits: $(session_get '.off_limits' | jq -c '.')"
  echo "iterations used: $used / $max_iter"
  if [ "$(harness_hash 2>/dev/null || echo missing)" != "$(session_get '.harness_sha256')" ]; then
    warn "$HARNESS differs from the segment baseline — bump segment before the next run (init --new-segment)"
  fi
  echo
  segment_summary
  echo
  echo "--- recent runs (last 10, this segment) ---"
  runs_json | jq -r --argjson seg "$seg" '
    [ .[] | select(.segment == $seg) ] | .[-10:] | .[]
    | "#\(.run) [\(.status)] \(.metric // "no-metric") — \(.desc)"
      + (if .flagged then " [FLAGGED: \(.flag_reason)]" else "" end)
      + (if .unjustified then " [UNJUSTIFIED deviations: \(.deviations | join(", "))]" else "" end)
      + (if (.asi | length) > 0 then "\n    ASI: \(.asi | tojson)" else "" end)'
  local unjust
  unjust=$(runs_json | jq -r --argjson seg "$seg" '
    [ .[] | select(.segment == $seg and .unjustified and (.flagged | not)) ]
    | if length == 0 then "" else
        "\n--- unjustified scope deviations ---\n"
        + (map("#\(.run): \(.deviations | join(", ")) — accept, justify on the next log, or flag it") | join("\n"))
      end')
  [ -n "$unjust" ] && echo "$unjust"
  if [ -f "$PENDING" ]; then
    echo
    echo "--- PENDING RUN (must be logged before anything else) ---"
    jq -r '"run #\(.run): exit \(.exit_code), \(.metrics | tojson) — log it: ar-ctl.sh log <status> --desc ..."' "$PENDING"
  fi
  echo
  echo "--- notes ($NOTES) ---"
  cat "$NOTES" 2>/dev/null || echo "(no notes)"
}

# ---------------------------------------------------------------------------
cmd_clear() {
  need_session
  local reset_baseline=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reset-to-baseline) reset_baseline=1; shift ;;
      *) die "clear: unknown option: $1" ;;
    esac
  done
  if [ "$reset_baseline" -eq 1 ]; then
    git reset --hard -q "$(session_get '.baseline_commit')"
    git clean -fd -q
    echo "worktree reset to baseline $(session_get '.baseline_commit' | cut -c1-10) (kept commits discarded)"
  fi
  rm -f "$PENDING"
  mv "$SESSION" "$AR_DIR/session.closed.$(date +%Y%m%d-%H%M%S).json"
  echo "session closed — run history preserved in $RUNS"
}

# ---------------------------------------------------------------------------
usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

need_jq
enter_repo_root
case "${1:-}" in
  init|run|log|flag|status|clear) cmd="$1"; shift; "cmd_$cmd" "$@" ;;
  *) usage ;;
esac
