# Future Work — Compounding Wiki

Parked here to keep MVP scope honest. Revisit once the MVP is in daily use and we have concrete pain points.

---

## Tools

- [ ] **Reference-resolvability check** — script that walks the wiki and flags unresolvable `nvim://`, `zathura://`, `(ref: conv:...)`, and `(ref: path)` targets. High value for catching rot. Probably the first thing we add.
- [ ] **`wk-move-ref`** — rename/move a file and update all references across the wiki (wikilinks, `nvim://`, `zathura://`, frontmatter `sources:`, inline `(ref:)`). Until we have it, moves are manual: `rg` + careful `sed` + a dry-run eye.
- [ ] **`wk-search`** — `rg` wrapper for wiki search. May never build — bare `rg` is fine.
- [ ] **`wk-ingest-cc` full parse** — convert the copied JSONL into a markdown transcript (human/assistant turns, frontmatter with date/project/token/topic). Currently we only copy the JSONL.
- [ ] **`log.md` regenerator** — if we decide we want an Obsidian-navigable temporal narrative, rebuild it from `git log` on demand. No live log for MVP.
- [ ] **`wk-init`** — one-shot bootstrap script. Currently the bootstrap is a documented procedure. Wrap it when we've run it enough times to know what's stable.

---

## Agents

- [ ] **`wiki-reflect` agent** — periodic health check: contradictions between pages, stale claims superseded by newer sources, orphan pages (no inbound wikilinks), red links, broken code anchors, unresolvable references, unreferenced claims, pitfall staleness, coverage gaps, suggested explorations. Fixes what's clear, flags what needs human input.
- [ ] **Conversation auto-ingest hook** — Claude Code exit hook that runs `wk-ingest-cc` automatically. Manual for MVP.

---

## Schema / content additions

- [ ] **`people/` directory** — entity pages for people (coworkers, collaborators). Add when you have a person to file.
- [ ] **`analyses/` per project** — filed query results. Add when the first query is worth filing.
- [ ] **`_templates/`** — Obsidian template files for each page type. Add if LLM output starts drifting from schema.
- [ ] **Top-level global `pitfalls.md`** — cross-project lessons. Add when a pitfall actually applies across projects; otherwise it's noise.
- [ ] **Confidence-field workflows** — the `confidence` frontmatter field exists but nothing consumes it. Either wire it into `wiki-reflect` or drop it.

---

## Infrastructure

- [ ] **MCP server** — expose wiki operations as MCP tools so Claude uses them natively rather than via CLI. Not needed at bootstrap.
- [ ] **Git LFS** — if large binaries (PDFs, images) end up needing version control after all.
- [ ] **Obsidian plugin recommendations** — Dataview, Graph View, Web Clipper, Templater, obsidian-git, Marp Slides. Document in bootstrap when we've decided which ones are actually useful.

---

## Open design questions (from `wiki-design-v3.md`)

1. **Search scaling** — `index.md` works up to ~100–200 pages per project. Beyond that, `rg` over the wiki. Beyond *that*, `qmd` or similar. Probably won't need it for a while.
2. **Multi-repo code references** — projects spanning multiple repos need a mapping in the project CLAUDE.md, e.g., `repos: {firmware: ~/projects/firmware, tools: ~/projects/fw-tools}`. Refs become `nvim://firmware/src/main.c::main`.
3. **Conversation auto-ingest** — Claude Code exit hook. Covered above.
4. **Wiki isolation** — one git repo / one Obsidian vault scoped by directory. Currently addressed by `$WIKI_ROOT` env var swap for work/personal. Split into separate vaults only if that turns out to be insufficient.
5. **MCP server** — covered above.
6. **SessionStart hook portability** — verify across Claude Code versions once we've been running on the current version for a while. If the output-capture behavior ever changes, we need a fallback (LLM-generated token at session start, for example).
