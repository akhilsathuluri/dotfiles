# Shell
set -o vi
# Keymap repair for vi mode - `bind` is bash-only, zsh has `bindkey` and its own
# viins/vicmd keymaps, so each shell gets the same set its own way. Two defaults bite:
#
#   - the insert keymap makes Ctrl+L self-insert; restore clear-screen.
#   - Option/Alt + arrow arrives as CSI 1;3<D|C|A|B> (ghostty/config maps the left
#     Option to Alt) and nothing binds it, so the leading ESC switches to the command
#     keymap and the trailing letter runs there as a command: option+left was
#     vi-kill-eol and option+right vi-change-eol - the rest of the line silently gone,
#     from a key that should only ever move the cursor. Binding the family keeps the
#     sequence matched. Up/Down have no word-motion meaning on one line, so they are
#     bound to nothing rather than left to fire vi-add-eol. \eb / \ef cover terminals
#     that send Option+arrow as meta-b / meta-f instead of the CSI form.
#   - Home/End arrive as CSI H / CSI F (or SS3 H/F in application-cursor mode, or
#     CSI 1~ / CSI 4~ from older terminals and some tmux setups) and only the SS3
#     pair was bound, so the CSI form hit the same ESC-falls-through trap: End ran
#     vi-find-prev-char in the command keymap and swallowed the next keypress.
#     All three encodings are bound line-wise here to match the GUI mapping in
#     ~/Library/KeyBindings/DefaultKeyBinding.dict. A prompt has no "document", so
#     Ctrl+Home/End go to the ends of the whole buffer - the closest analogue when
#     editing a multi-line command.
if [ -n "${BASH_VERSION:-}" ]; then
    bind -m vi-insert '"\C-l": clear-screen'
    bind -m vi-command -x '"\C-l": printf "\033[2J\033[H"'
    for _keymap in vi-insert vi-command; do
        bind -m "$_keymap" '"\e[1;3D": backward-word'
        bind -m "$_keymap" '"\e[1;3C": forward-word'
        bind -m "$_keymap" '"\eb": backward-word'
        bind -m "$_keymap" '"\ef": forward-word'
        bind -m "$_keymap" '"\e\C-?": backward-kill-word'
        bind -m "$_keymap" '"\e[1;3A": ""'
        bind -m "$_keymap" '"\e[1;3B": ""'
        bind -m "$_keymap" '"\e[H": beginning-of-line'
        bind -m "$_keymap" '"\e[F": end-of-line'
        bind -m "$_keymap" '"\eOH": beginning-of-line'
        bind -m "$_keymap" '"\eOF": end-of-line'
        bind -m "$_keymap" '"\e[1~": beginning-of-line'
        bind -m "$_keymap" '"\e[4~": end-of-line'
        bind -m "$_keymap" '"\e[1;5H": beginning-of-history'
        bind -m "$_keymap" '"\e[1;5F": end-of-history'
    done
    unset _keymap
elif [ -n "${ZSH_VERSION:-}" ]; then
    for _keymap in viins vicmd; do
        bindkey -M "$_keymap" '^[[1;3D' backward-word
        bindkey -M "$_keymap" '^[[1;3C' forward-word
        bindkey -M "$_keymap" '^[b' backward-word
        bindkey -M "$_keymap" '^[f' forward-word
        bindkey -M "$_keymap" '^[^?' backward-kill-word
        bindkey -M "$_keymap" '^[[1;3A' undefined-key
        bindkey -M "$_keymap" '^[[1;3B' undefined-key
        bindkey -M "$_keymap" '^[[H' beginning-of-line
        bindkey -M "$_keymap" '^[[F' end-of-line
        bindkey -M "$_keymap" '^[OH' beginning-of-line
        bindkey -M "$_keymap" '^[OF' end-of-line
        bindkey -M "$_keymap" '^[[1~' beginning-of-line
        bindkey -M "$_keymap" '^[[4~' end-of-line
        bindkey -M "$_keymap" '^[[1;5H' beginning-of-buffer-or-history
        bindkey -M "$_keymap" '^[[1;5F' end-of-buffer-or-history
    done
    unset _keymap
fi
export VISUAL=nvim
export EDITOR=nvim
# No TERM here: tmux sets it inside panes, the terminal sets it outside. Forcing
# it hid Ghostty from tmux, so 'xterm-ghostty:*' terminal-features never matched.
# `open` (macOS) opens URLs in the user's default browser; firefox elsewhere.
if [ "$(uname)" = "Darwin" ]; then
    export BROWSER="open"
else
    export BROWSER="firefox"
fi

# Git - gd/gds/gdw/gdm open hunk's interactive TUI; git's own pager is delta
alias gd='hunk diff'          # review working-tree changes (incl. untracked)
alias gds='hunk show'         # review the latest commit
alias gdw='hunk diff --watch' # working-tree review, auto-reload on change
alias gdl='git diff HEAD~1 HEAD'
alias gm='git commit -m'
alias gf='git fetch --prune'
# alias gl='git pull'
alias gl='git log'
alias gp='git push'
alias gpub='git push origin $(git branch --show-current)'
alias gplb='git pull origin $(git branch --show-current)'
alias gs='git status'
# alias gst='git status'
alias ga='git add .'
alias gpm='git pull origin main'
alias gsm='git switch main'
alias gsw='git switch'
# gb: local branches by recency, then the current one. A function, not an alias,
# so the awk program needs no escaping and the lines stay readable.
gb() {
    git branch --sort=committerdate --format="%(refname:short) %(committerdate:relative)" |
        tail -20 |
        awk -F" " '{name=$1; $1=""; printf "%-50s (%s)\n", name, substr($0,2)}'
    echo ""
    echo "* $(git branch --show-current)"
}

# gbr: remote branches (last 500 by recency) with tip author; run gf first to refresh
gbr() {
    git branch -r --sort=committerdate \
        --format="%(refname:short)%09%(authorname)%09%(committerdate:relative)" |
        grep -v "/HEAD" |
        tail -500 |
        awk -F"\t" '{ printf "%-60s %-20s (%s)\n", $1, $2, $3 }'
}
alias gdm='hunk diff origin/main...HEAD'
alias gw='while clear; do git diff --stat --color && echo "---" && git diff --color | head -60; sleep 2; done'

# Worktree family (mirrors oh-my-zsh git plugin naming: gwt/gwta/gwtls/gwtmv/gwtrm)
alias gwt='git worktree'
alias gwtls='git worktree list'
alias gwtmv='git worktree move'
alias gwtrm='git worktree remove'

# gwta: add a worktree for a branch, resolving it wherever it exists.
# Arg order mirrors `git worktree add <dir> <branch>`.
# Remote (latest) > local-only > new branch off base (default origin/main).
# Usage: gwta <dir> <branch> [base]
gwta() {
    local dir="$1" branch="$2" base="${3:-origin/main}"
    if [ -z "$dir" ] || [ -z "$branch" ]; then
        echo "usage: gwta <dir> <branch> [base]" >&2
        return 1
    fi
    git fetch origin "$branch" 2>/dev/null
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        # exists on remote -> (re)point local branch at remote tip
        git worktree add "$dir" -B "$branch" "origin/$branch"
    elif git show-ref --verify --quiet "refs/heads/$branch"; then
        # local-only branch -> check out as-is
        git worktree add "$dir" "$branch"
    else
        # nowhere -> create new branch off base
        git fetch origin 2>/dev/null
        echo "branch '$branch' not found; creating it off '$base'" >&2
        git worktree add "$dir" -b "$branch" "$base"
    fi
}

# gwts: fuzzy-switch between worktrees of the current repo (cd into the pick).
gwts() {
    local line dir
    line=$(git worktree list | grep -v ' (bare)$' | fzf --prompt='worktree> ') || return
    dir="${line%% *}"
    [ -n "$dir" ] || return
    cd "$dir" || return
}

# gwtm: put this worktree's branch (named after the worktree dir, created off
# origin/main if missing) on the latest origin/main. Always a merge, never a
# rebase - nothing already committed is rewritten, pushed or not - and it
# fast-forwards when we have no commits of our own. --autostash keeps a dirty
# tree out of the way.
gwtm() {
    local root name
    root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "not in a git repo" >&2
        return 1
    }
    name=$(basename "$root")
    git fetch origin || return
    if git show-ref --verify --quiet "refs/heads/$name"; then
        git switch "$name" || return
    else
        git switch -c "$name" origin/main || return
    fi
    git merge --no-edit --autostash origin/main
}

# Docker
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
alias docker-stop-all='docker stop $(docker ps -a -q)'
alias docker-rm-all='docker rm $(docker ps -a -q)'

# Files
alias ll='ls -lrth'
# --pager less -RFX: -X keeps paged output in tmux scrollback (no alt-screen),
# so mouse-drag selection still copies; -F prints inline when it fits one screen.
alias bat='bat --style=plain --pager="less -RFX"'

# Editor
alias vim='nvim'
alias vimr='NVIM_RESTORE=1 nvim'

# Tmux
# Attach to session (default: current dir name), creating if missing.
# Inside tmux, switch the client instead of nesting sessions.
ta() {
    local name="${1:-$(basename "$PWD")}"
    if [ -n "$TMUX" ]; then
        # Already inside tmux: create-if-missing, then switch (never nest).
        tmux new-session -d -s "$name" 2>/dev/null
        tmux switch-client -t "$name"
    elif tmux ls >/dev/null 2>&1; then
        # Server already running: attach, creating the session if needed.
        tmux new-session -A -s "$name"
    else
        # Cold start (post-reboot): let tmux-continuum auto-restore populate the
        # server first. Boot a throwaway 2-pane session so tmux-resurrect's
        # "restore from scratch" (which fires only when the whole server has exactly
        # one pane) does NOT absorb our launch pane into a restored session and
        # scramble its layout. Then drop the scratch and attach to the target.
        tmux new-session -d -s _resurrect_boot -c "$HOME"
        tmux split-window -t _resurrect_boot -c "$HOME"
        for _ in $(seq 1 60); do
            tmux has-session -t "$name" 2>/dev/null && break
            sleep 0.25
        done
        # Restore succeeded if any real session now exists; if so, drop the scratch.
        if tmux ls -F '#{session_name}' 2>/dev/null | grep -qvx _resurrect_boot; then
            tmux kill-session -t _resurrect_boot 2>/dev/null
        fi
        tmux attach -t "$name" 2>/dev/null ||
            tmux attach 2>/dev/null ||
            tmux new-session -A -s "$name"
    fi
}

# Quick reference
alias cheat='bat ~/git/dotfiles/CHEATSHEET.md 2>/dev/null || bat ~/dotfiles/CHEATSHEET.md'

# Fuzzy grep: interactive ripgrep across all files from cwd
alias rgg='rg --line-number "" | fzf --delimiter : --preview "bat --color=always {1} --highlight-line {2}"'
