---
name: godot-wiki
description: Use when working with the godot-wiki Obsidian vault at /Users/azyu/Library/Mobile Documents/iCloud~md~obsidian/Documents/godot-wiki, including Godot Engine notes, official docs ingestion, version-specific updates, wiki queries, linting, or schema/index/log maintenance.
---

# godot-wiki

Maintain the `godot-wiki` vault as a persistent, compounding markdown knowledge base for Godot Engine technical knowledge.
Prefer this skill over generic `llm-wiki` whenever the user mentions Godot wiki, Godot Engine notes, or this vault path.

## Vault Location

- Canonical vault path:
  `/Users/azyu/Library/Mobile Documents/iCloud~md~obsidian/Documents/godot-wiki`
- Use the absolute path in commands and file links.

## Active Layout

```text
godot-wiki/
├── SCHEMA.md
├── RESOLVER.md
├── index.md
├── log.md
├── _meta/
├── entities/
├── concepts/
├── comparisons/
├── queries/
└── raw/
    ├── articles/
    ├── papers/
    ├── transcripts/
    └── assets/
```

- `raw/` is immutable provenance.
- `entities/`, `concepts/`, `comparisons/`, and `queries/` are the compiled wiki layer.
- `_meta/topic-map.md` is selective theme navigation, not a second index.

## Always Orient First

Before answering, ingesting, linting, or editing:

1. Read `SCHEMA.md`
2. Read `RESOLVER.md`
3. Read `index.md`
4. Read the latest entries in `log.md`
5. If creating or moving a page, read the target directory `README.md` when present

This prevents duplicate pages, stale version claims, and wrong directory placement.

## Godot Source Policy

- Prefer official Godot sources for version facts: `https://docs.godotengine.org/en/stable/`, versioned docs such as `/en/4.6/`, release pages, changelogs, and class reference pages.
- Browse before using "latest", "stable", current version, release-date, platform-support, or API-availability claims.
- Preserve version distinctions explicitly. Newer Godot behavior supersedes older behavior only for the same version line.
- For Godot 4.6 content, note whether the claim is from the stable docs, the 4.6 release page, changelog, or class reference.
- Use non-official sources only as supporting context unless the user explicitly asks for community practice.

## Directory Decisions

- `entities/`: Godot Engine itself, named addons, tools, libraries, repositories, official products, organizations, or people when materially relevant.
- `concepts/`: scenes, nodes, resources, signals, scripting, rendering, physics, UI, animation, input, export, workflows, and reusable Godot patterns.
- `comparisons/`: side-by-side evaluations with explicit criteria.
- `queries/`: durable answers to concrete questions that would be costly to re-derive.
- `raw/`: captured source notes, documentation snapshots, transcripts, and provenance.

Use `RESOLVER.md` for ambiguous placement. Prefer updating an existing page over creating a near-duplicate.

## Core Operations

### Ingest Or Update

1. Capture new source evidence in `raw/` when the source is substantial or likely to be reused.
2. Search `index.md` and existing pages for exact names, aliases, and adjacent topics.
3. Create or update compiled pages in the correct directory.
4. Keep frontmatter `updated`, `sources`, tags, aliases, and contradictions consistent with `SCHEMA.md`.
5. Update `index.md` for new pages or changed summaries.
6. Update `_meta/topic-map.md` when a navigation cluster changes.
7. Append a meaningful action to `log.md`.

### Query

1. Read `index.md`, then open the relevant pages.
2. Answer from the markdown files first; browse official docs when current version accuracy matters.
3. If the result is durable and expensive to reconstruct, file it into `queries/` or update a concept page.
4. Log meaningful filed-back outputs.

### Lint

Check:
- broken `[[wikilinks]]`
- compiled pages missing from `index.md`
- stale `updated` dates after edits
- tags not listed in `SCHEMA.md`
- source paths that do not exist
- version claims that lack a source or mix Godot 3.x/4.x behavior
- pages that should move between `entities/`, `concepts/`, `comparisons/`, and `queries/`

## qmd Guidance

Markdown files are the source of truth. `qmd` is a retrieval and embedding acceleration layer.

- QMD collection: `godot_wiki`
- Collection root: `/Users/azyu/Library/Mobile Documents/iCloud~md~obsidian/Documents/godot-wiki`
- Mask: `**/*.md`

Use `qmd` for broad recall, semantic search, and stale-context checks, then open the markdown files themselves before answering or editing.
Run `qmd` commands sequentially for the same task; do not parallelize multiple `qmd` calls against this collection.

### Search Workflow

For user questions about existing wiki content:

1. Run semantic query first:
   ```bash
   qmd query "<question>" -c godot_wiki
   ```
2. If the query has specific terms, also run exact search:
   ```bash
   qmd search "<terms>" -c godot_wiki
   ```
3. For concept-level discovery, use vector search:
   ```bash
   qmd vsearch "<semantic concept>" -c godot_wiki
   ```
4. Open top hits through qmd or the filesystem:
   ```bash
   qmd get qmd://godot_wiki/<path>
   ```
5. Answer from the underlying markdown files, not snippets alone.

If retrieval is stale after meaningful content changes, refresh with:

```bash
qmd update
qmd embed -f
```

If the collection is missing or points at the wrong vault, recreate it with:

```bash
qmd collection add "/Users/azyu/Library/Mobile Documents/iCloud~md~obsidian/Documents/godot-wiki" --name godot_wiki --mask '**/*.md'
qmd context add qmd://godot_wiki/ "Godot Engine Obsidian wiki stored in iCloud. Source of truth is the markdown wiki itself."
qmd update
qmd embed -f
```

## Pitfalls

- Do not modify existing files under `raw/`.
- Do not add release chatter unless it changes durable Godot practice.
- Do not flatten version-specific behavior into timeless advice.
- Do not skip `index.md` and `log.md` updates after meaningful wiki changes.
- Do not create a new page when an existing concept page can absorb the update cleanly.
