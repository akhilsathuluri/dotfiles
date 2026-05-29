return {
  "folke/snacks.nvim",
  -- Render images inline in markdown via Ghostty's Kitty graphics protocol
  -- (works through tmux thanks to `allow-passthrough on`). Uses ImageMagick's
  -- `convert`/`identify` under the hood.
  opts = {
    image = {
      enabled = true,
      doc = {
        inline = true,
        float = true,
      },
    },
  },
  keys = {
    {
      "<leader>/",
      function()
        if not Snacks.picker.resume({ source = "grep" }) then
          Snacks.picker.grep()
        end
      end,
      desc = "Grep (resume last)",
    },
  },
}
