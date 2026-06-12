return {
  "folke/snacks.nvim",
  -- Image rendering is handled by image.nvim (see image.lua), which works
  -- inline through tmux. snacks.image is disabled to avoid two renderers.
  opts = {
    image = { enabled = false },
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
