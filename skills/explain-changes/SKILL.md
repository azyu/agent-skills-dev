---
name: explain-changes
description: Use when the user asks to explain a recent code change to someone new to the code ("방금 바뀐 거 설명해줘", "처음 보는 사람한테 설명", "구조부터 이해시켜줘"). Conversational in-chat explanation — structure first, code shown last. For a rich standalone HTML document instead, use explain-diff-html.
---

# Explain Changes (구조 우선 설명)

Explain the most recent code change to a reader who is NEW to this code. Structure first, code last.

## Scope

- Default target: the working tree if dirty, otherwise the last commit (`git status`, `git diff`, `git show`). The user may name a branch, PR, or commit instead.
- Explore the surrounding code enough to explain context — not just the diff itself.

## Structure (in this order — no code blocks until section 4)

1. **큰 그림** — 이 변경이 속한 시스템/모듈이 무엇을 하는지, 전체 구조에서 어디에 위치하는지.
2. **문제와 의도** — 무엇이 문제였고, 이 변경이 무엇을 하려는 것인지.
3. **동작 원리** — 개념 수준의 설명. 구체적인 toy 예시 데이터로 before/after 흐름을 보여줄 것. 파일명·함수명 언급은 허용, 코드 블록은 금지.
4. **코드** — 마지막에만 핵심 코드 발췌를 보여주고, 앞의 설명과 연결해 짚는다. 전체 diff 붙여넣기 금지 — 이해에 필요한 부분만.

## Rules

- Assume zero prior knowledge of this codebase; define project-specific terms on first use.
- No code blocks before section 4. This is the whole point of the skill — resist the urge.
- End by offering follow-ups: "이해 확인 퀴즈는 /explain-quiz, 인터랙티브 시각화는 /explain-playground."
