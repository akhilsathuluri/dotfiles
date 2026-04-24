# uv/uvx shell completions
command -v uv &>/dev/null && eval "$(uv generate-shell-completion bash)"
command -v uvx &>/dev/null && eval "$(uvx --generate-shell-completion bash)"

# yazi: run with y to cd to the chosen directory on quit
command -v yazi &>/dev/null && function y() {
    local tmp cwd
    tmp="$(mktemp -t yazi-cwd.XXXXXX)"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}
