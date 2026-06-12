#!/usr/bin/env bash
INPUT=$(cat)
# Claude fires Notification for both real attention-needed events and a
# periodic "Claude is waiting for your input" idle nudge (notification_type
# = "idle_prompt"). Skip the idle nudges — they'd otherwise flip a happily
# idle (done) session to question after ~60s.
ntype=$(printf '%s' "$INPUT" | jq -r '.notification_type // ""')
[ "$ntype" = "idle_prompt" ] && exit 0
# shellcheck source=_write-state.sh
. "$(dirname "$0")/_write-state.sh"
write_claude_state question
