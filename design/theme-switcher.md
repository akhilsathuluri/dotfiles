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

Flavors: `catppuccin-mocha-black` (the default) · `catppuccin-mocha` · `catppuccin-latte` · `solarized-dark` ·
`solarized-light`. The choice **persists** (via `~/.config/theme/`) and applies to new shells, new windows, and the
running tmux/ghostty. It is **explicit** - the switcher never picks a theme from the OS appearance or the time of day.

**The unswitched baseline.** With no flavor applied, every tool falls back to the default in its own tracked config -
ghostty's built-in dark (`#282c34`), tmux's green status bar, nvim's Catppuccin Mocha **on that ghostty ground**, the
hue-only fzf `--color` block in `fzf.bash` (its surfaces follow the terminal, so the popup blends into whatever bg
ghostty is wearing), the sidebar's compiled-in default. That is a coherent look in its own right, not a broken one, and
`theme none` returns to it: it deletes everything under `~/.config/theme/`, unsets `@agentbar-theme`, reloads ghostty
and re-sources `~/.tmux.conf`.

**nvim's baseline is the one that had to be built.** Every other tool's tracked default either follows the terminal
(fzf, the popup's ANSI slots) or is the terminal (ghostty). nvim paints its own ground, so `vscode`'s did not match
ghostty's `#282c34` and the editor read as a rectangle pasted into the terminal. The fallback in
`nvim/.config/nvim/lua/plugins/colorscheme.lua` is therefore Catppuccin Mocha with `base`/`mantle`/`surface0`/`surface1`
overridden to One Dark's tones - which is where ghostty's default background comes from - so Catppuccin's hues sit on
the terminal's own ground. `[meta] default` (`solarized-dark`) is unrelated to this: it feeds only the sidebar's
compiled-in fallback, since nothing applies a flavor on an unswitched machine.

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

| Tool           | Themed by       | What the switcher writes                                                                   | Reload                              |
| -------------- | --------------- | ------------------------------------------------------------------------------------------ | ----------------------------------- |
| agent sidebar  | hex → generated | `@agentbar-theme`; colors from `theme_gen.go` (built from the palette)                     | this session's, immediate           |
| ghostty        | named           | `theme = <Name>` then a `background =` override → `ghostty.conf` (a `config-file` include) | SIGUSR2 · macOS: `reload_config`    |
| tmux frame     | hex → generated | `tmux.conf` (status/window/pane + the workdesk/dictate/push/diff/⛭ chips)                  | `tmux source-file` (immediate)      |
| fzf            | hex → export    | `fzf.sh` (`_fzf_color` `--color` block, sourced by fzf.bash)                               | new shells                          |
| bat / `$THEME` | named           | `env.sh` (`export THEME`, `export BAT_THEME`)                                              | new shells                          |
| hunk name map  | named           | `env.sh` (`export HUNK_THEME`) - the flavor id unless hunk has no theme by that name       | next `hunk diff` / diff-pane re-run |
| leaf           | named           | `env.sh` (`export LEAF_THEME`)                                                             | next `leaf` launch                  |
| git-delta      | hex + named     | `delta.gitconfig` (a `[delta]` block, git-included)                                        | next `git` invocation               |
| nvim           | named           | `nvim.lua` (`colorscheme`, `background`, and `ground` for the catppuccin schemes)          | live `:colorscheme` / next launch   |
| session popup  | hex → generated | `agent-state.sh` (state colors + the popup's fzf palette, base mode and ground included)   | next open                           |
| hunk           | named           | `--theme <flavor>` on the diff pane's own command line                                     | the diff pane is re-run             |

Tools that follow the flavor **without** being driven by the switcher:

- **hunk** - a `hunk()` wrapper in `bash/.bashrc.d/theme.bash` appends `--theme $THEME` to `hunk diff` (hunk falls back
  gracefully on a flavor it lacks).
- **Claude Code** - the switcher deliberately does not write it. Claude persists `theme` into `~/.claude/settings.json`,
  a stow symlink into this repo, so any switcher write is a second writer that fights `/theme` and leaves the tracked
  file dirty. This repo pins `dark` there; `light-ansi` / `dark-ansi` paint from the terminal's 16 ANSI colours, so pick
  one of those to have the TUI inherit this palette. Plain `light`/`dark` are built-in hexes no palette can reach, and
  an unset theme leaves every accent faded on a light ground.
- **`tmux-gitlab.sh`** - ANSI palette names rather than hex, so its chips follow the terminal without the switcher
  writing anything for it.

## Where the choice lives

- `~/.config/theme/current` - the selected flavor id (one line); read back by `theme` to print the active flavor.
- `~/.config/theme/env.sh` - sourced by `bash/.bashrc.d/theme.bash`; exports `THEME`, `BAT_THEME` and `LEAF_THEME`.
  (fzf's colors are separate, in `fzf.sh`.)
- `~/.config/theme/agent-state.sh` - sourced by `tmux-agent-state.sh`, the shell side of the agent-state language (the
  session popup's glyph colors and its fzf palette). Absent - the case on any machine that has not switched, since
  `theme` is opt-in - those fall back to ANSI slots, so the popup follows the terminal palette like the tmux frame's own
  tracked defaults do.
- `tmux set -g @agentbar-theme <flavor>` - so the sidebar can read the flavor at launch.

## Operational notes

**Activation on a fresh pull:** `cd ~/dotfiles && stow theme bash`, open a new shell, `bat cache --build` (or run
`bootstrap.sh`), then `theme <flavor>`.

**Ghostty reload is per-platform.** Linux takes `pkill -USR2 -x ghostty`. macOS has no such handler to rely on - an
unhandled SIGUSR2 kills the terminal - so the switcher drives the same `reload_config` action through Ghostty's
scripting interface (`osascript … perform action "reload_config" on terminal 1`, declared in `Ghostty.sdef`). Both are
skipped unless Ghostty is already running, since `tell application` would otherwise launch it.

**Catppuccin Mocha Black** is Mocha with the indigo taken out of the ground - same content and accent hues,
`bg`/`surface`/`selection`/`border` as neutral greys. Mocha's `#1e1e2e` runs blue 16 points above red/green, and it is
already Catppuccin's darkest (Macchiato and Frappe are lighter _and_ bluer), so black has to be built rather than
picked. Three adapters differ from the other flavors, and all three are no-ops for them:

- **ghostty** writes `theme = Catppuccin Mocha` and then `background = <palette bg>`. Keys after `theme` override it.
  The other four flavors take their `bg` from that same ghostty theme, so the extra line changes nothing for them.
- **nvim** gets a `ground` table (`base`/`mantle`/`surface0`/`surface1`, from the palette's `bg`/`surface`/`selection`/
  `border`) that `colorscheme.lua` feeds to catppuccin's `color_overrides`. For latte and mocha every value already
  equals upstream's, so only the black variant moves.
- **hunk** ships `catppuccin-mocha` but nothing by the black name, and `--theme` on a name it lacks drops it to its own
  default. `env.sh` therefore exports `HUNK_THEME`, which both callers (the `hunk()` wrapper and the diff pane) prefer
  over the flavor id.

**Known limitation:** leaf ships no Catppuccin, so those two flavors get its closest light/dark built-in (`arctic` /
`ocean`) instead. Its Solarized Light is not upstream either: leaf ships only `solarized-dark`, so the light half is a
full palette registered as `[themes.solarized-light]` in `leaf/.config/leaf/config.toml`.

**leaf fails quietly, so keep the map total.** An unrecognised `LEAF_THEME` is not an error - leaf ignores its config's
`theme` and drops to its own default (`ocean`, a _dark_ theme), which on a light terminal looks like a bug rather than a
fallback. Every flavor in `apply_env` must therefore map to a name leaf knows. (`--theme` is the strict path by
contrast: it exits 1 with `Unknown theme "..."`.)

**Needs live verification** (not checkable headless - launch and eyeball): nvim colorscheme per flavor · hunk render for
solarized-dark / catppuccin.
