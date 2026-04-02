return {
  -- Add the solarized plugin
  {
    "maxmx03/solarized.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      on_highlights = function(colors, color)
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

  -- Tell LazyVim to use it
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "solarized",
    },
  },
}
