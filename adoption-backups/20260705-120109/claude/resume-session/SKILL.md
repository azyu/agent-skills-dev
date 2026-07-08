---
name: resume-session
description: 최근 과거 Claude Code 세션을 요약해 현재 세션에서 이어 작업한다. 지난 대화를 이어받고 싶을 때 사용 — "이어서 작업", "지난 세션 이어줘", "최근 작업 이어받아", "지난번에 하던 거", "resume session", "continue last session". 현재 프로젝트의 transcript(~/.claude/projects/<escaped-cwd>/*.jsonl)를 읽으며, 무거운 읽기·요약은 subagent에 격리해 메인 컨텍스트를 보호한다.
---

# resume-session

Summarize a past Claude Code session and **continue its work in the current session**.

Core principle — **protect the main context**: an active transcript can grow to ~8MB. If the main agent reads the raw transcript, its context is polluted before it can even summarize. So the **heavy reading/summarizing is isolated in a subagent**, and the main agent receives **only a compact summary**.

Deterministic work (listing, keyword matching, text extraction) is handled by the bundled script `scripts/sessions.mjs`; judgment (which decisions/open items matter) is handled by the subagent.

Script path (fixed, user scope): `~/.claude/skills/resume-session/scripts/sessions.mjs`

## Procedure

### 1. List candidates (run directly in main — output is small, so it is safe)

If the user gave a keyword, pass it as an argument. Otherwise list recent sessions without a keyword.

```bash
node ~/.claude/skills/resume-session/scripts/sessions.mjs list [keyword]
```

- The current active session (newest mtime) is excluded automatically.
- Each row is `[n] <age> · "<title>" · branch=… · Nu/Na · size [· matches=…]`, with the **absolute session file path** printed on the line below it (pass this path to the subagent in step 3).
- If there are zero keyword matches, re-run without the keyword.

### 2. Select a session

Present the candidate list to the user as a table and have them **pick one**.

- Even if a keyword strongly matches a single session, **do not auto-confirm** — let the user identify it by age/title and choose.
- Proceed without asking only when there is exactly one obvious candidate (confirm first).

### 3. Isolated summary (dispatch a subagent)

Dispatch ONE subagent (subagent_type: `general-purpose`), passing the **absolute path** of the chosen session. Prompt for the subagent:

> Run this command to get the condensed transcript of a past Claude Code session:
> `node ~/.claude/skills/resume-session/scripts/sessions.mjs extract <absolute_session_path>`
>
> Read the full output and return **only a summary** in the structure below. Do NOT return the raw transcript, verbose tool output, or full code blocks. **Write the summary in Korean** (the user works in Korean):
>
> 1. **목표/주제 (Goal/topic)** — what this session was trying to do
> 2. **완료한 작업 (Completed work)** — what was actually finished
> 3. **핵심 결정사항 (Key decisions)** — chosen approach / rules / trade-offs
> 4. **변경된 파일·브랜치·PR (Changed files, branch, PRs)** — use the CHANGED FILES footer + branch from the extract output
> 5. **미완 항목 / 다음 단계 (Open items / next steps)** — what remains (most important)
> 6. **재개에 필요한 파일 경로 (Files to reopen)** — key file paths needed to resume
>
> Keep it to 1–2 screens, compressed.

> ⚠️ **Always run `extract` through the subagent.** If the main agent runs `extract` itself, the whole reason for this skill (context isolation) collapses.

### 4. Inject + resume (main)

Take the summary returned by the subagent, present it to the user, and propose resuming work based on the **open items / next steps**. If the user agrees, continue with that context.

## Notes

- Target directory is `~/.claude/projects/<cwd with every [^a-zA-Z0-9] replaced by '-'>/`, relative to the current cwd. If `CLAUDE_PROJECT_DIR` is set, it takes precedence.
- `list` options: `--limit N` (rows shown, default 10), `--scan N` (number of recent files to scan, default 30), `--keep-current` (include the active session).
- `extract` options: `--with-thinking` (include assistant `thinking` blocks — use only when the rationale lives solely in thinking; excluded by default, large).
- Changed files are collected from the `file_path` of Edit/Write/MultiEdit-style tool_use calls. Files changed by other means may be missed.
