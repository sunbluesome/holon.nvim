-- =============================================================================
-- telescope-loam: Plugin initialization
-- =============================================================================
-- This file is automatically loaded by Neovim.
-- It sets up user commands for the telescope-loam plugin.
-- =============================================================================

if vim.g.loaded_loam then
  return
end
vim.g.loaded_loam = true

-- User commands
vim.api.nvim_create_user_command("Loam", function(opts)
  require("loam.pickers").notes()
end, { desc = "Open Loam notes picker" })

vim.api.nvim_create_user_command("LoamNew", function(opts)
  require("loam.pickers").templates()
end, { desc = "Create new Loam note" })

vim.api.nvim_create_user_command("LoamGrep", function(opts)
  require("loam.pickers").grep_notes({ default_text = opts.args })
end, { nargs = "?", desc = "Grep Loam notes" })

vim.api.nvim_create_user_command("LoamBacklinks", function(opts)
  require("loam.pickers").backlinks()
end, { desc = "Show backlinks to current note" })

vim.api.nvim_create_user_command("LoamIndexes", function(opts)
  require("loam.pickers").indexes()
end, { desc = "Browse index notes" })

vim.api.nvim_create_user_command("LoamJournal", function(opts)
  require("loam.pickers").journal()
end, { desc = "Open journal picker" })

vim.api.nvim_create_user_command("LoamTags", function(opts)
  require("loam.pickers").filter_tags()
end, { desc = "Filter notes by tags" })

vim.api.nvim_create_user_command("LoamTypes", function(opts)
  require("loam.pickers").filter_type()
end, { desc = "Filter notes by type" })

vim.api.nvim_create_user_command("LoamFollow", function(opts)
  require("loam.actions").follow_link_under_cursor()
end, { desc = "Follow link under cursor" })

vim.api.nvim_create_user_command("LoamToday", function(opts)
  local filepath = require("loam.actions").create_journal_entry()
  if filepath then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  end
end, { desc = "Open or create today's journal entry" })

-- Setup gd mapping for markdown files in notes directory
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    -- Check if file is in notes directory
    local config = require("loam.config")
    local notes_path = config.get("notes_path")
    if not notes_path then
      return
    end

    local filepath = vim.fn.expand("%:p")
    if not filepath:find(notes_path, 1, true) then
      return
    end

    -- Map gd to smart_gd (follow link or fallback to LSP/normal gd)
    vim.keymap.set("n", "gd", function()
      require("loam.actions").smart_gd()
    end, { buffer = args.buf, desc = "Loam: Go to definition / Follow link" })
  end,
})
