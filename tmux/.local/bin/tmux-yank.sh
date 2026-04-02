#!/bin/bash
# Copy stdin to both Wayland clipboard and primary selection
buf=$(cat)
printf '%s' "$buf" | wl-copy
printf '%s' "$buf" | wl-copy --primary
