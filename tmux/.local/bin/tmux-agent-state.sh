#!/usr/bin/env bash
# The agent-state language for shell surfaces - sourced, not run.
#
# One definition for the session picker AND its preview, because two copies is
# exactly how they drifted: the preview grew emoji circles while the picker and
# the sidebar drew glyphs. Glyphs and priority mirror the sidebar's `stateIcon`
# (apps/agentbar/internal/ui/render.go) - change them together.
#
# Colors come from the theme switcher's generated file, so the popup follows a
# `theme` switch like every other surface; per design/palette.toml nothing
# downstream hardcodes. `theme` is opt-in per machine, so the fallbacks below are
# ANSI slots rather than one flavor's hex: an unswitched machine follows whatever
# the terminal is themed as, exactly like the tmux frame.

# shellcheck disable=SC2034  # consumers read these
_state_blocked="31"
_state_asking="33"
_state_working="36"
_state_done="32"
_state_muted="2"
_popup_fzf_color="fg:-1,bg:-1,fg+:bright-white,bg+:black,gutter:-1,pointer:-1"
_popup_fzf_color+=",hl:blue,hl+:bright-white,border:blue,info:blue,header:blue"

_theme_state_file="${XDG_CONFIG_HOME:-$HOME/.config}/theme/agent-state.sh"
# shellcheck source=/dev/null
[ -r "$_theme_state_file" ] && . "$_theme_state_file"

# hex_sgr <#rrggbb|SGR> - truecolor foreground escape for a palette hex, or a bare
# SGR parameter through untouched, which is what the unthemed fallbacks above use.
hex_sgr() {
    case $1 in
        '#'*) ;;
        *)
            printf '\033[%sm' "$1"
            return 0
            ;;
    esac
    local hex=${1#\#}
    printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# agent_icon <state> - the one-cell glyph for a state, colored. Single-width on
# purpose: emoji are double-width and shift every column after them.
agent_icon() {
    case $1 in
        permission) printf '%s◔\033[0m' "$(hex_sgr "$_state_blocked")" ;;
        question) printf '%s?\033[0m' "$(hex_sgr "$_state_asking")" ;;
        working) printf '%s⠹\033[0m' "$(hex_sgr "$_state_working")" ;;
        done) printf '%s✓\033[0m' "$(hex_sgr "$_state_done")" ;;
        *) printf ' ' ;;
    esac
}

# agent_muted <text> - muted-grey run, for band dividers and other chrome.
agent_muted() {
    printf '%s%s\033[0m' "$(hex_sgr "$_state_muted")" "$1"
}

# agent_state_rank <state> - worst-state-wins priority for a per-session rollup:
# permission > asking > working > done > none.
agent_state_rank() {
    case $1 in
        permission) printf 4 ;;
        question) printf 3 ;;
        working) printf 2 ;;
        done) printf 1 ;;
        *) printf 0 ;;
    esac
}
