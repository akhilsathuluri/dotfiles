#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# All software installs (and every version pin) live in install.sh.
# shellcheck source=install.sh
. "$DOTFILES_DIR/install.sh"

# =============================================================================
# Canonical ~/dotfiles path
# =============================================================================

# The ~ in the messages below is for the reader, not a path to expand.
# shellcheck disable=SC2088
link_dotfiles_dir() {
    # agentbar's tmux entry line and the Claude hooks in settings.json address the
    # repo as ~/dotfiles, and neither a tmux config nor a JSON hook can resolve a
    # path at load time. Rather than hardcode one checkout location, make
    # ~/dotfiles a symlink to wherever this repo actually is, so the repo stays
    # movable and those two files need no per-machine edit.
    local link="$HOME/dotfiles"
    [ "$DOTFILES_DIR" = "$link" ] && return 0
    if [ -L "$link" ]; then
        [ "$(realpath_of "$link")" = "$(realpath_of "$DOTFILES_DIR")" ] && {
            ok "~/dotfiles already points here"
            return 0
        }
        ln -sfn "$DOTFILES_DIR" "$link"
        ok "~/dotfiles re-pointed at $DOTFILES_DIR"
    elif [ -e "$link" ]; then
        warn "~/dotfiles exists and is not a symlink - leaving it alone."
        warn "agentbar and the Claude hooks look there; move it or clone the repo to ~/dotfiles."
    else
        ln -s "$DOTFILES_DIR" "$link"
        ok "~/dotfiles -> $DOTFILES_DIR"
    fi
}

# =============================================================================
# Stow packages
# =============================================================================

# Canonical path of $1. BSD readlink has no -f, and returning empty there would
# make backup_if_not_symlink compare "" to "" and skip a real backup, so this
# always falls through to a cd -P walk rather than failing quietly.
realpath_of() {
    readlink -f -- "$1" 2>/dev/null && return 0
    greadlink -f -- "$1" 2>/dev/null && return 0
    local d b
    d=$(dirname -- "$1")
    b=$(basename -- "$1")
    if d=$(cd -P -- "$d" 2>/dev/null && pwd); then
        printf '%s/%s\n' "${d%/}" "$b"
    else
        printf '%s\n' "$1"
    fi
}

backup_if_not_symlink() {
    # $1: target path. $2 (optional): the repo source path.
    # Behavior:
    #   * target doesn't exist or is a symlink → nothing to do.
    #   * target resolves (via realpath, catching parent-dir symlinks)
    #     to the same inode as src → nothing to do; stow has already
    #     folded the parent directory.
    #   * src given AND content matches → silently remove target so stow
    #     can replace it with a symlink (no noisy .pre-dotfiles).
    #   * otherwise → move target aside to ${target}.pre-dotfiles.
    local target="$1" src="${2:-}"
    [ -e "$target" ] && [ ! -L "$target" ] || return 0
    if [ -n "$src" ] && [ "$(realpath_of "$target")" = "$(realpath_of "$src")" ]; then
        return 0
    fi
    if [ -n "$src" ] && [ -f "$target" ] && [ -f "$src" ] && cmp -s "$target" "$src"; then
        rm "$target"
    else
        warn "Backing up $target -> ${target}.pre-dotfiles"
        mv "$target" "${target}.pre-dotfiles"
    fi
}

# Per-file backup for directories shared with the user's own files.
# Only backs up files we're about to stow in - user's other files stay put.
backup_pkg_files() {
    local pkg_src="$1" target_dir="$2"
    [ -d "$pkg_src" ] || return
    local f
    for f in "$pkg_src"/*; do
        [ -e "$f" ] || continue
        backup_if_not_symlink "$target_dir/$(basename "$f")" "$f"
    done
}

stow_packages() {
    local packages=(bash bat claude clip dictate ghostty git hunk leaf nvim shot tex theme tmux trace)
    if is_linux; then
        # Linux-only: the GNOME indicator and the screenshot watcher (inotify)
        # have no macOS counterpart.
        packages+=(claude-indicator screenshot-watcher)
    fi

    # Single files we own outright: back up the file itself.
    backup_if_not_symlink "$HOME/.tmux.conf" "$DOTFILES_DIR/tmux/.tmux.conf"
    backup_if_not_symlink "$HOME/.local/bin/tmux-gitlab.sh" "$DOTFILES_DIR/tmux/.local/bin/tmux-gitlab.sh"
    backup_if_not_symlink "$HOME/.local/bin/tmux-rename-session.sh" \
        "$DOTFILES_DIR/tmux/.local/bin/tmux-rename-session.sh"
    backup_if_not_symlink "$HOME/.local/bin/tmux-session-name.sh" \
        "$DOTFILES_DIR/tmux/.local/bin/tmux-session-name.sh"
    backup_if_not_symlink "$HOME/.claude/settings.json" "$DOTFILES_DIR/claude/.claude/settings.json"
    backup_if_not_symlink "$HOME/.claude/statusline-command.sh" "$DOTFILES_DIR/claude/.claude/statusline-command.sh"

    # Directories the user may share with their own files: back up only the
    # specific files we ship, leaving the rest of the directory intact.
    backup_pkg_files "$DOTFILES_DIR/bash/.bashrc.d" "$HOME/.bashrc.d"
    backup_pkg_files "$DOTFILES_DIR/claude/.claude/hooks" "$HOME/.claude/hooks"

    # Directories we own outright: back up the whole directory.
    backup_if_not_symlink "$HOME/.config/nvim"
    backup_if_not_symlink "$HOME/.config/bat"
    backup_if_not_symlink "$HOME/.config/ghostty"
    backup_if_not_symlink "$HOME/.config/hunk"
    backup_if_not_symlink "$HOME/.config/leaf"

    cd "$DOTFILES_DIR"
    for pkg in "${packages[@]}"; do
        log "Stowing $pkg..."
        stow --restow -t "$HOME" "$pkg"
    done
    ok "All packages stowed"
}

# Bootstrap deliberately applies no theme flavor. The tracked configs carry their own
# defaults (ghostty's dark background, tmux's green status bar, nvim's catppuccin-mocha
# ground-matched to that background), so a fresh machine looks like every other
# unswitched machine; `theme <flavor>` is opt-in per machine and `theme none` comes back
# here. Seeding a flavor here instead made two boxes on the same commit look different,
# depending on which had been bootstrapped since the seeding landed.

enable_tmux_resurrect_timer() {
    # tmux-continuum only autosaves while a client is attached (its save hook
    # rides the status-bar redraw), so a long detached stretch before a reboot
    # loses everything since the last attached save. This user timer saves on a
    # schedule regardless of attachment. Units ship with the tmux stow package.
    if ! command -v systemctl &>/dev/null; then
        return
    fi
    log "Enabling tmux-resurrect autosave timer (systemd --user)..."
    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user enable --now tmux-resurrect-save.timer 2>/dev/null; then
        ok "tmux-resurrect-save.timer enabled"
    else
        warn "Could not enable tmux-resurrect-save.timer (no user systemd session?)"
    fi
    # Keep the timer running even with no active login session.
    loginctl enable-linger "$USER" 2>/dev/null || true
}

# =============================================================================
# Patch the shell rc (~/.bashrc on Linux, ~/.zshrc on macOS)
# =============================================================================

patch_shell_rc() {
    local rc legacy="# Load dotfiles shell customizations"
    local start="# >>> dotfiles >>>"
    local end="# <<< dotfiles <<<"
    if is_macos; then
        rc="$HOME/.zshrc"
        [ -f "$rc" ] || touch "$rc"
    else
        rc="$HOME/.bashrc"
    fi

    # First-time backup only.
    [ -f "${rc}.pre-dotfiles" ] || cp "$rc" "${rc}.pre-dotfiles"

    # Strip any existing patch so the file stays self-healing across upgrades.
    # Handles both the current start/end markers and the legacy single-marker
    # form (always appended last, so we drop from marker to EOF). Both branches
    # also drop trailing blank lines, so re-running never accumulates them.
    if grep -qF "$start" "$rc"; then
        awk -v s="$start" -v e="$end" '
            $0 == s { skip=1; next }
            $0 == e { skip=0; next }
            skip    { next }
            /^$/    { pending++; next }
                    { while (pending--) print ""; pending=0; print }
        ' "$rc" >"$rc.tmp" && mv "$rc.tmp" "$rc"
    elif grep -qF "$legacy" "$rc"; then
        awk -v m="$legacy" '
            $0 == m { found=1 }
            found   { next }
            /^$/    { pending++; next }
                    { while (pending--) print ""; pending=0; print }
        ' "$rc" >"$rc.tmp" && mv "$rc.tmp" "$rc"
    fi

    log "Patching $rc..."
    # Same loop for bash and zsh. Each .bashrc.d/*.bash guards its own bash-only
    # or zsh-only sections via $BASH_VERSION / $ZSH_VERSION.
    cat >>"$rc" <<EOF

$start
for f in ~/.bashrc.d/*.bash; do [ -r "\$f" ] && source "\$f"; done
$end
EOF
    ok "$rc patched (backup at ${rc}.pre-dotfiles)"
}

copy_if_absent() {
    # copy_if_absent SRC DEST - seed a file only when it doesn't exist yet, so a re-run
    # never clobbers edits the user (or an agent) has made in the live vault.
    local src="$1" dest="$2"
    if [ -e "$dest" ]; then return; fi
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
}

seed_vault() {
    # Seed one notes vault from vault-template/ as REAL files (not stow symlinks): the
    # scaffolding is committed into the vault's own private repo, so it stays portable
    # and self-contained on any machine. obsidian.nvim errors on startup if the
    # workspace path is missing, so the PARA + capture folders are always ensured;
    # everything else is copy-if-absent - idempotent, never overwriting live edits.
    # Never commits (that stays the user's call, same as the sync hints below).
    local vault="$1" type="$2"
    local tpl="$DOTFILES_DIR/vault-template" d f
    for d in archive areas assets dailies inbox projects resources templates; do
        mkdir -p "$vault/$d"
    done
    copy_if_absent "$tpl/common/.gitignore" "$vault/.gitignore"
    copy_if_absent "$tpl/common/.prettierrc" "$vault/.prettierrc"
    copy_if_absent "$tpl/common/Home.md" "$vault/Home.md"
    copy_if_absent "$tpl/$type/CLAUDE.md" "$vault/CLAUDE.md"
    copy_if_absent "$tpl/$type/README.md" "$vault/README.md"
    for f in "$tpl"/common/templates/*; do
        copy_if_absent "$f" "$vault/templates/$(basename "$f")"
    done
    copy_if_absent "$tpl/common/.claude/settings.json" "$vault/.claude/settings.json"
    copy_if_absent "$tpl/common/.claude/vault-check.sh" "$vault/.claude/vault-check.sh"
    for f in "$tpl"/common/.claude/hooks/*.sh; do
        copy_if_absent "$f" "$vault/.claude/hooks/$(basename "$f")"
    done
    copy_if_absent "$tpl/common/.githooks/pre-commit" "$vault/.githooks/pre-commit"
    # vault-check.sh must be +x - the pre-commit runs it only under `[ -x ]`, else integrity is silently skipped.
    chmod +x "$vault/.claude/vault-check.sh" "$vault/.claude/hooks/"*.sh \
        "$vault/.githooks/pre-commit" 2>/dev/null || true
    # git ignores empty dirs, so a fresh skeleton has nothing to commit and the first
    # push fails. Keep each still-empty capture dir trackable with a .gitkeep.
    for d in archive areas assets dailies inbox projects resources templates; do
        [ -n "$(ls -A "$vault/$d" 2>/dev/null)" ] || touch "$vault/$d/.gitkeep"
    done
    # Route git hooks at the tracked .githooks/ dir (the secrets pre-commit guard).
    # Harmless to set repeatedly; only applies once the vault is a git repo. Kept as an
    # if (not `&&`) so a not-yet-a-repo vault leaves the function returning 0 under set -e.
    if [ -d "$vault/.git" ]; then
        git -C "$vault" config core.hooksPath .githooks
    fi
}

create_personal_vault() {
    # Personal knowledge vault (private GitHub). If it isn't a git repo yet, just flag
    # it - the wiring steps are shown together at the very end (print_vault_sync_hints)
    # so they aren't buried mid-run. Idempotent.
    local vault="$HOME/vaults/personal"
    seed_vault "$vault" personal
    if [ -d "$vault/.git" ]; then
        ok "personal vault ready at $vault"
    else
        ok "personal vault skeleton ready at $vault (not synced to a remote)"
        PERSONAL_VAULT_UNWIRED=1
    fi
}

create_work_vault() {
    # Work knowledge vault, an independent sibling on its own separate remote (private
    # GitLab). Same skeleton; if it isn't a git repo yet, flag it for the end-of-run
    # hints rather than printing steps mid-run. Idempotent.
    local vault="$HOME/vaults/work"
    seed_vault "$vault" work
    if [ -d "$vault/.git" ]; then
        ok "work vault ready at $vault"
    else
        ok "work vault skeleton ready at $vault (not synced to a remote)"
        WORK_VAULT_UNWIRED=1
    fi
}

print_vault_sync_hints() {
    # Printed at the very end so it isn't buried in the build logs. Optional: a vault
    # works locally without a remote; this only shows how to back one up / sync it.
    # We never create the remote or store identity here (these dotfiles are public),
    # so the user runs the steps himself. One independent block per vault by design.
    [ -n "${PERSONAL_VAULT_UNWIRED:-}" ] || [ -n "${WORK_VAULT_UNWIRED:-}" ] || return 0
    echo ""
    warn "Optional - notes vault(s) not yet synced to a git remote."
    warn "Set up only the ones you want backed up / synced (run these yourself):"
    if [ -n "${PERSONAL_VAULT_UNWIRED:-}" ]; then
        cat <<'EOF'

  personal vault -> your PRIVATE personal remote:
    cd ~/vaults/personal
    git init -b main
    git remote add origin <private-remote-url>   # e.g. a private <user>/vaults-personal
    git add -A
    git commit -m "Initialize personal vault"
    git push -u origin main
EOF
    fi
    if [ -n "${WORK_VAULT_UNWIRED:-}" ]; then
        cat <<'EOF'

  work vault -> your PRIVATE work remote:
    cd ~/vaults/work
    git init -b main
    git remote add origin <private-remote-url>   # e.g. a private <user>/vaults-work
    git add -A
    git commit -m "Initialize work vault"
    git push -u origin main
EOF
    fi
}

# =============================================================================
# Apps (built from source under apps/)
# =============================================================================

build_apps() {
    # Uniform contract for every project under apps/, regardless of language:
    # a Makefile with a `build` target. Install its toolchain above (e.g. Go)
    # and add nothing here. The built binary lives in the app's own bin/.
    [ -d "$DOTFILES_DIR/apps" ] || return
    local app name
    for app in "$DOTFILES_DIR"/apps/*/; do
        [ -f "$app/Makefile" ] || continue
        name=$(basename "$app")
        log "Building app: $name..."
        if make -C "$app" build >/dev/null 2>&1; then
            ok "Built $name"
        else
            warn "Build failed for $name (toolchain missing?)"
        fi
    done
    link_app_clis
}

# The one exception to "the built binary lives in the app's own bin/": workdesk is a
# CLI you and your agents type (`workdesk board`, `workdesk mr <iid>`), and a command
# you cannot type is a worse tool. agentbar is never typed - tmux and the Claude hooks
# invoke it by absolute path - so it gets no link.
link_app_clis() {
    local bin="$DOTFILES_DIR/apps/agentbar/bin/workdesk"
    [ -x "$bin" ] || return 0
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$bin" "$HOME/.local/bin/workdesk"
    ok "workdesk linked into ~/.local/bin"
}

# =============================================================================
# Commit guard
# =============================================================================

# This repo is public and its configs are stowed, so the Claude runtime writes
# machine-local state (an autoMode environment description) straight into a tracked
# file. Wire the pre-commit guard that refuses to commit it, and seed the untracked
# pattern file it reads for the names a public repo cannot list.
enable_commit_guard() {
    git -C "$DOTFILES_DIR" config core.hooksPath .githooks
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
    local f="$dir/redact-patterns"
    mkdir -p "$dir"
    if [ ! -f "$f" ]; then
        cat >"$f" <<'PATTERNS'
# Machine-local redact patterns for the dotfiles pre-commit guard.
# One extended-regex per line; '#' comments and blank lines ignored. Case-insensitive.
# Deliberately OUTSIDE the repo: the public repo can name none of this. Add employer,
# product, project, internal host and bucket names as you meet them.
PATTERNS
        ok "seeded $f (add your employer/product/host patterns)"
    fi
    ok "pre-commit guard wired (core.hooksPath=.githooks)"
}

# =============================================================================
# Main
# =============================================================================

bootstrap_usage() {
    cat <<'EOF'
usage: ./bootstrap.sh [--help] [step...]

Sets up this machine: tools, stow packages, the shell rc, vaults, resurrect timer,
apps/. Idempotent. A step name is forwarded to install.sh, so `./bootstrap.sh
dictate-deps` runs only that one.

Per-step CLI: ./install.sh, run it to list the steps.
Unattended: nothing prompts; on Linux the apt steps need sudo, asked for once up front.
EOF
}

case "${1:-}" in
    -h | --help)
        bootstrap_usage
        exit 0
        ;;
esac

# Everything lands under $HOME; as root that becomes /root and leaves
# root-owned files behind. install.sh sudo's the steps that need it.
if [ "$(id -u)" -eq 0 ]; then
    warn "run bootstrap.sh as your own user, not root - it installs into \$HOME" >&2
    exit 2
fi

# Opt-in steps, not part of the default run:  ./bootstrap.sh dictate-deps
if [ $# -gt 0 ]; then
    for step in "$@"; do run_step "$step"; done
    exit 0
fi

# Ask once here rather than at the first apt step. macOS has no apt steps; brew
# prompts for itself when it needs to.
if is_linux && ! sudo -n true 2>/dev/null; then
    log "The apt steps need sudo - authenticating once now..."
    sudo -v || {
        warn "cannot acquire sudo; pre-cache with 'sudo -v' or add a NOPASSWD entry" >&2
        exit 2
    }
fi

log "Starting dotfiles bootstrap on $OS_KIND..."
link_dotfiles_dir
enable_commit_guard
all_tools

stow_packages
# These two need the stowed configs in place first.
install_bat_themes
enable_tmux_resurrect_timer
patch_shell_rc
create_personal_vault
create_work_vault
install_nvim_plugins
build_apps

echo ""
if is_macos; then
    ok "Done! Restart your shell or run: source ~/.zshrc"
else
    ok "Done! Restart your shell or run: source ~/.bashrc"
fi
print_vault_sync_hints
