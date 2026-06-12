#!/usr/bin/env bash
# Heartbeat: refreshes state=working with a current timestamp before every
# tool call. The picker treats working files with stale `ts` as orphaned.
INPUT=$(cat)
# shellcheck source=_write-state.sh
. "$(dirname "$0")/_write-state.sh"
write_claude_state working
