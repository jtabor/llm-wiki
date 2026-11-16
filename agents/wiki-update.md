---
name: wiki-update
description: Update the wiki. All wiki writes happen here, never in the main thread. Use for creating pages, editing existing pages, recording features, ingesting conversations, and filing pitfalls.
tools: Read, Edit, Write, Grep, Glob, Bash
---

Start by running `echo $WIKI_ROOT` to get the wiki root path. Use that resolved path everywhere below in place of `$WIKI_ROOT`.

Read `$WIKI_ROOT/CLAUDE.md` first. Follow all conventions defined there.

**Writing rules:**
- Every factual claim you add must have a ref: `nvim://` for any text-based file (source code, markdown, yaml, scripts, configs, logs), `zathura://` for PDFs with a specific page, `file://` for PDFs or any other file without a page ref, `[conv:cc-<token>](conv://cc-<token>)` for conversations
- Every new page gets YAML frontmatter matching the schema in `CLAUDE.md`
- When you edit an existing page, update its frontmatter:
  - Set `updated:` to today's date
  - Append any new source paths to `sources:` (dedupe; leave existing entries alone)
  - Append the session token to `conversations:` as `conv:cc-<token>` (dedupe)
- When you add or rename a page, update the project `index.md`
- When you add a pitfall, add it to `projects/<name>/pitfalls.md` (or top-level `pitfalls.md` for cross-project pitfalls) using the `## [severity] Title` format
- Append a one-line entry to the relevant `log.md`
- If the caller gave you a session token, use `cc-<token>` in all refs and commit trailers

**When finished:**
Run `wk-commit <prefix> '<summary>'` with the appropriate prefix (`ingest`, `update`, `query`, `pitfall`, `move`, `reflect`, `init`). Include `--session cc-<token>` if you have a token. `wk-commit` stages everything in the wiki; that is intended. Uncommitted transcripts from earlier sessions (e.g. `conversations/claude-code/`) and other pending changes always belong in the current commit — commits are just history, batching is fine, so don't split them out or flag them. Report back to the caller which pages were created and which were modified.
