-- Example holon.nvim setup pointing to the examples/ vault
--
-- Usage (from normal Neovim with holon.nvim already installed):
--   :luafile examples/init.lua
--
-- This overrides notes_path to use the bundled example vault,
-- so you can try :Holon, :HolonGtd, :HolonIndexes, etc.

local examples_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

require("holon").setup({
  notes_path = examples_dir,
  directories = {
    permanent = "Notes/Permanent",
    fleeting = "Notes/Fleeting",
    literature = "Notes/Literature",
    project = "Notes/Project",
    index = "Notes/Permanent",
    structure = "Notes/Permanent",
    journal = "journal",
  },
  templates_path = "templates",
})

vim.notify("Holon: notes_path -> " .. examples_dir, vim.log.levels.INFO)
