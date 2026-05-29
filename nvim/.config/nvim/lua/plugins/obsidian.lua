-- Obsidian-style markdown notes: a ~/notes vault with [[wiki-links]],
-- backlinks, tags, daily notes and templates. Inline image rendering is
-- handled by snacks.image (see snacks.lua); clipboard paste by img-clip.
return {
  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
    ft = "markdown",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      -- Use the new `:Obsidian <subcommand>` form (keymaps below already do).
      legacy_commands = false,
      workspaces = {
        { name = "notes", path = "~/notes" },
      },
      notes_subdir = "notes",
      new_notes_location = "notes_subdir",
      daily_notes = {
        folder = "dailies",
        date_format = "%Y-%m-%d",
        template = nil,
      },
      templates = {
        folder = "templates",
      },
      attachments = {
        folder = "assets",
      },
      -- LazyVim's completion engine is blink.cmp.
      completion = {
        blink = true,
        min_chars = 2,
      },
    },
    keys = {
      { "<leader>o", "", desc = "+obsidian/notes", ft = "markdown" },
      { "<leader>on", "<cmd>Obsidian new<cr>", desc = "New note" },
      { "<leader>oo", "<cmd>Obsidian quick_switch<cr>", desc = "Quick switch note" },
      { "<leader>os", "<cmd>Obsidian search<cr>", desc = "Search notes (grep)" },
      { "<leader>ot", "<cmd>Obsidian today<cr>", desc = "Today's daily note" },
      { "<leader>oy", "<cmd>Obsidian yesterday<cr>", desc = "Yesterday's daily note" },
      { "<leader>od", "<cmd>Obsidian dailies<cr>", desc = "List daily notes" },
      { "<leader>ob", "<cmd>Obsidian backlinks<cr>", desc = "Backlinks", ft = "markdown" },
      { "<leader>ol", "<cmd>Obsidian links<cr>", desc = "Links in note", ft = "markdown" },
      { "<leader>oT", "<cmd>Obsidian tags<cr>", desc = "Search tags", ft = "markdown" },
      { "<leader>or", "<cmd>Obsidian rename<cr>", desc = "Rename note & update links", ft = "markdown" },
      { "<leader>oc", "<cmd>Obsidian toggle_checkbox<cr>", desc = "Toggle checkbox", ft = "markdown" },
      { "<leader>og", "<cmd>Obsidian follow_link<cr>", desc = "Follow link under cursor", ft = "markdown" },
    },
  },

  -- Paste images from the clipboard straight into a note (Wayland-aware via
  -- wl-paste). Saves the file under `assets/` next to the note and inserts the
  -- markdown link at the cursor.
  {
    "HakonHarnes/img-clip.nvim",
    event = "VeryLazy",
    opts = {
      default = {
        dir_path = "assets",
        relative_to_current_file = true,
        use_absolute_path = false,
        file_name = "%Y-%m-%d-%H-%M-%S",
        prompt_for_file_name = false,
      },
      filetypes = {
        markdown = {
          url_encode_path = true,
          template = "![$CURSOR]($FILE_PATH)",
        },
      },
    },
    keys = {
      { "<leader>op", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard", ft = "markdown" },
    },
  },
}
