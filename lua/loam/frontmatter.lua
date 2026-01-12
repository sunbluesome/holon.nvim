-- =============================================================================
-- loam/frontmatter: YAML frontmatter parsing for telescope-loam
-- =============================================================================

local utils = require("loam.utils")

local M = {}

--- Parse YAML frontmatter from content
--- Supports the note format used in personal-knowledge:
--- ---
--- title: ...
--- created: ...
--- lastmod: ...
--- url: ...
--- type: ...
--- tags:
---     - tag1
---     - tag2
--- ---
---@param content string File content
---@return table|nil frontmatter Parsed frontmatter or nil if not found
function M.parse(content)
  -- Find frontmatter boundaries
  local start_pos = content:find("^%-%-%-\n")
  if not start_pos then
    return nil
  end

  local end_pos = content:find("\n%-%-%-", start_pos + 3)
  if not end_pos then
    return nil
  end

  -- Extract frontmatter content (between the --- markers)
  local fm_content = content:sub(start_pos + 4, end_pos - 1)

  -- Parse YAML-like content
  local frontmatter = {}
  local current_key = nil
  local in_array = false
  local array_values = {}

  for line in fm_content:gmatch("[^\n]+") do
    -- Check for array item (starts with spaces and -)
    local array_item = line:match("^%s+%-%s*(.+)$")
    if array_item and in_array and current_key then
      -- Handle null as empty
      if array_item ~= "null" then
        table.insert(array_values, array_item)
      end
    else
      -- Save previous array if we were in one
      if in_array and current_key then
        frontmatter[current_key] = array_values
        in_array = false
        array_values = {}
      end

      -- Check for key: value pair
      local key, value = line:match("^([%w_]+):%s*(.*)$")
      if key then
        current_key = key
        value = vim.trim(value)

        if value == "" then
          -- Empty value, might be start of array
          in_array = true
          array_values = {}
        elseif value == "null" then
          frontmatter[key] = nil
        else
          frontmatter[key] = value
        end
      end
    end
  end

  -- Handle last array if content ended in array
  if in_array and current_key then
    frontmatter[current_key] = array_values
  end

  return frontmatter
end

--- Parse frontmatter from file path
---@param filepath string Absolute path to file
---@return table|nil frontmatter Parsed frontmatter or nil
function M.parse_file(filepath)
  local content = utils.read_file(filepath)
  if not content then
    return nil
  end
  return M.parse(content)
end

--- Get title from frontmatter
---@param frontmatter table Parsed frontmatter
---@return string title Note title or empty string
function M.get_title(frontmatter)
  if not frontmatter then
    return ""
  end
  return frontmatter.title or ""
end

--- Get tags from frontmatter
---@param frontmatter table Parsed frontmatter
---@return table tags List of tags (empty table if none)
function M.get_tags(frontmatter)
  if not frontmatter or not frontmatter.tags then
    return {}
  end

  -- Handle both array and string formats
  if type(frontmatter.tags) == "table" then
    -- Filter out nil/null values
    local tags = {}
    for _, tag in ipairs(frontmatter.tags) do
      if tag and tag ~= "null" then
        table.insert(tags, tag)
      end
    end
    return tags
  elseif type(frontmatter.tags) == "string" and frontmatter.tags ~= "null" then
    return { frontmatter.tags }
  end

  return {}
end

--- Get type from frontmatter
--- If type is an array, returns the first type
---@param frontmatter table Parsed frontmatter
---@return string type Note type or "unknown"
function M.get_type(frontmatter)
  if not frontmatter then
    return "unknown"
  end

  local t = frontmatter.type
  if not t then
    return "unknown"
  end

  -- Handle array format (type: \n - project \n - index)
  if type(t) == "table" then
    return t[1] or "unknown"
  end

  return t
end

--- Get all types from frontmatter (for notes with multiple types)
---@param frontmatter table Parsed frontmatter
---@return table types List of types
function M.get_types(frontmatter)
  if not frontmatter then
    return {}
  end

  local t = frontmatter.type
  if not t then
    return {}
  end

  -- Handle array format
  if type(t) == "table" then
    return t
  end

  -- Single type as string
  return { t }
end

--- Check if frontmatter has a specific type (supports multiple types)
---@param frontmatter table Parsed frontmatter
---@param note_type string Type to check
---@return boolean matches
function M.has_type(frontmatter, note_type)
  local types = M.get_types(frontmatter)
  for _, t in ipairs(types) do
    if t == note_type then
      return true
    end
  end
  return false
end

--- Get created date from frontmatter
---@param frontmatter table Parsed frontmatter
---@return string|nil created ISO 8601 timestamp or nil
function M.get_created(frontmatter)
  if not frontmatter then
    return nil
  end
  return frontmatter.created
end

--- Get lastmod date from frontmatter
---@param frontmatter table Parsed frontmatter
---@return string|nil lastmod ISO 8601 timestamp or nil
function M.get_lastmod(frontmatter)
  if not frontmatter then
    return nil
  end
  return frontmatter.lastmod
end

--- Get URL from frontmatter
---@param frontmatter table Parsed frontmatter
---@return string|nil url URL or nil
function M.get_url(frontmatter)
  if not frontmatter or frontmatter.url == "null" then
    return nil
  end
  return frontmatter.url
end

--- Check if frontmatter has a specific type
---@param frontmatter table Parsed frontmatter
---@param note_type string Type to check
---@return boolean matches
function M.is_type(frontmatter, note_type)
  return M.get_type(frontmatter) == note_type
end

--- Check if frontmatter has a specific tag
---@param frontmatter table Parsed frontmatter
---@param tag string Tag to check
---@return boolean has_tag
function M.has_tag(frontmatter, tag)
  local tags = M.get_tags(frontmatter)
  for _, t in ipairs(tags) do
    if t == tag then
      return true
    end
  end
  return false
end

--- Get body content (everything after frontmatter)
---@param content string Full file content
---@return string body Content after frontmatter
function M.get_body(content)
  local end_pos = content:find("\n%-%-%-", 4)
  if not end_pos then
    return content
  end

  -- Skip the closing --- and any following newlines
  local body_start = content:find("[^\n]", end_pos + 4) or #content + 1
  return content:sub(body_start)
end

--- Generate frontmatter string from table
---@param data table Frontmatter data
---@return string frontmatter Formatted frontmatter string
function M.generate(data)
  local lines = { "---" }

  -- Order of keys for consistent output
  local key_order = { "title", "created", "lastmod", "url", "type", "tags" }

  for _, key in ipairs(key_order) do
    local value = data[key]
    if value ~= nil then
      if type(value) == "table" then
        table.insert(lines, key .. ":")
        for _, item in ipairs(value) do
          table.insert(lines, "    - " .. tostring(item))
        end
      elseif value == "" or value == nil then
        table.insert(lines, key .. ": null")
      else
        table.insert(lines, key .. ": " .. tostring(value))
      end
    end
  end

  -- Add any additional keys not in the standard order
  for key, value in pairs(data) do
    if not vim.tbl_contains(key_order, key) then
      if type(value) == "table" then
        table.insert(lines, key .. ":")
        for _, item in ipairs(value) do
          table.insert(lines, "    - " .. tostring(item))
        end
      else
        table.insert(lines, key .. ": " .. tostring(value))
      end
    end
  end

  table.insert(lines, "---")
  return table.concat(lines, "\n")
end

return M
