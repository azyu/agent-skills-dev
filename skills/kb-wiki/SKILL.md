---
name: kb-wiki
description: Use when working with the kb-wiki Obsidian vault at /Users/azyu/Library/Mobile Documents/iCloud~md~obsidian/Documents/kb-wiki, including ingesting sources, querying compiled pages, auditing wiki structure, or updating schema/index/log files for that specific knowledge base.
---

# kb-wiki

Maintain the `kb-wiki` vault as a persistent, compounding markdown knowledge base.
This skill is specific to the `kb-wiki` scope and should be preferred over the generic
`llm-wiki` skill when the task is about this vault.

## Vault Location

- Canonical vault path:
  `/Users/azyu/Library/Mobile Documents/iCloud~md~obsidian/Documents/kb-wiki`
- Use the absolute path in commands and file references.

## Active Layout

```text
kb-wiki/
├── SCHEMA.md
├── RESOLVER.md
├── index.md
├── log.md
├── _meta/
├── entities/
├── concepts/
├── comparisons/
├── queries/
├── raw/
│   ├── articles/
│   ├── papers/
│   ├── transcripts/
│   └── assets/
└── _legacy/
    └── pre-llm-wiki-2026-04-17/
```

- `raw/` is immutable provenance.
- `entities/`, `concepts/`, `comparisons/`, and `queries/` are the active compiled layer.
- `_legacy/` is historical reference only, not the active wiki.
- Legacy `howto`, `incident`, and `decision` pages live under `queries/`.

## Always Orient First

Before answering, ingesting, linting, or editing:

1. Read `SCHEMA.md`
2. Read `RESOLVER.md`
3. Read `index.md`
4. Read the latest entries in `log.md`
5. If the task is about prior repo operations or migration history, also scan `.context/log.md`

This prevents duplicate pages, stale assumptions, and placing content in the wrong directory.

## When To Use Which Directory

- `entities/`:
  Named tools, platforms, services, products, libraries
- `concepts/`:
  Durable ideas, patterns, architecture notes, reusable technical knowledge
- `comparisons/`:
  Side-by-side evaluations with shared criteria
- `queries/`:
  Investigations, incidents, how-to guides, decisions, filed answers
- `raw/articles/`:
  Source notes, captures, misc provenance
- `raw/transcripts/`:
  Session-derived raw markdown

Use `RESOLVER.md` if placement is ambiguous.

## Core Operations

### 1. Ingest

When the user provides a source:

1. Capture the source into `raw/`
2. Check `index.md` and existing pages before creating anything new
3. Create or update compiled pages in the correct directory
4. Preserve `sources` and `source_urls`
5. Update `index.md`
6. Append the action to `log.md`

Rules:
- Do not modify existing files under `raw/` except to add newly captured raw sources
- Prefer updating an existing page over creating a near-duplicate
- Keep project/general distinctions in frontmatter/body content, not top-level folder splits

### 2. Query

When the user asks about kb-wiki content:

1. Read `index.md`
2. Open the most relevant pages
3. Answer from the markdown files, not memory alone
4. If the answer is durable and expensive to re-derive, file it back into `queries/` or `comparisons/`
5. Log meaningful filed-back outputs in `log.md`

### 3. Lint

When asked to audit kb-wiki:

1. Check for broken `[[wikilinks]]`
2. Check for orphan compiled pages
3. Check `index.md` coverage
4. Validate required frontmatter
5. Check tags/sources/path consistency against `SCHEMA.md`
6. Flag pages that should move between `concepts/`, `entities/`, `comparisons/`, and `queries/`
7. Treat `_legacy/` as out of scope unless the user explicitly asks for migration-history review

## qmd Guidance

`qmd` is an acceleration layer, not the source of truth.

Current note:
- `kb-wiki` was recently renamed from `KnowledgeBase`
- `qmd` collections may need re-bootstrap or refresh before they reflect the active layout

Use `qmd` only if the collection is clearly current. Otherwise read markdown files directly.

If you need to refresh search after meaningful content changes:

```bash
qmd update
qmd embed -f
```

If the user explicitly asks to re-bootstrap search, use the active `kb-wiki` paths, not the old `KnowledgeBase` paths.

## kb-wiki-Specific Rules

- Active wiki operations go to `log.md`
- Historical repo operations remain in `.context/log.md`
- Current structure and conventions live in `SCHEMA.md`
- Placement disputes are resolved via `RESOLVER.md`
- `_legacy/pre-llm-wiki-2026-04-17/` is archival only

## Pitfalls

- Do not treat `_legacy/` as the active wiki
- Do not file new content into old `General/Projects/Raw` paths
- Do not overwrite raw provenance because a compiled page is wrong
- Do not skip `index.md` and `log.md` updates after meaningful wiki changes
- Do not assume `qmd` is current after the recent rename without checking
