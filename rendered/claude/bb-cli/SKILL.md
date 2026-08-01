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
- Outside a cloned Bitbucket repo, pass `-R <workspace>/<repo>` or explicit `--workspace` and `--repo`; `-R` conflicts with the two explicit flags.
- Before any write operation, inspect the exact subcommand help in the current session and use only documented flags.
- Existing-PR commands accept positional `ID` or `--id`; passing both is an error.
- For `bb pr comments`, `ID`/`--id` always mean the pull request ID. Use `--comment-id` to target a single comment; never pass a comment ID via `--id`.
- For write operations, do not guess IDs, branch names, or target repos. Resolve them first.
- `bb pr create` uses `--destination`; `--body` is an accepted alias for `--description`, but `--base` and `--dest` are not accepted.
- Use `bb api` when the wrapped command surface does not cover the operation you need.
- `bb api` request bodies are JSON-only (`--input <file>` or `--input -`). Responses follow the server's content type: JSON responses print as pretty-printed JSON, anything else (pipeline step logs, diffs, binaries) prints the raw body verbatim — redirect large or binary output to a file. Pagination still requires JSON pages. Prefer the wrapped commands (`bb pipeline log`, `bb pr diff`) when you need their selector flags.
- `bb api` has no `--output` flag. Passing one is a clap argument error on stderr; if you redirect stderr away you will see an empty result and misread it as empty data. Do not suppress stderr when probing flags.
- Do not combine `bb api --input` with `--paginate`; paginated mode is read-only.
- `bb pipeline get`/`steps`/`log` select a pipeline via a positional selector (`bb pipeline get 14588`, `bb pipeline log 14588 --step "{uuid}"`) — numeric means build number, brace-wrapped means UUID — or via the `--build <number>`/`--uuid "{uuid}"` flags; passing the positional together with either flag is an error. Step UUIDs go to `--step "{uuid}"` including braces.
- `bb pipeline list` returns the API default order (oldest first) and only the first page unless `--all`. For recent builds always pass `--sort=-created_on`.
- `bb pipeline list` filters by branch with `--branch <name>` (sent as the `target.branch` query parameter); the pipelines endpoint ignores `q`.
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

- Raw Bitbucket Cloud REST calls with JSON request bodies and content-type-aware response output.

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
bb pipeline get "{pipeline-uuid}" --workspace acme --repo widgets --output json
bb pipeline log "{pipeline-uuid}" --workspace acme --repo widgets --step "{step-uuid}"
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
# 1. Recent pipelines for a branch
bb pipeline list --branch feature/x --sort=-created_on --output json

# 1b. Recent pipelines regardless of branch (default order is oldest-first — always sort)
bb pipeline list --sort=-created_on --output json

# 2. Steps for a build — find the failed step's UUID
bb pipeline steps 14588 --output json

# 3. Step log — `bb api .../log` now prints the raw log, but prefer the wrapped
#    command for its selector and --step handling. Logs can be MBs — redirect, then grep/tail.
bb pipeline log 14588 --step "{step-uuid}" > step.log
tail -100 step.log
```

## GitHub CLI Compatibility

Subcommand aliases accepted: `view`→`get`, `edit`→`update`, `close`→`decline`, `checks`→`statuses`.

Flag names differ — `bb pr create` uses `--destination` (not `--base`/`--dest`); `--body` is accepted as an alias for `--description`. When unsure, run `<command> --help`.
