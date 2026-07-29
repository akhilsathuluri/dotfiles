#!/bin/bash
# Print "<repo>/<branch>" for the given path (or $PWD). Empty if not in a git work tree.
# Worktree-aware: repo comes from the parent of `git rev-parse --git-common-dir`, so every
# worktree of one repo reports the same repo name.
path="${1:-$PWD}"
cd "$path" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
case "$common_dir" in
    /*) abs="$common_dir" ;;
    *) abs="$PWD/$common_dir" ;;
esac
repo_root=$(cd "$(dirname "$abs")" 2>/dev/null && pwd) || exit 0
repo=$(basename "$repo_root")

branch=$(git symbolic-ref --short HEAD 2>/dev/null) ||
    branch=$(git rev-parse --short HEAD 2>/dev/null) ||
    exit 0

# ":" is tmux's session/window separator, so it can never appear in a session name.
name="$repo/$branch"
printf '%s\n' "${name//:/-}"
