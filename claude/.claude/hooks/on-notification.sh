#!/usr/bin/env bash
INPUT=$(cat)
# shellcheck source=_write-state.sh
. "$(dirname "$0")/_write-state.sh"
write_claude_state question
printf '\a'
