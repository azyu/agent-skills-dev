---
name: release-notes
description: Use when a GitHub release is published or about to be, or the user asks for release notes ("릴리스 노트", "배포 설명", "release notes"). Rewrites the auto-generated PR list into user-facing notes (summary line, grouped changes, compatibility, install/upgrade), shows the draft, and applies it with gh release edit after approval. Not for in-repo CHANGELOG files.
---

# Release Notes

## Overview

`gh release create --generate-notes` produces a list of PR titles. Users cannot tell from
`fix: align dividend query with KIS ksdinfo/dividend spec` that `kis info dividend` failed on
every call and now works, and release-prep or CI PRs sit next to real changes. This skill
replaces that body with notes written for the person who installs the tool: what changed for
them, what may break, and how to upgrade.

Reference shape: https://github.com/midagedev/mwoyeo/releases/tag/v1.1.3 (one-line summary,
grouped bold-titled items, measured numbers, install line).

The release workflow keeps `--generate-notes`. That body is the fallback when this skill is not
run, and editing after publish never races the workflow's create step.

## Workflow

1. **Find the range.**
   - Target tag: the one the user named, else the latest `gh release list --limit 2`.
   - Previous tag: the release before it. The range is `<prev>..<tag>`.
   - Confirm the release exists and its workflow finished (`gh run list --workflow <release workflow> --limit 1`).
     Edit only a published release.

2. **Collect the evidence.** Notes come from these sources only.
   - Merged PRs in the range: PR numbers from `git log --merges --oneline <prev>..<tag>`, then
     `gh pr view <n> --json title,body,labels` for each.
   - Direct commits that are not part of a PR: `git log --no-merges --first-parent <prev>..<tag>`.
   - Install/upgrade commands from the README, or the Homebrew formula name in the tap.
   - The previous release body, for language and structure (follow the repo's own convention once it has one).

3. **Classify each change** by its effect on the user, not by its commit prefix.

   | Group | Contains | Goes in the notes as |
   |---|---|---|
   | New | New commands, options, supported targets | One item each |
   | Fixed | Behavior that was wrong and is now right | One item each, state the old symptom |
   | Compatibility | Renamed output fields, changed defaults, config format, removed commands, platform support | Always listed, with the action the user must take |
   | Internal | Release prep, CI, refactors, tests, docs for contributors | Omitted, or one line if it affects trust (security advisories patched) |

   A `fix:` PR can be Compatibility too (it changed `--json` field names). A `chore(deps):` PR
   is Internal unless it patches an advisory or changes a runtime requirement.

4. **Draft the body** in the repo's language (default Korean; add an English section only when
   earlier releases are bilingual).

   ```markdown
   **<one sentence: the change most users will notice>**

   ### 새 기능
   - **<user-facing title>.** <what the user can do now, 1–2 sentences>

   ### 고친 점
   - **<symptom in user terms>.** <what happened before, what happens now>

   ### 호환성
   - **<what changed>.** <who is affected and what to do>

   ### 기타
   - **<trust-relevant internal change>.** <e.g. security advisories patched, with package names>

   ### 설치와 업데이트
   `<install command>` · `<upgrade command>`

   **Full Changelog**: <compare URL>
   ```

   - Drop empty sections. Keep the Full Changelog link.
   - Name commands, flags, and fields exactly as the CLI spells them; check against `--help` when unsure.
   - Numbers only when a PR body or commit states the measurement. Never estimate one.
   - No PR numbers, author handles, or commit prefixes in the items.
   - Korean prose follows the sentence rules in `~/.claude/rules/writing.md` when that file exists.

5. **Verify before showing.**
   - Each item traces to a named PR or commit. List the mapping under the draft for the user.
   - Every Compatibility candidate from step 3 appears in the draft.
   - No Internal-only change is presented as a user benefit.

6. **Show the draft and stop.** Publishing changes a public page, so wait for approval.

7. **Apply after approval.**
   - Save the current body first: `gh release view <tag> --json body --jq .body > <scratch>/<tag>.prev.md`.
   - Write the draft to a file and run `gh release edit <tag> --notes-file <file>`.
   - Read it back with `gh release view <tag> --json body --jq .body` and confirm it matches.

## Common Mistakes

- Rewording PR titles one-to-one instead of grouping by user effect.
- Listing release-prep, CI, or lint PRs as changes.
- Missing a compatibility break hidden inside a `fix:` or `refactor:` PR. Read the PR body, not only the title.
- Inventing impact ("faster", "more stable") that no PR measured.
- Overwriting the body without saving the previous one.
