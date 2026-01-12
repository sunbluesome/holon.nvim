-- =============================================================================
-- loam/make_entry: Entry maker for Telescope display
-- =============================================================================

local entry_display = require("telescope.pickers.entry_display")

local config = require("loam.config")
local frontmatter = require("loam.frontmatter")
local utils = require("loam.utils")

local M = {}

--- Create entry maker for notes
---@param opts table Options
---@return function entry_maker
function M.make_note_entry(opts)
  opts = opts or {}

  -- Get config with defaults
  local show_icons = config.get("picker.show_icons")
  if show_icons == nil then
    show_icons = true
  end
  local show_tags = config.get("picker.show_tags")
  if show_tags == nil then
    show_tags = true
  end

  -- Calculate display widths
  local icon_width = show_icons and 3 or 0
  local type_width = 12
  local title_width = 60
  local tags_width = 30

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = icon_width },
      { width = type_width },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    local icon, icon_hl = config.get_icon(entry.note_type)
    local type_display = show_icons and icon or entry.note_type

    -- Build title with tags
    local display_str = entry.title or ""
    if show_tags and entry.tags and #entry.tags > 0 then
      local tags_str = "[" .. table.concat(entry.tags, ", ") .. "]"
      display_str = display_str .. " " .. tags_str
    end

    return displayer({
      { type_display, icon_hl },
      { entry.note_type or "unknown", "Comment" },
      { display_str },
    })
  end

  return function(filepath)
    -- Parse frontmatter
    local fm = frontmatter.parse_file(filepath)

    local title = frontmatter.get_title(fm)
    local note_type = frontmatter.get_type(fm)
    local tags = frontmatter.get_tags(fm)
    local uuid = utils.extract_uuid_from_path(filepath)

    -- Use filename as title if frontmatter title is empty or same as UUID
    if not title or title == "" or title == uuid then
      title = vim.fn.fnamemodify(filepath, ":t:r")
    end

    return {
      value = filepath,
      ordinal = title .. " " .. (table.concat(tags, " ") or ""),
      display = make_display,
      path = filepath,

      -- Custom fields for actions
      uuid = uuid,
      title = title,
      note_type = note_type,
      tags = tags,
      frontmatter = fm,
    }
  end
end

--- Create entry maker for templates
---@param opts table Options
---@return function entry_maker
function M.make_template_entry(opts)
  opts = opts or {}

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 3 },
      { width = 20 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    local icon, icon_hl = config.get_icon(entry.template_type)
    return displayer({
      { icon, icon_hl },
      { entry.name, "TelescopeResultsIdentifier" },
      { entry.description or "", "Comment" },
    })
  end

  return function(template)
    return {
      value = template.path,
      ordinal = template.name,
      display = make_display,
      path = template.path,

      -- Custom fields
      name = template.name,
      template_type = template.type,
      description = template.description,
    }
  end
end

--- Create entry maker for backlinks
---@param opts table Options
---@return function entry_maker
function M.make_backlink_entry(opts)
  opts = opts or {}

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 3 },
      { width = 12 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    local icon, icon_hl = config.get_icon(entry.note_type)
    -- Show title, fallback to UUID if title is empty or same as UUID
    local display_title = entry.title
    if not display_title or display_title == "" or display_title == entry.uuid then
      display_title = entry.uuid or vim.fn.fnamemodify(entry.value, ":t:r")
    end
    return displayer({
      { icon, icon_hl },
      { entry.note_type or "unknown", "Comment" },
      { display_title },
    })
  end

  return function(filepath)
    local fm = frontmatter.parse_file(filepath)
    local title = frontmatter.get_title(fm)
    local note_type = frontmatter.get_type(fm)
    local uuid = utils.extract_uuid_from_path(filepath)

    -- If title is empty or UUID, try to use filename
    if not title or title == "" or title == uuid then
      title = vim.fn.fnamemodify(filepath, ":t:r")
    end

    return {
      value = filepath,
      ordinal = title,
      display = make_display,
      path = filepath,

      uuid = uuid,
      title = title,
      note_type = note_type,
      frontmatter = fm,
    }
  end
end

--- Create entry maker for index links
---@param opts table Options
---@return function entry_maker
function M.make_index_link_entry(opts)
  opts = opts or {}

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 3 },
      { width = 40 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    local icon, icon_hl = config.get_icon(entry.note_type or "default")
    return displayer({
      { icon, icon_hl },
      { entry.display_text },
      { entry.uuid, "Comment" },
    })
  end

  return function(link_info)
    -- link_info: {filepath, display_text, uuid}
    local filepath = link_info.filepath
    local fm = nil
    local note_type = "unknown"

    if filepath and utils.file_exists(filepath) then
      fm = frontmatter.parse_file(filepath)
      note_type = frontmatter.get_type(fm)
    end

    return {
      value = filepath or "",
      ordinal = link_info.display_text,
      display = make_display,
      path = filepath,

      uuid = link_info.uuid,
      display_text = link_info.display_text,
      note_type = note_type,
      frontmatter = fm,
      exists = filepath ~= nil,
    }
  end
end

--- Create entry maker for tags
---@param opts table Options
---@return function entry_maker
function M.make_tag_entry(opts)
  opts = opts or {}

  return function(tag_info)
    -- tag_info: {tag, count}
    return {
      value = tag_info.tag,
      ordinal = tag_info.tag,
      display = string.format("%s (%d)", tag_info.tag, tag_info.count),

      tag = tag_info.tag,
      count = tag_info.count,
    }
  end
end

--- Create entry maker for journal entries
---@param opts table Options
---@return function entry_maker
function M.make_journal_entry(opts)
  opts = opts or {}

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 3 },
      { width = 12 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    return displayer({
      { "󰃭", "DiagnosticInfo" },
      { entry.date },
      { entry.preview or "", "Comment" },
    })
  end

  return function(filepath)
    local filename = vim.fn.fnamemodify(filepath, ":t:r")
    local content = utils.read_file(filepath)
    local preview = ""

    if content then
      -- Get first non-empty line after frontmatter
      local body = frontmatter.get_body(content)
      for line in body:gmatch("[^\n]+") do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not trimmed:match("^#") then
          preview = utils.truncate(trimmed, 60)
          break
        end
      end
    end

    return {
      value = filepath,
      ordinal = filename,
      display = make_display,
      path = filepath,

      date = filename,
      preview = preview,
    }
  end
end

return M
