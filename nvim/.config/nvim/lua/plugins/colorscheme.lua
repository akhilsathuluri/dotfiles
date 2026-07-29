-- VS Code Dark is the default. The `theme` switcher can override it by writing
-- ~/.config/theme/nvim.lua ({ colorscheme, background }); absent = stay on vscode.
local flavor = { colorscheme = "vscode", background = "dark" }
do
  local ok, t = pcall(dofile, vim.fn.expand("~/.config/theme/nvim.lua"))
  if ok and type(t) == "table" and t.colorscheme then
    flavor = t
  end
end
vim.o.background = flavor.background

return {
  -- VS Code Dark+ (the default).
  {
    "Mofiqul/vscode.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("vscode").setup({
        style = "dark",
        transparent = false,
        italic_comments = true,
      })
      if flavor.colorscheme == "vscode" then
        require("vscode").load()
      end
    end,
  },

  -- Solarized (one scheme for light + dark, driven by vim.o.background).
  {
    "maxmx03/solarized.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      -- Tuned highlights only make sense on the light background.
      on_highlights = function()
        if vim.o.background ~= "light" then
          return {}
        end
        ---@type table<string, vim.api.keyset.highlight>
        return {
          Visual = { bg = "#eee8d5", fg = "#002b36" },
          Search = { bg = "#93A1A1", fg = "#fdf6e3" },
          IncSearch = { bg = "#B58900", fg = "#fdf6e3" },
          CurSearch = { bg = "#B58900", fg = "#fdf6e3" },
        }
      end,
    },
  },

  -- Catppuccin (latte + mocha).
  { "catppuccin/nvim", name = "catppuccin", lazy = false, priority = 1000 },

  -- Tell LazyVim which colorscheme this flavor uses.
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = flavor.colorscheme },
  },
}
