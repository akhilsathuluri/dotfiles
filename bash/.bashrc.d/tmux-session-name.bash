_tmux_rename_session_to_repo_branch() {
    [ -n "$TMUX" ] || return 0
    [ -x "$HOME/.local/bin/tmux-rename-session.sh" ] || return 0
    local sid
    sid=$(tmux display-message -p '#{session_id}' 2>/dev/null) || return 0
    "$HOME/.local/bin/tmux-rename-session.sh" "$sid" "$PWD" >/dev/null 2>&1 || true
}

# Run it before each prompt. PROMPT_COMMAND is bash-only; zsh uses precmd_functions.
if [ -n "${BASH_VERSION:-}" ]; then
    case "$PROMPT_COMMAND" in
        *_tmux_rename_session_to_repo_branch*) ;;
        *) PROMPT_COMMAND="_tmux_rename_session_to_repo_branch${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
elif [ -n "${ZSH_VERSION:-}" ]; then
    case " ${precmd_functions[*]} " in
        *" _tmux_rename_session_to_repo_branch "*) ;;
        *) precmd_functions+=(_tmux_rename_session_to_repo_branch) ;;
    esac
fi
