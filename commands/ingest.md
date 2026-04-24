Ingest a single file into the wiki. Place the file, find what the wiki already knows about its topics, surface contradictions with the user in real time, then delegate confirmed facts to `wiki-update`.

**Setup:**
1. Identify the file from $ARGUMENTS. If empty, ask the user to specify a file. If multiple files are given, process only the first and tell the user to run `/ingest` again for the rest. If the user included an explicit project in the args (e.g. `project=motor-controller`), capture it.
2. Get the session token from system context (format: `cc-<uuid>`).
3. Read the repo's `CLAUDE.md`. Its "Wiki" section names the repo's project path (`$WIKI_ROOT/projects/<name>/`) — treat `<name>` as the default ingest project. Read `$WIKI_ROOT/CLAUDE.md` and `$WIKI_ROOT/index.md` to orient.

---

**Step 1 — Focus**

Ask the user:

> "What are you looking to get out of this file? (e.g. technical concepts, API or protocol details, architectural decisions, pitfalls, a source summary, code patterns, etc.)"

Hold the answer — everything downstream is filtered by it.

---

**Step 2 — Topic scan**

Skim just enough to identify topics for project routing. Do NOT extract facts yet.

- PDF: headings + abstract
- Markdown/text: section titles
- Code: top-level symbols

---

**Step 3 — Project selection**

Resolve in this order and stop at the first that fires:

1. Explicit project from $ARGUMENTS.
2. The project named in the repo's `CLAUDE.md` "Wiki" section (the `<name>` in `$WIKI_ROOT/projects/<name>/`).
3. Delegate to `wiki-read` with the focus + topics from Step 2. Ask it to return a short list of projects whose scope could plausibly include this material, one-line rationale each.

Propose the winner:

> "I'm planning to file this under `<project>`. Override? (y/n or name another)"

Record as `PROJECT`. If no project exists yet, offer to run `wk-new-project` — do not silently create one.

---

**Step 4 — Place the file**

Decide how the wiki will reference the file. Pick by rule, tell the user which rule fired, accept overrides:

- **Code files** (c/cpp/h/py/js/ts/go/rs/java/sh/lua/etc.): always link via `nvim://<repo>/<path>::symbol`. Never copy.
- **Files already under `$WIKI_ROOT`**: reference in place.
- **Files inside another git repo or a user-maintained notes vault**: default link (absolute path in a `file://` or `nvim://` URI).
- **Loose external material (downloaded PDFs, one-off articles)**: default copy into `$WIKI_ROOT/projects/$PROJECT/raw/{papers,articles,assets}/` — choose subdir by kind.

If copying: `cp` via Bash, record the new wiki-relative path as `RAW_PATH`. If linking: record the absolute source path as `RAW_PATH`.

---

**Step 5 — Already-ingested check**

Check whether the wiki already cites this file:

```bash
rg -l "<filename-or-path>" "$WIKI_ROOT" --glob '*.md'
```

If any page's frontmatter `sources:` already lists it, tell the user:

> "This file is already referenced by: <pages>. Is this an updated version?"

- **Updated version**: try to diff against the prior content (previous copy under `raw/` via `git log -- <path>` + `git show`; or ask the user for the prior path if linked). Scope the rest of the ingest to the *differences* — the wiki update should reflect what changed, not re-add the whole thing.
- **Not an update**: note it and continue — don't re-file facts already present.

---

**Step 6 — Read the file**

Read in full, filtered by focus. For every candidate fact you extract, record its specific ref anchor:

- PDF: 0-indexed zathura page number
- Code: the exact symbol name for `nvim://...::symbol`
- Markdown/text: section heading or line number

If the file has nothing on the stated focus, stop and tell the user.

---

**Step 7 — Wiki coverage check**

Delegate to `wiki-read`. Give it specific terms from the candidate facts. Ask for:
- Pages on these topics, with a concise summary of what they say
- Page citations

`wiki-read` does NOT do contradiction detection. You compare its output to your candidate facts in the main thread.

---

**Step 8 — Contradictions (interactive)**

For each conflict you identify, surface it one at a time and wait for a decision:

> "The file says [X]. The wiki currently says [Y] on [page]. Keep the wiki as-is, replace with the file's version, or note both?"

Record each resolution.

---

**Step 9 — Present the ingest plan**

```
## Placement
<RAW_PATH> — copied | linked in place

## Candidate facts
<numbered list — only facts matching the stated focus, each with its ref anchor>

## Wiki coverage
<what already exists on these topics, with page refs>

## Proposed changes
<for each fact: new page to create OR existing page to edit, with the specific addition and its ref>

## Contradictions resolved
<one line per conflict and how it will be written>
```

Ask the user:
- Which facts to include (all, a numbered subset, or none)
- Project still right?
- Any other adjustments

---

**Step 10 — Delegate to `wiki-update`**

Once the user confirms, delegate to `wiki-update` with a structured brief:

- Project: `$PROJECT`
- Session token: `cc-<token>`
- `RAW_PATH` — add to every touched page's frontmatter `sources:`
- Per fact: target page path, create-or-edit, the exact text to add, and its ref anchor
- Resolved contradictions: what to write and where
- Commit prefix: `ingest`

When `wiki-update` returns, briefly report to the user which pages were created/modified.
