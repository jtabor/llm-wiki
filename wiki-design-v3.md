# Compounding Wiki — Design Document (v3)

## Overview

An LLM-maintained, git-versioned knowledge base organized as a collection of **project vaults** under a single Obsidian vault. Each project is self-contained with its own schema, index, log, and pitfalls. Cross-cutting knowledge (user preferences, people, global pitfalls) lives at the top level.

The human curates sources, explores interactively, and edits freely. The LLM does the bookkeeping. Both can write.

---

## Top-Level Structure

```
wiki/                              # the obsidian vault root
├── CLAUDE.md                      # top-level schema + conventions
├── index.md                       # master index across all projects
├── log.md                         # global activity log
├── pitfalls.md                    # cross-project lessons learned
│
├── user/                          # cross-cutting user info
│   ├── preferences.md             # coding style, formatting, tool prefs
│   ├── email-style.md             # how the user writes emails
│   └── communication.md           # general comm preferences
│
├── people/                        # entity pages for people
│   ├── alice-chen.md
│   ├── bob-martinez.md
│   └── ...
│
├── conversations/                 # claude code session transcripts
│   └── claude-code/
│       ├── <session-uuid>.jsonl           # raw transcript (auto-archived)
│       └── <session-uuid>/
│           └── <agent-id>.jsonl           # subagent transcripts
│
├── projects/                      # project-scoped vaults
│   ├── motor-controller/          # one project
│   │   ├── CLAUDE.md              # project-specific schema
│   │   ├── index.md               # project index
│   │   ├── log.md                 # project activity log
│   │   ├── pitfalls.md            # project-specific pitfalls
│   │   ├── sources/               # source summaries
│   │   ├── concepts/              # topic pages
│   │   ├── codebases/             # codebase exploration notes
│   │   ├── analyses/              # filed query results
│   │   └── raw/                   # immutable source material
│   │       ├── papers/
│   │       ├── articles/
│   │       ├── code/
│   │       └── assets/
│   │
│   ├── rtos-research/             # another project
│   │   ├── CLAUDE.md
│   │   ├── index.md
│   │   └── ...
│   │
│   └── ...
│
├── tools/                         # CLI tooling
│   ├── wk-commit
│   ├── wk-search
│   ├── wk-move-ref
│   └── wk-ingest-cc
│
├── _templates/                    # obsidian templates (excluded from index)
│   ├── project-claude.md          # template for new project CLAUDE.md
│   ├── person.md
│   ├── concept.md
│   ├── source.md
│   ├── codebase.md
│   └── analysis.md
│
└── .git/
```

---

## The Two CLAUDE.md Files

### 1. Wiki CLAUDE.md (lives at wiki root)

The master schema. Defines conventions, page formats, cross-project
rules, and how the LLM should behave when operating on the wiki.
Each project's wiki CLAUDE.md starts as a copy of relevant sections,
then diverges.

### 2. Project CLAUDE.md (lives in each project dir on disk)

This lives in the **actual project directory** on the filesystem
(e.g., `~/projects/motor-controller/CLAUDE.md`), NOT in the wiki.
It's what Claude Code sees when you open the project. It bridges
the project to its wiki:

```markdown
# CLAUDE.md — Motor Controller Firmware

## Wiki
This project's wiki lives at: ~/wiki/projects/motor-controller/
Read the wiki's CLAUDE.md for documentation conventions.
Read the wiki's index.md before any documentation task.
Read the user preferences at: ~/wiki/user/preferences.md

## Project
- Language: C (arm-none-eabi-gcc), Python (tooling)
- Build: CMake + Ninja
- Target: STM32H743
- Repo root: ~/projects/motor-controller/

## Session ID
A session token is injected at startup via the SessionStart hook
(see "Session Identification" in wiki CLAUDE.md). Use this token
in all wiki references made during this session. To find the full
transcript later:
  grep -rl "SESSION_TOKEN" ~/.claude/projects/ --include="*.jsonl" \
    --exclude="*history.jsonl"

## File References
All file references in wiki pages use paths relative to this
project root. Example: `src/drivers/dma.c::dma_init` means
~/projects/motor-controller/src/drivers/dma.c, symbol dma_init.

## After Feature Completion
When a feature is implemented, update the wiki:
1. Update relevant codebase/concept pages with what changed
2. Reference the conversation (by session ID) where the work happened
3. Add any new pitfalls discovered during implementation
4. Update the project index and log
5. Commit the wiki: wk-commit "update: {feature description}"
```

---

## Agents (not Skills)

Wiki operations are Claude Code **sub-agents** — not Claude.ai
skills. The wiki's own CLAUDE.md serves as the agent's prompt.
Claude Code reads it and knows how to operate.

Why agents over skills:
- Wiki ops need to read files, grep, edit multiple pages, run git — that's agent territory
- Skills are prompt templates for Claude.ai's file-creation environment — wrong execution context
- The CLAUDE.md *is* the agent definition — no separate skill file needed
- Sub-agents can be invoked via `claude --print` or task delegation within a session

### Agent Definitions (in wiki CLAUDE.md)

Three agent roles, defined as sections in the wiki CLAUDE.md:

#### wiki-update agent
When to invoke: creating or modifying wiki pages.
Responsibilities: page format conventions, frontmatter schema,
wikilink syntax, index.md and log.md updates, pitfall checks,
verifiable references, git commits.

#### wiki-read agent
When to invoke: finding and reading wiki content to answer
questions or load context.
Responsibilities: read index.md to locate pages, navigate project
structure, resolve code anchors, cross-reference people pages
and user preferences.

#### wiki-reflect agent
When to invoke: user asks for a wiki health check.
Responsibilities: scan for contradictions, orphans, red links,
broken anchors, stale content, coverage gaps, unresolvable
references. Report findings and suggest fixes.

These aren't separate executables — they're workflow instructions
embedded in CLAUDE.md that Claude Code follows based on the task.
Think of them as "modes" the agent enters.

---

## Verifiable References

**Every claim in the wiki must trace back to a verifiable source.**
This is a core invariant. If you can't check where something came
from, it's not trustworthy.

### Reference Types

#### Code References — use the `nvim` skill
All code references use `nvim://` URIs as defined by the **nvim skill**.
Prefer semantic anchors (`::symbol`) over line numbers — they survive
edits. Use git-pinned links (`@hash`) when referencing a specific
historical version. See the nvim skill for full URI format details.

```markdown
The DMA setup lives in [`dma_init()`](nvim://motor-ctrl/src/drivers/dma.c::dma_init).
As it was at the regression: [`dma_init@abc1234`](nvim://motor-ctrl/src/drivers/dma.c::dma_init@abc1234).
```

The nvim skill is the source of truth for URI format, supported
languages, and resolution behavior. Do not duplicate its spec here.

#### PDF References — use the `pdf` skill
All PDF page references use `zathura://` URIs as defined by the
**pdf skill**. Always use absolute paths. Page numbers in zathura
links are **0-indexed** (PDF page 31 = `/30`).

```markdown
See register description → [p.43](zathura:///home/jtabor/workspace/project/datasheet.pdf/42)
```

The pdf skill is the source of truth for URI format and zathura
interaction. Do not duplicate its spec here.

#### Conversation References
```markdown
(ref: conv:cc-WK7x9mQ3)
```
Links to the conversation transcript. The session token maps to
a JSONL file in `~/.claude/projects/` via grep (excluding
history.jsonl). Ingested transcripts are stored in
`conversations/claude-code/`.

#### Source File References
```markdown
(ref: raw/papers/rtos-survey-2024.pdf)
(ref: raw/articles/2026-04-01-dma-best-practices.md)
```
Path to the raw source material.

### Reference Rules (enforced by wiki-update agent)

1. Every factual claim added to a wiki page MUST have a reference
2. Code references use `nvim://` URIs (read the nvim skill for format)
3. PDF page references use `zathura://` URIs (read the pdf skill for format)
4. Conversation references use `(ref: conv:cc-{token})`
5. Source file references use `(ref: path/to/source)`
6. No free-form "I think..." without attribution
7. During reflection, the wiki-reflect agent checks that all references still resolve

### Frontmatter Source Tracking

Every wiki page's frontmatter lists its sources:

```yaml
sources:
  - raw/papers/rtos-survey-2024.pdf
  - raw/articles/2026-04-01-dma-best-practices.md
conversations:
  - conv:cc-WK7x9mQ3
```

This gives a page-level bill of materials — "everything this page
depends on." The wiki-reflect agent uses it to detect staleness.

---

## Code and PDF Links

Code references and PDF page links in wiki pages are handled
entirely by the **nvim skill** and **pdf skill** respectively.
Those skills define the URI formats, resolution behavior, and
tooling. The wiki CLAUDE.md should instruct the agent to read
those skills when creating or updating references.

Summary:
- Code → `nvim://` URIs with semantic anchors (see nvim skill)
- PDFs → `zathura://` URIs with 0-indexed pages (see pdf skill)
- Both are clickable in Obsidian

---

## Session Identification

### How It Works (Implemented)

The session token IS the Claude Code session UUID, prefixed with `cc-`.
It is injected into model context via a `UserPromptSubmit` hook on the
first message of each session.

**Why not `SessionStart`:** `SessionStart` hooks do not support
`additionalContext` injection — the field is silently ignored.
`UserPromptSubmit` does.

**Why not a custom random token:** Claude Code's own UUID is already
in every JSONL entry, so it's grep-able without any additional tracking.

Hook: `~/.claude/hooks/wiki-session-token.sh` (in tools repo).
On first message: creates `~/.claude/wiki-tokens/<session_id>`, injects:
> "Wiki session token for this session: cc-`<session_id>`. Use it in
> wiki refs and commit trailers this session."
On subsequent messages: exits silently.

Token is stable across resume/continue. A new UUID only appears on a
genuinely fresh session (not resume, not `/clear` — `/clear` triggers
`SessionEnd` and starts a new session with a new UUID).

### JSONL Archiving (Implemented)

JOSNLs are automatically archived to `$WIKI_ROOT/conversations/claude-code/`
by two hooks:
- `UserPromptSubmit` — archives before each new user message (captures completed exchanges)
- `SessionEnd` — archives on Ctrl-D / process exit

**`Stop` is NOT used for archiving.** It fires after every assistant turn
(not on process exit) and before the JSONL is committed to disk for that
turn — making it unreliable for this purpose.

Archive structure:
```
conversations/claude-code/
├── <session-id>.jsonl          # parent transcript
└── <session-id>/
    └── <agent-id>.jsonl        # one per subagent
```

Subagents share the parent's `session_id` but have a unique `agent_id`.

### Finding a Transcript

```bash
ls $WIKI_ROOT/conversations/claude-code/<session-id>.jsonl
# or, if not yet archived:
grep -rl "<session-id>" ~/.claude/projects/ --include="*.jsonl" \
  --exclude="*history.jsonl"
```

### Reference Format

```markdown
(ref: conv:cc-<session-uuid>)
```

### What Gets Extracted During Ingest

The LLM extracts from conversations:
- **Decisions made** → project concept/codebase pages
- **Preferences stated** → user preferences or person pages
- **Technical facts** → concept/codebase pages
- **Mistakes/debugging** → pitfalls.md

Each extraction cites the session token. You can always trace
"where did this come from?" back to the transcript.

---

## Reference Moving: wk-move-ref

When a file or directory gets renamed/moved, all references across
the entire wiki must update. `wk-move-ref` handles this automatically.

### Usage

```bash
# Move/rename a wiki page
$ wk-move-ref projects/motor-controller/concepts/dma.md \
               projects/motor-controller/concepts/dma-transfers.md
# 1. Renames the file
# 2. Finds all references to the old path across the entire wiki
#    (frontmatter sources, wikilinks, inline refs)
# 3. Replaces them with the new path
# 4. Reports what it changed
# 5. wk-commit "move: dma.md → dma-transfers.md"

# Move a raw source file
$ wk-move-ref projects/motor-controller/raw/papers/old-name.pdf \
               projects/motor-controller/raw/papers/new-name.pdf

# Move a code file (updates nvim:// URIs)
$ wk-move-ref --code --project ~/projects/motor-controller \
    src/drivers/dma.c src/drivers/dma_v2.c
# Updates all nvim://motor-controller/src/drivers/dma.c references to
# nvim://motor-controller/src/drivers/dma_v2.c

# Dry run — show what would change without doing it
$ wk-move-ref --dry-run projects/motor-controller/concepts/dma.md \
                         projects/motor-controller/concepts/dma-transfers.md
```

### What It Searches

The tool scans all `.md` files in the wiki for:
- `[[old/path]]` and `[[old/path|display text]]` (wikilinks)
- `(ref: old/path` ... `)` (inline references)
- `nvim://` URIs containing the old path
- `zathura://` URIs containing the old path
- YAML frontmatter `sources:` arrays
- Any other occurrence of the old path string

Implementation: `rg --files-with-matches "old-path" ~/wiki/ | xargs sed -i`
plus some awareness of wikilink and frontmatter syntax. Not rocket science,
but important to get right — the dry-run flag exists for a reason.

---

## Page Format Convention

Every wiki page uses YAML frontmatter. Both human and LLM can edit.

```markdown
---
type: entity | concept | source | analysis | codebase | pitfall
project: motor-controller
created: 2026-04-12
updated: 2026-04-12
tags: [embedded, stm32, rtos]
sources:
  - raw/papers/rtos-survey-2024.pdf
  - raw/articles/dma-best-practices.md
conversations:
  - conv:cc-WK7x9mQ3
confidence: high | medium | low | speculative
---

# Page Title

Content with verifiable references:

The DMA controller requires 32-byte alignment for buffers in
AXI SRAM ([p.42](zathura:///home/jtabor/workspace/motor-controller/raw/papers/cortex-m7-trm.pdf/41)).
The initialization lives in
[`dma_init()`](nvim://motor-controller/src/drivers/dma.c::dma_init),
which was refactored during the UART work (ref: conv:cc-WK7x9mQ3).

## See Also
- [[Related Page]]
```

---

## People Pages

```markdown
---
type: entity
subtype: person
created: 2026-04-12
updated: 2026-04-12
tags: [coworker, firmware-team]
conversations:
  - conv:cc-Rm4pX2aL
---

# Alex Chen

## Context
- Role: Senior firmware engineer
- Works on: motor control, CAN bus stack
- Timezone: US/Pacific

## Communication Preferences
- Prefers concise, technical emails — no fluff
- Likes diagrams over walls of text
- Responds faster on Slack than email

## Coding Style
- Tabs, not spaces
- Explicit error handling, no errno patterns
- Doxygen comments on public APIs

## Email Style
- Signs off with first name
- Uses bullet points
- Gets to the point fast

## Key Interactions
- Agreed on ping-pong DMA pattern
  (ref: conv:cc-Rm4pX2aL)
- Decided to split CAN driver into transport + application layers
  (ref: conv:cc-Tn8qY5bK)

## Notes
- Allergic to cats
- Into mountain biking
```

---

## Pitfalls

Per-project: `projects/{name}/pitfalls.md`.
Cross-project: top-level `pitfalls.md`.

```markdown
# Pitfalls

## [critical] DMA alignment on STM32H7
The H7 requires 32-byte alignment for DMA buffers in AXI SRAM.
`__attribute__((aligned(4)))` is NOT enough — need `aligned(32)`
or you get silent data corruption.
(ref: raw/papers/cortex-m7-trm.pdf)
(ref: conv:cc-Jw3nP8cR)
- Affected: [`dma_init()`](nvim://motor-controller/src/drivers/dma.c::dma_init)
- Tags: #stm32 #dma #alignment

## [moderate] UART RX overflow at high baud
At 921600 baud with DMA idle-line detection, half-transfer
interrupt fires too often with small buffers. Use >= 256 bytes.
(ref: conv:cc-Hv2mK6dQ)
- Tags: #stm32 #uart #dma
```

Severity: `critical`, `moderate`, `minor`.

The LLM checks pitfalls during feature implementation, ingest,
and reflection.

---

## Workflows

### Feature Implementation (Primary Coding Workflow)

1. User asks to implement a feature
2. LLM reads project CLAUDE.md → finds wiki location
3. LLM has session token from SessionStart hook
4. LLM reads wiki index.md + relevant codebase/concept pages
5. LLM reads pitfalls.md — flags anything relevant
6. LLM explores code (grep, reading files), assisted by wiki notes
7. LLM drafts implementation plan
8. User reviews, adjusts, approves
9. LLM implements, iterates with user
10. Feature complete — LLM updates wiki:
    - Updates codebase/concept pages with what changed
    - All new claims have verifiable references (source paths, session token)
    - Adds any new pitfalls discovered
    - Updates project index.md and log.md
    - `wk-commit "update: implemented {feature}"`

Step 10 is the one that usually gets skipped. Putting it in
CLAUDE.md means the LLM does it automatically.

### Interactive Source Ingest

Not fire-and-forget. The human and LLM read together.

1. Source arrives in `projects/{name}/raw/` (paper, article, code)
2. User tells LLM to read it
3. LLM reads, gives initial impressions / key takeaways
4. User and LLM discuss — what's important? what connects?
5. Together they decide what to extract and where it goes
6. LLM creates/updates wiki pages with verifiable references
   (every claim cites its source file path or session token)
7. LLM updates index.md, appends to log.md
8. LLM checks pitfalls — new ones? existing ones updated?
9. `wk-commit "ingest: {source title}"`

### Conversation Ingest

1. `wk-ingest-cc {token}` finds and converts the JSONL transcript
2. LLM reads the transcript, extracts:
   decisions, preferences, facts, pitfalls, action items
3. LLM files extractions to appropriate wiki pages, citing session token
4. All extracted claims include verifiable refs back to the transcript
5. Updates log.md
6. `wk-commit "ingest: conversation {conv-id}"`

### Query

1. User asks a question
2. LLM reads project index.md (and optionally global index.md)
3. LLM reads relevant pages, synthesizes answer
4. If the answer is reusable: offer to file as `analyses/{topic}.md`
5. Filed analyses include refs to the pages they synthesized from
6. Append query + summary to log.md
7. `wk-commit "query: {topic}"`

### Reflection

Periodic wiki health check. LLM scans for:

- **Contradictions** between pages
- **Stale claims** superseded by newer sources
- **Orphan pages** with no inbound wikilinks
- **Red links** — mentioned but nonexistent pages
- **Broken code anchors** — symbols that no longer resolve
- **Unresolvable references** — PDFs missing, pages deleted
- **Unreferenced claims** — statements without verifiable refs
- **Pitfall staleness** — pitfalls that may no longer apply
- **Coverage gaps** — important concepts lacking their own page
- **Suggested explorations** — new questions, sources to find

LLM fixes what's clear, flags what needs human input.
`wk-commit "reflect: {summary}"`

---

## User Preferences

Top-level `user/preferences.md`:

```markdown
---
type: meta
---

# User Preferences

## Coding
- Languages: C, Python
- Editor: neovim
- Prefer CLI over GUI
- Formatting: (project-specific, see project CLAUDE.md)

## Communication
- Technical, casual tone
- Concise — don't restate the question
- A little sarcasm is welcome
- No emojis unless asked
- No business jargon

## Documentation
- Markdown unless told otherwise
- No excessive headers or bullet nesting
- Code examples over prose explanations

## Email
- (user's email writing style and conventions)

## Other
- Linux daily driver
- Works from home
```

---

## Obsidian Integration

The wiki root IS the Obsidian vault.

- **Wikilinks**: enabled (default)
- **Attachment folder path**: each project's `raw/assets/`
- **Excluded folders**: `_templates` (from search/index)
- **Recommended plugins**:
  - **Dataview**: query frontmatter ("all pitfalls tagged #stm32")
  - **Graph View** (built-in): visualize connectivity
  - **Web Clipper**: clip articles to project `raw/articles/`
  - **Templater**: page templates from `_templates/`
  - **obsidian-git**: manual git trigger
  - **Marp Slides**: presentations from wiki content

---

## Git Workflow

Every wiki modification ends with a commit via `wk-commit`:

```bash
wk-commit "ingest: RTOS scheduling paper"
wk-commit "update: implemented DMA ping-pong"
wk-commit "reflect: fixed 3 broken wikilinks"
wk-commit "query: DMA mode comparison on STM32H7"
wk-commit "pitfall: UART buffer size at high baud"
wk-commit "move: dma.md → dma-transfers.md"
wk-commit "ingest: conversation conv:cc-WK7x9mQ3"
```

Prefixes: `ingest:`, `update:`, `reflect:`, `query:`, `pitfall:`, `move:`.

Time-travel:
```bash
git log --oneline -- projects/motor-controller/concepts/dma.md
git show HEAD~10:projects/motor-controller/concepts/dma.md
git log --since="2 hours ago" --oneline
git diff HEAD~5 -- projects/motor-controller/pitfalls.md
```

---

## CLI Tools

All live in `wiki/tools/`. Added to `$PATH` or symlinked.

| Tool | Purpose |
|------|---------|
| `wk-commit` | `cd ~/wiki && git add -A && git commit -m "$1"` |
| `wk-search` | Full-text search across wiki (ripgrep wrapper) |
| `wk-move-ref` | Rename/move a reference, update all wiki occurrences |
| `wk-ingest-cc` | Find JSONL by session token, convert to markdown |

Build order: `wk-commit`, `wk-move-ref`, `wk-ingest-cc`, `wk-search`.

---

## Bootstrapping

### New wiki from scratch

```bash
mkdir -p ~/wiki/{user,people,conversations/claude-code,projects,tools,_templates}
cd ~/wiki && git init
# LLM generates: CLAUDE.md, index.md, log.md, pitfalls.md
# LLM generates: templates in _templates/
# LLM generates: user/preferences.md from current session context
# Open as Obsidian vault
```

### New project

```bash
wk-new-project motor-controller ~/projects/motor-controller

# Creates:
# ~/wiki/projects/motor-controller/{CLAUDE.md,index.md,log.md,pitfalls.md}
# ~/wiki/projects/motor-controller/{sources,concepts,codebases,analyses}
# ~/wiki/projects/motor-controller/raw/{papers,articles,code,assets}
# ~/projects/motor-controller/CLAUDE.md (pointing to wiki)
# wk-commit "init: project motor-controller"
```

---

## Deliverables

In build order:

1. **Top-level CLAUDE.md** — the master schema with all conventions,
   agent definitions, reference formats, and workflows documented above.
   This is the single most important file. Everything else flows from it.

2. **CLI tools** — `wk-commit`, `wk-move-ref`,
   `wk-ingest-cc`, `wk-search`. Small shell scripts / Python scripts.

3. **Templates** — `_templates/` directory with page templates for
   each type (person, concept, source, codebase, analysis).

4. **Bootstrap script** — `wk-init` that creates the full directory
   structure and generates initial files.

---

## Open Design Questions

1. **Search scaling**: index.md works to ~100-200 pages per project.
   Beyond that, `rg` over the wiki. Beyond *that*, `qmd` or similar.
   Probably won't need it for a while.

2. **Multi-repo code references**: projects spanning multiple repos
   need a mapping in the project CLAUDE.md:
   `repos: {firmware: ~/projects/firmware, tools: ~/projects/fw-tools}`.
   Anchors become `code://firmware/src/main.c::main`.

3. **Conversation auto-ingest**: JSONL archiving is now automatic via
   `UserPromptSubmit` + `SessionEnd` hooks. Extraction (converting
   transcripts to wiki pages) remains manual — run `wk-ingest-cc`
   then have an LLM read and extract.

4. **Wiki isolation**: one git repo / one Obsidian vault, scoped by
   directory. Split into separate vaults if work/personal separation
   is needed. Start mono — cross-project links are valuable.

5. **MCP server**: eventually expose wiki tools as MCP so Claude uses
   them as native tools. Not needed at bootstrap — CLI works fine.

6. **SessionStart hook portability**: RESOLVED. `SessionStart`
   `additionalContext` is silently ignored — switched to `UserPromptSubmit`.
   Token is Claude Code's own session UUID (no custom generation needed).
   Tested and working on Claude Code (Sonnet 4.6, 2026-04-20).
