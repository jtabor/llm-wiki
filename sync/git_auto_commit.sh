#!/bin/bash
# Nightly multi-device sync for a notes repo and its submodules.
#
#   git_auto_commit.sh <repo_dir> [phone] [--no-ai] [--leave-conflicts]
#
#   phone / --phone     Termux notifications instead of notify-send
#   --no-ai             don't call claude -p on conflicts (same as NOTES_SYNC_NO_AI=1)
#   --leave-conflicts   on an unresolved conflict, leave the merge in progress
#                       (markers in files, `git status` shows it) instead of
#                       aborting, so you can fix it by hand. Finish with
#                       `git add <files> && git commit`, or `git merge --abort`.
#                       While a merge is in progress, later runs refuse to touch
#                       that repo and just remind you.
#
# Order of operations:
#   1. Init any submodules that aren't checked out yet.
#   2. Sync each submodule, deepest first: commit local changes, re-attach a
#      detached HEAD to its branch, fetch, merge origin, push.
#   3. Sync the parent the same way. Conflicts on submodule *pointers* are
#      resolved automatically (the pointer is always "whatever the submodule's
#      synced branch is"). Only real file conflicts abort and notify.
#   4. Push with retries, in case another device pushes at the same moment.
#
# Real file conflicts are handed to `claude -p`, which either resolves them
# (merge is committed, you get a normal notification) or answers NEEDS_INPUT
# (merge is aborted, you get a critical notification saying what to decide).
# Transcripts land in ~/scripts/merge-logs/. Set NOTES_SYNC_NO_AI=1 to skip,
# CLAUDE_MERGE_MODEL=<model> to pick a model.
#
# Auth: cron has no ssh-agent, so if ~/.ssh/notes_sync exists (passphrase-less
# key registered on GitHub) it is used for all git network operations.
# Override with NOTES_SYNC_KEY=/path/to/key.

set -uo pipefail

echo "=== $(date)"
REPO_DIR="${1:?usage: $0 <repo_dir> [phone] [--no-ai] [--leave-conflicts]}"
shift
echo "SYNCING REPO: $REPO_DIR"

LEAVE_CONFLICTS=""
[[ -n "${USING_PHONE:-}" ]] && ON_PHONE=1
for arg in "$@"; do
    case "$arg" in
        phone|--phone)     ON_PHONE=1 ;;
        --no-ai)           NOTES_SYNC_NO_AI=1 ;;
        --leave-conflicts) LEAVE_CONFLICTS=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

KEY="${NOTES_SYNC_KEY:-$HOME/.ssh/notes_sync}"
if [[ -z "${GIT_SSH_COMMAND:-}" && -f "$KEY" ]]; then
    export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
fi
export GIT_TERMINAL_PROMPT=0

PUSH_RETRIES=3
STAMP="$(date '+%Y-%m-%d %H:%M:%S')"
HOST="$(hostname 2>/dev/null || echo unknown)"

# Never let git recurse into submodules on its own; this script manages them.
g() { git -c submodule.recurse=false "$@"; }

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
MERGE_LOG_DIR="${MERGE_LOG_DIR:-$HOME/scripts/merge-logs}"
AI_TIMEOUT="${AI_TIMEOUT:-900}"

# notify <urgency: normal|critical> <title> <message>
notify() {
    local urgency="$1" title="$2" msg="$3"
    echo "NOTIFY [$urgency] $title: $msg" >&2
    if [[ -n "${ON_PHONE:-}" ]]; then
        local prio=default
        [[ "$urgency" == critical ]] && prio=high
        command -v termux-notification >/dev/null &&
            termux-notification --title "$title" --content "$msg" --priority "$prio"
    else
        local uid
        uid=$(id -u)
        export DISPLAY="${DISPLAY:-:0}"
        export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$uid/bus}"
        command -v notify-send >/dev/null && notify-send -u "$urgency" "$title" "$msg"
    fi
}

notify_conflict() { notify critical "git_auto_commit conflict" "$REPO_DIR: $1"; }
notify_input() { NOTIFIED=1; notify critical "Notes merge needs you ($1)" "$2"; }

# Skip the generic alert if a more specific one (e.g. from ai_resolve) was sent.
NOTIFIED=""
die() { [[ -z "$NOTIFIED" ]] && notify_conflict "$1"; exit 1; }

# Commit everything in repo $1 if dirty.
commit_local() {
    local dir="$1" msg="$2"
    if [[ -n $(g -C "$dir" status --porcelain) ]]; then
        g -C "$dir" add -A || return 1
        g -C "$dir" commit -q -m "$msg" || return 1
        echo "  committed local changes in $dir"
    fi
}

# Is commit $2 already contained in HEAD of repo $1?
contains() { g -C "$1" merge-base --is-ancestor "$2" HEAD 2>/dev/null; }

push_branch() {
    local dir="$1" branch="$2"
    if [[ -n $(g -C "$dir" rev-list "origin/$branch..$branch" 2>/dev/null) ]]; then
        g -C "$dir" push -q origin "$branch"
    fi
}

# Merge $2 into repo $1. Conflicts that are only on submodule pointers get
# resolved to the submodule's current HEAD, provided it contains both sides
# (submodules are synced before their parent, so normally it does).
merge_resolving() {
    local dir="$1" rev="$2" path mode ours theirs br bad=0 msg=""
    local -a files=()
    g -C "$dir" merge -q --no-edit "$rev" && return 0

    while IFS= read -r path; do
        mode=$(g -C "$dir" ls-files -u -- "$path" | awk '$3==2||$3==3{print $1; exit}')
        if [[ "$mode" != "160000" ]]; then
            echo "  file conflict: $dir/$path" >&2
            files+=("$path")
            continue
        fi
        ours=$(g -C "$dir" ls-files -u -- "$path" | awk '$3==2{print $2}')
        theirs=$(g -C "$dir" ls-files -u -- "$path" | awk '$3==3{print $2}')
        # Make sure the submodule has caught up with the other side.
        if [[ -n "$theirs" ]] && ! contains "$dir/$path" "$theirs"; then
            br=$(g -C "$dir/$path" symbolic-ref --short -q HEAD) || { bad=1; continue; }
            g -C "$dir/$path" fetch -q origin || { bad=1; continue; }
            merge_resolving "$dir/$path" "origin/$br" || { bad=1; continue; }
            push_branch "$dir/$path" "$br" || { bad=1; continue; }
        fi
        for c in $ours $theirs; do
            if ! contains "$dir/$path" "$c"; then
                echo "  submodule $dir/$path cannot reach ${c:0:7}" >&2
                bad=1
            fi
        done
        [[ $bad -ne 0 ]] && continue
        g -C "$dir" add -- "$path" && echo "  resolved pointer conflict on $path"
    done < <(g -C "$dir" diff --name-only --diff-filter=U)

    if [[ $bad -eq 0 && ${#files[@]} -gt 0 ]]; then
        if ai_resolve "$dir" "$rev" "${files[@]}"; then
            msg="Merge $rev ($HOST): conflicts in ${files[*]} resolved by claude -p"
        else
            bad=1
        fi
    fi

    if [[ $bad -ne 0 ]]; then
        if [[ -n "$LEAVE_CONFLICTS" ]]; then
            echo "  leaving merge of $rev in progress in $dir (--leave-conflicts)" >&2
        else
            g -C "$dir" merge --abort 2>/dev/null
        fi
        return 1
    fi
    if [[ -n "$msg" ]]; then
        g -C "$dir" commit -q -m "$msg"
    else
        g -C "$dir" commit -q --no-edit
    fi
}

# Ask claude -p to resolve file conflicts in repo $1 (merge of $2 in progress).
# Returns 0 only if Claude says RESOLVED and nothing is left unmerged.
# On NEEDS_INPUT (or any failure) sends a critical notification and returns 1;
# the caller aborts the merge so the repo is left clean.
ai_resolve() {
    local dir="$1" rev="$2"; shift 2
    local -a files=("$@")
    local name log verdict f
    name=$(basename "$dir")

    if [[ -n "${NOTES_SYNC_NO_AI:-}" || ! -x "$CLAUDE_BIN" ]]; then
        notify_input "$name" "file conflicts: ${files[*]} (claude -p off or not installed)"
        return 1
    fi

    mkdir -p "$MERGE_LOG_DIR"
    log="$MERGE_LOG_DIR/$(date +%Y%m%d-%H%M%S)-$name.log"
    echo "  asking claude -p to resolve ${#files[@]} file(s), log: $log"

    local -a model_args=()
    [[ -n "${CLAUDE_MERGE_MODEL:-}" ]] && model_args=(--model "$CLAUDE_MERGE_MODEL")

    (
        cd "$dir" || exit 1
        timeout "$AI_TIMEOUT" "$CLAUDE_BIN" -p \
            "${model_args[@]}" \
            --permission-mode acceptEdits \
            --allowedTools "Read" "Edit" "Write" "Grep" "Glob" \
                "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" \
                "Bash(git status:*)" "Bash(git rm:*)" \
                "Bash(git checkout --ours:*)" "Bash(git checkout --theirs:*)" \
            --settings '{"disableAllHooks": true}' \
            --strict-mcp-config \
            --no-session-persistence <<EOF
You are resolving git merge conflicts in a personal notes repository
(markdown notes plus an LLM-maintained wiki) that a nightly script syncs
between several devices. The script merged \`$rev\` into the current branch
and it stopped with conflicts in these files:

$(printf -- '- %s\n' "${files[@]}")

For each file, look at both sides (\`git diff\`, \`git show :2:<file>\` for ours,
\`git show :3:<file>\` for theirs, \`git log --oneline --merge -- <file>\`) and
edit the file so it has no conflict markers and keeps what both sides meant.

Usually the answer is obvious:
- Both sides added different content (new bullets, paragraphs, log entries,
  index rows): keep both, in a sensible order, with no duplicates.
- One side made a small edit (typo, formatting) and the other added content:
  keep both changes.
- Both sides made the same change: keep one copy.
- App/editor state files (e.g. .obsidian/*.json, workspace files): pick either
  side with \`git checkout --ours\` or \`--theirs\`, as long as the result is valid.
- Deleted on one side, modified on the other: keep the modified file unless
  the deletion was clearly intended (e.g. the note was moved or merged into
  another file); delete with \`git rm\` only in that case.

Don't guess when it isn't obvious: if the two sides contradict each other
(the same fact, value, date or decision changed in different ways), or
resolving it would mean throwing away meaningful content from one side,
leave that file alone.

Rules: only edit the conflicted files listed above. Don't run git add,
commit, merge, reset or any other command that changes git state, apart
from \`git rm\` and \`git checkout --ours/--theirs\` as described.

End your reply with exactly one final line, either
RESOLVED: <one-sentence summary of what you did>
or
NEEDS_INPUT: <what the user has to decide, naming the file(s)>
(If any file needs the user, answer NEEDS_INPUT even if you resolved others.)
EOF
    ) >"$log" 2>&1
    local rc=$?

    verdict=$(grep -E '^(RESOLVED|NEEDS_INPUT):' "$log" | tail -1)
    echo "  claude (exit $rc): ${verdict:-<no verdict>}"

    if [[ "$verdict" != RESOLVED:* ]]; then
        local why="${verdict#NEEDS_INPUT: }"
        [[ -z "$verdict" ]] && why="claude -p failed (exit $rc)"
        local what
        if [[ -n "$LEAVE_CONFLICTS" ]]; then
            what="Merge left in progress in $dir: fix, then git add + git commit"
        else
            what="Merge aborted; repo is clean. To redo by hand: $0 $REPO_DIR --leave-conflicts"
        fi
        notify_input "$name" "$why
$what
Log: $log"
        return 1
    fi

    # Verify: no markers left in the conflicted files, nothing unmerged.
    for f in "${files[@]}"; do
        if [[ -f "$dir/$f" ]] && grep -qE '^(<<<<<<<|>>>>>>>) ' "$dir/$f"; then
            notify_input "$name" \
                "Claude said RESOLVED but $f still has conflict markers. Log: $log"
            return 1
        fi
    done
    g -C "$dir" add -A || return 1
    if [[ -n $(g -C "$dir" diff --name-only --diff-filter=U) ]]; then
        notify_input "$name" "Unmerged paths remain. Log: $log"
        return 1
    fi

    notify normal "Notes merge auto-resolved ($name)" "${verdict#RESOLVED: }
Files: ${files[*]}
Log: $log"
}

# If repo $1 is on a detached HEAD, move it onto branch $2 and merge in
# whatever was committed while detached (e.g. after `git submodule update`).
reattach() {
    local dir="$1" want="$2" detached
    g -C "$dir" symbolic-ref -q HEAD >/dev/null && return 0
    detached=$(g -C "$dir" rev-parse HEAD)
    echo "  $dir: detached at ${detached:0:7}, re-attaching to $want"
    if g -C "$dir" show-ref --verify -q "refs/heads/$want"; then
        g -C "$dir" checkout -q "$want" || return 1
    else
        g -C "$dir" checkout -q -b "$want" --track "origin/$want" || return 1
    fi
    if ! contains "$dir" "$detached"; then
        merge_resolving "$dir" "$detached" || return 1
    fi
}

# Bring each submodule's checkout up to (at least) the commit its parent
# records. Needed after the parent merges a pointer bump from another device.
catch_up_submodules() {
    local dir="$1" path rec
    while IFS= read -r path; do
        [[ -z "$path" || ! -e "$dir/$path/.git" ]] && continue
        rec=$(g -C "$dir" rev-parse "HEAD:$path" 2>/dev/null) || continue
        contains "$dir/$path" "$rec" && continue
        echo "  $path: behind recorded ${rec:0:7}, syncing"
        sync_repo "$dir/$path" \
            "$(g -C "$dir/$path" symbolic-ref --short -q HEAD || echo master)" || return 1
    done < <(g -C "$dir" config -f .gitmodules --get-regexp '\.path$' 2>/dev/null | awk '{print $2}')
}

# Full sync of one repo: commit, re-attach, fetch, merge, push (with retry).
sync_repo() {
    local dir="$1" branch="$2" attempt
    commit_local "$dir" "Auto-commit ($HOST): $STAMP" || return 1
    g -C "$dir" fetch -q origin || { echo "  fetch failed in $dir" >&2; return 1; }
    reattach "$dir" "$branch" || return 1
    branch=$(g -C "$dir" symbolic-ref --short HEAD)

    for ((attempt = 1; attempt <= PUSH_RETRIES; attempt++)); do
        merge_resolving "$dir" "origin/$branch" || return 1
        catch_up_submodules "$dir" || return 1
        commit_local "$dir" "Sync submodule pointers ($HOST): $STAMP" || return 1
        push_branch "$dir" "$branch" && return 0
        echo "  push rejected in $dir (attempt $attempt), refetching" >&2
        g -C "$dir" fetch -q origin || return 1
    done
    return 1
}

cd "$REPO_DIR" || exit 1
ROOT=$(g rev-parse --show-toplevel) || exit 1

# 0. Never touch a repo with a merge in progress (e.g. left by
#    --leave-conflicts): committing now would commit the conflict markers.
while IFS= read -r d; do
    if g -C "$d" rev-parse -q --verify MERGE_HEAD >/dev/null ||
       [[ -n $(g -C "$d" diff --name-only --diff-filter=U 2>/dev/null) ]]; then
        notify_input "$(basename "$d")" "Merge in progress in $d. Finish it (git add + git commit) or run git merge --abort; sync skipped."
        exit 1
    fi
done < <(echo "$ROOT"; g submodule foreach --quiet --recursive 'echo "$toplevel/$sm_path"')

# 1. Initialize submodules that haven't been checked out (new device).
while read -r line; do
    path=$(awk '{print $2}' <<<"$line")
    echo "  initializing submodule $path"
    g submodule update --init --recursive -- "$path" || die "submodule init failed: $path"
done < <(g submodule status 2>/dev/null | grep '^-' || true)

# 2. Sync submodules, deepest first, so parents see pushed pointers.
while IFS=$'\t' read -r _depth path branch; do
    echo "submodule: $path ($branch)"
    sync_repo "$path" "$branch" || die "submodule sync failed: $path"
done < <(g submodule foreach --quiet --recursive '
    b=$(git config -f "$toplevel/.gitmodules" "submodule.$name.branch" || echo master)
    p="$toplevel/$sm_path"
    printf "%s\t%s\t%s\n" "$(echo "$p" | tr -cd / | wc -c)" "$p" "$b"
' | sort -t$'\t' -k1,1nr)

# 3. Sync the parent.
PARENT_BRANCH=$(g symbolic-ref --short -q HEAD) || die "parent repo is on a detached HEAD"
echo "parent: $ROOT ($PARENT_BRANCH)"
sync_repo "$ROOT" "$PARENT_BRANCH" || die "parent sync failed (see log)"
echo "  done"
