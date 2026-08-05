---
name: quiz
description: Use when the user asks for quiz questions on recently explained or changed code ("퀴즈 내줘", "문제 내줘", "이해했는지 확인해줘"). Interactive 5-question quiz where answers are withheld until the user solves them.
---

# Quiz (이해도 확인 퀴즈)

Quiz the user on the material most recently explained in this session. If nothing was explained yet, quiz on the most recent code change instead (read it first).

## Format

- Exactly 5 questions, medium difficulty: answerable only with real understanding of the substance — but no gotchas, and no trivia (변수명 암기형 문제 금지).
- Mix multiple-choice (4 options) and short-answer. Number them Q1–Q5.
- Present all 5 questions at once, then stop and wait for the user's answers.

## Grading rules — IMPORTANT

- NEVER reveal a correct answer until the user has answered that question correctly.
- When an answer is wrong: say which question is wrong, diagnose WHAT the user misunderstood (the specific concept behind the mistake — not the answer itself), give a hint pointing at that concept, and re-ask.
- When an answer is right: confirm it and briefly reinforce why it is right.
- Track progress each round (e.g. "3/5 해결").
- The quiz ends only when all 5 are answered correctly, or the user explicitly gives up — only then reveal the remaining answers with explanations.
