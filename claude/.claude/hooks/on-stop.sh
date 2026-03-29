#!/usr/bin/env bash
INPUT=$(cat)
DIR=$(echo "$INPUT" | jq -r '.cwd // "unknown"' | xargs basename)
SID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SID" ] && exit 0
mkdir -p /tmp/claude-sessions
echo "done:$DIR" > "/tmp/claude-sessions/$SID"
printf '\a'
