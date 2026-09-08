# shot

Take a screenshot on the machine with the screen; read it with the agent at the other end of an ssh session.

```sh
shot                  # the clipboard image, else the newest screenshot
shot FILE             # that file
shot --clip           # the clipboard image only, never the folder
shot --send           # ... and press Enter once the path is in the pane
shot --watch          # stay up; send every screenshot as it lands
shot --check          # what it would send, and where
```

## Why it exists

A terminal carries no image inbound. OSC 52 is text and outbound only, so a screenshot on your laptop cannot be pasted
into a Claude running on another host - the paste arrives as nothing, or as a filename that host does not have.

So the file is shipped over ssh and only its **path** is typed into the pane. Claude reads a path.

## Where it runs

**On the machine with the screen, never the far end** - the same rule as dictate's microphone. A `shot` on the remote
has no clipboard to read, exactly as its `dictate` has no mic.

## Route

One host, resolved once, used for both halves: the file must land on the machine whose pane gets the path, or the agent
is handed a path to a file that is not there. The typing is pinned to it (`DICTATE_REMOTE`), so a change of focus
between the two halves cannot strand them.

Resolved in order:

1. `SHOT_REMOTE` - an ssh destination. Set it to the empty string to force local-only.
2. `dictate --route` - whichever tmux holds focus, if dictate is set up.
3. The first host in `~/.config/dictate/remote`. **On macOS this is usually the one that answers**: dictate discovers
   open ssh sessions by reading `/proc`, which macOS has not, so that file is its whole candidate list there.

`shot --check` prints which one answered, whether ssh reaches it, and what a bare `shot` would pick up.

## Config

| Variable          | Default                       | What                                                              |
| ----------------- | ----------------------------- | ----------------------------------------------------------------- |
| `SHOT_REMOTE`     | (unset)                       | ssh destination of the machine the agent runs on                  |
| `SHOT_DIR`        | `$HOME/.cache/dotfiles/shots` | where the image lands **there** - carried as text, expanded there |
| `SHOT_KEEP_DAYS`  | `7`                           | images older than this are pruned on the next send                |
| `SHOT_SOURCE_DIR` | the OS screenshot folder      | the folder scanned and watched                                    |

The folder is read from `com.apple.screencapture location` on macOS (`~/Desktop` when unset) and is
`~/Pictures/Screenshots` on Linux. Never by filename - macOS localises it.

## Binding a key

There is no tmux key and no status chip, and that is deliberate: both would run on the machine hosting tmux, which is
the machine with no clipboard. The trigger has to be local.

- **macOS**: Shortcuts.app → run shell script → `shot`. It starts from a bare `PATH`, so give the full path
  (`~/.local/bin/shot`) and put brew's prefix on `PATH` inside the shortcut, as dictate's shortcut does.
- **Anywhere**: `shot --watch` in a spare terminal. Then Cmd+Shift+4 (or PrintScreen) is the whole gesture - the path
  appears in the pane on its own.

## Tracing

One line per send: `src=shot evt=send host=… why=… bytes=… path=… rc=… ms=…`. `dotfiles-trace show --src shot`.

- **Nothing arrived.** No line at all means `shot` never ran (the hotkey, not this). `rc` non-zero with no `path=` is
  the transport - run `shot --check`.
- **The path is typed but Claude cannot read it.** `host=` says where the file went; if that is not the machine Claude
  runs on, the route is wrong, and `SHOT_REMOTE` is the fix.
