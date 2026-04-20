# MVP TODO — Compounding Wiki

Build order. Each task is independently verifiable. Scope is MVP — not polish.

Conventions used in this doc:
- `$WIKI_ROOT` — env var pointing at the wiki (e.g., `~/wiki`)
- "code-repo" — the actual source project (e.g., `~/projects/motor-controller`)
- "project-wiki" — that project's wiki subdirectory (`$WIKI_ROOT/projects/motor-controller`)

---

## 0. Prerequisites

- [x] Pick `$WIKI_ROOT` location
- [x] Add to shell rc: `export WIKI_ROOT=~/wiki`
- [x] Confirm Claude Code version supports `SessionStart` hooks with stdout injected as context. RESULT: `SessionStart` additionalContext is silently ignored. Switched to `UserPromptSubmit`. Token uses Claude Code session UUID directly. Tested 2026-04-20.

---

## 1. Directory structure + git init

- [x] `mkdir -p $WIKI_ROOT/{projects,conversations/claude-code,tools,user}`
- [x] `cd $WIKI_ROOT && git init`
- [x] Write `$WIKI_ROOT/.gitignore`:
  ```
  raw/**/*.pdf
  raw/**/*.png
  raw/**/*.jpg
  raw/**/*.jpeg
  raw/**/*.mp4
  raw/**/*.mov
  .obsidian/workspace*
  ```
- [x] Initial commit with empty structure

Acceptance: `ls $WIKI_ROOT` shows the layout; `git log` has one commit.

---

## 2. Wiki CLAUDE.md — the schema

Location: `$WIKI_ROOT/CLAUDE.md`. Single source of truth for conventions. Both agents read it at the start of every invocation.

Must define:
- [x] Page frontmatter schema (type, project, created, updated, tags, sources, conversations, confidence)
- [x] Reference rules:
  - Code refs → `nvim://` URIs (point to nvim skill for format)
  - PDF refs → `zathura://` URIs, 0-indexed (point to pdf skill for format)
  - Conversation refs → `(ref: conv:cc-<TOKEN>)`
  - Source file refs → `(ref: path/to/source)`
  - Every factual claim must have a ref
- [x] Per-project directory layout: `sources/`, `concepts/`, `codebases/`, `raw/{papers,articles,code,assets}`, `pitfalls.md`, `index.md`
- [x] Per-project `index.md` format: title + one-line summary, grouped by subdir
- [x] Top-level `index.md` format: project list + cross-cutting page list
- [x] `pitfalls.md` format: `## [severity] Title`, body, refs, affected anchors, tags
- [x] Commit message format:
  ```
  <prefix>: <summary>

  session: cc-<TOKEN>
  touched: path/a.md, path/b.md
  ```
  Prefixes: `ingest`, `update`, `query`, `pitfall`, `move`.
- [x] **Delegation rule** — main thread MUST NOT edit wiki pages directly. All writes go through the `wiki-update` agent. All reads go through the `wiki-read` agent. State this clearly.
- [x] Session token usage: "Use `cc-<TOKEN>` in every ref to this session."

Acceptance: Another LLM can read this file and produce a correct wiki page without prior context.

---

## 3. SessionStart hook

Location: `~/.claude/settings.json`, `"hooks"` key (not `hooks.json` — the design doc is wrong on this).

- [x] Hook command generates token: uses Claude Code session UUID directly (cc-<session_id>); UserPromptSubmit hook, not SessionStart (SessionStart additionalContext is silently ignored)
- [x] Hook output format: `The wiki session token is: cc-<TOKEN>. Use it in all wiki references this session.`
- [x] Verify token appears in the assistant's context at session start (inspect JSONL or ask the model)
- [x] Verify token ends up in the JSONL transcript (so it's grep-findable later)

Acceptance: Start a fresh session, ask the LLM for the session token, it returns the correct `cc-<TOKEN>`. Then `grep -rl "<TOKEN>" ~/.claude/projects/ --include="*.jsonl" --exclude="*history.jsonl"` finds exactly one file.

---

## 4. `wk-commit` (bash)

Location: `$WIKI_ROOT/tools/wk-commit`. Symlink to `~/.local/bin/` or add `$WIKI_ROOT/tools` to `$PATH`.

- [x] Error if `$WIKI_ROOT` unset
- [x] Args: `wk-commit <prefix> <summary> [--session <token>]`
- [x] Validate prefix against allowed list
- [x] If `--session` not passed, read from `$WIKI_SESSION_TOKEN` env or prompt
- [x] Compute `touched` from `git -C $WIKI_ROOT status --porcelain` (limit to staged + modified, strip status prefix)
- [x] Build commit message with session + touched trailers
- [x] `git -C $WIKI_ROOT add -A && git -C $WIKI_ROOT commit -m "$MSG"`

Acceptance: `wk-commit update "test"` in a wiki with changes produces a commit with the expected message format.

---

## 5. `wk-ingest-cc` (python, minimal)

Location: `$WIKI_ROOT/tools/wk-ingest-cc`. Shebang `#!/usr/bin/env python3`.

Scope: find the JSONL, copy it. No parsing yet.

- [x] Args: `wk-ingest-cc <TOKEN> [--project <name>]`
- [x] `grep -rl <TOKEN> ~/.claude/projects/ --include="*.jsonl" --exclude="*history.jsonl"`
- [x] Error on zero or multiple matches
- [x] `cp` matched file to `$WIKI_ROOT/conversations/claude-code/<TOKEN>.jsonl`
- [x] Print hint: "Ingested. Now have an LLM read it and extract to the appropriate project pages, then `wk-commit ingest 'conversation cc-<TOKEN>'`."

Acceptance: Running it with a real session token copies the JSONL into the wiki.

---

## 6. `wiki-read` subagent

Location: `~/.claude/agents/wiki-read.md`.

Content:
- [x] Frontmatter: `name: wiki-read`, `description: "Read the wiki to answer a question. Returns a concise summary to the caller."`, `tools: Read, Grep, Glob`
- [x] Body: "Read `$WIKI_ROOT/CLAUDE.md` first for conventions. Then read `$WIKI_ROOT/projects/<project>/index.md` to locate relevant pages. Read only what you need. Resolve refs where useful. Report back to the caller with: (a) a concise answer, (b) the page citations. Never edit anything."

Acceptance: Main thread invokes it with a question; it returns a focused answer without dumping whole pages into main-thread context.

---

## 7. `wiki-update` subagent

Location: `~/.claude/agents/wiki-update.md`.

Content:
- [x] Frontmatter: `name: wiki-update`, `description: "Update the wiki. All wiki writes happen here, never in the main thread."`, `tools: Read, Edit, Write, Grep, Glob, Bash`
- [x] Body:
  - "Read `$WIKI_ROOT/CLAUDE.md` first."
  - "Every factual claim you add must have a ref (nvim://, zathura://, conv:cc-<token>, or source path)."
  - "Every new page gets frontmatter matching the schema."
  - "When you add or rename a page, update the project `index.md`."
  - "When you finish, run `wk-commit <prefix> '<summary>'` with the right prefix."
  - "If the caller gave you a session token, use it in refs and in the commit."

Acceptance: Main thread delegates "document the DMA change"; agent creates/edits pages with valid frontmatter + refs, updates index, commits.

---

## 8. Code-repo CLAUDE.md template

Location: `$WIKI_ROOT/bootstrap/code-repo-CLAUDE.md` (reference file for the bootstrap procedure). This is the template the user copies into each code-repo's `CLAUDE.md`.

Must include:
- [x] Pointer to wiki location: `$WIKI_ROOT/projects/<name>/`
- [x] Pointer to user preferences: `$WIKI_ROOT/user/preferences.md`
- [x] Rule: "Before any documentation task, delegate to the `wiki-read` agent."
- [x] Rule: "For any wiki edit, delegate to the `wiki-update` agent. Do NOT edit wiki pages from the main thread."
- [x] Session token note: "A session token is injected by the SessionStart hook. Pass it to the wiki-update agent when delegating."
- [x] File reference convention: "All code refs in wiki pages use paths relative to this repo root."
- [x] Post-feature checklist: "When a feature is done, delegate to wiki-update to record it."

Acceptance: Copy-paste this into a code repo's CLAUDE.md and Claude Code, opening that repo, knows how to talk to the wiki.

---

## 9. User preferences seed

Location: `$WIKI_ROOT/user/preferences.md`.

- [x] Frontmatter: `type: meta`
- [x] Sections: Coding, Communication, Documentation, Other
- [x] Seed from current session context (what the user has already told you about their preferences) or ask

Acceptance: Exists, is readable, captures the user's current known preferences.

---

## 10. Bootstrap procedure (the deliverable)

Location: `$WIKI_ROOT/bootstrap/README.md`. This is the documented procedure for setting up a new wiki from scratch OR adding a new project. Generic enough to reuse.

Two sections:

### New wiki from scratch
- [x] Steps 0–9 from this TODO, rewritten as copy-pasteable commands + file drops
- [x] Fold in installation steps from `INSTALL.md` in the tools repo (hooks, settings.json changes, shell rc, wiki-tokens dir)
- [x] Includes the SessionStart hook snippet
- [x] Includes the `.gitignore`
- [x] Includes stubs for top-level `index.md`, wiki `CLAUDE.md`

### New project within an existing wiki
- [x] `mkdir -p $WIKI_ROOT/projects/<name>/{sources,concepts,codebases,raw/{papers,articles,code,assets}}`
- [x] Drop `pitfalls.md`, `index.md` stubs
- [x] Drop code-repo CLAUDE.md into the code repo (copy template)
- [x] `wk-commit update "init: project <name>"`

Acceptance: Following the doc on a clean machine produces a working wiki + one pilot project.

---

## 11. End-to-end smoke test

- [ ] Bootstrap `$WIKI_ROOT` using the procedure
- [ ] Bootstrap one pilot project
- [ ] Start a fresh Claude Code session in the code repo
- [ ] Verify session token is in context (ask the LLM for it)
- [ ] Ask the LLM a trivial doc question — it should invoke `wiki-read`
- [ ] Have the LLM "implement" a tiny change and then update the wiki — it should invoke `wiki-update`
- [ ] Inspect the result: page has valid frontmatter, refs resolve, index was updated, commit has correct prefix + session + touched trailers
- [ ] Run `wk-ingest-cc <TOKEN> --project <name>` — JSONL lands in `conversations/claude-code/`

If all six check out, MVP is working.

---

## Build order (dependency-respecting)

1. Prerequisites (0)
2. Directory + git (1)
3. Wiki CLAUDE.md (2) — agents reference this
4. SessionStart hook (3) — independent, can be parallel with 2
5. `wk-commit` (4) — agents call this
6. `wk-ingest-cc` (5) — independent
7. `wiki-read` agent (6)
8. `wiki-update` agent (7) — needs `wk-commit`
9. Code-repo CLAUDE.md template (8)
10. User preferences (9)
11. Bootstrap doc (10) — folds in everything above
12. E2E test (11)
