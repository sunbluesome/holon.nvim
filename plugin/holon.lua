-- =============================================================================
-- holon.nvim: Plugin initialization
-- =============================================================================
-- This file is automatically loaded by Neovim.
-- It sets up user commands for the holon.nvim plugin.
-- =============================================================================

if vim.g.loaded_holon then
  return
end
vim.g.loaded_holon = true

-- User commands
vim.api.nvim_create_user_command("Holon", function(opts)
  require("holon.zk.pickers").notes()
end, { desc = "Open Holon notes picker" })

vim.api.nvim_create_user_command("HolonNew", function(opts)
  require("holon.zk.pickers").templates()
end, { desc = "Create new Holon note" })

vim.api.nvim_create_user_command("HolonGrep", function(opts)
  require("holon.zk.pickers").grep_notes({ default_text = opts.args })
end, { nargs = "?", desc = "Grep Holon notes" })

vim.api.nvim_create_user_command("HolonBacklinks", function(opts)
  require("holon.zk.pickers").backlinks()
end, { desc = "Show backlinks to current note" })

vim.api.nvim_create_user_command("HolonLinks", function(opts)
  require("holon.zk.pickers").forward_links()
end, { desc = "Show forward links from current note" })

vim.api.nvim_create_user_command("HolonIndexes", function(opts)
  require("holon.zk.pickers").indexes()
end, { desc = "Browse index notes" })

vim.api.nvim_create_user_command("HolonJournal", function(opts)
  require("holon.zk.pickers").journal()
end, { desc = "Open journal picker" })

vim.api.nvim_create_user_command("HolonTags", function(opts)
  require("holon.zk.pickers").filter_tags()
end, { desc = "Filter notes by tags" })

vim.api.nvim_create_user_command("HolonTypes", function(opts)
  require("holon.zk.pickers").filter_type()
end, { desc = "Filter notes by type" })

vim.api.nvim_create_user_command("HolonOrphans", function(opts)
  require("holon.zk.pickers").orphans()
end, { desc = "Find orphan notes with no links" })

vim.api.nvim_create_user_command("HolonFollow", function(opts)
  require("holon.zk.actions").follow_link_under_cursor()
end, { desc = "Follow link under cursor" })

vim.api.nvim_create_user_command("HolonToday", function(opts)
  local filepath = require("holon.zk.actions").create_journal_entry()
  if filepath then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  end
end, { desc = "Open or create today's journal entry" })

vim.api.nvim_create_user_command("HolonGtd", function(opts)
  require("holon.gtd.board").open()
end, { desc = "Open GTD board" })

vim.api.nvim_create_user_command("HolonBrowse", function(opts)
  require("holon.zk.link_browser").open()
end, { desc = "Open link browser" })

-- Setup gd mapping for markdown files in notes directory
-- vim.schedule ensures this runs after other LspAttach handlers in the same event loop
local function setup_gd_mapping(bufnr)
  local config = require("holon.config")
  local notes_path = config.get("notes_path")
  if not notes_path then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if not filepath:find(notes_path, 1, true) then
    return
  end

  vim.keymap.set("n", "gd", function()
    require("holon.zk.actions").smart_gd()
  end, { buffer = bufnr, desc = "Holon: Go to definition / Follow link" })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    setup_gd_mapping(args.buf)
  end,
})

-- Re-apply after LspAttach with vim.schedule to run after all synchronous
-- LspAttach handlers (e.g., LSP plugins that set gd to vim.lsp.buf.definition)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    if vim.bo[args.buf].filetype == "markdown" then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          setup_gd_mapping(args.buf)
        end
      end)
    end
  end,
})
