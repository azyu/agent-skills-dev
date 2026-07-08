---
name: recap
description: Use when the user asks for a recap, session summary, work summary, handoff, or documentation update after recent coding, operations, debugging, infrastructure, or research work.
---

# Recap

## Overview

Create an evidence-backed summary of recent work and keep nearby project documentation aligned with the current state. Treat recap as a closure workflow: verify what actually happened, update useful records, and separate completed work from follow-up decisions.

## Workflow

1. Establish the evidence.
   - Review the current conversation context for completed actions, commands, decisions, and unresolved questions.
   - Inspect the workspace with `git status`, `rg`, and relevant existing docs.
   - Prefer direct evidence from files, command output, service status, or logs over memory.

2. Classify the work.
   - Completed: changes already made and verified.
   - Current state: names, hosts, ports, schedules, config paths, backup paths, URLs, or operational caveats that future work needs.
   - Follow-ups: unresolved risks, optional cleanup, manual checks, or decisions that still need the user.

3. Update documentation when it will help future work.
   - Prefer updating existing docs before creating new files.
   - Create a new focused doc only when the topic is likely to be reused operationally.
   - Keep edits minimal and consistent with the repository style.
   - Do not perform unrelated cleanup during recap.

4. Verify the documentation.
   - Re-read changed files.
   - Search for stale names, dates, or contradictory statements with `rg` when relevant.
   - Run a lightweight validation command such as `git diff --check` when files were edited.

5. Report back.
   - Use the user's language unless they requested another language.
   - Lead with what was documented or changed.
   - Include changed file paths and any remaining follow-ups.
   - Do not claim a service, test, or doc state is verified unless it was actually checked.

## Documentation Heuristics

- Update `README` or an index when new operational docs are added.
- Update a change log when the work changed infrastructure, production-like config, schedules, credentials flow, networking, DNS, backups, or recovery behavior.
- Update topology or access docs when hostnames, IPs, ports, reverse proxies, certificates, or service ownership changed.
- Create focused runbooks for repeatable operations or fragile fixes.
- Keep one-off narrative details out of long-lived docs unless they explain a current operational constraint.

## Common Mistakes

- Writing a generic summary without checking the repo.
- Recording guesses as facts.
- Creating a new recap file when an existing change log or runbook is the better home.
- Hiding follow-up work inside completed-work language.
- Forgetting to update indexes after adding docs.
