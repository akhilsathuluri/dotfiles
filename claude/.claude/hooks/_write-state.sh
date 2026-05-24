#!/usr/bin/env bash
# Shared writer for /tmp/claude-sessions/<sid> state files.
#
# Usage: write_claude_state <state>
#   <state> ∈ question | working | done
#
# Reads Claude hook JSON from stdin (variable INPUT, expected to be set by
# caller — typically `INPUT=$(cat)` at the top of the hook). Captures tmux
# session/window/pane if TMUX_PANE is inherited. Records the parent Claude
# PID so the picker can detect orphaned files via `kill -0`.

write_claude_state() {
    local state=$1
    [ -z "$state" ] && return 1
    [ -z "${INPUT:-}" ] && return 1

    local sid cwd project
    sid=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
    [ -z "$sid" ] && return 0
    cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

    # Project name must be stable across worktrees of the same repo.
    # --git-common-dir points at the main repo's .git even from a worktree;
    # --show-toplevel would return the worktree path and split one repo into N.
    project=$(
        d=${cwd:-unknown}
        if [ -d "$d" ] && common=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null); then
            [ "${common#/}" = "$common" ] && common="$d/$common"
            common=${common%/.git}
            basename "$(readlink -f "$common" 2>/dev/null || echo "$common")"
        else
            basename "$d"
        fi
    )

    local tmux_session='' tmux_window='' tmux_pane=''
    if [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
        tmux_session=$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null || true)
        tmux_window=$(tmux display-message -p -t "$TMUX_PANE" '#I' 2>/dev/null || true)
        tmux_pane=$TMUX_PANE
    fi

    mkdir -p /tmp/claude-sessions
    jq -nc \
        --arg state "$state" \
        --arg sid "$sid" \
        --argjson pid "${PPID:-0}" \
        --arg cwd "$cwd" \
        --arg project "$project" \
        --arg tmux_session "$tmux_session" \
        --arg tmux_window "$tmux_window" \
        --arg tmux_pane "$tmux_pane" \
        --argjson ts "$(date +%s)" \
        '{state:$state, sid:$sid, pid:$pid, cwd:$cwd, project:$project,
          tmux_session:$tmux_session, tmux_window:$tmux_window,
          tmux_pane:$tmux_pane, ts:$ts}' \
        > "/tmp/claude-sessions/$sid"
}
