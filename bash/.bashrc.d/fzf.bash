command -v fzf &>/dev/null || return

# Use fd for faster file listing (respects .gitignore)
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
fi

eval "$(fzf --bash)"

# ff: fuzzy find → enter=open in nvim, ctrl-y=copy path
ff() {
    local out key file
    out=$(fd --type f --hidden --exclude .git --absolute-path | fzf \
        --preview 'bat --color=always {}' \
        --header 'enter: open in nvim  |  ctrl-y: copy path' \
        --expect=ctrl-y)
    key=$(head -1 <<< "$out")
    file=$(tail -1 <<< "$out")
    [ -z "$file" ] && return
    if [ "$key" = "ctrl-y" ]; then
        echo "$file"
    else
        nvim "$file"
    fi
}
