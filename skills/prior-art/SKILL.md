---
name: prior-art
description: Use before designing or building a new tool, app, plugin, bot command, CLI, or feature from scratch ("만들고 싶어", "이런 기능 있으면 좋겠다", "I want to build"). Searches GitHub and communities for existing implementations and returns an adopt / extend / reference / build verdict. Not for edits, bug fixes, or work inside existing code.
---

# Prior Art

## Overview

Most "I want to build X" ideas already have an implementation somewhere. Find it before
designing anything, and turn the search into one verdict the user can act on. Past sessions
skipped this step even when the user asked for "references": agents collected design
references (how `gh` structures commands) but never asked whether the tool itself already
existed.

The question this skill answers is **"does this already exist, and is it good enough to use?"**,
not "what should the design look like". Design comes after, and only if the verdict is
`extend` or `build`.

## When Not to Use

- Changes to existing code, bug fixes, refactors, config tweaks.
- The user already named the implementation they want to use or fork.
- The user explicitly says to skip research.

## Workflow

1. **Restate the need in one line**, as the capability, not the user's wording.
   "Delete empty agent session files periodically" → "agent session transcript cleanup /
   pruning". Derive 3–5 search phrasings from it, including English terms when the request
   is in Korean.

2. **Check what is already on this machine first.** It is the cheapest hit.
   - Installed CLIs and existing skills (`which`, `brew list`, the skills directories).
   - The kb-wiki vault, when present: `rg -il <term> "<vault>" -g '!**/_legacy/**' -g '!**/raw/**'`.

3. **Search outward, in parallel** when the harness supports subagents or parallel calls.
   - GitHub: `gh search repos "<phrase>" --sort stars --limit 15 --json fullName,description,stargazersCount,pushedAt,license`,
     plus `gh search code` for a distinctive API or file name.
   - Package registries for the target ecosystem (crates.io, npm, PyPI, VS Code / JetBrains
     marketplaces, Homebrew, plugin stores).
   - Communities: Hacker News, Reddit, GeekNews (news.hada.io), awesome-* lists, via the
     available web search tool.

4. **Vet the top candidates (at most 5).** For each, record from evidence, not the README pitch:
   - Last commit / release date, open-issue health, license.
   - Coverage: which parts of the restated need it does and does not do.
   - Fit: language/runtime, platform (macOS?), install cost, whether it is extensible.
   Open the repo (README, issues, latest release) before claiming coverage.

5. **Give one verdict.**

   | Verdict | When |
   |---|---|
   | `adopt` | A candidate covers the need as-is; using it beats writing anything. |
   | `extend` | A candidate covers most of it; fork, plugin, wrapper, or upstream PR closes the gap. |
   | `reference` | Nothing fits, but a candidate's design or approach is worth copying. |
   | `build` | Nothing close exists, or every candidate fails a hard constraint (license, platform, abandoned). |

   Pick one and say why. Do not hand back a menu.

## Output

Report in the user's language:

1. The verdict and a one-line reason.
2. A candidate table: name + link, stars, last activity, license, covers / misses.
3. For `extend` / `reference` / `build`: the gap that justifies writing code, stated so the
   next design step can start from it.
4. What was searched (queries and sources), so "nothing found" is checkable.

When the project directory exists and the user is moving on to build, offer to save the
report as `docs/prior-art.md`; do not write it unasked.

## Common Mistakes

- Treating design references as prior art. "`gh` has a nice command layout" does not answer
  "does a Bitbucket CLI already exist".
- Judging by star count alone. An abandoned 5k-star repo can lose to an active 200-star one.
- Claiming a candidate covers a feature based on its description without opening the repo.
- Reporting "nothing exists" after one query phrasing. Absence needs several phrasings and at
  least two sources.
- Sliding into design or implementation before the user has seen the verdict.
