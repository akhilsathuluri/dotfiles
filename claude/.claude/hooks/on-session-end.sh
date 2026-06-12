#!/usr/bin/env bash
# Cleanup: remove the state file when Claude exits cleanly.
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -n "$SID" ] && rm -f "/tmp/claude-sessions/$SID"
