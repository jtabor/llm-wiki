#!/bin/bash
# Idempotent installer for nightly multi-device notes sync. See SYNC.md.
#
#   install-sync.sh [options] <repo_dir>[=<clone_url>] ...
#
# Options:
#   --phone        Termux/Android: pass `phone` to the sync script (termux-notification)
#   --start HH:MM  time of the first nightly sync (default 03:00); each further
#                  repo is staggered by 30 min
#   --run-now      run one sync per repo at the end
#   --dry-run      print what would change, change nothing
#
# Env:
#   NOTES_SYNC_KEY   ssh key used by cron (default ~/.ssh/notes_sync)
#   NOTES_SYNC_LOG   log file for cron runs (default ~/scripts/git_auto_commit.log)
#   SCRIPTS_DIR      where the scripts are linked for cron (default ~/scripts)
#
# Exit codes: 0 ok; 1 error; 3 the ssh key must be added to GitHub by hand
# (printed with instructions; re-run afterwards).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
KEY="${NOTES_SYNC_KEY:-$HOME/.ssh/notes_sync}"
LOG="${NOTES_SYNC_LOG:-$HOME/scripts/git_auto_commit.log}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/scripts}"
PHONE="" START="03:00" RUN_NOW="" DRY=""
REPOS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phone)   PHONE=1 ;;
        --start)   START="$2"; shift ;;
        --run-now) RUN_NOW=1 ;;
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
        -*)        echo "unknown option $1" >&2; exit 1 ;;
        *)         REPOS+=("$1") ;;
    esac
    shift
done
[[ ${#REPOS[@]} -gt 0 ]] || { echo "usage: $0 [options] <repo_dir>[=<clone_url>] ..." >&2; exit 1; }

say()  { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }
run()  { if [[ -n "$DRY" ]]; then echo "  [dry-run] $*"; else "$@"; fi; }

# --- 1. dependencies ---------------------------------------------------------
say "checking dependencies"
for c in git ssh ssh-keygen; do command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; done
if [[ -z "$PHONE" ]]; then
    command -v crontab >/dev/null || { echo "missing: crontab (install cron/cronie)" >&2; exit 1; }
    command -v notify-send >/dev/null || warn "notify-send missing: no desktop alerts (apt install libnotify-bin)"
else
    command -v crontab >/dev/null || { echo "Termux: pkg install cronie termux-api && crond" >&2; exit 1; }
    command -v termux-notification >/dev/null || warn "termux-notification missing (pkg install termux-api + Termux:API app)"
fi
CLAUDE=$(command -v claude || ls "$HOME/.local/bin/claude" 2>/dev/null || true)
[[ -n "$CLAUDE" ]] || warn "claude CLI not found: conflicts will only notify, not auto-resolve"

# --- 2. scripts linked into SCRIPTS_DIR ---------------------------------------
say "linking scripts into $SCRIPTS_DIR"
run mkdir -p "$SCRIPTS_DIR" "$(dirname "$LOG")"
for s in git_auto_commit.sh git_submodule_follow.sh; do
    chmod +x "$SRC_DIR/$s"
    dst="$SCRIPTS_DIR/$s"
    if [[ "$(readlink -f "$dst" 2>/dev/null)" == "$SRC_DIR/$s" ]]; then continue; fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        run mv "$dst" "$dst.bak-$(date +%Y%m%d%H%M%S)"
    fi
    run ln -sfn "$SRC_DIR/$s" "$dst"
done
SYNC="$SCRIPTS_DIR/git_auto_commit.sh"

# --- 3. ssh key for cron -------------------------------------------------------
GIT_SSH="ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
if [[ ! -f "$KEY" ]]; then
    say "creating passphrase-less key $KEY"
    run ssh-keygen -q -t ed25519 -N "" -C "notes-sync@$(hostname) (cron)" -f "$KEY"
fi

github_ok() {
    # GitHub answers "successfully authenticated" and exits 1 on a working key.
    local out
    out=$($GIT_SSH -T git@github.com 2>&1 || true)
    [[ "$out" == *"successfully authenticated"* ]]
}

if [[ -z "$DRY" ]] && ! github_ok; then
    # Try to register the key via gh, but only if gh is logged in as the owner
    # of the first repo's GitHub remote (avoids adding it to the wrong account).
    owner=""
    first="${REPOS[0]}"
    if [[ "$first" == *=* ]]; then url="${first#*=}"
    else url=$(git -C "${first%%=*}" remote get-url origin 2>/dev/null || true); fi
    [[ "$url" =~ github\.com[:/]([^/]+)/ ]] && owner="${BASH_REMATCH[1]}"
    login=""
    command -v gh >/dev/null && login=$(gh api user -q .login 2>/dev/null || true)
    if [[ -n "$owner" && "$login" == "$owner" ]]; then
        say "adding $KEY.pub to GitHub account $owner via gh"
        gh ssh-key add "$KEY.pub" --title "notes-sync $(hostname)" || true
        sleep 2
    fi
    if ! github_ok; then
        cat >&2 <<EOF

MANUAL STEP: add this key to the GitHub account that owns the notes repos
(${owner:-<owner>}): https://github.com/settings/ssh/new
  (or: gh auth switch -u ${owner:-<owner>} && gh ssh-key add $KEY.pub)

$(cat "$KEY.pub")

Then re-run this installer with the same arguments.
EOF
        exit 3
    fi
fi
say "ssh key works with GitHub"

# --- 4. clone repos (if missing) + post-merge hook ----------------------------
DIRS=()
for spec in "${REPOS[@]}"; do
    dir="${spec%%=*}"; url=""
    [[ "$spec" == *=* ]] && url="${spec#*=}"
    dir="${dir/#\~/$HOME}"; dir="${dir%/}"
    if [[ ! -d "$dir/.git" ]]; then
        [[ -n "$url" ]] || { echo "$dir is not a git repo and no clone url given" >&2; exit 1; }
        say "cloning $url -> $dir"
        run env GIT_SSH_COMMAND="$GIT_SSH" git clone -q "$url" "$dir"
    fi
    DIRS+=("$dir")
    if [[ -f "$dir/.gitmodules" ]]; then
        hook="$(git -C "$dir" rev-parse --git-path hooks 2>/dev/null || echo .git/hooks)"
        [[ "$hook" = /* ]] || hook="$dir/$hook"
        hook="$hook/post-merge"
        if [[ "$(readlink -f "$hook" 2>/dev/null)" == "$SRC_DIR/git_submodule_follow.sh" ]]; then
            :
        elif [[ -e "$hook" ]]; then
            warn "$hook exists and isn't ours; not replacing (call $SCRIPTS_DIR/git_submodule_follow.sh from it)"
        else
            say "installing post-merge hook in $dir"
            run ln -s "$SRC_DIR/git_submodule_follow.sh" "$hook"
        fi
    fi
done

# --- 5. crontab -----------------------------------------------------------------
say "updating crontab"
h=${START%%:*}; m=${START##*:}; h=$((10#$h)); m=$((10#$m))
current=$(crontab -l 2>/dev/null || true)
new="$current"
for dir in "${DIRS[@]}"; do
    line="$m $h * * * $SYNC $dir/${PHONE:+ phone} >> $LOG 2>&1"
    if ! printf '%s\n' "$new" | grep -qxF -- "$line"; then
        # replace any previous sync line for this repo (with or without trailing slash)
        new=$(printf '%s\n' "$new" | grep -vE "git_auto_commit\.sh[[:space:]]+${dir//./\\.}/?([[:space:]]|$)" || true)
        new=$(printf '%s\n%s\n' "$new" "$line")
    fi
    m=$((m + 30)); (( m >= 60 )) && { m=$((m - 60)); h=$(((h + 1) % 24)); }
done
new=$(printf '%s\n' "$new" | sed -e '/./,$!d')   # trim leading blank lines
if [[ "$new" == "$current" ]]; then
    echo "  crontab unchanged"
elif [[ -n "$DRY" ]]; then
    diff <(printf '%s\n' "$current") <(printf '%s\n' "$new") | sed 's/^/  [dry-run] /' || true
else
    printf '%s\n' "$new" | crontab -
    crontab -l | grep git_auto_commit | sed 's/^/  /'
fi

# --- 6. first sync ----------------------------------------------------------------
if [[ -n "$RUN_NOW" && -z "$DRY" ]]; then
    for dir in "${DIRS[@]}"; do
        say "syncing $dir"
        "$SYNC" "$dir" ${PHONE:+phone} || warn "sync of $dir failed (see output above)"
    done
fi
say "done"
