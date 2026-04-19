return {
  "folke/snacks.nvim",
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
