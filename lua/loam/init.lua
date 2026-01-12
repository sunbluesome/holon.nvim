-- =============================================================================
-- loam: Main module for telescope-loam
-- =============================================================================
-- Telescope extension for Zettelkasten workflow.
-- Provides note searching, creation, backlink discovery, and index navigation.
-- =============================================================================

local M = {}

-- Lazy-load modules to avoid circular dependencies
local function get_module(name)
  return require("loam." .. name)
end

--- Setup the plugin with user configuration
---@param opts table|nil User configuration options
function M.setup(opts)
  get_module("config").setup(opts)
end

-- Module accessors (lazy-loaded)
setmetatable(M, {
  __index = function(_, key)
    local modules = {
      config = "config",
      pickers = "pickers",
      actions = "actions",
      utils = "utils",
      frontmatter = "frontmatter",
      links = "links",
      finders = "finders",
      make_entry = "make_entry",
    }

    if modules[key] then
      return get_module(modules[key])
    end

    return nil
  end,
})

return M
