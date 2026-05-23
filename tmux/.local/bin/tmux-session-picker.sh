#!/usr/bin/env bash
# fzf-based tmux session picker. Sorts by last-attached (most recent first),
# excludes the current session, and shows the target's windows in a preview.

set -euo pipefail

current=$(tmux display-message -p '#S')

target=$(
  tmux list-sessions -F '#{session_last_attached} #{session_name}' \
    | sort -rn \
    | cut -d' ' -f2- \
    | grep -vx -- "$current" \
    | fzf --reverse --no-input \
          --preview 'tmux list-windows -t {} -F "#I:#W"' \
          --preview-window=right:45% \
          --bind 'j:down,k:up,g:first,G:last,alt-;:abort'
) || exit 0

[ -n "$target" ] && tmux switch-client -t "$target"
