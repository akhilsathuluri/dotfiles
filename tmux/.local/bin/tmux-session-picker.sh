#!/usr/bin/env bash
# fzf-based tmux session picker. Sorts by last-attached (most recent first),
# excludes the current session, shows branch + Claude state inline, previews
# windows with per-pane state breakdown.

set -euo pipefail

current=$(tmux display-message -p '#S')

sessions=$(
  tmux list-sessions -F '#{session_last_attached} #{session_name}' \
    | sort -rn \
    | cut -d' ' -f2- \
    | { grep -vx -- "$current" || true; }
)

[ -z "$sessions" ] && exit 0

# ---- Build map: tmux_session -> aggregated Claude state (worst wins) -------
# State priority: question(3) > working(2) > done(1) > blank(0).
# Liveness: state file's tmux_pane must still exist in tmux. Working files
# older than 5 min are also dropped (covers hung Claudes).
declare -A STATE_BY_SESSION
state_rank() {
  case $1 in
    question) echo 3 ;;
    working)  echo 2 ;;
    done)     echo 1 ;;
    *)        echo 0 ;;
  esac
}

now=$(date +%s)
stale_working_threshold=300  # 5 minutes

# Set of currently-live tmux pane ids (e.g. "%17")
declare -A LIVE_PANES
while read -r p; do LIVE_PANES[$p]=1; done < <(tmux list-panes -a -F '#{pane_id}')

shopt -s nullglob
for f in /tmp/claude-sessions/*; do
  read -r state ts tsess tpane < <(
    jq -r '[.state, (.ts // 0), (.tmux_session // ""), (.tmux_pane // "")] | @tsv' "$f" 2>/dev/null
  ) || continue
  [ -z "$tsess" ] && continue
  [ -n "$tpane" ] && [ -z "${LIVE_PANES[$tpane]:-}" ] && continue
  if [ "$state" = "working" ] && [ $((now - ts)) -gt "$stale_working_threshold" ]; then
    continue
  fi
  prev=${STATE_BY_SESSION[$tsess]:-}
  if [ "$(state_rank "$state")" -gt "$(state_rank "$prev")" ]; then
    STATE_BY_SESSION[$tsess]=$state
  fi
done
shopt -u nullglob

icon_for() {
  case $1 in
    question) printf '🔴' ;;
    working)  printf '🟡' ;;
    done)     printf '🟢' ;;
    *)        printf '  ' ;;
  esac
}

# ---- Build "<name>TAB<display>" lines -------------------------------------
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
    icon=$(icon_for "${STATE_BY_SESSION[$name]:-}")
    printf '%s\t%s %-18s  %s\n' "$name" "$icon" "$name" "$branch"
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
