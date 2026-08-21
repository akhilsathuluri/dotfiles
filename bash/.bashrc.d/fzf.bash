command -v fzf &>/dev/null || return

# Use fd for faster file listing (respects .gitignore)
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
fi

# Default bat theme for preview subprocesses (bat config isn't always picked up there).
# theme.bash loads after this and overrides BAT_THEME with the selected flavor.
export BAT_THEME="${BAT_THEME:-Solarized (dark)}"

# Global look + preview toggle. Content hues only - the surfaces (bg, bg+, border, gutter,
# and the fg contrasts picked against them) are left to fzf's own `dark` scheme, which
# inherits the terminal's background. An unswitched machine is on ghostty's built-in dark,
# so naming Solarized surfaces here painted a blue box in a terminal that is not Solarized.
# The `theme` switcher reassigns the whole block via ~/.config/theme/fzf.sh, and a switched
# machine does get the flavor's surfaces - ghostty is wearing them by then.
_fzf_color='--color=dark --color=hl:#268bd2,hl+:#268bd2'
_fzf_color+=' --color=info:#586e75,prompt:#268bd2,pointer:#268bd2'
_fzf_color+=' --color=marker:#859900,spinner:#2aa198,header:#586e75'
# shellcheck source=/dev/null  # written by the `theme` switcher, absent until first run
[ -f ~/.config/theme/fzf.sh ] && . ~/.config/theme/fzf.sh
export FZF_DEFAULT_OPTS="
  --height=80% --layout=reverse --border
  --bind ctrl-/:toggle-preview
  $_fzf_color
"
unset _fzf_color

# Ctrl-T: file picker with bat preview; Ctrl-Y copies file contents to the clipboard
if command -v bat &>/dev/null && command -v clip &>/dev/null; then
    export FZF_CTRL_T_OPTS="
      --preview 'bat --color=always --style=numbers --line-range=:200 {}'
      --bind 'ctrl-y:execute-silent(clip < {})+abort'
    "
fi

# Ctrl-R: history search; Ctrl-Y copies the command (fields 2..) without running it
if command -v clip &>/dev/null; then
    export FZF_CTRL_R_OPTS="
      --bind 'ctrl-y:execute-silent(echo -n {2..} | clip)+abort'
    "
fi

if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(fzf --zsh)"
else
    eval "$(fzf --bash)"
fi

# ff: fuzzy find → enter=open in nvim, ctrl-y=copy path
ff() {
    local out key file
    out=$(fd --type f --hidden --exclude .git --absolute-path | fzf \
        --preview 'bat --color=always {}' \
        --header 'enter: open in nvim  |  ctrl-y: copy path' \
        --expect=ctrl-y)
    key=$(head -1 <<<"$out")
    file=$(tail -1 <<<"$out")
    [ -z "$file" ] && return
    if [ "$key" = "ctrl-y" ]; then
        echo "$file"
    else
        nvim "$file"
    fi
}

# rfv: live ripgrep through fzf, Enter opens nvim at the matched line.
# Usage: rfv [initial-query]
if command -v rg &>/dev/null && command -v bat &>/dev/null; then
    rfv() {
        local rg_prefix='rg --column --line-number --no-heading --color=always --smart-case'
        fzf --ansi --disabled --query "${1:-}" \
            --bind "start:reload:$rg_prefix {q} || :" \
            --bind "change:reload:sleep 0.1; $rg_prefix {q} || :" \
            --bind "enter:become(nvim {1} +{2})" \
            --delimiter=: \
            --preview 'bat --color=always --style=numbers --highlight-line {2} {1}' \
            --preview-window 'up,60%,border-bottom,+{2}+3/3'
    }
fi
