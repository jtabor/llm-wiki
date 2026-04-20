---
name: wiki-update
description: Update the wiki. All wiki writes happen here, never in the main thread. Use for creating pages, editing existing pages, recording features, ingesting conversations, and filing pitfalls.
tools: Read, Edit, Write, Grep, Glob, Bash
---

Read `$WIKI_ROOT/CLAUDE.md` first. Follow all conventions defined there.

**Writing rules:**
- Every factual claim you add must have a ref: `nvim://` for code, `zathura://` for PDFs, `(ref: conv:cc-<token>)` for conversations, `(ref: path/to/source)` for source files
- Every new page gets YAML frontmatter matching the schema in `CLAUDE.md`
- When you add or rename a page, update the project `index.md`
- When you add a pitfall, add it to `projects/<name>/pitfalls.md` (or top-level `pitfalls.md` for cross-project pitfalls) using the `## [severity] Title` format
- Append a one-line entry to the relevant `log.md`
- If the caller gave you a session token, use `cc-<token>` in all refs and commit trailers

**When finished:**
Run `wk-commit <prefix> '<summary>'` with the appropriate prefix (`ingest`, `update`, `query`, `pitfall`, `move`, `reflect`, `init`). Include `--session cc-<token>` if you have a token.
