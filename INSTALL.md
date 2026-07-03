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
ln -s "$REPO/agents/wiki-read.md"   ~/.claude/agents/wiki-read.md
ln -s "$REPO/agents/wiki-update.md" ~/.claude/agents/wiki-update.md
```

---

## Step 5b — Install slash commands

```bash
mkdir -p ~/.claude/commands
ln -s "$REPO/commands/wiki-sync.md" ~/.claude/commands/wiki-sync.md
ln -s "$REPO/commands/ingest.md"    ~/.claude/commands/ingest.md
```

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
│   └── wiki-update.md              # → ~/.claude/agents/
│
├── commands/
│   └── wiki-sync.md                # → ~/.claude/commands/  (/wiki-sync slash command)
│
├── install/
│   └── wk-conv-goto.desktop        # → ~/.local/share/applications/ (conv:// URI handler)
│
├── tools/                          # → $WIKI_ROOT/tools/ (and ~/bin/ for URI handlers)
│   ├── wk-commit                   # git commit wrapper with session + touched trailers
│   ├── wk-ingest-cc                # find + copy session JSONL into wiki
│   ├── wk-new-project              # scaffold a new project directory
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
