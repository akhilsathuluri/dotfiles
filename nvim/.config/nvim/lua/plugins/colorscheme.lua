-- Catppuccin Mocha is the default, on GHOSTTY'S OWN ground (#282c34, One Dark's) rather
-- than Mocha's indigo #1e1e2e. Nothing applies a flavor on an unswitched machine, so nvim's
-- default has to match the terminal's or the editor paints a differently-coloured rectangle
-- inside it.
--
-- That ground is 1.78x brighter than the one Catppuccin was drawn for, which cost every
-- foreground ~15% of its contrast (Comment 5.81:1 -> 4.96:1) on a palette already pastel by
-- design. So the whole neutral ladder is lifted to land at or above Mocha's own ratios on
-- its own ground - Normal 11.42:1, Comment 6.80:1, LineNr 2.30:1. The accents are NOT
-- touched: they are Catppuccin's identity and all still clear 6.8:1 here.
-- The `theme` switcher overrides all of this by writing ~/.config/theme/nvim.lua
-- ({ colorscheme, background, ground }); absent = stay here.
local flavor = {
  colorscheme = "catppuccin-mocha",
  background = "dark",
  ground = {
    base = "#282c34",
    mantle = "#21252b",
    crust = "#1b1f24",
    surface0 = "#363c49",
    surface1 = "#5b6274",
    surface2 = "#6b7285",
    overlay0 = "#838aa4",
    overlay1 = "#98a0b8",
    overlay2 = "#aeb4cc",
    subtext0 = "#c0c7dd",
    subtext1 = "#d2d9ee",
    text = "#e2e8f8",
  },
}
do
  local ok, t = pcall(dofile, vim.fn.expand("~/.config/theme/nvim.lua"))
  if ok and type(t) == "table" and t.colorscheme then
    flavor = t
  end
end
vim.o.background = flavor.background

return {
  -- VS Code Dark+ (kept selectable; no longer the default).
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

  -- Catppuccin (latte + mocha), and the default. `flavor.ground` recolours the four
  -- surface tones: from the palette when a flavor is applied (latte/mocha already equal
  -- upstream's, so only catppuccin-mocha-black moves), else from ghostty's default above.
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      color_overrides = flavor.ground and { all = flavor.ground } or {},
    },
  },

  -- Tell LazyVim which colorscheme this flavor uses.
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = flavor.colorscheme },
  },
}
