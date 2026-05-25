#!/usr/bin/env bash
# fzf-based tmux session picker. Shows branch + Claude state inline, previews
# windows with per-pane state breakdown. Opens with the current session
# pre-selected.
#
# Keys: c = new session, r = rename, D = kill, K = move up, J = move down.
# Order is persisted in $XDG_STATE_HOME/tmux/session-order; sessions not in
# that file are appended alphabetically.
#
# Internal flags (used by fzf reload callbacks):
#   --list                       emit fzf line data
#   --move-up    NAME            shift NAME up in the order file
#   --move-down  NAME            shift NAME down
#   --rename     NAME            interactive rename
#   --rename-in-order OLD NEW    rewrite OLD → NEW in the order file
#   --kill       NAME            interactive kill
#   --new                        interactive new session

set -euo pipefail

order_file="${XDG_STATE_HOME:-$HOME/.local/state}/tmux/session-order"
mkdir -p "$(dirname "$order_file")"
touch "$order_file"

ordered_session_names() {
  local -A live seen
  local s
  while IFS= read -r s; do live[$s]=1; done < <(tmux list-sessions -F '#{session_name}')
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if [ -n "${live[$s]:-}" ] && [ -z "${seen[$s]:-}" ]; then
      printf '%s\n' "$s"
      seen[$s]=1
    fi
  done < "$order_file"
  while IFS= read -r s; do
    [ -z "${seen[$s]:-}" ] && printf '%s\n' "$s"
  done < <(tmux list-sessions -F '#{session_name}' | sort)
  return 0
}

move_in_order() {
  local target=$1 dir=$2 tmp
  tmp=$(mktemp)
  ordered_session_names > "$tmp"
  awk -v t="$target" -v d="$dir" '
    {a[NR]=$0}
    END {
      idx=0
      for (i=1;i<=NR;i++) if (a[i]==t) { idx=i; break }
      j=idx+d
      if (idx>=1 && j>=1 && j<=NR) { x=a[idx]; a[idx]=a[j]; a[j]=x }
      for (i=1;i<=NR;i++) print a[i]
    }
  ' "$tmp" > "$order_file"
  rm -f "$tmp"
}

rename_in_order() {
  local old=$1 new=$2 tmp
  tmp=$(mktemp)
  awk -v o="$old" -v n="$new" '{ if ($0==o) print n; else print }' "$order_file" > "$tmp"
  mv "$tmp" "$order_file"
}

remove_in_order() {
  local target=$1 tmp
  tmp=$(mktemp)
  awk -v t="$target" '$0 != t' "$order_file" > "$tmp"
  mv "$tmp" "$order_file"
}

append_in_order() {
  local target=$1
  grep -Fxq -- "$target" "$order_file" 2>/dev/null || printf '%s\n' "$target" >> "$order_file"
}

do_new() {
  local name dir default_dir err
  clear
  read -e -p "new session name: " name || return 0
  [ -z "$name" ] && return 0
  if tmux list-sessions -F '#{session_name}' | grep -Fxq -- "$name"; then
    printf '\n✗ session "%s" already exists\n' "$name" >&2
    sleep 1.2
    return 0
  fi
  default_dir=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || true)
  { [ -z "$default_dir" ] || [ ! -d "$default_dir" ]; } && default_dir=$HOME
  read -e -i "$default_dir" -p "start dir: " dir || return 0
  dir=${dir/#~/$HOME}
  if [ ! -d "$dir" ]; then
    printf '\n✗ no such directory: %s\n' "$dir" >&2
    sleep 1.2
    return 0
  fi
  if ! err=$(tmux new-session -d -s "$name" -c "$dir" 2>&1); then
    printf '\n✗ %s\n' "$err" >&2
    sleep 1.2
    return 0
  fi
  append_in_order "$name"
}

do_kill() {
  local name=$1 ans err
  clear
  printf 'kill session "%s"? [y/N] ' "$name"
  read -r ans || return 0
  case $ans in y|Y|yes) ;; *) return 0 ;; esac
  if ! err=$(tmux kill-session -t "$name" 2>&1); then
    printf '\n✗ %s\n' "$err" >&2
    sleep 1.2
    return 0
  fi
  remove_in_order "$name"
}

do_rename() {
  local old=$1 new err
  clear
  read -e -i "$old" -p "rename to: " new || return 0
  [ -z "$new" ] && return 0
  [ "$new" = "$old" ] && return 0
  if tmux list-sessions -F '#{session_name}' | grep -Fxq -- "$new"; then
    printf '\n✗ session "%s" already exists\n' "$new" >&2
    sleep 1.2
    return 0
  fi
  if ! err=$(tmux rename-session -t "$old" -- "$new" 2>&1); then
    printf '\n✗ rename failed: %s\n' "$err" >&2
    sleep 1.2
    return 0
  fi
  rename_in_order "$old" "$new"
}

list_only=0
case "${1:-}" in
  --list)             list_only=1 ;;
  --move-up)          move_in_order "$2" -1; exit 0 ;;
  --move-down)        move_in_order "$2"  1; exit 0 ;;
  --rename)           do_rename "$2"; exit 0 ;;
  --rename-in-order)  rename_in_order "$2" "$3"; exit 0 ;;
  --kill)             do_kill "$2"; exit 0 ;;
  --new)              do_new; exit 0 ;;
esac

current=$(tmux display-message -p '#S')

sessions=$(ordered_session_names)

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

if [ "$list_only" = 1 ]; then
  printf '%s\n' "$lines"
  exit 0
fi

current_pos=$(printf '%s\n' "$lines" | awk -F'\t' -v c="$current" '$1==c{print NR; exit}')
: "${current_pos:=1}"

self=$(realpath "$0")

target=$(
  printf '%s\n' "$lines" \
    | fzf --sync --reverse --no-input --highlight-line \
          --delimiter=$'\t' --with-nth=2 \
          --preview "$HOME/.local/bin/tmux-session-preview.sh {1}" \
          --preview-window=down:50% \
          --pointer=' ' \
          --color='bg+:#268bd2,fg+:#fdf6e3,gutter:-1,pointer:-1,hl:#268bd2,hl+:#fdf6e3,border:#93a1a1,info:#93a1a1,prompt:#586e75' \
          --bind "start:pos($current_pos)" \
          --bind 'j:down,k:up,g:first,G:last,alt-;:abort' \
          --bind "r:execute($self --rename {1})+reload($self --list)" \
          --bind "D:execute($self --kill {1})+reload($self --list)" \
          --bind "c:execute($self --new)+reload($self --list)+last" \
          --bind "K:execute-silent($self --move-up {1})+reload($self --list)+up" \
          --bind "J:execute-silent($self --move-down {1})+reload($self --list)+down" \
    | cut -f1
) || exit 0

[ -n "$target" ] && tmux switch-client -t "$target"
