#!/usr/bin/env bash
INPUT=$(cat)
# Atomically increment the counter for the top bar indicator
flock /tmp/claude-ready.lock bash -c 'n=$(cat /tmp/claude-ready-count 2>/dev/null || echo 0); echo $((n+1)) > /tmp/claude-ready-count'
# Bell for tmux window highlight
printf '\a'
