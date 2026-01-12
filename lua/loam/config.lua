-- =============================================================================
-- loam/config: Configuration management for telescope-loam
-- =============================================================================

local M = {}

--- Default configuration
M.defaults = {
  -- Path to the Zettelkasten notes directory
  notes_path = vim.fn.expand("~/Projects/personal-knowledge"),

  -- Subdirectory structure mapping (relative to notes_path)
  directories = {
    permanent = "Notes/Permanent",
    fleeting = "Notes/Fleeting",
    literature = "Notes/Literature",
    project = "Notes/Project",
    index = "Notes/Permanent", -- Index notes go with permanent
    structure = "Notes/Permanent", -- Structure notes go with permanent
    journal = "journal",
  },

  -- Template directory (relative to notes_path)
  templates_path = ".foam/templates",

  -- File extension for notes
  extension = ".md",

  -- Note types supported
  types = { "permanent", "fleeting", "literature", "project", "index", "structure" },

  -- UUID generation style
  uuid_style = "uuid4",

  -- Link format preference: "wiki" for [[UUID|title]] or "markdown" for [title](UUID.md)
  default_link_format = "wiki",

  -- Picker settings
  picker = {
    -- Show type icons in results
    show_icons = true,
    -- Show tags in results
    show_tags = true,
    -- Initial mode for pickers
    initial_mode = "insert",
    -- Layout strategy
    layout_strategy = "horizontal",
    layout_config = {
      horizontal = {
        preview_width = 0.5,
      },
      width = 0.9,
      height = 0.8,
    },
  },

  -- Type icons (nerd font icons with fallbacks)
  icons = {
    permanent = { icon = "󰆼", hl = "LoamPermanent" },
    fleeting = { icon = "󱞁", hl = "LoamFleeting" },
    literature = { icon = "󰂺", hl = "LoamLiterature" },
    project = { icon = "󰳏", hl = "LoamProject" },
    index = { icon = "󰉋", hl = "LoamIndex" },
    structure = { icon = "󰙅", hl = "LoamStructure" },
    default = { icon = "󰈙", hl = "LoamDefault" },
  },

  -- Keymappings for pickers (can be overridden by user)
  mappings = {
    i = {
      ["<C-n>"] = "create_note",
      ["<C-b>"] = "show_backlinks",
      ["<C-l>"] = "insert_link",
    },
    n = {
      ["n"] = "create_note",
      ["b"] = "show_backlinks",
      ["l"] = "insert_link",
    },
  },
}

--- Current configuration (merged with defaults)
M.options = {}

--- Setup configuration with user options
---@param opts table|nil User configuration options
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- Setup highlight groups
  M.setup_highlights()
end

--- Setup highlight groups for type icons
function M.setup_highlights()
  local highlights = {
    LoamPermanent = { link = "DiagnosticInfo" },
    LoamFleeting = { link = "DiagnosticHint" },
    LoamLiterature = { link = "DiagnosticWarn" },
    LoamProject = { link = "DiagnosticOk" },
    LoamIndex = { link = "Special" },
    LoamStructure = { link = "Identifier" },
    LoamDefault = { link = "Normal" },
    LoamTags = { link = "Comment" },
  }

  for name, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

--- Get a configuration value
---@param key string Configuration key (supports dot notation: "picker.show_icons")
---@return any
function M.get(key)
  local keys = vim.split(key, ".", { plain = true })
  -- Use options if available, fallback to defaults
  local value = next(M.options) and M.options or M.defaults

  for _, k in ipairs(keys) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[k]
  end

  return value
end

--- Get the full path to a directory for a note type
---@param note_type string Note type
---@return string path Full path to the directory
function M.get_directory(note_type)
  local base = M.options.notes_path
  local subdir = M.options.directories[note_type]

  if subdir then
    return base .. "/" .. subdir
  end

  -- Fallback to permanent directory
  return base .. "/" .. M.options.directories.permanent
end

--- Get the full path to the templates directory
---@return string path Full path to templates
function M.get_templates_path()
  return M.options.notes_path .. "/" .. M.options.templates_path
end

--- Get icon for a note type
---@param note_type string Note type
---@return string icon, string highlight_group
function M.get_icon(note_type)
  -- Fallback to defaults if options not initialized
  local icons = M.options.icons or M.defaults.icons
  local icon_config = icons[note_type] or icons.default
  return icon_config.icon, icon_config.hl
end

return M
