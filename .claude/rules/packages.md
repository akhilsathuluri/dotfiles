---
paths:
  - "bash/**"
  - "claude/**"
  - "claude-indicator/**"
  - "clip/**"
  - "dictate/**"
  - "hunk/**"
  - "leaf/**"
  - "nvim/**"
  - "screenshot-watcher/**"
  - "shot/**"
  - "tex/**"
  - "theme/**"
---

# Per-package pitfalls

- **`bash/`** - `~/.bashrc.d/` (shell customizations). `ssh.bash` wraps `ssh` with `RequestTTY yes`, so a remote command
  gets a pty and `ssh host tmux` stops failing with `open terminal failed: not a terminal` - ssh requests one only for a
  bare login session. **A shell function, not `~/.ssh/config`**: `RequestTTY yes` under `Host *` reaches git, rsync and
  cron too, which hand ssh a pipe on stdin, and ssh then logs
  `Pseudo-terminal will not be allocated because stdin is not a terminal.` on every fetch - measured, and cosmetic only,
  since ssh still declines the pty. A function is scoped to interactive shells, so nothing scripted sees it, and
  `~/.ssh/config` stays untracked (it holds hosts). Opt out per call with `-T`; the wrapper's `-o` is parsed before the
  config files, so it wins over a per-host `RequestTTY no`. A script that wants a pty passes `-tt` itself, and
  `Match exec` cannot condition on this - ssh runs it with stdin detached, so it never sees the terminal.
- **`claude/`** - the status line names the session's place, and the `⚠` names the other place: the worktree Claude last
  wrote in, shown only while its root differs. Roots are compared, never paths, so a subdirectory is not a move.
  **Nothing in the row depends on tmux** - the payload never says which file was written, so `statusline-workdir.sh`
  (this package's `PostToolUse` hook) records the edited file's repo root in
  `$XDG_STATE_HOME/dotfiles/claude-workdir/<session id>` and the row reads that. `refreshInterval` is 1s: no event fires
  when a hook writes that file, and the dictation chip has to light while you are still talking. That cadence is only
  affordable because the script forks nothing - helpers write a named global instead of printing into a `$( )` subshell,
  and jq reading the payload is the one process a run starts (5ms; a subshell per segment cost 14ms). Anything needing a
  command sits behind a TTL and refreshes detached. `test/statusline.sh` is the guard, tmux off PATH. The second row's
  rate limits ride the same stdin payload, so they cost no process and no network; each window is absent before the
  session's first API response and after its own reset, and an absent window shows nothing. The dictation chip reads the
  herdr plugin's state file (`$XDG_STATE_HOME/herdr/plugins/abhishekrana.dictate/recording.json`) and never writes it,
  so polling cannot disturb a recording; a pid with no process is a recorder that died, not a recording. Its label never
  changes, only its colour - grey idle, red recording, amber transcribing, the tmux footer chip's rule - because the
  meters sit beside it and must not shift as you speak.
- **`claude/` has three writers**: this repo, `herdr integration install claude`, and Claude's own `/theme`. Its TUI
  theme is therefore **deliberately not switched by `theme`**. Prefer `light-ansi`/`dark-ansi`, which paint from the
  terminal's own 16 colours and so follow this palette; this repo pins `dark`, so the tracked value only moves when
  someone runs `/theme`. Claude Code does not load a user-level `settings.local.json`, so anything that must take effect
  goes in `settings.json`.
- **`claude/` also stows `hooks/` and `skills/`** in this fork, so `settings.json` wires two agent-state consumers on
  every lifecycle event: the agentbar hook, and the local scripts that write `/tmp/claude-sessions/` for the GNOME
  `claude-indicator`.
- **`claude-indicator/`** - `~/.local/bin/claude-indicator`, `~/.config/autostart/` (Linux only - GNOME top-bar
  indicator, fed by the `claude/.claude/hooks/` state files)
- **`clip/`** - every copy path (tmux `copy-command`, `tmux-yank.sh`, fzf's Ctrl-Y, nvim) goes through it, so the
  backend is chosen in one place.
- **`dictate/`** - `~/.local/bin/dictate` (toggle-key local Whisper dictation into tmux; opt-in). Has its own nested
  `CLAUDE.md` - read it before touching the script. Deps are opt-in too: `./bootstrap.sh dictate-deps`. Cross platform:
  capture is `parec` on Linux and `ffmpeg -f avfoundation` on macOS, which also needs a one-time microphone grant for
  the terminal. The `--install-shortcut` GNOME binding is Linux-only; on macOS use `prefix + m`. Two transcription
  backends, named for the hardware and picked by what is installed rather than an env var: `gpu` (whisper.cpp via
  Vulkan, on an AMD or Intel iGPU or NVIDIA) once `./install.sh whisper-vulkan` has run, else `cpu` (faster-whisper).
  Same `small.en`, measured 2.7× faster on the GPU. Vulkan is Linux-only, so macOS is always `cpu`. Dictating into a
  tmux on another machine needs no setup - the ssh sessions open now are the candidates, it routes to whichever tmux
  holds focus, and only the transcript crosses, never the audio. `DICTATE_REMOTE` (older name: `DICTATE_TMUX_SSH`) pins
  one host. dictate runs where the mic is, never on the remote (no mic there to reach).
- **`hunk/`** - `~/.config/hunk/` (hunk diff viewer config, Ayu Dark default; the `hunk()` wrapper in
  `bash/.bashrc.d/theme.bash` passes the active flavor to `hunk diff`). `mode = "stack"` is what every hunk here starts
  from - full width per line, no half-width columns. **Workdesk's `D` overrides it to `split` at the call**, because a
  merge request's diff is the one that gets a window of its own and so the one with room for two columns; the diff pane
  beside your work does not. The pane's `L` still flips its own window, and hunk reads the file at startup, so an open
  pane keeps its layout until respawned.
- **`leaf/`** - **leaf writes this file itself**; a first run with no config seeds upstream's sample there, which blocks
  `stow leaf`, so the backup step in `bootstrap.sh` is load-bearing. It carries a Solarized Light palette because leaf
  ships only the dark one.
- **`nvim/`** - `~/.config/nvim/` (LazyVim config). **Over ssh the clipboard is write-only OSC 52.** The terminal is the
  only route to the local clipboard there, and `unnamedplus` makes `v:register` `+`, so anything reading a register -
  blink.cmp resolving a snippet's `$TM_SELECTED_TEXT`, once per completion, and 54 of the LaTeX snippets carry it -
  fires an OSC 52 read, which the terminal asks about before answering (Ghostty's `clipboard-read = ask`): a dialogue
  per keystroke. So `config/options.lua` pins `g:clipboard` to a provider that writes and never reads. Yank still
  reaches the local clipboard, `p` returns nvim's own last yank, and the terminal's own paste (Cmd/Ctrl+V) is what
  brings the system clipboard in.
- **`screenshot-watcher/`** - `~/.local/bin/screenshot-watcher`, `~/.config/autostart/` (Linux only - auto-copy
  screenshots to the clipboard)
- **`shot/`** - `~/.local/bin/shot` (send a local screenshot to the machine your agent is on, and type its path into the
  pane; has its own `README.md`). **A terminal carries no image inbound** - OSC 52 is text and outbound only - so the
  file goes over ssh and only its _path_ is typed. **It runs where the screen is, never the far end**, the same rule as
  dictate's mic: a `shot` on the remote has no clipboard to read. **One host, resolved once, for both halves** - the
  file must land on the machine whose pane gets the path, so the route (`SHOT_REMOTE` → `dictate --route` → dictate's
  candidate file) is settled here and pinned for the typing via `DICTATE_REMOTE`. `dictate --route` is read-only: it
  resolves a route and never delivers on one, so dictate keeps its single delivery path. **No tmux key and no chip**,
  deliberately - both would run on the machine hosting tmux, which is the one with no clipboard; the trigger has to be
  local (Shortcuts.app, or `shot --watch`). Bash 3.2 clean, since macOS ships that and brew's bash is not installed.
- **`tex/`** - `~/.local/bin/` (`tex-dev`, `texpeek`, `texpage` - LaTeX build/preview helpers)
- **`theme/`** - `~/.local/bin/theme` (theme switcher; re-skins the terminal stack across the five flavors from
  `design/palette.toml`, writing per-tool files into `~/.config/theme/`. **Opt-in per machine** - nothing applies a
  flavor for you, so an unswitched machine keeps the defaults in the tracked configs: ghostty's own dark `#282c34`,
  tmux's green status bar, and nvim's Catppuccin Mocha re-grounded to that same `#282c34` (an unswitched nvim must match
  the terminal, since it paints its own ground); `theme ghostty-default` clears the state and returns there - it is the
  baseline, so it is also the first row of the `⛭` dialogue's Theme setting, which is what makes trying a flavor on
  reversible (`none`/`off` are older names for it). `catppuccin-mocha-black` is Mocha's content and accent hues over a
  neutral (R=G=B) ground, so it needs four adapters the others do not, all no-ops for them - ghostty takes
  `theme = Catppuccin Mocha` then a `background =` override, nvim takes the palette's four surface roles through
  catppuccin's `color_overrides`, `HUNK_THEME` in `env.sh` maps it back to `catppuccin-mocha` because hunk ships no
  theme by that name, and folio's `embedded()` maps it to bat's Catppuccin Mocha for the same reason. **A flavor this
  repo adds carries every role**: folio refuses a palette where one lacks `float`, which is what a fifth flavor missed.
  `[meta] default` feeds only the sidebar's compiled fallback; change it in `palette.toml` alone, then
  `make -C apps/agentbar gen`)
