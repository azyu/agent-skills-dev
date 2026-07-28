---
name: bb-cli
description: "Bitbucket Cloud: inspect and operate repos, pull requests, pipelines, issues, wiki pages, and raw REST endpoints through the local bb CLI."
metadata:
  openclaw:
    category: "developer-tools"
    requires:
      bins: ["bb"]
    cliHelp: "bb --help"
---

# bb CLI

```bash
bb <command> <subcommand> [flags]
```

## Agent Usage Rules

- Prefer `--output json` for automation.
- Use `--json-fields` only on commands that explicitly support it.
- Outside a cloned Bitbucket repo, pass `--workspace` and `--repo` explicitly.
- Before any write operation, inspect the exact subcommand help in the current session and use only documented flags.
- Existing-PR commands accept positional `ID` or `--id`; passing both is an error.
- For `bb pr comments`, `ID`/`--id` always mean the pull request ID. Use `--comment-id` to target a single comment; never pass a comment ID via `--id`.
- For write operations, do not guess IDs, branch names, or target repos. Resolve them first.
- `bb pr create` uses `--description` and `--destination`; do not substitute `--body` or `--dest`.
- Use `bb api` when the wrapped command surface does not cover the operation you need.
- `bb api` is JSON-only in both directions: request bodies via `--input <file>` or `--input -`, and every response is decoded as JSON. Endpoints that return plain text or binary (pipeline step logs, diffs) fail with `internal_error: decode response` — use the wrapped command (`bb pipeline log`, `bb pr diff`) for those.
- `bb api` has no `--output` flag. Passing one is a clap argument error on stderr; if you redirect stderr away you will see an empty result and misread it as empty data. Do not suppress stderr when probing flags.
- Do not combine `bb api --input` with `--paginate`; paginated mode is read-only.
- `bb pipeline get`/`steps`/`log` select a pipeline via `--build <number>` or `--uuid "{uuid}"` flags only — no positional ID, unlike `bb pr get 123`. Step UUIDs go to `--step "{uuid}"` including braces.
- `bb pipeline list` returns the API default order (oldest first) and only the first page unless `--all`. For recent builds always pass `--sort=-created_on`.
- `bb pipeline list` has no branch filter and the pipelines endpoint ignores `q`; filter by branch via `bb api` with the `target.branch=<name>` query parameter.
- Use `bb pr comment --parent <comment-id>` for PR comment replies.
- Wiki commands use the repo's wiki Git remote, not a REST endpoint.
- Runtime failures in JSON mode return JSON error envelopes; parse/help failures stay text.

## Command Groups

### auth

- `login` - Save a profile and set it active.
- `status` - Show current profile status without leaking token values.
- `logout` - Remove a saved profile.

### repo

- `list` - List repositories in a workspace.

### pr

- `list`, `get`, `create`, `update`, `merge`
- `approve`, `unapprove`, `request-changes`, `remove-request-changes`, `decline`
- `comment`, `comments`, `diff`, `statuses`, `activity`

### pipeline

- `list`, `get`, `run`, `steps`, `log`

### issue

- `list`, `create`, `update`

### wiki

- `list`, `get`, `put`

### api

- Raw Bitbucket Cloud REST calls with JSON output.

## Discovering Commands

Before calling a subcommand, inspect it:

```bash
# Root command surface
bb --help

# Group help
bb pr --help
bb pipeline --help

# Exact flags and positional arguments
bb api --help
bb pr create --help
bb pr comment --help
bb pr get --help
bb pr comments --help
bb pipeline log --help
bb wiki put --help
```

## Common Calls

```bash
# Auth
bb auth status
bb auth login --token "$BITBUCKET_TOKEN" --username you@example.com

# Read operations
bb repo list --workspace acme --output json
bb pr list --workspace acme --repo widgets --state OPEN --output json
bb pr get 123 --workspace acme --repo widgets --output json
bb pr comments 123 --workspace acme --repo widgets --output json
bb pr comments 123 --comment-id 456 --workspace acme --repo widgets --output json
bb pipeline list --workspace acme --repo widgets --output json
bb pipeline get --workspace acme --repo widgets --uuid "{pipeline-uuid}" --output json
bb pipeline log --workspace acme --repo widgets --uuid "{pipeline-uuid}"
bb issue list --workspace acme --repo widgets --output json
bb wiki get --workspace acme --repo widgets --page Home.md

# Write operations
bb pr create --workspace acme --repo widgets --title "Add widget support" --source feature/widgets --destination main
bb pr comment 123 --workspace acme --repo widgets --content "Reply text" --parent 456
bb pr create --workspace acme --repo widgets --title "Add widget support" --source feature/widgets --destination main --description "$(cat ./pr-body.md)"
bb issue create --workspace acme --repo widgets --title "Broken widget" --kind bug --priority major --output json
bb wiki put --workspace acme --repo widgets --page Home.md --file ./docs/home.md

# Escape hatch
bb api repositories/acme/widgets/pullrequests --paginate
bb api --method POST --input ./body.json repositories/acme/widgets/pullrequests/123/comments
printf '{"content":{"raw":"Reply text"}}' | bb api --method POST --input - repositories/acme/widgets/pullrequests/123/comments
```

## Recipe: Pipeline Failure Triage

```bash
# 1. Recent pipelines for a branch (list has no branch filter — use the API param)
bb api "repositories/acme/widgets/pipelines?target.branch=feature/x&sort=-created_on&pagelen=10"

# 1b. Recent pipelines regardless of branch (default order is oldest-first — always sort)
bb pipeline list --sort=-created_on --output json

# 2. Steps for a build — find the failed step's UUID
bb pipeline steps --build 14588 --output json

# 3. Step log via the wrapped command, never `bb api .../log` (non-JSON response).
#    Logs can be MBs — redirect to a file, then grep/tail.
bb pipeline log --build 14588 --step "{step-uuid}" > step.log
tail -100 step.log
```

## GitHub CLI Compatibility

Subcommand aliases accepted: `view`→`get`, `edit`→`update`, `close`→`decline`, `checks`→`statuses`.

Flag names differ — `bb pr create` uses `--description` (not `--body`) and `--destination` (not `--base`/`--dest`). When unsure, run `<command> --help`.
