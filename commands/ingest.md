Ingest material into the wiki from whatever the user describes — one or more files, a directory or repo, this conversation, a topic in prose, or any mix. Interpret the request, gather candidate material, find what the wiki already knows, surface contradictions in real time, then delegate confirmed facts to `wiki-update`.

This is the focused, contradiction-checked path for building or extending wiki pages. It is distinct from `/wiki-sync`, which does a broad end-of-session sweep (log, pitfalls, decisions across many pages). If the user wants "record everything we did this session," prefer `/wiki-sync`.

**HARD RULES — read before doing anything:**

- This command IS the procedure. Work through Steps 0–11 in order. Do not improvise a shortcut.
- You do NOT write wiki content yourself, and you do NOT delegate to `wiki-update` until **Step 11**, and only **after** the user has explicitly approved the plan you present in Step 10. Calling `wiki-update` before then is a failure of this command.
- Several steps are interactive and BLOCK on a user reply: the early echo (Step 1), focus (Step 2), project confirmation (Step 4), each contradiction (Step 9), and the plan approval (Step 10). Stop and wait at each — never assume the answer and continue.
- If you find yourself about to call `wiki-update` and you have not yet presented a plan and gotten a "yes," stop: you have skipped the backbone. Go back to the earliest step you skipped.

**Setup:**
1. Get the session token from system context (format: `cc-<uuid>`).
2. Read the repo's `CLAUDE.md`. Its "Wiki" section names the repo's project path (`$WIKI_ROOT/projects/<name>/`) — treat `<name>` as the default ingest project. Read `$WIKI_ROOT/CLAUDE.md` and `$WIKI_ROOT/index.md` to orient.

---

**Step 0 — Interpret the request**

Read `$ARGUMENTS` as a free-form description, not as rigid path args. Combine it with the conversation context to figure out what the user wants ingested. The sources may be any mix of:

- **Named files** (one or many) — resolve to absolute paths.
- **A directory, glob, or whole repo** — for overviews and structure.
- **This conversation** — when the user says things like "I'm building X, add a page about it" or the material lives in what you just discussed.
- **A topic in prose** — a subject to write up, drawing on the conversation and any files it points to.

Do not force the request into a single "mode." A single ingest can blend sources (e.g. "this conversation plus `camera_controller.py`"). The source types below are gather-strategies, not exclusive branches.

If the request is empty and the conversation gives no clear subject, ask the user what they want to ingest.

---

**Step 1 — Early echo (lightweight)**

Before reading anything substantial, restate your interpretation in one or two lines and get a go-ahead:

> "I'll pull from: `<source A>`, `<source B>`, and this conversation about `<topic>`. Output as `<discrete facts | overview page>` under `<project guess>`. Go?"

This is cheap insurance against a misread — especially before reading a whole directory. Accept corrections, then proceed. The project-selection and final-plan gates still backstop you.  In general spec files used to generate features are ephemeral, so specifically ask the user about `.md` files that look like specs.

---

**Step 2 — Focus + output intent**

Ask the user (skip if the echo already made both clear):

> "What are you looking to get out of this? (e.g. technical concepts, API/protocol details, architectural decisions, pitfalls, a source summary, code patterns, or a structured overview with links.)"

Capture two things:

- **Focus** — the filter for what's worth extracting. Everything downstream is filtered by it.
- **Output shape**:
  - **Discrete facts** — default for single files, PDFs, conversations. Each fact is filed individually with its own ref anchor.
  - **Overview page with links** — default for directories/repos. A structured page (purpose, architecture, key modules) with `nvim://` links to entry points, rather than a flat list of facts.

Infer the default from the dominant source but let the user override.

---

**Step 3 — Topic scan**

Skim just enough to identify topics for project routing. Do NOT extract facts yet.

- PDF: headings + abstract
- Markdown/text: section titles
- Code: top-level symbols
- Directory/repo: top-level layout + entry points
- Conversation/topic: the subjects already in play

---

**Step 4 — Project selection**

Resolve in this order and stop at the first that fires:

1. Explicit project named in the request (e.g. `project=motor-controller`).
2. The project named in the repo's `CLAUDE.md` "Wiki" section (the `<name>` in `$WIKI_ROOT/projects/<name>/`).
3. Delegate to `wiki-read` with the focus + topics from Step 3. Ask it to return a short list of projects whose scope could plausibly include this material, one-line rationale each.

Propose the winner:

> "I'm planning to file this under `<project>`. Override? (y/n or name another)"

Record as `PROJECT`. If no project exists yet, offer to run `wk-new-project` — do not silently create one.

---

**Step 5 — Place / reference the sources**

For each file-backed source, decide how the wiki will reference it. Pick by rule, tell the user which rule fired, accept overrides:

- **Code files** (c/cpp/h/py/js/ts/go/rs/java/sh/lua/etc.): always link via `nvim://<repo>/<path>::symbol`. Never copy.
- **Files already under `$WIKI_ROOT`**: reference in place.
- **Files inside another git repo or a user-maintained notes vault**: default link (absolute path in a `file://` or `nvim://` URI).
- **Loose external material (downloaded PDFs, one-off articles)**: default copy into `$WIKI_ROOT/projects/$PROJECT/raw/{papers,articles,assets}/` — choose subdir by kind.

If copying: `cp` via Bash, record the new wiki-relative path as a `RAW_PATH`. If linking: record the absolute source path as a `RAW_PATH`. There may be several.

Conversation/topic-only sources have no file to place — their ref anchor is `(ref: conv:cc-<token>)`. Skip this step for them.

---

**Step 6 — "Material already covered?" check**

Avoid re-adding what the wiki already has.

- **File sources**: check whether the wiki already cites the file:

  ```bash
  rg -l "<filename-or-path>" "$WIKI_ROOT" --glob '*.md'
  ```

  If a page's frontmatter `sources:` already lists it:

  > "This file is already referenced by: `<pages>`. Is this an updated version?"

  - **Updated version**: try to diff against the prior content (previous copy under `raw/` via `git log -- <path>` + `git show`; or ask the user for the prior path if linked). Scope the rest of the ingest to the *differences*.
  - **Not an update**: note it and continue — don't re-file facts already present.

- **Conversation / topic / overview sources**: there's no filename to grep. Fold the dedup into the coverage check (Step 8): `wiki-read` finds existing pages on the topic, and the plan (Step 9) marks each target as *create-new-page* vs *extend-existing*.

---

**Step 7 — Gather candidate material**

Read the sources, filtered by focus. For every candidate fact, record its specific ref anchor:

- **PDF**: 0-indexed zathura page number
- **Code**: the exact symbol name for `nvim://...::symbol`
- **Markdown/text**: section heading or line number
- **Conversation/topic**: `(ref: conv:cc-<token>)`
- **Directory/repo overview**: map structure and identify entry points/key symbols (do NOT read every line); collect `nvim://` links to the files/symbols the overview will reference.

For the **overview** output shape, produce a structured draft (purpose, architecture, key modules) with its links rather than a flat fact list. For **discrete facts**, produce a numbered candidate list.

If a source has nothing on the stated focus, say so and drop it.

---

**Step 8 — Wiki coverage check**

Delegate to `wiki-read`. Give it specific terms from the candidate material. Ask for:
- Pages on these topics, with a concise summary of what they say
- Page citations

`wiki-read` does NOT do contradiction detection. You compare its output to your candidate material in the main thread.

---

**Step 9 — Contradictions (interactive)**

For each conflict you identify, surface it one at a time and wait for a decision:

> "The material says [X]. The wiki currently says [Y] on [page]. Keep the wiki as-is, replace with the new version, or note both?"

Record each resolution.

---

**Step 10 — Present the ingest plan**

```
## Sources
<each source — RAW_PATH copied | linked in place | conversation>

## Output
discrete facts | overview page

## Candidate material
<numbered facts with ref anchors, OR the overview draft with its links>

## Wiki coverage
<what already exists on these topics, with page refs>

## Proposed changes
<for each target: create-new-page OR extend-existing, with the specific addition and its ref>

## Contradictions resolved
<one line per conflict and how it will be written>
```

Ask the user:
- Which facts/sections to include (all, a numbered subset, or none)
- Project still right?
- Any other adjustments

---

**Step 11 — Delegate to `wiki-update`**

Once the user confirms, delegate to `wiki-update` with a structured brief:

- Project: `$PROJECT`
- Session token: `cc-<token>`
- Each `RAW_PATH` — add to every touched page's frontmatter `sources:` (conversation sources contribute `conv:cc-<token>` refs instead)
- Per fact/section: target page path, create-or-extend, the exact text to add, and its ref anchor
- Resolved contradictions: what to write and where
- Commit prefix: `ingest`

When `wiki-update` returns, briefly report to the user which pages were created/modified.
