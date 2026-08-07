# Theme switcher

_How one command re-skins the whole terminal stack from [`palette.toml`](./palette.toml). Companion to
[README.md](./README.md) (the design language)._

## Usage

```
theme                      # print the current flavor
theme --list               # list the four flavors
theme <flavor>             # re-skin the whole stack
theme none                 # clear the state - back to the tracked defaults
```

Flavors: `solarized-dark` · `solarized-light` · `catppuccin-latte` · `catppuccin-mocha`. The choice **persists** (via
`~/.config/theme/`) and applies to new shells, new windows, and the running tmux/ghostty. It is **explicit** - the
switcher never picks a theme from the OS appearance or the time of day, and nothing (`bootstrap.sh` included) applies
one for you.

**The unswitched baseline.** With no flavor applied, every tool falls back to the default in its own tracked config -
ghostty's built-in dark (`#282c34`), tmux's green status bar, nvim's `vscode`, the fzf `--color` block in `fzf.bash`,
the sidebar's built-in solarized-dark. That is a coherent look in its own right, not a broken one, and `theme none`
returns to it: it deletes everything under `~/.config/theme/`, unsets `@agentbar-theme`, reloads ghostty and re-sources
`~/.tmux.conf`.

## Two kinds of tools

- **Name-driven** (ghostty, bat, delta, nvim): the switcher sets a theme _identifier_ the tool already ships and lets
  the tool render it.
- **Hex-driven** (tmux frame, fzf, agent sidebar): the switcher reads hexes from `palette.toml` and writes a small
  generated config the tool consumes.

`palette.toml` is the source of truth for the hex-driven half; the name-driven half maps a flavor to each tool's own
identifier.

## Adapter table

Everything the switcher touches writes into `~/.config/theme/` and is consumed from there, so switching never edits a
tracked config.

| Tool           | Themed by       | What the switcher writes                                          | Reload                            |
| -------------- | --------------- | ----------------------------------------------------------------- | --------------------------------- |
| agent sidebar  | option (id)     | `tmux set -g @agentbar-theme <flavor>`                            | restart (`prefix + e` ×2)         |
| ghostty        | named           | `theme = <Name>` → `ghostty.conf` (a `config-file` include)       | SIGUSR2 · macOS: `reload_config`  |
| tmux frame     | hex → generated | `tmux.conf` (status/window/pane + dictate/submit/push/diff chips) | `tmux source-file` (immediate)    |
| fzf            | hex → export    | `fzf.sh` (`_fzf_color` `--color` block, sourced by fzf.bash)      | new shells                        |
| bat / `$THEME` | named           | `env.sh` (`export THEME`, `export BAT_THEME`)                     | new shells                        |
| git-delta      | hex + named     | `delta.gitconfig` (a `[delta]` block, git-included)               | next `git` invocation             |
| nvim           | named           | `nvim.lua` (`colorscheme` + `background`)                         | live `:colorscheme` / next launch |

Tools that follow the flavor **without** being driven by the switcher:

- **hunk** - a `hunk()` wrapper in `bash/.bashrc.d/theme.bash` appends `--theme $THEME` to `hunk diff` (hunk falls back
  gracefully on a flavor it lacks).
- **session picker & `tmux-gitlab.sh`** - still hardcode Solarized hexes (not yet palette-driven).

## Where the choice lives

- `~/.config/theme/current` - the selected flavor id (one line); read back by `theme` to print the active flavor.
- `~/.config/theme/env.sh` - sourced by `bash/.bashrc.d/theme.bash`; exports `THEME` and `BAT_THEME`. (fzf's colors are
  separate, in `fzf.sh`.)
- `tmux set -g @agentbar-theme <flavor>` - so the sidebar can read the flavor at launch.

## Operational notes

**Activation on a fresh pull:** `cd ~/dotfiles && stow theme bash`, open a new shell, `bat cache --build` (or run
`bootstrap.sh`), then `theme <flavor>`.

**Ghostty reload is per-platform.** Linux takes `pkill -USR2 -x ghostty`. macOS has no such handler to rely on - an
unhandled SIGUSR2 kills the terminal - so the switcher drives the same `reload_config` action through Ghostty's
scripting interface (`osascript … perform action "reload_config" on terminal 1`, declared in `Ghostty.sdef`). Both are
skipped unless Ghostty is already running, since `tell application` would otherwise launch it.

**Needs live verification** (not checkable headless - launch and eyeball): nvim colorscheme per flavor · hunk render for
solarized-dark / catppuccin.
