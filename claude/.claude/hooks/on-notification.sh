#!/usr/bin/env bash
INPUT=$(cat)
DIR=$(echo "$INPUT" | jq -r '.cwd // "unknown"' | xargs basename)
mkdir -p /tmp/claude-sessions
echo "question:$DIR" > "/tmp/claude-sessions/$$"
printf '\a'
