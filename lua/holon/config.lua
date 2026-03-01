-- =============================================================================
-- holon/config: Configuration management for holon.nvim
-- =============================================================================

local M = {}

--- Default configuration
M.defaults = {
  -- Path to the Zettelkasten notes directory
  notes_path = vim.fn.expand("~/notes"),

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
  templates_path = "templates",

  -- File extension for notes
  extension = ".md",

  -- Filename style: "uuid" = auto-generated UUID, "manual" = user-specified filename
  filename_style = "uuid",

  -- Link format preference: "wiki" for [[UUID|title]] or "markdown" for [title](UUID.md)
  default_link_format = "wiki",

  -- Timezone offset from UTC in hours (nil = use system local time, 9 = JST, -5 = EST)
  timezone_offset = nil,

  -- Picker settings
  picker = {
    -- Show type icons in results
    show_icons = true,
    -- Show tags in results
    show_tags = true,
    -- Initial mode for pickers ("insert" or "normal")
    initial_mode = "insert",
    -- Layout configuration
    layout_config = {
      width = 0.9,
      height = 0.8,
      horizontal = {
        preview_width = 0.5,
      },
    },
  },

  -- Type icons (nerd font icons with fallbacks)
  icons = {
    permanent = { icon = "󰆼", hl = "HolonPermanent" },
    fleeting = { icon = "󱞁", hl = "HolonFleeting" },
    literature = { icon = "󰂺", hl = "HolonLiterature" },
    project = { icon = "󰳏", hl = "HolonProject" },
    index = { icon = "󰉋", hl = "HolonIndex" },
    structure = { icon = "󰙅", hl = "HolonStructure" },
    default = { icon = "󰈙", hl = "HolonDefault" },
  },

  -- Keymappings for pickers (can be overridden by user)
  mappings = {
    i = {
      ["<C-n>"] = "create_note",
      ["<C-b>"] = "show_backlinks",
      ["<C-f>"] = "show_forward_links",
      ["<C-l>"] = "insert_link",
      ["<C-t>"] = "filter_by_type",
      ["<C-g>"] = "filter_by_tag",
    },
    n = {
      ["n"] = "create_note",
      ["b"] = "show_backlinks",
      ["f"] = "show_forward_links",
      ["l"] = "insert_link",
      ["t"] = "filter_by_type",
      ["g"] = "filter_by_tag",
    },
  },

  -- GTD board settings
  gtd = {
    -- Status progression order (used for h/l navigation)
    statuses = { "inbox", "todo", "inprogress", "waiting", "delegate", "done" },

    -- Status display icons
    status_icons = {
      inbox = { icon = "󰁔", hl = "HolonGtdInbox" },
      todo = { icon = "󰝖", hl = "HolonGtdTodo" },
      inprogress = { icon = "󱓻", hl = "HolonGtdProgress" },
      waiting = { icon = "󰏤", hl = "HolonGtdWaiting" },
      delegate = { icon = "󰜵", hl = "HolonGtdDelegate" },
      done = { icon = "󰄲", hl = "HolonGtdDone" },
    },

    -- Blocked indicator
    blocked_icon = "🔒",

    -- Board layout (ratios relative to editor size)
    layout = {
      width = 0.9,
      height = 0.8,
      timeline_min_width = 30, -- hide timeline if it would be narrower than this
      preview_ratio = 0.45, -- bottom preview panel height ratio
    },
  },
}

--- Current configuration (merged with defaults)
M.options = {}

--- Setup configuration with user options
---@param opts table|nil User configuration options
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- Validate notes_path
  local notes_path = M.options.notes_path
  if not notes_path or notes_path == "" then
    vim.notify("[Holon] notes_path is not configured", vim.log.levels.WARN)
  elseif not vim.uv.fs_stat(notes_path) then
    vim.notify("[Holon] notes_path does not exist: " .. notes_path, vim.log.levels.WARN)
  end

  -- Check external dependencies
  if vim.fn.executable("fd") ~= 1 then
    vim.notify("[Holon] 'fd' not found. Install fd: https://github.com/sharkdp/fd", vim.log.levels.ERROR)
  end
  if vim.fn.executable("rg") ~= 1 then
    vim.notify("[Holon] 'rg' not found. Install ripgrep: https://github.com/BurntSushi/ripgrep", vim.log.levels.ERROR)
  end

  -- Setup highlight groups
  M.setup_highlights()
end

--- Setup highlight groups for type icons
function M.setup_highlights()
  local highlights = {
    HolonPermanent = { link = "DiagnosticInfo" },
    HolonFleeting = { link = "DiagnosticHint" },
    HolonLiterature = { link = "DiagnosticWarn" },
    HolonProject = { link = "DiagnosticOk" },
    HolonIndex = { link = "Special" },
    HolonStructure = { link = "Identifier" },
    HolonDefault = { link = "Normal" },
    HolonTags = { link = "Comment" },
    -- GTD status highlights
    HolonGtdInbox = { link = "DiagnosticHint" },
    HolonGtdTodo = { link = "DiagnosticInfo" },
    HolonGtdProgress = { link = "DiagnosticOk" },
    HolonGtdWaiting = { link = "DiagnosticWarn" },
    HolonGtdDelegate = { link = "Special" },
    HolonGtdDone = { link = "Comment" },
    HolonGtdOverdue = { link = "DiagnosticError" },
    HolonGtdBlocked = { link = "DiagnosticError" },
    HolonGtdProgressDone = { link = "DiagnosticOk" },
    HolonGtdBoardActive = { link = "CursorLine" },
    HolonGtdBoardBorder = { link = "FloatBorder" },
    HolonGtdBoardBorderActive = { link = "DiagnosticInfo" },
    HolonGtdTimeline = { link = "Comment" },
    HolonGtdTimelineToday = { link = "DiagnosticWarn" },
    HolonGtdTimelineBar = { link = "DiagnosticInfo" },
    -- Dependency graph lane colors
    HolonGtdDepGreen = { link = "DiagnosticOk" },
    HolonGtdDepYellow = { link = "DiagnosticWarn" },
    HolonGtdDepBlue = { link = "DiagnosticInfo" },
    HolonGtdDepMagenta = { link = "Special" },
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
  local base = M.get("notes_path")
  local directories = M.get("directories")
  local subdir = directories[note_type]

  if subdir then
    return base .. "/" .. subdir
  end

  -- Fallback to permanent directory
  return base .. "/" .. directories.permanent
end

--- Get the list of note types derived from directories keys (excluding journal)
---@return string[] types Sorted list of note type names
function M.get_types()
  local directories = M.get("directories")
  local types = {}
  for key, _ in pairs(directories) do
    if key ~= "journal" then
      table.insert(types, key)
    end
  end
  table.sort(types)
  return types
end

--- Get the full path to the templates directory
---@return string path Full path to templates
function M.get_templates_path()
  return M.get("notes_path") .. "/" .. M.get("templates_path")
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
