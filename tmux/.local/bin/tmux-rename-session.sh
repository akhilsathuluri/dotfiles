#!/bin/bash
# Rename a tmux session ($1) to the repo/branch derived from a path ($2). No-op outside git.
# Called from the after-new-session / client-attached hooks in .tmux.conf and from the
# prompt hook in bash/.bashrc.d/tmux-session-name.bash, so it must stay silent and cheap.
sid="$1"
path="$2"
[ -z "$sid" ] && exit 0
name=$("$HOME/.local/bin/tmux-session-name.sh" "$path") || exit 0
[ -z "$name" ] && exit 0
current=$(tmux display-message -p -t "$sid" '#{session_name}' 2>/dev/null) || exit 0

# Two worktrees on the same branch would collide, so suffix -2, -3, ... until free.
target="$name"
n=2
while :; do
    other=$(tmux display-message -p -t "=$target" '#{session_id}' 2>/dev/null)
    if [ -z "$other" ] || [ "$other" = "$sid" ]; then
        break
    fi
    target="${name}-${n}"
    n=$((n + 1))
    [ "$n" -gt 50 ] && exit 0
done

[ "$current" = "$target" ] && exit 0
tmux rename-session -t "$sid" "$target" 2>/dev/null || true
