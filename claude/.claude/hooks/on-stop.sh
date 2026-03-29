#!/usr/bin/env bash
INPUT=$(cat)
DIR=$(echo "$INPUT" | jq -r '.cwd // "unknown"' | xargs basename)
mkdir -p /tmp/claude-sessions
echo "done:$DIR" > "/tmp/claude-sessions/$$"
printf '\a'
