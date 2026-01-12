-- =============================================================================
-- telescope-loam: Telescope extension for Zettelkasten workflow
-- =============================================================================
-- This is the entry point for the Telescope extension.
-- It registers the extension with Telescope and exposes pickers.
--
-- Usage:
--   :Telescope loam notes     - Find notes
--   :Telescope loam grep      - Grep note contents
--   :Telescope loam new       - Create new note from template
--   :Telescope loam backlinks - Show backlinks to current note
--   :Telescope loam indexes   - Browse index notes
--   :Telescope loam journal   - Browse journal entries
--   :Telescope loam tags      - Filter by tags
--   :Telescope loam types     - Filter by type
-- =============================================================================

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("telescope-loam requires nvim-telescope/telescope.nvim")
end

local loam = require("loam")

return telescope.register_extension({
  setup = function(ext_config, config)
    loam.setup(ext_config)
  end,
  exports = {
    -- Default picker (same as notes)
    loam = function(opts)
      loam.pickers.notes(opts)
    end,

    -- Main pickers
    notes = function(opts)
      loam.pickers.notes(opts)
    end,
    grep = function(opts)
      loam.pickers.grep_notes(opts)
    end,
    new = function(opts)
      loam.pickers.templates(opts)
    end,
    backlinks = function(opts)
      loam.pickers.backlinks(opts)
    end,
    indexes = function(opts)
      loam.pickers.indexes(opts)
    end,
    journal = function(opts)
      loam.pickers.journal(opts)
    end,
    tags = function(opts)
      loam.pickers.filter_tags(opts)
    end,
    types = function(opts)
      loam.pickers.filter_type(opts)
    end,

    -- Export actions for custom mappings
    actions = loam.actions,
  },
})
