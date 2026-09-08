-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Migrated from VS Code settings
vim.o.colorcolumn = "120"          -- ruler at column 120
vim.o.tabstop = 4                  -- tab display width
vim.o.shiftwidth = 4               -- indent width
vim.o.softtabstop = 4              -- tab key width
vim.opt.clipboard = "unnamedplus"  -- yank to system clipboard
vim.o.relativenumber = false       -- absolute line numbers
vim.o.wrap = true                  -- wrap long lines
vim.o.linebreak = true             -- wrap at word boundaries, not mid-word

-- With no local clipboard to reach - an ssh session, or a machine with no display - the terminal is the only route and
-- nvim falls back to OSC 52. Writes over it are silent, but every *read* makes the terminal ask (Ghostty's
-- `clipboard-read = ask`), and `unnamedplus` makes `v:register` `+`: blink.cmp resolving a snippet's
-- `$TM_SELECTED_TEXT` then reads the clipboard once per completion - a dialogue per keystroke, and 54 of the LaTeX
-- snippets carry that variable. So the provider is pinned write-only: `p` returns nvim's own last yank, and the
-- terminal's own paste (Cmd/Ctrl+V) still brings the system clipboard in.
local no_local_clipboard = vim.fn.has("mac") == 0 and not vim.env.DISPLAY and not vim.env.WAYLAND_DISPLAY
if vim.env.SSH_CONNECTION or vim.env.SSH_TTY or no_local_clipboard then
  local osc52 = require("vim.ui.clipboard.osc52")
  local last = { "" }
  local function writer(reg)
    local send = osc52.copy(reg)
    return function(lines)
      last = lines
      send(lines)
    end
  end
  local function reader()
    return last
  end
  vim.g.clipboard = {
    name = "osc52-write-only",
    copy = { ["+"] = writer("+"), ["*"] = writer("*") },
    paste = { ["+"] = reader, ["*"] = reader },
  }
end


-- Mirror yank to the primary selection (for Shift+Insert). `clip` picks the backend
-- and is a no-op for --primary on macOS, which has no primary selection.
if vim.fn.executable("clip") == 1 then
  vim.api.nvim_create_autocmd("TextYankPost", {
    callback = function()
      vim.fn.system("clip --primary", vim.fn.getreg('"'))
    end,
  })
end
