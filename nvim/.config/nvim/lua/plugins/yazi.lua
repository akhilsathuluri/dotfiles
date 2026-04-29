return {
  "mikavilpas/yazi.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>-", "<cmd>Yazi<cr>", desc = "Open yazi at current file" },
    { "<leader>cw", "<cmd>Yazi cwd<cr>", desc = "Open yazi in working directory" },
  },
  opts = {
    open_for_directories = true,
    hooks = {
      yazi_closed_successfully = function()
        vim.schedule(function()
          vim.cmd("redraw!")
        end)
      end,
    },
  },
}
