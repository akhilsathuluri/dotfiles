#!/usr/bin/env bash
# fzf preview for tmux-session-picker: shows cwd, git repo+branch, and windows.

set -u
session=${1:-}
[ -z "$session" ] && exit 0

path=$(tmux display-message -p -t "$session" '#{pane_current_path}' 2>/dev/null)
home_short=${path/#$HOME/\~}

echo "dir:    $home_short"

if [ -n "$path" ] && [ -d "$path" ]; then
  repo=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$repo" ]; then
    branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$path" rev-parse --short HEAD 2>/dev/null)
    echo "repo:   $(basename "$repo")"
    echo "branch: $branch"
  fi
fi

echo
echo "windows:"
tmux list-windows -t "$session" -F '  #I:#W#{?window_active, *,}' 2>/dev/null
