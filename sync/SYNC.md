# Notes sync: nightly multi-device git sync

Keeps the notes repos (and the wiki submodule inside `~/notes`) in sync between
devices. Each device commits whatever changed locally, merges the other devices'
work, and pushes every night from cron. Merge conflicts in files go to `claude -p`,
which resolves the obvious ones itself and sends a desktop notification when it
needs a person to decide.

This file is written so that an LLM agent can set the system up on a new machine.
**Agent instructions: [Setting up a new machine](#setting-up-a-new-machine).**

---

## Layout

| Thing | Where | Notes |
|---|---|---|
| Sync script | `sync/git_auto_commit.sh` | Run by cron, once per repo |
| Pull hook | `sync/git_submodule_follow.sh` | `post-merge` hook in repos with submodules |
| Installer | `sync/install-sync.sh` | Safe to re-run; does every step below |
| Cron entry point | `~/scripts/git_auto_commit.sh` | Symlink to the repo copy |
| SSH key for cron | `~/.ssh/notes_sync` | Passphrase-less ed25519; must be on the repo owner's GitHub account |
| Cron log | `~/scripts/git_auto_commit.log` | stdout and stderr |
| Claude merge transcripts | `~/scripts/merge-logs/` | One file per conflict that went to Claude |

Repos on the original machine (`synapse`):

| Local dir | Remote | Submodules | Cron time |
|---|---|---|---|
| `~/notes` | `git@github.com:jtabor/hatch_notes.git` | `wiki` → `git@github.com:jtabor/hatch_wiki.git` (branch `master`) | 03:00 |
| `~/personal_notes` | `git@github.com:jtabor/churchNotes.git` | none | 03:30 |
| `~/thalchemy_notes` | `git@github.com:jtabor/thalchemyNotes.git` | none | 04:00 |

All branches are `master`.

---

## Setting up a new machine

The steps assume Linux or macOS with cron. For Android/Termux, see [Phone](#phone-termux).

1. **Prerequisites.** You need `git`, `ssh`, `crontab`, and optionally `notify-send`
   (`libnotify-bin`) and the `claude` CLI, logged in. Without `claude`, conflicts
   only send a notification. Without `notify-send`, alerts only go to the log.
2. **Get this repo:** `git clone <llm-wiki url> ~/tools/llm-wiki`.
3. **Run the installer.** Pass each notes repo as `dir=url`; repos that don't
   exist yet get cloned.
   ```bash
   ~/tools/llm-wiki/sync/install-sync.sh --run-now \
     ~/notes=git@github.com:jtabor/hatch_notes.git \
     ~/personal_notes=git@github.com:jtabor/churchNotes.git \
     ~/thalchemy_notes=git@github.com:jtabor/thalchemyNotes.git
   ```
   For a repo that's already cloned, the plain path (`~/notes`) is enough.
4. **If the installer exits with code 3**, the new key `~/.ssh/notes_sync.pub` isn't
   on GitHub yet. The installer adds it automatically only when `gh` is logged in as
   the account that owns the repos (`jtabor`). If `gh` has that account but another
   one is active, run `gh auth switch -u jtabor` and re-run the installer. Otherwise
   this is the **one manual step**: ask the user to paste the printed public key into
   https://github.com/settings/ssh/new on the `jtabor` account, then re-run step 3
   with the same arguments.
5. **Check it worked.** All of these should hold:
   - `crontab -l | grep git_auto_commit` shows one line per repo, ending `>> ~/scripts/git_auto_commit.log 2>&1`
   - `git -C ~/notes/wiki symbolic-ref --short HEAD` prints `master` (not detached)
   - `git -C <each repo> status -sb` shows no `ahead`/`behind` after the `--run-now` sync
   - `ls -l ~/notes/.git/hooks/post-merge` points to `git_submodule_follow.sh`

The installer is safe to re-run. It:
- links the scripts into `~/scripts`, backing up any real files already there;
- creates the key if it's missing and checks it against GitHub;
- clones missing repos;
- installs the `post-merge` hook in repos that have submodules, but won't replace a hook it didn't install;
- writes one crontab line per repo, starting at `--start` (default 03:00) and 30 minutes apart, replacing any older line for the same repo.

Options:
- `--dry-run` shows what would change without changing anything.
- `--phone` sets it up for Termux on Android.

Environment overrides: `NOTES_SYNC_KEY`, `NOTES_SYNC_LOG`, `SCRIPTS_DIR`.

### Phone (Termux)

```bash
pkg install git openssh cronie termux-api   # plus the Termux:API app
crond                                       # start cron (add to ~/.bashrc or use termux-boot)
~/tools/llm-wiki/sync/install-sync.sh --phone --run-now ~/notes=git@github.com:jtabor/hatch_notes.git ...
```
Alerts use `termux-notification`. `claude` is normally missing on the phone, so
conflicts only send a notification there.

---

## How a sync run works (`git_auto_commit.sh <repo> [phone] [--no-ai] [--leave-conflicts]`)

0. **Unfinished merge check.** If the repo or any of its submodules is in the middle of
   a merge, the script sends a notification and exits without touching anything.
   Otherwise it would commit the conflict markers.
1. **Initialize submodules** that aren't checked out yet (first run on a new device).
2. **Sync each submodule first** (the deepest ones first, if they're nested):
   - commit local changes as `Auto-commit (<host>): <time>`;
   - fetch;
   - if the submodule is on a detached HEAD, move it back onto its branch, merging in
     anything committed while detached;
   - merge `origin/<branch>`;
   - push.
3. **Sync the parent the same way.** Any wiki changes it records have already been
   pushed, so the parent never points at a wiki commit that isn't on GitHub.
4. **Retry on a rejected push:** if another device pushed in the meantime, fetch and
   merge again, up to 3 tries.
5. **Exit status:** 0 if everything is synced, 1 after a notification.

All git commands in the script run with `submodule.recurse=false`, because the
script handles submodules itself. Every network call uses
`GIT_SSH_COMMAND="ssh -i ~/.ssh/notes_sync -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"`
whenever the key file exists.

### Conflicts

- **Two devices moved the wiki pointer** (both committed to the wiki). The script
  resolves this itself: the pointer always becomes "whatever the wiki's synced
  `master` is". It checks that the wiki's checkout contains both sides, syncing the
  wiki again if needed, then stages the pointer.
- **Conflicts in note files** go to `claude -p`. Claude runs:
  - in the conflicted repo;
  - with `--permission-mode acceptEdits`;
  - limited to Read/Edit/Write/Grep/Glob, plus read-only git commands, `git rm`, and
    `git checkout --ours/--theirs`;
  - with hooks off (`--settings '{"disableAllHooks": true}'`), no MCP servers
    (`--strict-mcp-config`), and no saved session (`--no-session-persistence`), so
    the wiki's own Claude hooks don't run;
  - with a 15-minute timeout.

  Claude must end its reply with `RESOLVED: …` or `NEEDS_INPUT: …`.
  - **`RESOLVED`:** the script checks that no `<<<<<<<`/`>>>>>>>` markers are left and
    nothing is still unmerged, then commits
    `Merge … conflicts in <files> resolved by claude -p`. It sends a **normal**
    notification with Claude's summary.
  - **`NEEDS_INPUT`, or anything going wrong:** the script undoes the merge, so the
    repo is clean, and sends a **critical** notification with Claude's question and
    the log path.
- **Fixing a conflict by hand:**
  `git_auto_commit.sh <repo> --leave-conflicts` stops with the merge still open
  (`--no-ai` skips Claude). Edit the files, run `git add <files> && git commit`, then
  run the sync again. `git merge --abort` gives up on it instead.

Environment variables:
- `NOTES_SYNC_NO_AI=1` turns off the Claude step;
- `CLAUDE_MERGE_MODEL=<model>` picks Claude's model;
- `CLAUDE_BIN`, `MERGE_LOG_DIR` and `AI_TIMEOUT` (seconds) override the defaults;
- `USING_PHONE=1` does the same as `phone`.

### `git pull` in the parent

The `post-merge` hook (`git_submodule_follow.sh`) runs after any `git pull` or `git merge`
in `~/notes`. It brings each submodule up to the commit the parent now records,
keeping it on its branch. It fast-forwards, or merges if the submodule has its own
local commits. Don't use `git pull --recurse-submodules` or `submodule.recurse=true`
for this: they leave the wiki on a detached HEAD.

---

## Design decisions (and why)

- **Submodules were kept, with a pointer rule.** Running `git pull` in `notes` should
  bring the wiki along. The usual problem with submodules on several devices is that
  every wiki commit changes the parent's pointer, so two devices conflict on it all
  the time. The rule "pointer = the wiki's synced `master`" makes those conflicts
  resolve automatically. Rejected alternatives: the wiki as a separate repo ignored by
  the parent (pulling the parent wouldn't bring it along), and merging the wiki into
  `notes` (large transcript files, and the wiki tooling expects its own repo).
- **Cron uses a dedicated passphrase-less key.** Cron has no ssh-agent, so a
  passphrase-protected key can't connect. This caused the original failure: every
  night `fetch` failed with `Permission denied (publickey)`. The parent repo ignored
  the error and printed "Already up to date", and only the submodule step reported a
  failure. A repo-scoped deploy key would be tighter, but the account key covers all
  the repos with one key.
- **Merge, not rebase**, so that unpushed local commits are never rewritten.
- **The scripts live in this repo, symlinked into `~/scripts`**, so there's one copy
  under version control.
- **Interaction with `wk-autonomous`** (INSTALL.md Step 8): on a headless box that
  also runs `wk-autonomous`, both jobs commit and push inside the wiki. Schedule them
  at least 30 minutes apart, for example by passing `--start 04:00` to
  `install-sync.sh`, so they don't race. If they do overlap, the sync script's merge
  and push retries usually recover.

## Troubleshooting

- **Read the log first:** `tail -50 ~/scripts/git_auto_commit.log`. Since stderr is
  logged now, git errors show up there.
- **"fetch failed" or `Permission denied (publickey)`.** Test the key with
  `ssh -i ~/.ssh/notes_sync -o IdentitiesOnly=yes -T git@github.com`; it should greet
  `jtabor`. If not, add the key to GitHub again.
- **No desktop notifications from cron.** The script sets `DISPLAY=:0` and
  `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus`. Both need a graphical
  session for that user.
- **"Merge in progress … sync skipped"**: an earlier `--leave-conflicts` run left a
  merge open. Finish it or abort it.
- **Testing:** use throwaway bare repos in a temp directory, with
  `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always`
  so `file://` submodules work. Set `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent`
  so tests don't send real desktop notifications.
