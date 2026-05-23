command -v fzf &>/dev/null || return

# Use fd for faster file listing (respects .gitignore)
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
fi

# Global look + preview toggle
export FZF_DEFAULT_OPTS='
  --height=80% --layout=reverse --border
  --bind ctrl-/:toggle-preview
'

# Ctrl-T: file picker with bat preview; Ctrl-Y copies file contents to wl-clipboard
if command -v bat &>/dev/null && command -v wl-copy &>/dev/null; then
    export FZF_CTRL_T_OPTS="
      --preview 'bat --color=always --style=numbers --line-range=:200 {}'
      --bind 'ctrl-y:execute-silent(wl-copy < {})+abort'
    "
fi

# Ctrl-R: history search; Ctrl-Y copies the command (fields 2..) without running it
if command -v wl-copy &>/dev/null; then
    export FZF_CTRL_R_OPTS="
      --bind 'ctrl-y:execute-silent(echo -n {2..} | wl-copy)+abort'
    "
fi

eval "$(fzf --bash)"
