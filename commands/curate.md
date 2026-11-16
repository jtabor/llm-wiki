Autonomously ingest material into the wiki — no human in the loop. Interpret the request, gather the material, find what the wiki already knows, resolve contradictions by policy, and file everything worth keeping immediately.

This is the **headless** sibling of `/ingest`. `/ingest` blocks on human approval at every step; `/curate` never asks. Whatever is worth keeping gets written now. Git history is the undo; there is no plan-approval gate.

Use `/curate` when running unattended (cron, `SessionEnd` hook, inbox watcher). Use `/ingest` when a human is present and wants to steer.

**Autonomous policy — how former human gates are resolved:**

- **Focus** → extract anything of lasting technical value: decisions, technical facts, API/protocol details, architecture, code patterns, pitfalls. Skip transient chatter.
- **Output shape** → discrete facts for single files / PDFs / conversations; a structured overview page (purpose, architecture, key modules, `nvim://` links) for directories and repos. Infer from the dominant source.
- **Project routing** → resolve without asking; see Step 3.
- **Contradictions** → resolve without asking; see Step 6.
- **Plan approval** → none. Gather → dedup → write. The commit is the record.

**Hard rules:**
- Never ask a question and then answer it yourself. If something is genuinely undecidable, file the fact with `confidence: low` and note the ambiguity inline — don't stall, and don't fabricate.
- Every claim you file must carry a resolvable ref. No ref, no write.
- You do not write pages yourself — you gather and decide, then delegate the actual writes to `wiki-update` (Step 7).

**Setup:**
- Get the session token from system context (format: `cc-<uuid>`).
- Read `$WIKI_ROOT/CLAUDE.md` and `$WIKI_ROOT/index.md` to orient. If the repo has a `CLAUDE.md` with a "Wiki" section, its `<name>` is the default project.

---

**Step 0 — Interpret the request & gather sources**

Read `$ARGUMENTS` as a free-form description. Combine with conversation context. Sources may be any mix of:
- Named files → resolve to absolute paths.
- A directory / glob / repo → overview.
- **The inbox** → if `$ARGUMENTS` is empty or says "inbox", ingest everything in `$WIKI_ROOT/inbox/`. After a file is successfully ingested, move it to the project's `raw/` (if copied) or delete it from the inbox (if it was linked in place) so it isn't re-ingested next run.
- This conversation → when the material lives in what was just discussed.
- A topic in prose → a subject to write up.

If there is genuinely nothing to ingest (empty inbox, empty args, no conversational subject), report "nothing to ingest" and stop. Do not invent work.

---

**Step 1 — Topic scan**

Skim just enough to route: PDF headings/abstract, markdown section titles, code top-level symbols, directory layout + entry points. Do not extract facts yet.

---

**Step 2 — Place / reference the sources**

For each file-backed source, decide by rule (no ask):
- **Code files** (c/cpp/h/py/js/ts/go/rs/java/sh/lua/etc.) → link via `nvim://<repo>/<path>::symbol`. Never copy.
- **Files already under `$WIKI_ROOT`** → reference in place.
- **Files inside another git repo or notes vault** → link (absolute path in `file://` or `nvim://`).
- **Loose external material** (downloaded PDFs, one-off articles) → copy into `$WIKI_ROOT/projects/$PROJECT/raw/{papers,articles,assets}/`, subdir by kind.

Record each as a `RAW_PATH`. Conversation/topic sources have no file — their anchor is `(ref: conv:cc-<token>)`.

---

**Step 3 — Project routing (no ask)**

Resolve in order, stop at the first that fires:
1. Explicit project named in the request (`project=<name>`).
2. The project named in the repo's `CLAUDE.md` "Wiki" section.
3. Delegate to `wiki-read` with the focus + topics; take the best-fit existing project it returns.
4. If nothing fits, **create** one: pick a short kebab-case name from the dominant topic, run `wk-new-project <name>`, and add it to `$WIKI_ROOT/index.md`. Do not stall waiting for a name.

Record as `PROJECT`.

---

**Step 4 — Already covered?**

Avoid re-adding what's present:
```bash
rg -l "<filename-or-path>" "$WIKI_ROOT" --glob '*.md'
```
If a page's frontmatter `sources:` already lists the file, treat this as a possible update: diff against the prior `raw/` copy via `git log -- <path>` + `git show`, and scope the ingest to the *differences*. If it's clearly the same content already filed, skip it.

For conversation/topic/overview sources (no filename), fold dedup into Step 5's coverage check — mark each target create-new vs. extend-existing.

---

**Step 5 — Gather candidate facts + coverage check**

Read the sources filtered by focus. For every candidate fact, record its exact ref anchor:
- PDF → 0-indexed zathura page.
- Code → the exact symbol for `nvim://...::symbol`.
- Markdown/text → section heading or line number.
- Conversation/topic → `(ref: conv:cc-<token>)`.
- Directory/repo overview → map structure, collect `nvim://` links to entry points/key symbols (don't read every line).

Then delegate to `wiki-read` with specific terms to learn what the wiki already says on these topics, with page citations. You compare its output to your candidates in this thread.

---

**Step 6 — Resolve contradictions (by policy, no ask)**

For each conflict between new material and an existing page:
- **Default: prefer the newer, better-sourced claim.** Update the page to the new version, but preserve the old assertion as a dated note ("Previously: X — superseded YYYY-MM-DD by <ref>") rather than deleting it. Git holds the full history regardless.
- If you cannot tell which is correct, **keep both**, mark the page `confidence: low`, and include a `needs-human.md` queue entry in the Step 7 brief (`wiki-update` appends it) so a human can review later.
- Never silently overwrite a well-sourced claim with a weakly-sourced one.

---

**Step 7 — Delegate to `wiki-update` immediately**

No approval step. Hand `wiki-update` a structured brief:
- Project: `$PROJECT`
- Session token: `cc-<token>`
- Each `RAW_PATH` → add to every touched page's frontmatter `sources:` (conversation sources contribute `conv:cc-<token>` instead)
- Per fact/section: target page path, create-or-extend, the exact text to add, its ref anchor, and a `confidence:` value
- Resolved contradictions: what to write and where
- Commit prefix: `ingest`

When `wiki-update` returns, complete the inbox cleanup from Step 0 (move/delete ingested files), then report which pages were created/modified and which inbox items were consumed.
