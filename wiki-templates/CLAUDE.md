# Wiki CLAUDE.md — Master Schema

This file is the single source of truth for the compounding wiki. All agents read it at the start of every invocation.

---

## Delegation Rule

**The main thread MUST NOT edit wiki pages directly.**

- All wiki reads → delegate to the `wiki-read` subagent
- All wiki writes → delegate to the `wiki-update` subagent
- Exception: the main thread may read `CLAUDE.md` and `index.md` to orient itself

---

## Session Token

A session token is injected by the `UserPromptSubmit` hook on the first message of each session. Format: `cc-<session-uuid>`.

Use `cc-<TOKEN>` in every ref to this session. Pass it to `wiki-update` when delegating.

To find the transcript later:
```bash
ls $WIKI_ROOT/conversations/claude-code/<session-id>.jsonl
# or, if not yet archived:
grep -rl "<session-id>" ~/.claude/projects/ --include="*.jsonl" --exclude="*history.jsonl"
```

---

## Page Frontmatter Schema

Every wiki page must have YAML frontmatter:

```yaml
---
type: entity | concept | source | analysis | codebase | pitfall | meta
project: <project-name>          # omit for cross-project pages
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [tag1, tag2]
sources:
  - raw/papers/paper-name.pdf
  - raw/articles/article-name.md
conversations:
  - conv:cc-<session-uuid>
confidence: high | medium | low | speculative
---
```

---

## Reference Rules

**Every factual claim must have a verifiable reference.**

### Text File References — `nvim://` URIs
Use `nvim://` for **all** text-based files: source code, markdown, yaml, shell scripts, config files, logs, etc. Read the `nvim` skill for the full URI format. Prefer semantic anchors over line numbers for code; use line-number form for files without named symbols (yaml, config, logs).

```markdown
[`dma_init()`](nvim://motor-controller/src/drivers/dma.c::dma_init)
[`dma_init@abc1234`](nvim://motor-controller/src/drivers/dma.c::dma_init@abc1234)
[`CLAUDE.md`](nvim://llm-wiki/CLAUDE.md)
[`wiki-session-token.sh`](nvim://llm-wiki/hooks/wiki-session-token.sh)
[`projects.json:3`](nvim:///home/jtabor/.config/nvim-goto/projects.json/3)
```

### PDF References — `zathura://` URIs
Read the `pdf` skill for URI format. Page numbers are **0-indexed**.

```markdown
[p.43](zathura:///home/jtabor/workspace/project/datasheet.pdf/42)
```

### Binary / Arbitrary File References — `file://` URIs
Use `file://` for anything that isn't a text file or a page-linked PDF: images, spreadsheets, videos, compiled binaries, etc. Obsidian delegates to `xdg-open`, so the system default app opens the file.

```markdown
[rtos-survey-2024.pdf](file:///home/jtabor/notes/wiki/raw/papers/rtos-survey-2024.pdf)
[screenshot.png](file:///home/jtabor/notes/wiki/raw/assets/screenshot.png)
```

### Conversation References — `conv://` URIs
Use `conv://` for session references. A handler will be wired up later to open conversations in a viewer; for now the link is a placeholder that captures the ref in a clickable form.

```markdown
[conv:cc-<session-uuid>](conv://cc-<session-uuid>)
```

### Reference Hierarchy Summary

| Type | Scheme | When to use |
|---|---|---|
| Text files (code, md, yaml, sh, config, log) | `nvim://` | Always — opens in nvim at correct line/symbol |
| PDF with specific page | `zathura://` | When pointing at a specific page (0-indexed) |
| PDF or any other file, no page ref | `file://` | Opens in system default app via xdg-open |
| Session transcript | `conv://` | Reference a Claude Code session (handler TBD) |

### Frontmatter Source Tracking
Every page's frontmatter `sources:` and `conversations:` lists everything the page depends on.

---

## Per-Project Directory Layout

```
projects/<name>/
├── CLAUDE.md          # project-specific additions (optional)
├── index.md           # title + one-line summary, grouped by subdir
├── log.md             # activity log (append-only)
├── pitfalls.md        # project-specific pitfalls
├── sources/           # source summaries
├── concepts/          # topic/concept pages
├── codebases/         # codebase exploration notes
├── analyses/          # filed query results
└── raw/               # immutable source material
    ├── papers/
    ├── articles/
    ├── code/
    └── assets/
```

---

## index.md Format

### Project index.md
```markdown
# <Project Name>

One-line summary of the project.

## Sources
- [[sources/paper-name]] — one-line description

## Concepts
- [[concepts/topic-name]] — one-line description

## Codebases
- [[codebases/repo-name]] — one-line description

## Analyses
- [[analyses/query-topic]] — one-line description
```

### Top-level index.md
```markdown
# Wiki Index

## Projects
- [[projects/motor-controller/index]] — Motor controller firmware for STM32H7
- [[projects/rtos-research/index]] — RTOS scheduling research

## Cross-Cutting
- [[user/preferences]] — User preferences
- [[pitfalls]] — Cross-project pitfalls
```

---

## pitfalls.md Format

```markdown
# Pitfalls

## [critical] Short title
Body — what the pitfall is and why it matters.
[source.pdf](file:///home/jtabor/notes/wiki/raw/papers/source.pdf)
[conv:cc-<token>](conv://cc-<token>)
- Affected: [`symbol()`](nvim://project/path/to/file.c::symbol) or [`config.yaml:12`](nvim://project/config.yaml/12)
- Tags: #tag1 #tag2

## [moderate] Another pitfall
...
```

Severity levels: `critical`, `moderate`, `minor`.

---

## Commit Message Format

All commits use `wk-commit`:

```
<prefix>: <summary>

session: cc-<TOKEN>
touched: path/a.md, path/b.md
```

Prefixes: `ingest`, `update`, `query`, `pitfall`, `move`, `reflect`, `init`.

---

## Agent Definitions

### wiki-read

**When to invoke:** any time the main thread needs to find or read wiki content.

1. Read this `CLAUDE.md` for conventions
2. Read the relevant `projects/<name>/index.md` to locate pages
3. Read only what's needed — don't dump whole pages into main-thread context
4. Resolve refs where useful (follow nvim:// or zathura:// links)
5. Report back: (a) concise answer, (b) page citations
6. **Never edit anything**

### wiki-update

**When to invoke:** creating or modifying any wiki page.

1. Read this `CLAUDE.md` first
2. Every factual claim you add must have a ref (nvim://, zathura://, file://, or conv://)
3. Every new page gets frontmatter matching the schema above
4. When you add or rename a page, update the project `index.md`
5. When you add pitfalls, add to `pitfalls.md` in the correct format
6. Append a one-line entry to `log.md`
7. When finished, run `wk-commit <prefix> '<summary>'` with the right prefix
8. If the caller gave you a session token, use it in refs and in the commit

### wiki-reflect

**When to invoke:** user asks for a wiki health check.

Scan for: contradictions between pages, stale claims, orphan pages, red links, broken code anchors, unresolvable refs, unreferenced claims, pitfall staleness, coverage gaps. Fix what's clear, flag what needs human input. Commit with `reflect:` prefix.

---

## Workflows Summary

### Feature Implementation
After completing a feature: update codebase/concept pages, add pitfalls discovered, update index.md and log.md, commit with `update:` prefix.

### Source Ingest
Read source together with user, extract to wiki pages with verifiable refs, update index.md and log.md, commit with `ingest:` prefix.

### Conversation Ingest
Run `wk-ingest-cc <token>`, read transcript, extract decisions/preferences/facts/pitfalls to appropriate pages, commit with `ingest:` prefix.

### Query
Read index.md → relevant pages → synthesize answer. If reusable, file as `analyses/<topic>.md`. Append to log.md. Commit with `query:` prefix.
