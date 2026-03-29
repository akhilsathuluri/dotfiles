#!/usr/bin/env bash
INPUT=$(cat)
SID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SID" ] && exit 0
rm -f "/tmp/claude-sessions/$SID"
