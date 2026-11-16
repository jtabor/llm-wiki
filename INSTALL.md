# Installation — Compounding Wiki

This repo contains everything needed to set up a self-maintaining, git-versioned wiki
that Claude Code populates automatically as you work.

## Prerequisites

- Claude Code CLI installed and authenticated
- `jq` on `$PATH`
- `git` on `$PATH`
- Python 3 (for `wk-ingest-cc`)

---

## Step 1 — Clone this repo

```bash
git clone <this-repo-url> ~/tools/llm-wiki
cd ~/tools/llm-wiki
```

---

## Step 2 — Shell environment

Add to `~/.zshrc` (or `~/.bashrc`):

```bash
export WIKI_ROOT=~/notes/wiki          # adjust path to taste
export PATH="$WIKI_ROOT/tools:$PATH"   # wiki CLI tools
```

Reload:
```bash
source ~/.zshrc
```

---

## Step 3 — Install hooks

```bash
REPO=~/tools/llm-wiki   # adjust if you cloned elsewhere
mkdir -p ~/.claude/hooks ~/.claude/wiki-tokens

ln -s "$REPO/hooks/wiki-session-token.sh"       ~/.claude/hooks/wiki-session-token.sh
ln -s "$REPO/hooks/wiki-archive-session.sh"     ~/.claude/hooks/wiki-archive-session.sh
ln -s "$REPO/hooks/wiki-allow-safe-commands.sh" ~/.claude/hooks/wiki-allow-safe-commands.sh
chmod +x "$REPO"/hooks/wiki-*.sh
```

---

## Step 4 — Merge settings into `~/.claude/settings.json`

`settings-fragment.json` contains the hook wiring. Merge it into your existing
`~/.claude/settings.json` — **do not replace the whole file**, just add the
`hooks` key (and `cleanupPeriodDays` if you want it).

The fragment to merge:

```json
{
  "cleanupPeriodDays": 365,
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/wiki-allow-safe-commands.sh" }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/wiki-session-token.sh" },
          { "type": "command", "command": "~/.claude/hooks/wiki-archive-session.sh" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/wiki-archive-session.sh" }
        ]
      }
    ]
  }
}
```

If you already have other hooks, merge carefully — both arrays need all their entries.

---

## Step 5 — Install subagents

```bash
mkdir -p ~/.claude/agents
ln -s "$REPO/agents/wiki-read.md"    ~/.claude/agents/wiki-read.md
ln -s "$REPO/agents/wiki-update.md"  ~/.claude/agents/wiki-update.md
ln -s "$REPO/agents/wiki-reflect.md" ~/.claude/agents/wiki-reflect.md
```

`wiki-reflect` is the unattended health-check agent (contradictions, broken refs,
orphans, coverage gaps). It fixes what's unambiguous and queues the rest to
`$WIKI_ROOT/needs-human.md`. It's the engine behind headless self-curation (Step 8).

---

## Step 5b — Install slash commands

```bash
mkdir -p ~/.claude/commands
ln -s "$REPO/commands/wiki-sync.md" ~/.claude/commands/wiki-sync.md
ln -s "$REPO/commands/ingest.md"    ~/.claude/commands/ingest.md
ln -s "$REPO/commands/curate.md"    ~/.claude/commands/curate.md
```

`/curate` is the **headless** sibling of `/ingest`: same gather → dedup →
contradiction-check → write flow, but with zero interactive gates. Whatever is
worth keeping is filed immediately; git history is the undo. Use `/ingest` when a
human is steering, `/curate` when running unattended (Step 8).

`/wiki-sync` — use at the end of any coding session to record what happened into the wiki. Optionally pass a focus area:

```
/wiki-sync
/wiki-sync focus on the DMA refactor
```

`/ingest <file>` — ingest a single file (paper, article, code, notes) into the wiki. Walks you through focus, project selection, placement, contradiction checks, and delegates writing to `wiki-update`.

```
/ingest ~/Downloads/rtos-survey-2024.pdf
/ingest src/drivers/dma.c project=motor-controller
```

---

## Step 6 — Bootstrap the wiki

```bash
mkdir -p $WIKI_ROOT/{projects,conversations/claude-code,tools,user,people,_templates,bootstrap}
cd $WIKI_ROOT && git init
```

Copy core template files (these are copied, not symlinked — you will edit them in place):

```bash
cp $REPO/wiki-templates/CLAUDE.md       $WIKI_ROOT/CLAUDE.md
cp $REPO/wiki-templates/index.md        $WIKI_ROOT/index.md
cp $REPO/wiki-templates/log.md          $WIKI_ROOT/log.md
cp $REPO/wiki-templates/pitfalls.md     $WIKI_ROOT/pitfalls.md
cp $REPO/wiki-templates/user/preferences.md  $WIKI_ROOT/user/preferences.md
cp $REPO/wiki-templates/bootstrap/code-repo-CLAUDE.md  $WIKI_ROOT/bootstrap/code-repo-CLAUDE.md

# Edit user/preferences.md to match your actual preferences
```

Copy the wiki `.gitignore`:

```bash
cat > $WIKI_ROOT/.gitignore <<'EOF'
raw/**/*.pdf
raw/**/*.png
raw/**/*.jpg
raw/**/*.jpeg
raw/**/*.mp4
raw/**/*.mov
.obsidian/workspace*
EOF
```

Install CLI tools into the wiki (so they live with the wiki and are on `$PATH`):

```bash
ln -s "$REPO/tools/wk-commit"      $WIKI_ROOT/tools/wk-commit
ln -s "$REPO/tools/wk-ingest-cc"   $WIKI_ROOT/tools/wk-ingest-cc
ln -s "$REPO/tools/wk-new-project" $WIKI_ROOT/tools/wk-new-project
ln -s "$REPO/tools/wk-autonomous"  $WIKI_ROOT/tools/wk-autonomous
chmod +x "$REPO"/tools/wk-*
```

Install the `conv://` URI handler (opens conversation transcripts in nvim):

```bash
ln -s "$REPO/tools/wk-open-conv" ~/bin/wk-open-conv
chmod +x "$REPO/tools/wk-open-conv"
ln -s "$REPO/install/wk-conv-goto.desktop" ~/.local/share/applications/wk-conv-goto.desktop
xdg-mime default wk-conv-goto.desktop x-scheme-handler/conv
```

Initial commit:

```bash
cd $WIKI_ROOT && git add -A && git commit -m "init: wiki bootstrap"
```

---

## Step 7 — Add your first project

```bash
wk-new-project my-project-name
```

This creates `$WIKI_ROOT/projects/my-project-name/` with `index.md`, `pitfalls.md`,
`log.md`, and all subdirectories.

Then copy the code-repo template into the actual project:

```bash
cp $WIKI_ROOT/bootstrap/code-repo-CLAUDE.md ~/projects/my-project-name/CLAUDE.md
# Edit it: fill in project name, language, build system, repo root path
```

Update `$WIKI_ROOT/index.md` to list the new project, then commit:

```bash
wk-commit init "project my-project-name"
```

---

## Step 8 — Headless / autonomous deployment (e.g. Raspberry Pi)

This runs the wiki as a self-curating system with **no human in the loop**: new
material gets ingested via `/curate`, and `wiki-reflect` periodically cleans up.
Intended for a dedicated always-on box.

**Safety model.** With no human gating writes, two things replace the reviewer:
1. **Git history** — every change is a revertable commit. Set up a remote so a bad
   autonomous run can be rolled back *and* the wiki survives the SD card dying.
2. **`needs-human.md`** — anything the agents can't resolve confidently is queued
   here instead of guessed at. Skim it periodically.

### 8a — Add a git remote (strongly recommended)

```bash
cd $WIKI_ROOT
git remote add origin <your-remote-url>
git push -u origin "$(git symbolic-ref --short HEAD)"
```

`wk-autonomous` pushes after each run if a remote exists.

### 8b — The inbox

Drop files (PDFs, articles, notes, code) into `$WIKI_ROOT/inbox/` and the next
`ingest` run files them, then clears them out:

```bash
mkdir -p $WIKI_ROOT/inbox
```

### 8c — The runner

`wk-autonomous <mode>` sets the environment cron doesn't give you (`WIKI_ROOT`,
`PATH`), pins a session id (so commits get a correct token with no interactive
prompt), serializes runs with a lock, logs **outside** the repo, and pushes.

```bash
wk-autonomous ingest    # ingest inbox (no-op if empty)
wk-autonomous reflect   # health-check pass
wk-autonomous all       # ingest then reflect (default)
```

It invokes Claude with `--dangerously-skip-permissions`, so **only run it on a box
where that blast radius is acceptable** — keep the wiki repo the only thing of
value on that machine. Logs land in `~/.local/state/wk-autonomous/`.

### 8d — Schedule it

Cron (note the explicit `WIKI_ROOT` — cron has a bare environment):

```cron
# ingest new inbox material every 30 min; full reflect pass nightly at 03:00
*/30 * * * *  WIKI_ROOT=/home/pi/notes/wiki /home/pi/notes/wiki/tools/wk-autonomous ingest
0    3 * * *  WIKI_ROOT=/home/pi/notes/wiki /home/pi/notes/wiki/tools/wk-autonomous reflect
```

If `claude` isn't on cron's `PATH`, set `CLAUDE_BIN=/full/path/to/claude` in the
crontab line too.

### 8e — Per-conversation auto-ingest (optional)

To ingest every interactive session automatically when it ends, add `/curate` to
the `SessionEnd` hook chain (the JSONL is already archived there). Keep this
separate from the cron loop so they don't double-ingest the same transcript.

---

## Step 9 — Multi-device notes sync (nightly cron)

When the wiki is a submodule of a notes repo that's edited on several devices, a
nightly cron job commits, merges, and pushes both repos, and hands merge conflicts
to `claude -p`. The full setup and agent instructions are in
[`sync/SYNC.md`](sync/SYNC.md). Short version:

```bash
~/tools/llm-wiki/sync/install-sync.sh --run-now ~/notes=git@github.com:<owner>/<notes-repo>.git
```

---

## Verify

Start a fresh Claude Code session anywhere and send one message. Then ask:

> "What is my wiki session token?"

It should reply with `cc-<UUID>`. After you `Ctrl-D` the session,
`$WIKI_ROOT/conversations/claude-code/<UUID>.jsonl` should exist.

---

## Directory map (this repo)

```
llm-wiki/
├── INSTALL.md                      # this file
├── settings-fragment.json          # hooks config to merge into settings.json
│
├── hooks/
│   ├── wiki-session-token.sh           # → ~/.claude/hooks/
│   ├── wiki-archive-session.sh         # → ~/.claude/hooks/
│   └── wiki-allow-safe-commands.sh     # → ~/.claude/hooks/ (PreToolUse allowlist)
│
├── agents/
│   ├── wiki-read.md                # → ~/.claude/agents/
│   ├── wiki-update.md              # → ~/.claude/agents/
│   └── wiki-reflect.md             # → ~/.claude/agents/  (unattended health check)
│
├── commands/
│   ├── wiki-sync.md                # → ~/.claude/commands/  (/wiki-sync slash command)
│   ├── ingest.md                   # → ~/.claude/commands/  (/ingest — interactive)
│   └── curate.md                   # → ~/.claude/commands/  (/curate — headless, no gates)
│
├── install/
│   └── wk-conv-goto.desktop        # → ~/.local/share/applications/ (conv:// URI handler)
│
├── sync/                           # multi-device notes sync — see sync/SYNC.md
│   ├── SYNC.md                     # setup + design doc (LLM-followable)
│   ├── install-sync.sh             # idempotent installer (key, hooks, crontab)
│   ├── git_auto_commit.sh          # nightly sync, → ~/scripts/ (symlink)
│   └── git_submodule_follow.sh     # post-merge hook: `git pull` updates submodules
│
├── tools/                          # → $WIKI_ROOT/tools/ (and ~/bin/ for URI handlers)
│   ├── wk-commit                   # git commit wrapper with session + touched trailers
│   ├── wk-ingest-cc                # find + copy session JSONL into wiki
│   ├── wk-new-project              # scaffold a new project directory
│   ├── wk-autonomous               # headless cron runner (ingest/reflect, sets env, locks, pushes)
│   └── wk-open-conv                # conv:// URI handler — open transcript in nvim
│
└── wiki-templates/                 # copy into $WIKI_ROOT during bootstrap
    ├── CLAUDE.md                   # master schema — agents read this first
    ├── index.md
    ├── log.md
    ├── pitfalls.md
    ├── user/
    │   └── preferences.md
    ├── bootstrap/
    │   └── code-repo-CLAUDE.md     # copy into each code repo's CLAUDE.md
    └── projects/
        └── _project-name_/         # reference stubs (used by wk-new-project)
            ├── index.md
            ├── pitfalls.md
            └── log.md
```
