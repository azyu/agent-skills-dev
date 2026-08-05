---
name: playground
description: Use when the user wants an interactive HTML page to explore or visualize recently developed code ("놀이터", "시각화해서 상호작용 가능한 페이지", "인터랙티브 HTML로 보여줘"). Produces one self-contained HTML file outside the repo; never modifies service code. For a narrative explanation document with a quiz, use explain-diff-html instead.
---

# Playground (인터랙티브 코드 놀이터)

Build a single self-contained interactive HTML page that lets the user explore how the recently developed code actually behaves.

## Scope

- Default target: the code the user just developed or discussed in this session; otherwise the last commit. Read the real source first.

## Hard rules

- Do NOT modify or add any file inside the repo/service source tree. The output is exactly ONE `.html` file, nothing else.
- Save it outside the repo with a date prefix so files stay time-sorted and out of version control: `/tmp/YYYY-MM-DD-playground-<slug>.html`, then open it in the browser (`open <file>`).
- Fully self-contained: inline all CSS/JS, no CDN or network requests.

## Content

- Re-implement the core logic of the target code in plain JavaScript inside the page — a faithful port of the actual rules/formulas/branches, not a mock. Note in the page which source files/functions each part corresponds to (`path/file.ts:line`).
- Interactive controls: editable inputs, sliders, buttons; preloaded realistic example data; a step-through or before/after view where flow or ordering matters.
- Visualize structure with simple HTML/CSS diagrams (boxes, arrows, lists — no ASCII art) showing components and data flow, updating live as inputs change.
- Include a short "사용법" note at the top.
- Code blocks must use `<pre>` tags (or CSS `white-space: pre-wrap`), or newlines collapse.
