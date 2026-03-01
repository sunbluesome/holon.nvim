-- =============================================================================
-- holon: Main module for holon.nvim
-- =============================================================================
-- Zettelkasten workflow plugin for Neovim.
-- Provides note searching, creation, backlink discovery, and index navigation.
-- =============================================================================

local M = {}

-- Lazy-load modules to avoid circular dependencies
local function get_module(name)
  return require("holon." .. name)
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
      -- Shared infrastructure
      config = "config",
      utils = "utils",
      frontmatter = "frontmatter",
      links = "links",
      graph = "graph",
      file_search = "file_search",
      picker = "picker",
      -- Zettelkasten
      pickers = "zk.pickers",
      actions = "zk.actions",
      finders = "zk.finders",
      make_entry = "zk.make_entry",
      link_browser = "zk.link_browser",
      -- GTD
      gtd = "gtd.board",
    }

    if modules[key] then
      return get_module(modules[key])
    end

    return nil
  end,
})

return M
