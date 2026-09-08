# CLAUDE.md

Toggle-key local speech-to-text into tmux. See `README.md` for usage and config; this file is for hacking on the script.
Keep it a single file - do not split it into a package.

## Backends (`DICTATE_BACKEND`)

Two, named for the hardware and resolved from what is installed rather than from the environment: **`gpu`** runs
`small.en` through whisper.cpp against Vulkan on whatever GPU is present, else **`faster-whisper`** runs `small.en` int8
on the CPU, in-process. `bootstrap.sh` installs the GPU build when a GPU is visible; a machine without one is a skip,
never a bootstrap failure. Measured on a Radeon 860M over five dictated clips (102s of audio): GPU `small.en` **3.6s**
total, CPU `small.en` **9.7s**, GPU `large-v3-turbo` **10.7s**. Install or rebuild it alone with
`./install.sh whisper-vulkan`; `DICTATE_BACKEND=cpu` forces the CPU back, and the old `whispercpp`/`faster-whisper`
values still resolve.

- **The backend is detected, not configured, on purpose.** The GNOME shortcut and the tmux status chip both launch
  `dictate` without sourcing `~/.bashrc.d`, so an env var set there reaches only a fresh interactive shell - the path
  used least. The binary and model existing is the signal; do not replace this with an env var.
- **The GPU is an optimisation, never a dependency, and nothing here is AMD-specific.** File existence only says what to
  _try_: `load_model()` falls back to faster-whisper when whisper.cpp will not start, and every caller dispatches on the
  handle (`is_whispercpp()`) rather than on `BACKEND`, so the fallback routes itself. Keep it that way - a machine with
  no GPU, a broken driver or a VM without passthrough must still dictate.
- **Strip whisper.cpp's non-speech tokens.** It narrates silence as `[BLANK_AUDIO]`, `[END]`, `[SOUND]`; faster-whisper
  returns `""`, and a stray toggle must not type a token into the pane. The rule is shape (square-bracketed all-caps),
  not a name list, because the set is open-ended - but parentheses are dictated, so only known words go there.
- **`large-v3-turbo` lost on both axes** - slower than the CPU backend on real-length clips, and no better on the
  technical vocabulary. Do not assume the bigger model wins here; re-measure before switching to one.
- **The prompt moves accuracy more than the model does, in both directions.** Terms in `DICTATE_PROMPT` come out right;
  terms absent from it come out as "work tree", ".files", "source reuse port". But each entry is also a word that can be
  hallucinated into unclear audio: adding `origin/main` turned "diff pane" into "diff_main". **Add a term only after
  hearing it fail, then re-run the clips and check nothing common broke** - a vocabulary dump trades frequent words for
  rare ones. Prompting a term is not a guarantee either: `agentbar` never displaced "agent sidebar".
- **The prompt's word order is load-bearing, and is not alphabetical.** Sorting the same terms turned "task check" into
  "taskcheck" and appended a stray "merge request"; proven-failing terms first and the loosest term last measured clean.
  Do not tidy it into alphabetical order without re-running the clips.

- **Keep faster-whisper as the CPU path.** whisper.cpp's own CPU build measured _slower_ than faster-whisper here
  (3143ms vs 2455ms on the same clip) - CTranslate2's int8 kernels win on CPU. The GPU is the only reason to switch.
- whisper.cpp has no usable in-process binding, so `whispercpp` holds a **`whisper-server` child** and posts each clip
  to it over loopback. Per-call `whisper-cli` was 410ms slower - process start plus Vulkan context setup, every time.
  The child must die with `serve()` (it holds the GPU and the port), which is what `_bye()` handles.
- The multipart POST is built by hand from stdlib: the script keeps its two PEP 723 deps and adds no HTTP library.

## Packaging (why it is a stow package, not an app)

- One self-contained Python script run via `#!/usr/bin/env -S uv run --script`; deps are declared inline (PEP 723:
  `faster-whisper`, `numpy`). There is nothing to build, so it is **not** an `apps/` build target. The `whispercpp`
  backend's binary is a downloaded tool, so it is pinned and built in `install.sh` like every other one - not here.
- It is a **stow package** -> `~/.local/bin/dictate` (a symlink). It must stay on PATH under the short name `dictate`,
  because the GNOME shortcut, `tmux/.tmux.conf` (`$HOME/.local/bin/dictate`), and the script's own self-re-exec
  (`shutil.which("dictate")`, used to spawn `--serve`/`--watch`) all resolve it by that name. Stow is what provides it;
  moving to `apps/` (run-in-place) would only reintroduce a symlink.

## Platform split (linux + macOS)

- Exactly three things differ, all guarded by `IS_MAC`: **capture** (`parec` vs `ffmpeg -f avfoundation`, both writing
  the same raw s16le mono PCM, so the watcher, the model and the tmux send never learn which ran), **pid identity**
  (`/proc/<pid>/comm|cmdline` vs `ps -o comm=|command=`, behind `proc_name()` / `proc_cmdline()`), and
  **`--install-shortcut`** (GNOME `gsettings` only - macOS has no user-level global-hotkey API that skips the
  Accessibility prompt, so it exits with the Shortcuts.app recipe for binding `dictate --toggle --send` yourself).
- `CAPTURE_BIN` is the name both the liveness checks and `require()` compare against - add a backend and it is the only
  string to teach them.
- Audio **ducking is Linux-only in practice**: `_pactl()` swallows the `OSError` when `pactl` is absent, so macOS simply
  records without muting. Not a guard - a graceful degrade that predates the port.
- macOS device selection: `DICTATE_SOURCE` takes an avfoundation index or name from
  `ffmpeg -f avfoundation -list_devices true -i ""`. Default is `default` (the system input), **not** index 0 - the
  indices renumber across reboots and headsets, and 0 is often a virtual device.
- The first macOS recording raises the mic prompt for the **terminal**, not for dictate. Denied or undecided, capture
  yields silence with no error - the failure looks like a bad mic, not a permission.

## Process model

- The **toggle client** never imports faster-whisper. It ships raw PCM to a model server and reads text back.
- **`--serve`**: a lazy model server, spawned on first dictation, holding the model resident on a Unix socket in
  `$XDG_RUNTIME_DIR`. Self-exits after `DICTATE_IDLE`s. Binding the socket only after the model loads doubles as the
  readiness signal (connect == ready).
- **`--watch PID`**: a silence-watcher subprocess that auto-stops recording after trailing silence / the cap.
- If the server is unreachable the client falls back to loading the model **in-process**, so dictation always works.

## Remote tmux (`~/.config/dictate/remote`)

Every tmux call funnels through `tmux()`, so a remote is an `ssh` wrap there and nothing else moves: the mic, the model
and the GPU stay local and only the transcript crosses.

- **`--route` prints the resolved host and delivers nothing.** `shot` ships a file to the machine whose pane will be
  typed, so it has to resolve the same route this does - and resolving it twice is how the file and its path end up on
  different machines. Exposing the resolver is not a second delivery path; keep it read-only, and keep `--type` the only
  way text reaches a pane.
- **One routing point: `tmux()`.** Never grow a second delivery path - a remote-only send would drift from the local
  one, and the `@dictate` chips would stop reporting. A machine with no tmux binary at all (a laptop that only ever
  dictates into remotes) is a failed local probe there, never a crash.
- **The mic never moves.** dictate runs where the microphone is; only tmux is remote. Audio forwarding was the
  alternative and lost: it needs a sound server on the far end, adds latency, and dies with the tunnel.
- **Multiplexing is not optional, and `BatchMode=yes` is its other half.** One dictation makes ~10 tmux calls, each
  otherwise paying a TCP + auth handshake, and a passphrase prompt nobody can see would hang a keypress.
- **`DICTATE_TMUX_SSH` is an accepted alias for `DICTATE_REMOTE`**, so a hotkey binding written against the old pin
  keeps working. One env read, not a second code path.
- **Discovery reads `/proc`, which macOS has not** - there `~/.config/dictate/remote` is the whole candidate list.
- **The macOS hotkey is Shortcuts.app, and it starts from a bare `PATH`.** `install_shortcut`'s message carries the brew
  prefixes for that reason: without them the shebang finds no `uv` and `require()` no `ffmpeg`, and the key reads as
  dead. The mic grant lands on Shortcuts, the process that launched the capture, as it lands on the terminal for a chip.
- **The remote tmux path is absolute on purpose.** A non-interactive ssh resolves `/usr/bin/tmux`, which cannot speak to
  a server built from source - the client dies with `server exited unexpectedly` and names no version. `REMOTE_TMUX`
  prefers `~/.local/bin/tmux` and falls back for a stock box; `--check` prints each host's client version beside whether
  that server answered, which is the whole diagnosis.
- **Its own ControlPath namespace** (`cm-dictate-…`), because sharing the interactive one would hand an `ssh -X` alias a
  master with no X forwarding.
- **The host is stamped at record-start, not resolved at send.** The chip that lit has to be the chip that clears, so a
  tab change mid-clip cannot strand one red. The pane within that host is still resolved at send time, as before.
- **Routing is the terminal's own focus report, not a guess.** `#{client_flags}` carries `focused` because
  `focus-events` is on; last-typed-in is the fallback for when no terminal is in front, and it assumes the clocks agree.
  The same flag picks the session when two terminals are attached to one host.
- **Hosts are discovered, not configured** - the same rule as the backend. An ssh process with a controlling terminal is
  a session you type in; that test is what excludes git's ssh, a mux master and our own probes, and `-N`/`-W` excludes
  tunnels. The file remains for what discovery cannot see, and its lines are ssh argument lists, not bare destinations.
- **Local is probed first, synchronously, and wins alone.** Focus is exclusive, so a focused local client is the answer
  and no ssh is opened at all - dictating into this machine must not touch the network.
- **The remote probes are daemon threads read through a queue, and the first `focused` wins.** Waiting for every host
  would charge a down one its full timeout on every dictation (measured: 106 ms to 2.17 s from one dead entry). Only the
  no-focus fallback waits, bounded by `PROBE_WAIT`.
- **`shlex.quote` on every argument**, so a transcript reaches the remote tmux as one argv element and never the remote
  shell.
- **A remote's own status-bar chips cannot work** - they run that machine's `dictate`, which has no mic - so
  `mic_here()` makes that click say so (`outcome=no-mic`) instead of recording a dead stream. `pactl info` failing is a
  headless box, never a quiet room; `pactl` absent is unknown, and the recording is left to try. Driving the mic from
  that chip would take a trigger socket reverse-forwarded over the ssh session and a listener at the mic end; a hotkey
  on the machine with the mic does the same with none of it, and is the answer.

## tmux coupling (change both sides together)

- The script sets `@dictate` to `"rec"` (red) / `"work"` (amber) / unset (idle grey). `tmux/.tmux.conf` renders that via
  `@dictate_seg`, and its status bar defines the mouse ranges `dictate` -> `dictate --toggle`, `dictsend` ->
  `dictate --toggle --send` (records, types, then presses Enter), and `push` -> `dictate --type 'commit and push'`
  (types the phrase + Enter). Renaming a state string or a range means editing `tmux.conf` too. The `@*_seg` chips are
  also regenerated per-flavor by `theme/.local/bin/theme` (`apply_tmux`), so relabel/recolor a chip in both. Chip colors
  also appear in `design/*.md`. Every chip also has a key, bound in `tmux.conf` beside the ranges: `prefix + m`
  (dictate), `prefix + M` (dictate+send), `prefix + p` (push), `prefix + D` (the diff menu), `Alt+n` (the workdesk
  float) - same commands, so change them together. `prefix + Enter` (send) is the one key with no chip, since the
  toolbar retired `⏎ send`.
- **`--send` / `--type` are tmux-only paths.** They touch no audio, so they work anywhere dictate runs, and they are
  what `prefix + Enter` and the ⇡ commit+push chip call. Before the macOS port those two paths were dead on macOS purely
  because the package was not stowed there - which is why the port stows dictate on both platforms rather than
  reimplementing the send half somewhere cross-platform.

## Footer chips

- Five ranges, in this order: `workdesk` · `dictate` · `dictsend` · `push` · `diff`. **One space of padding inside every
  chip and one between them** - every gap is the same three columns. The old row mixed one- and two-space padding and
  read as ragged; keep it uniform when editing a label.
- **Labels name the effect, not the key.** `⇡ commit+push` rather than "push", `◧ changes` rather than "diff", because a
  status bar has no tooltips and a first-time reader gets one chance. Glyphs alone were rejected: a bare glyph is a 2-3
  column click target, too small to hit.
- `dictate+send` is one press-pair, not a second recorder: the first press drops `SEND_FILE` beside the PCM buffer and
  the second reads it _before_ `cleanup()` removes it, then presses Enter once the transcript is in the pane. Only the
  chip you clicked lights up - both read `@dictate`, but each colours itself only when `@dictate_src` names it.
- **One chip rests lit, and it is `dictate+send`**; `dictate` and `≡ workdesk` rest plain. It is the one used most, and
  plain reads as unavailable. Never a warm hue: the chip's own states are red (recording) and amber (transcribing), so
  orange blurs idle into busy. To recolor, move the highlight - do not add a second.
- **Hover is impossible** - tmux 3.7b rejects `MouseMoveStatus`; only Down/Up/Drag/Wheel exist for the status line.

## Key binding

- **Two shortcuts, one action (`--toggle --send`): the Copilot key and Pause.** `--install-shortcut` resets every
  `dictate*` keybinding it does not install, so the dconf list matches its arguments exactly - which is also why adding
  a key means adding it to `DEFAULT_BINDINGS`, never installing it by hand.
- **Pause is bound bare, and is not the media key.** GNOME claims no shortcut on the `Pause` keysym, while
  `play-static`/`pause-static` hold `XF86AudioPlay`/`XF86AudioPause` with static grabs a custom binding cannot outrank.
  A keyboard whose key emits the media keysym therefore needs that key, not this one - `--check` prints every bound key
  so this is diagnosable without dconf spelunking.
- **The string is `<Shift><Super>XF86TouchpadOff`, not `F23`.** The key emits `LeftMeta`+`LeftShift`+`F23`, and
  `KEY_F23`'s keycode carries the `XF86TouchpadOff` keysym, so `F23` does not match. GNOME's static touchpad-off grab is
  on the bare keysym, which the held modifiers do not match either - the touchpad is unaffected.
- **The numpad's Backspace and `=` cannot be bound.** They emit the main-row scancodes (`0xe`, `0xd`), so no layer -
  hwdb, keyd, xkb, GNOME - can distinguish them.

## Tracing

- `log()` prints to stderr, which is **discarded** in every real launch context (tmux `run-shell -b`, the GNOME
  shortcut, `--serve`/`--watch` DEVNULL). The `trace(evt, **kv)` helper is the only durable record: it fires edges
  (`toggle`, `rec`, `transcribe`, `send`, `result` with outcome/chars/ms) into the shared dotfiles trace log
  (`dotfiles-trace`). Call it at action edges only - **never** in `watch()` (150ms poll) or the `--serve` loop. View
  with `dotfiles-trace show --src dictate`; see the repo-root CLAUDE.md "Debugging" section.

## Config, deploy, smoke test

- All config is `DICTATE_*` env vars, read at **process start**. The server captures its config at spawn, and a running
  server holds the **old code** - so after editing config _or_ the script, run `dictate --serve-stop` so the next
  dictation starts a fresh server. The stowed symlink itself is live the moment the file is saved.
- Audio ducking mutes the default sink via `pactl` while recording; `DUCK_FILE` persists the prior mute state so a crash
  cannot strand it muted.
- Smoke test: `dictate --check` (parec + tmux, server state, model cache, bound key), `dictate --test` (record 5s, print
  transcript). `bootstrap.sh` installs the deps; `./install.sh dictate-deps` does them alone.
