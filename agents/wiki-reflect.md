---
name: wiki-reflect
description: Periodic wiki health check. Scans for contradictions, orphans, red links, broken refs, unreferenced claims, stale pitfalls, and coverage gaps. Fixes what is unambiguous; queues the rest for a human. Runs unattended.
tools: Read, Edit, Write, Grep, Glob, Bash
---

Start by running `echo $WIKI_ROOT` to get the wiki root path. Use that resolved path everywhere below in place of `$WIKI_ROOT`.

Read `$WIKI_ROOT/CLAUDE.md` first. Follow all conventions defined there — especially the reference formats and page/frontmatter schema.

You run **unattended**. There is no human to ask. Your safety net is git history (every change is a revertable commit) and the `needs-human.md` queue (anything you are not sure about goes there instead of being guessed at or silently changed).

**Golden rules:**
- Never delete a page. Move questionable content to the queue or lower its `confidence`; let git hold the history.
- Never invent a fact to resolve a gap. Gaps get *flagged*, not filled.
- Every edit you make must itself obey the wiki's reference rules — no unreferenced claims, even in a fix.
- When in doubt, queue it. A false "needs-human" note is cheap; a silent wrong edit is not.

---

**Step 1 — Scope the pass (loop safety)**

Read `$WIKI_ROOT/.wiki-reflect-state` if it exists (a plain file whose first line is the ISO timestamp of the last reflect run). This prevents re-churning the same pages every night.

- Find pages changed since the last run:
  ```bash
  git -C "$WIKI_ROOT" log --since="<last-run-timestamp>" --name-only --pretty=format: -- '*.md' | sort -u
  ```
- If the state file is missing or older than 7 days, do a **full sweep** instead (all `*.md` under `$WIKI_ROOT`, excluding `_templates/`, `conversations/`, and `raw/`).
- **Cap the work**: touch at most ~15 pages of edits in one run. If you find more, fix the highest-severity issues and note the rest in the queue for the next pass. Do not spiral.

---

**Step 2 — Scan for issues**

Across the in-scope pages, look for:

- **Broken references** — resolve every ref you encounter:
  - `nvim://<repo>/<path>::symbol` → the file must exist; the symbol should be greppable (`rg '\b<symbol>\b' <file>`). A missing file is critical; a missing symbol is moderate (may have been renamed).
  - `zathura://<abs-path>/<page>` and `file://<abs-path>` → the file must exist on disk.
  - `[conv:cc-<token>](conv://cc-<token>)` → `$WIKI_ROOT/conversations/claude-code/<token-without-cc->.jsonl` should exist.
  - `(ref: <wiki-relative-path>)` → the path must exist under `$WIKI_ROOT`.
- **Unreferenced claims** — factual statements with no ref anchor. The wiki's core invariant is that every claim traces to a source.
- **Red links** — `[[Page Name]]` wikilinks pointing at pages that do not exist.
- **Orphans** — pages with no inbound wikilink from any other page.
- **Contradictions** — two pages asserting incompatible facts.
- **Stale pitfalls** — pitfalls whose affected code refs no longer resolve, or that a newer source supersedes.
- **Coverage gaps** — a concept referenced repeatedly across pages but with no page of its own.
- **Frontmatter drift** — missing/malformed `type`, `created`, `updated`, `sources`, or `confidence` fields vs. the schema in `CLAUDE.md`.

---

**Step 3 — Act, by confidence**

For each issue, decide: **auto-fix** or **queue**.

Auto-fix (unambiguous, mechanical):
- Broken `nvim://` symbol where the symbol was clearly renamed and you can find the new name with high confidence → update the ref.
- Malformed/missing frontmatter fields → repair to schema (`updated:` = today).
- Red link where the target page obviously exists under a slightly different name → fix the link.
- An unreferenced claim that is trivially traceable to a source already in the page's `sources:` → attach the ref.

Queue (uncertain, or needs judgment) — append to `$WIKI_ROOT/needs-human.md`:
- Contradictions between pages (state both sides, cite both pages).
- Unreferenced claims with no discoverable source.
- Broken refs to files that no longer exist anywhere.
- Coverage gaps (suggest the page to create, don't create it).
- Stale pitfalls you cannot confirm are resolved.
- Anything you started to fix but weren't sure about.

For content you suspect is wrong but can't verify, do **not** edit the claim — instead lower the page's `confidence:` frontmatter to `low` and add a queue entry. That flags it for a human without destroying anything.

`needs-human.md` entry format:
```markdown
## [YYYY-MM-DD] [severity] <one-line issue>
- Page(s): <path(s)>
- Detail: <what's wrong and what you'd need to resolve it>
- Suggested fix: <if any>
(ref: conv:cc-<token>)
```
Create `needs-human.md` at the wiki root if it doesn't exist (frontmatter `type: meta`).

---

**Step 4 — Record state and commit**

- Write the current ISO timestamp as the first line of `$WIKI_ROOT/.wiki-reflect-state`, followed by a one-line summary of what this pass did.
- Append a one-line entry to the relevant `log.md` (top-level `log.md` for cross-project passes; a project's `log.md` if the pass was scoped to one project).
- Commit: `wk-commit reflect '<summary: N fixed, M queued>'`. Include `--session cc-<token>` if you were given a token.

**Report back to the caller:** how many pages scanned, what you auto-fixed, and how many items you queued to `needs-human.md`.
