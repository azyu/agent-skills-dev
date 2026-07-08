---
name: oracle-research
description: >-
  Use when web research, deep investigation, or post-cutoff information is
  needed — delegate the question to a ChatGPT (GPT-5.5 Pro) browser session via
  the oracle CLI (steipete/oracle). Triggers: "research this on the web",
  "look up latest trends/best practices", "deep research", library comparisons,
  release notes, ecosystem/industry questions beyond the knowledge cutoff.
  Do NOT use for simple fact checks that a couple of WebSearch calls can
  answer — reserve for heavy questions needing server-side search plus large
  context.
---

# Oracle Web Research

## Overview

`oracle` automates a local Chrome to send a prompt to ChatGPT (GPT-5.5 Pro) and
retrieve the answer in the terminal. It leverages ChatGPT's server-side web
search, making it well suited for delegating research that needs up-to-date
information. Runs are detached sessions with saved logs.

## Base Command

```bash
oracle --engine browser --browser-manual-login --browser-keep-browser \
  --browser-input-timeout 120000 \
  -p "<prompt>"
```

- `--engine browser`: use the ChatGPT web session instead of an API key
- `--browser-manual-login`: reuse a persistent automation profile (skips cookie copy; manual login only on first use)
- `--browser-keep-browser`: leave Chrome running after completion
- `--browser-input-timeout 120000`: cap the wait for the composer (milliseconds)
- Works with a prompt alone — file attachments are optional

## Prompt Writing

- One-line questions yield generic answers. Write **6–30 sentences** covering
  background, goal, what was already tried, and the desired output format.
- Spell out versions, platforms, and constraints (e.g. "NestJS v11, Node 24,
  MySQL 8.4").
- Attach code context when needed: `--file "apps/svc/src/**/*.ts" --file "!**/*.spec.ts"`
  (globs allowed, `!` excludes, keep total under ~196k tokens).

## Useful Variants

| Purpose                                     | Extra flags                                        |
| ------------------------------------------- | -------------------------------------------------- |
| ChatGPT Deep Research mode                  | `--browser-research deep`                          |
| Planned multi-turn in the same conversation | `--browser-follow-up "<next prompt>"` (repeatable) |
| Continue a finished session                 | `oracle --followup <sessionId> -p "..."`           |
| Save only the final answer to a file        | `--write-output <path>`                            |
| Memorable session ID                        | `--slug "three word slug"`                         |
| Hide the Chrome window (macOS)              | `--browser-hide-window`                            |

## Session Management — never re-run on timeout

Runs are detached. Even if the CLI times out, the browser-side run may still be
in progress — do NOT re-run the same command:

```bash
oracle status              # list recent sessions (24h window)
oracle session <id>        # reattach — streams the saved answer/log
```

- If an identical prompt is already running, the duplicate guard blocks new
  runs. Do not bypass with `--force` — attach to the existing session instead.
- If any oracle session is already running, attach to it rather than starting
  a new one.

## Failure Modes

- **Logged-out profile**: if the ChatGPT session in the manual-login profile
  expires, the Chrome window needs a manual login. Only the user can do this —
  if the window is stuck on a login screen, ask the user to log in and wait.
- **Composer timeout**: run fails past `--browser-input-timeout`. Check
  `oracle status` for the existing session state before retrying.
- When citing results, mark oracle's answer as a secondary source (LLM
  summary) and cross-check important facts against original source links.
