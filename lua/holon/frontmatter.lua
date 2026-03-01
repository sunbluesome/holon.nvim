-- =============================================================================
-- holon/frontmatter: YAML frontmatter parsing for holon.nvim
-- =============================================================================

local utils = require("holon.utils")

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
        elseif value:match("^%[.*%]$") then
          -- Inline YAML list: [A, B] or [A,B]
          local inner = value:sub(2, -2)
          local items = {}
          for item in inner:gmatch("[^,]+") do
            item = vim.trim(item)
            if item ~= "" and item ~= "null" then
              table.insert(items, item)
            end
          end
          frontmatter[key] = items
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

--- Get tags from frontmatter and optionally from body #tags
---@param frontmatter table|nil Parsed frontmatter
---@param content string|nil Full file content (if provided, extracts #tags from body)
---@return table tags List of tags (empty table if none)
function M.get_tags(frontmatter, content)
  local seen = {}
  local tags = {}

  local function add_tag(tag)
    if tag and tag ~= "null" and not seen[tag] then
      seen[tag] = true
      table.insert(tags, tag)
    end
  end

  -- Extract from frontmatter
  if frontmatter and frontmatter.tags then
    if type(frontmatter.tags) == "table" then
      for _, tag in ipairs(frontmatter.tags) do
        add_tag(tag)
      end
    elseif type(frontmatter.tags) == "string" then
      add_tag(frontmatter.tags)
    end
  end

  -- Extract #tags from body
  if content then
    local body = M.get_body(content)
    for tag in body:gmatch("#([%w][%w%d_-]*)") do
      add_tag(tag)
    end
  end

  return tags
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
local function get_types(frontmatter)
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
  local types = get_types(frontmatter)
  for _, t in ipairs(types) do
    if t == note_type then
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

-- =============================================================================
-- Frontmatter write operations (line-level to preserve formatting)
-- =============================================================================

--- Find the frontmatter region boundaries
---@param lines string[] Lines of the file
---@return number|nil start_line Opening --- line number
---@return number|nil end_line Closing --- line number
local function find_fm_boundaries(lines)
  local start_line, end_line
  for i, line in ipairs(lines) do
    if line:match("^%-%-%-$") then
      if not start_line then
        start_line = i
      else
        end_line = i
        break
      end
    end
  end
  return start_line, end_line
end

--- Find a key's line and its associated array lines within frontmatter
---@param lines string[] Lines of the file
---@param key string Frontmatter key to find
---@param start_line number Opening --- line number
---@param end_line number Closing --- line number
---@return number|nil key_line Line number of the key
---@return number|nil array_end Last line of array items (nil if scalar)
local function find_key_range(lines, key, start_line, end_line)
  local key_line = nil
  for i = start_line + 1, end_line - 1 do
    if lines[i]:match("^" .. key .. ":%s") or lines[i]:match("^" .. key .. ":$") then
      key_line = i
      break
    end
  end
  if not key_line then
    return nil, nil
  end

  -- Check for array items following the key
  local array_end = nil
  for i = key_line + 1, end_line - 1 do
    if lines[i]:match("^%s+%-%s") then
      array_end = i
    else
      break
    end
  end

  return key_line, array_end
end

--- Set a scalar field in frontmatter. Adds the field if it doesn't exist.
--- If the field currently has array items, they are removed.
---@param content string Full file content
---@param key string Frontmatter key
---@param value string|nil Value to set (nil becomes "null")
---@return string new_content Updated content
function M.set_field(content, key, value)
  local display_value = value or "null"
  local lines = vim.split(content, "\n")
  local start_line, end_line = find_fm_boundaries(lines)
  if not start_line or not end_line then
    return content
  end

  local key_line, array_end = find_key_range(lines, key, start_line, end_line)

  if key_line then
    -- Remove array items if present
    if array_end then
      for _ = key_line + 1, array_end do
        table.remove(lines, key_line + 1)
      end
    end
    -- Replace the key line
    lines[key_line] = key .. ": " .. display_value
  else
    -- Insert before closing ---
    table.insert(lines, end_line, key .. ": " .. display_value)
  end

  return table.concat(lines, "\n")
end

--- Add an item to an array field. Creates the array if the field is scalar/null/missing.
---@param content string Full file content
---@param key string Frontmatter key
---@param value string Value to add
---@return string new_content Updated content
function M.add_to_array(content, key, value)
  local lines = vim.split(content, "\n")
  local start_line, end_line = find_fm_boundaries(lines)
  if not start_line or not end_line then
    return content
  end

  local key_line, array_end = find_key_range(lines, key, start_line, end_line)
  local item_line = "    - " .. value

  if key_line then
    if array_end then
      -- Already an array, append after last item
      table.insert(lines, array_end + 1, item_line)
    else
      -- Scalar value, convert to array
      lines[key_line] = key .. ":"
      table.insert(lines, key_line + 1, item_line)
    end
  else
    -- Key doesn't exist, add before closing ---
    table.insert(lines, end_line, item_line)
    table.insert(lines, end_line, key .. ":")
  end

  return table.concat(lines, "\n")
end

--- Remove an item from an array field. Sets to null if array becomes empty.
---@param content string Full file content
---@param key string Frontmatter key
---@param value string Value to remove
---@return string new_content Updated content
function M.remove_from_array(content, key, value)
  local lines = vim.split(content, "\n")
  local start_line, end_line = find_fm_boundaries(lines)
  if not start_line or not end_line then
    return content
  end

  local key_line, array_end = find_key_range(lines, key, start_line, end_line)
  if not key_line or not array_end then
    return content
  end

  -- Find and remove the matching item
  local removed = false
  for i = array_end, key_line + 1, -1 do
    local item = lines[i]:match("^%s+%-%s*(.+)$")
    if item and item == value then
      table.remove(lines, i)
      removed = true
      break
    end
  end

  if not removed then
    return content
  end

  -- Check if array is now empty (next line after key is either another key or ---)
  local has_items = false
  local next_line = lines[key_line + 1]
  if next_line and next_line:match("^%s+%-%s") then
    has_items = true
  end

  if not has_items then
    lines[key_line] = key .. ": null"
  end

  return table.concat(lines, "\n")
end

return M
