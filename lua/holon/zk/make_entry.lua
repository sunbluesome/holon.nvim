-- =============================================================================
-- holon/zk/make_entry: Entry formatting for picker display
-- =============================================================================

local config = require("holon.config")
local frontmatter = require("holon.frontmatter")
local utils = require("holon.utils")

local M = {}

-- =============================================================================
-- Metadata parsing
-- =============================================================================

--- Parse common note metadata from filepath
---@param filepath string File path
---@return table metadata { uuid, title, note_type, tags, frontmatter }
local function parse_note_metadata(filepath)
  local content = utils.read_file(filepath)
  local fm = content and frontmatter.parse(content) or nil
  local title = frontmatter.get_title(fm)
  local note_type = frontmatter.get_type(fm)
  local tags = frontmatter.get_tags(fm, content)
  local uuid = utils.extract_uuid_from_path(filepath)
    or vim.fn.fnamemodify(filepath, ":t:r")

  if not title or title == "" or title == uuid then
    title = vim.fn.fnamemodify(filepath, ":t:r")
  end

  return {
    uuid = uuid,
    title = title,
    note_type = note_type,
    tags = tags,
    frontmatter = fm,
  }
end

-- =============================================================================
-- Entry makers
-- =============================================================================

--- Create entry maker for notes
---@param opts table|nil Options
---@return function entry_maker
function M.make_note_entry(opts)
  opts = opts or {}

  local show_icons = config.get("picker.show_icons")
  if show_icons == nil then
    show_icons = true
  end
  local show_tags = config.get("picker.show_tags")
  if show_tags == nil then
    show_tags = true
  end

  return function(filepath)
    local meta = parse_note_metadata(filepath)
    local icon, icon_hl = config.get_icon(meta.note_type)

    local parts = {}
    local highlights = {}
    local pos = 0

    -- Icon column (width 3)
    if show_icons then
      local icon_str = utils.display_fit(icon, 3)
      table.insert(parts, icon_str)
      table.insert(highlights, { col_start = pos, col_end = pos + #icon_str, hl = icon_hl })
      pos = pos + #icon_str + 1
    end

    -- Type column (width 12)
    local type_str = utils.display_fit(meta.note_type or "unknown", 12)
    table.insert(parts, type_str)
    table.insert(highlights, { col_start = pos, col_end = pos + #type_str, hl = "Comment" })
    pos = pos + #type_str + 1

    -- Title + tags
    local display = meta.title or ""
    if show_tags and meta.tags and #meta.tags > 0 then
      display = display .. " [" .. table.concat(meta.tags, ", ") .. "]"
    end
    table.insert(parts, display)

    return {
      ordinal = meta.title .. " " .. table.concat(meta.tags, " "),
      display_text = table.concat(parts, " "),
      highlights = highlights,
      value = filepath,
      path = filepath,
      uuid = meta.uuid,
      title = meta.title,
      note_type = meta.note_type,
      tags = meta.tags,
      frontmatter = meta.frontmatter,
    }
  end
end

--- Create entry maker for templates
---@param opts table|nil Options
---@return function entry_maker
function M.make_template_entry(opts)
  opts = opts or {}

  return function(template)
    local icon, icon_hl = config.get_icon(template.type)

    local icon_str = utils.display_fit(icon, 3)
    local name_str = utils.display_fit(template.name, 20)
    local desc_str = template.description or ""

    local display_text = icon_str .. " " .. name_str .. " " .. desc_str
    local highlights = {
      { col_start = 0, col_end = #icon_str, hl = icon_hl },
      { col_start = #icon_str + 1, col_end = #icon_str + 1 + #name_str, hl = "Identifier" },
      { col_start = #icon_str + 1 + #name_str + 1, col_end = #display_text, hl = "Comment" },
    }

    return {
      ordinal = template.name,
      display_text = display_text,
      highlights = highlights,
      value = template.path,
      path = template.path,
      name = template.name,
      template_type = template.type,
      description = template.description,
    }
  end
end

--- Create entry maker for backlinks
---@param opts table|nil Options
---@return function entry_maker
function M.make_backlink_entry(opts)
  opts = opts or {}

  return function(filepath)
    local meta = parse_note_metadata(filepath)
    local icon, icon_hl = config.get_icon(meta.note_type)

    local icon_str = utils.display_fit(icon, 3)
    local type_str = utils.display_fit(meta.note_type or "unknown", 12)
    local title_str = meta.title or ""

    local display_text = icon_str .. " " .. type_str .. " " .. title_str
    local highlights = {
      { col_start = 0, col_end = #icon_str, hl = icon_hl },
      { col_start = #icon_str + 1, col_end = #icon_str + 1 + #type_str, hl = "Comment" },
    }

    return {
      ordinal = meta.title,
      display_text = display_text,
      highlights = highlights,
      value = filepath,
      path = filepath,
      uuid = meta.uuid,
      title = meta.title,
      note_type = meta.note_type,
      frontmatter = meta.frontmatter,
    }
  end
end

--- Create entry maker for index links
---@param opts table|nil Options
---@return function entry_maker
function M.make_index_link_entry(opts)
  opts = opts or {}

  return function(link_info)
    local filepath = link_info.filepath
    local note_type = "unknown"

    if filepath and utils.file_exists(filepath) then
      local meta = parse_note_metadata(filepath)
      note_type = meta.note_type
    end

    local icon, icon_hl = config.get_icon(note_type)
    local icon_str = utils.display_fit(icon, 3)
    local text_str = utils.display_fit(link_info.display_text, 40)
    local uuid_str = link_info.uuid

    local display_text = icon_str .. " " .. text_str .. " " .. uuid_str
    local uuid_start = #icon_str + 1 + #text_str + 1
    local highlights = {
      { col_start = 0, col_end = #icon_str, hl = icon_hl },
      { col_start = uuid_start, col_end = uuid_start + #uuid_str, hl = "Comment" },
    }

    return {
      ordinal = link_info.display_text,
      display_text = display_text,
      highlights = highlights,
      value = filepath or "",
      path = filepath,
      uuid = link_info.uuid,
      display_text_raw = link_info.display_text,
      note_type = note_type,
      exists = filepath ~= nil,
    }
  end
end

--- Create entry maker for tags
---@param opts table|nil Options
---@return function entry_maker
function M.make_tag_entry(opts)
  opts = opts or {}

  return function(tag_info)
    return {
      ordinal = tag_info.tag,
      display_text = string.format("%s (%d)", tag_info.tag, tag_info.count),
      highlights = {},
      value = tag_info.tag,
      tag = tag_info.tag,
      count = tag_info.count,
    }
  end
end

--- Create entry maker for journal entries
---@param opts table|nil Options
---@return function entry_maker
function M.make_journal_entry(opts)
  opts = opts or {}

  return function(filepath)
    local filename = vim.fn.fnamemodify(filepath, ":t:r")
    local content = utils.read_file(filepath)
    local preview = ""

    if content then
      local body = frontmatter.get_body(content)
      for line in body:gmatch("[^\n]+") do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not trimmed:match("^#") then
          preview = utils.truncate(trimmed, 60)
          break
        end
      end
    end

    local icon_str = utils.display_fit("󰃭", 3)
    local date_str = utils.display_fit(filename, 12)
    local display_text = icon_str .. " " .. date_str .. " " .. preview

    local highlights = {
      { col_start = 0, col_end = #icon_str, hl = "DiagnosticInfo" },
      { col_start = #icon_str + 1 + #date_str + 1, col_end = #display_text, hl = "Comment" },
    }

    return {
      ordinal = filename,
      display_text = display_text,
      highlights = highlights,
      value = filepath,
      path = filepath,
      date = filename,
      preview = preview,
    }
  end
end

return M
