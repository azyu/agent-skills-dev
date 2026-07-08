---
name: backlog
description: Deferred work queue manager for lxp_services. Use when user wants to defer a task ("나중에 하자", "일단 A부터", "B는 backlog에 넣어둬", "deferred"), list pending deferred work ("backlog 보여줘", "남은 거 뭐야"), resume an old item ("backlog X 이어서 하자"), or mark complete ("X 끝났어 backlog에서 빼"). Triggers on the keywords "backlog", "나중에 할", "이어서 작업", "deferred".
---

# Backlog Skill

Personal deferred-work queue. Distinct from `.context/TASKS.md` (current sprint) and Memory (knowledge/preferences).

## Responsibility Boundary

| Where | What |
|---|---|
| `.context/TASKS.md` | **이번 sprint** in-progress / blocked 작업 |
| `.context/BACKLOG.md` | **나중에 할** 작업 (this skill) |
| Memory (`~/.claude/.../memory/`) | 재사용 가능한 **지식·선호** (작업 큐 아님) |

규칙 1줄: **"할 일이면 TASKS.md(지금) 또는 BACKLOG.md(나중). 알아둘 사실이면 Memory."**

## Data Location

`.context/BACKLOG.md` (Obsidian vault symlink, gitignored — 개인 영역)

## File Format

```markdown
---
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

# Backlog

> 나중에 할 일. 현재 sprint는 `.context/TASKS.md` 참조.
> session id는 옵션 — 막히면 transcript grep해서 deep dive.

## Active

- [ ] **<Title>**
  - Created: <ISO datetime>
  - Next: <단일 행동 한 줄>
  - Session: `<session-id-prefix>` (없으면 `-`)
  - Notes: <옵션 — 추가 컨텍스트 필요 시>

## Archived

- [x] **<Title>** — done <YYYY-MM-DD> (created <YYYY-MM-DD>)
```

## Operations

### List (`/backlog` 또는 "backlog 보여줘")

1. `.context/BACKLOG.md` 읽기. 없으면 빈 큐 메시지 출력.
2. Active 섹션의 모든 항목을 번호 매겨 출력.
3. 각 항목마다:
   - 제목
   - `added: <YYYY-MM-DD> (N일 전)` — 상대 시간은 오늘 날짜 기준 계산
   - `next: <Next 필드>`
   - `session: <session id 앞 8자> 또는 -`
4. 7일 이상 묵은 항목이 있으면 마지막에 `💡 7일 이상 묵은 항목 N개. 정리 검토 권장.`

### Add (`/backlog add <제목>` 또는 "backlog에 넣어줘")

1. 현재 session id 추출 (아래 절차).
2. ISO 시각 (`date -u +%Y-%m-%dT%H:%M`) 생성.
3. `.context/BACKLOG.md`의 Active 섹션 끝에 새 항목 append:
   ```markdown
   - [ ] **<Title>**
     - Created: <ISO>
     - Next: <사용자가 제공하거나, 없으면 비워두고 사용자에게 물음>
     - Session: <session-id 또는 ->
   ```
4. 파일 frontmatter `updated:` 갱신.

### Done (`/backlog done <번호>` 또는 "X 끝났어 backlog에서 빼")

1. 번호로 항목 식별 (List 출력 순서 기준).
2. Active에서 제거, Archived 섹션에 `[x] **<Title>** — done <오늘> (created <원래 날짜>)` 한 줄로 추가.
3. `updated:` 갱신.

### Resume (`/backlog resume <번호>` 또는 "backlog X 이어서 하자")

1. 번호로 항목 식별.
2. Next 필드 출력.
3. **사용자가 deep dive 원하면** (혹은 Next로 부족해 보이면) session id로 transcript 접근:
   ```bash
   SESSION_ID=<id>
   TRANSCRIPT=~/.claude/projects/-Volumes-EXTSSD-code-work-lxp-services/${SESSION_ID}.jsonl
   # 키워드 grep
   grep -i "<keyword>" "$TRANSCRIPT" | head -20
   # 또는 jq로 assistant 메시지만
   jq 'select(.type=="assistant")' "$TRANSCRIPT" | less
   ```
4. session id가 `-`거나 transcript 파일이 없으면 deep dive 스킵하고 Next만 사용.

## Session ID Extraction

추출 우선순위:

1. **Transcript 경로 역추출** (primary, 안정적):
   ```bash
   # 현재 실행 중인 jsonl 파일을 lsof로 찾기
   lsof -p $$ 2>/dev/null | grep '\.claude/projects/.*\.jsonl' | awk '{print $NF}' | head -1
   # 또는 가장 최근 수정된 jsonl을 추정 (Claude Code가 활성 세션 파일에 계속 쓰기 때문)
   ls -t ~/.claude/projects/-Volumes-EXTSSD-code-work-lxp-services/*.jsonl 2>/dev/null | head -1 | xargs basename | sed 's/\.jsonl$//'
   ```
2. **`CLAUDE_SESSION_ID` env var** (fallback):
   ```bash
   echo "${CLAUDE_SESSION_ID:-}"
   ```
3. 둘 다 실패 시: `Session: -` 로 빈칸 처리, add는 정상 동작 (deep dive만 불가).

## Lazy Initialization

`.context/BACKLOG.md`가 없으면 첫 사용 시 자동 생성:

```markdown
---
created: <오늘>
updated: <오늘>
---

# Backlog

> 나중에 할 일. 현재 sprint는 `.context/TASKS.md` 참조.

## Active

## Archived
```

## Stale Detection (묘지화 방지)

List 출력 시:
- 7일 미만: 표시 색 없음
- 7~14일: `(N일 전)` 그대로
- 14일 이상: 마지막에 정리 권장 메시지

자동 archive는 하지 않음 (사용자가 명시적으로 `/backlog done` 하거나 항목 보고 직접 결정).

## Examples

```
사용자: "이거 backlog에 넣어두자 — bff-ac-cms에 audit 로그 추가"
스킬: Add 동작 → BACKLOG.md에 항목 추가, session id 자동 채움
응답: "✅ Added to backlog: 'bff-ac-cms audit 로그 추가' (session abc123de)"

사용자: "/backlog"
스킬: List → 추가 시점/상대 시간 포함 출력

사용자: "backlog 2번 이어서 하자"
스킬: Resume → Next 출력. 사용자가 더 필요하다 하면 transcript grep
```
