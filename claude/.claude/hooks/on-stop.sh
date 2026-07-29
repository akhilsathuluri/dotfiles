#!/usr/bin/env bash
# shellcheck disable=SC2034  # read by write_claude_state in _write-state.sh
INPUT=$(cat)
# shellcheck source=_write-state.sh
. "$(dirname "$0")/_write-state.sh"
write_claude_state "done"
