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

# Build maps of live tmux panes + Claude panes (for cwd-based fallback when
# the hook didn't inherit TMUX_PANE).
declare -A LIVE_PANES CLAUDE_PANE_SESSION PATH_TO_CLAUDE_PANE
while IFS=$'\t' read -r sess pid cmd path; do
  LIVE_PANES[$pid]=1
  case $cmd in claude|node)
    CLAUDE_PANE_SESSION[$pid]=$sess
    PATH_TO_CLAUDE_PANE[$path]=$pid
  ;;
  esac
done < <(tmux list-panes -a -F $'#{session_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}')

# First pass: collapse all state files to one (state, ts) per live pane,
# keeping the most recent ts. Prevents a stale background-session file from
# beating a fresh one when both cwd-resolve to the same pane.
declare -A PANE_STATE PANE_TS PANE_SESSION
shopt -s nullglob
for f in /tmp/claude-sessions/*; do
  jq -e . "$f" >/dev/null 2>&1 || continue
  state=$(jq -r '.state' "$f")
  ts=$(jq -r '.ts // 0' "$f")
  tsess=$(jq -r '.tmux_session // ""' "$f")
  tpane=$(jq -r '.tmux_pane // ""' "$f")
  cwd=$(jq -r '.cwd // ""' "$f")

  # Resolve to a live pane. Prefer recorded tmux_pane; fall back to cwd match
  # against panes currently running claude.
  if [ -z "$tpane" ] || [ -z "${LIVE_PANES[$tpane]:-}" ]; then
    tpane=${PATH_TO_CLAUDE_PANE[$cwd]:-}
    [ -z "$tpane" ] && continue
    tsess=${CLAUDE_PANE_SESSION[$tpane]:-}
  fi
  [ -z "$tsess" ] && continue

  if [ "$state" = "working" ] && [ $((now - ts)) -gt "$stale_working_threshold" ]; then
    continue
  fi

  if [ "$ts" -gt "${PANE_TS[$tpane]:-0}" ]; then
    PANE_STATE[$tpane]=$state
    PANE_TS[$tpane]=$ts
    PANE_SESSION[$tpane]=$tsess
  fi
done
shopt -u nullglob

# Second pass: aggregate per tmux session, worst state across its panes wins.
for tpane in "${!PANE_STATE[@]}"; do
  tsess=${PANE_SESSION[$tpane]}
  state=${PANE_STATE[$tpane]}
  prev=${STATE_BY_SESSION[$tsess]:-}
  if [ "$(state_rank "$state")" -gt "$(state_rank "$prev")" ]; then
    STATE_BY_SESSION[$tsess]=$state
  fi
done

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
