#!/bin/bash
# post-merge hook: after `git pull` in the parent, move each submodule up to
# the commit the parent now records, staying on its branch (unlike
# `git pull --recurse-submodules`, which leaves submodules on a detached HEAD).
#
# Installed per repo by install-sync.sh, i.e.:
#   ln -sf ~/scripts/git_submodule_follow.sh <repo>/.git/hooks/post-merge

top=$(git rev-parse --show-toplevel) || exit 0
cd "$top" || exit 0
[[ -f .gitmodules ]] || exit 0

git config -f .gitmodules --get-regexp '\.path$' | while read -r key path; do
    name=${key#submodule.}; name=${name%.path}
    branch=$(git config -f .gitmodules "submodule.$name.branch" || echo master)
    rec=$(git rev-parse "HEAD:$path" 2>/dev/null) || continue

    if [[ ! -e "$path/.git" ]]; then
        git -c submodule.recurse=false submodule update --init --recursive -- "$path" || continue
    fi
    sub=(git -C "$path")

    "${sub[@]}" cat-file -e "$rec^{commit}" 2>/dev/null || "${sub[@]}" fetch -q origin

    if ! "${sub[@]}" symbolic-ref -q HEAD >/dev/null; then
        cur=$("${sub[@]}" rev-parse HEAD)
        "${sub[@]}" checkout -q "$branch" 2>/dev/null ||
            "${sub[@]}" checkout -q -b "$branch" --track "origin/$branch" || continue
        "${sub[@]}" merge-base --is-ancestor "$cur" HEAD || "${sub[@]}" merge -q --no-edit "$cur"
    fi

    if "${sub[@]}" merge-base --is-ancestor "$rec" HEAD; then
        continue    # already has it (or is ahead)
    fi
    if "${sub[@]}" merge -q --no-edit "$rec"; then
        echo "submodule $path: updated to include ${rec:0:7}"
    else
        "${sub[@]}" merge --abort 2>/dev/null
        echo "submodule $path: could not merge ${rec:0:7} (local edits?) - run git_auto_commit.sh" >&2
    fi
done
exit 0
