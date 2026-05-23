#!/usr/bin/env bash
# fzf-based tmux session picker. Sorts by last-attached (most recent first),
# excludes the current session, shows branch inline, and previews windows.

set -euo pipefail

current=$(tmux display-message -p '#S')

sessions=$(
  tmux list-sessions -F '#{session_last_attached} #{session_name}' \
    | sort -rn \
    | cut -d' ' -f2- \
    | { grep -vx -- "$current" || true; }
)

[ -z "$sessions" ] && exit 0

# Build "<name>TAB<display>" lines so fzf shows formatted text but we can
# recover the raw session name from field 1 after selection.
lines=$(
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    path=$(tmux display-message -p -t "$name" '#{pane_current_path}' 2>/dev/null || true)
    branch=
    if [ -n "$path" ] && [ -d "$path" ]; then
      branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null \
               || git -C "$path" rev-parse --short HEAD 2>/dev/null \
               || true)
    fi
    printf '%s\t%-18s  %s\n' "$name" "$name" "$branch"
  done <<< "$sessions"
)

target=$(
  printf '%s\n' "$lines" \
    | fzf --reverse --no-input \
          --delimiter=$'\t' --with-nth=2 \
          --preview "$HOME/.local/bin/tmux-session-preview.sh {1}" \
          --preview-window=down:50% \
          --bind 'j:down,k:up,g:first,G:last,alt-;:abort' \
    | cut -f1
) || exit 0

[ -n "$target" ] && tmux switch-client -t "$target"
