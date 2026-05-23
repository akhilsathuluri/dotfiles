#!/usr/bin/env bash
# fzf preview for tmux-session-picker. Shows cwd, git repo+branch,
# aggregated Claude state, and per-pane breakdown.

set -u
session=${1:-}
[ -z "$session" ] && exit 0

path=$(tmux display-message -p -t "$session" '#{pane_current_path}' 2>/dev/null)
home_short=${path/#$HOME/\~}
now=$(date +%s)

# ---- Read Claude state files, key by tmux_pane (e.g. "%17") ----------------
# Liveness: pane must still exist; working files older than 5 min are dropped.
declare -A LIVE_PANES
while read -r p; do LIVE_PANES[$p]=1; done < <(tmux list-panes -a -F '#{pane_id}')

declare -A PANE_STATE PANE_TS
shopt -s nullglob
for f in /tmp/claude-sessions/*; do
  read -r pane state ts < <(
    jq -r '[(.tmux_pane // ""), .state, (.ts // 0)] | @tsv' "$f" 2>/dev/null
  ) || continue
  [ -z "$pane" ] && continue
  [ -z "${LIVE_PANES[$pane]:-}" ] && continue
  if [ "$state" = "working" ] && [ $((now - ts)) -gt 300 ]; then continue; fi
  PANE_STATE[$pane]=$state
  PANE_TS[$pane]=$ts
done
shopt -u nullglob

fmt_ago() {
  local delta=$((now - $1))
  if [ $delta -lt 60 ]; then echo "${delta}s ago"
  elif [ $delta -lt 3600 ]; then echo "$((delta/60))m ago"
  elif [ $delta -lt 86400 ]; then echo "$((delta/3600))h ago"
  else echo "$((delta/86400))d ago"
  fi
}

state_rank() {
  case $1 in question) echo 3 ;; working) echo 2 ;; done) echo 1 ;; *) echo 0 ;; esac
}

icon_for() {
  case $1 in question) printf '🔴' ;; working) printf '🟡' ;; done) printf '🟢' ;; *) printf '  ' ;; esac
}

# ---- Aggregate state across all panes in this session ----------------------
agg_state=
agg_ts=0
panes_in_session=$(tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null)
for p in $panes_in_session; do
  st=${PANE_STATE[$p]:-}
  [ -z "$st" ] && continue
  if [ "$(state_rank "$st")" -gt "$(state_rank "$agg_state")" ]; then
    agg_state=$st
    agg_ts=${PANE_TS[$p]}
  elif [ "$(state_rank "$st")" = "$(state_rank "$agg_state")" ] && [ "${PANE_TS[$p]}" -gt "$agg_ts" ]; then
    agg_ts=${PANE_TS[$p]}
  fi
done

# ---- Header lines ----------------------------------------------------------
echo "dir:     $home_short"

if [ -n "$path" ] && [ -d "$path" ]; then
  repo=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$repo" ]; then
    branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$path" rev-parse --short HEAD 2>/dev/null)
    echo "repo:    $(basename "$repo")"
    echo "branch:  $branch"
  fi
fi

if [ -n "$agg_state" ]; then
  echo "state:   $(icon_for "$agg_state") $agg_state ($(fmt_ago "$agg_ts"))"
fi

# ---- Windows + per-pane state ----------------------------------------------
echo
echo "windows:"
# Use tab (#{\t} not supported; tmux passes literal $'\t' through -F if quoted).
# Filter to this session via -t. Fields: window_index, window_name, pane_id,
# pane_active, window_active.
tmux list-panes -t "$session" -F $'#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_active}\t#{window_active}' 2>/dev/null \
  | while IFS=$'\t' read -r widx wname pid pactive wactive; do
      marker=' '
      [ "$wactive" = "1" ] && [ "$pactive" = "1" ] && marker='*'
      st=${PANE_STATE[$pid]:-}
      icon=$(icon_for "$st")
      if [ -n "$st" ]; then
        printf '  %s:%-8s %s  %s %s (%s)\n' "$widx" "$wname" "$marker" "$icon" "$st" "$(fmt_ago "${PANE_TS[$pid]}")"
      else
        printf '  %s:%-8s %s\n' "$widx" "$wname" "$marker"
      fi
    done
