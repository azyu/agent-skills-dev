---
name: session-resume
description: Use when the user wants to resume, continue, or pick up work from a recent Codex conversation or local ~/.codex session, including "이어서 작업", "지난 세션 이어줘", "최근 작업 이어받아", "지난번에 하던 거", "resume session", or "pick up where we left off".
---

# Session Resume

Resume work from recent local Codex sessions while keeping the main agent context small.

## Core Rule

Delegate session-log mining to a subagent. The main agent should not read large raw
`~/.codex/sessions` JSONL files except for tiny spot checks after the subagent reports back.

Use this division:

| Actor | Owns |
| --- | --- |
| Main agent | Trigger skill, spawn subagent, receive compact handoff, gather only current task context needed to continue |
| Subagent | Search `~/.codex`, inspect candidate sessions, compact the relevant conversation, collect related current context |

## Workflow

1. State that `session-resume` is being used and that session mining will run in a subagent.
2. Spawn one subagent with a bounded read-only task. Do not fork full context unless the user explicitly needs the current thread included.
3. Instruct the subagent to run the bundled script first:

```bash
python3 ~/.codex/skills/session-resume/scripts/prepare_resume.py --cwd "$PWD" --query "<user request>" --detail
```

4. Tell the subagent to inspect only the most relevant candidate sessions from the script output.
5. Require the subagent to return a compact handoff using this shape:

```markdown
## Resumed Session
- session file:
- confidence:
- original user goal:
- important decisions:
- files touched:
- commands and verification:
- unresolved work:
- risks or warnings:

## Current Context
- cwd:
- git status:
- relevant project instructions:
- relevant files or tests to read next:

## Recommended Continuation
- next action:
- why:
```

6. While the subagent works, gather lightweight current context only:
   `pwd`, `git status --short`, project instructions, task ledger, and obvious gate docs.
7. Continue the work from the subagent handoff. If the handoff has low confidence or multiple likely sessions, ask the user before editing.

## Subagent Prompt

Use this prompt pattern:

```text
Read-only session resume task. Search local Codex sessions under ~/.codex for the conversation most relevant to: <user request>.

Start with:
python3 ~/.codex/skills/session-resume/scripts/prepare_resume.py --cwd "<cwd>" --query "<user request>" --detail

Then inspect only the best candidate JSONL files enough to produce a compact handoff. Do not edit files. Do not paste long raw logs. Return: resumed session, confidence, original goal, important decisions, files touched, commands and verification, unresolved work, risks, current repo context, and recommended continuation.
```

## Main Agent Guardrails

- Do not paste raw session logs into the main context.
- Do not ask the subagent to continue implementation unless the user explicitly asks for delegated implementation.
- Do not treat the prior session as authoritative if current files, git status, or project instructions disagree.
- If source changes will be made after resuming, follow the current repository workflow before editing.
- If the user asks only for a summary, stop after the compact handoff and current-context report.

## Helper Script

`scripts/prepare_resume.py` ranks recent sessions by current working directory, query terms, recency, changed files, and commands. It prints small Markdown candidate summaries rather than full logs.

Useful flags:

```bash
python3 ~/.codex/skills/session-resume/scripts/prepare_resume.py --help
python3 ~/.codex/skills/session-resume/scripts/prepare_resume.py --cwd "$PWD" --query "tone match" --days 14 --limit 4 --detail
```
