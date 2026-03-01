-- =============================================================================
-- holon/links: Link parsing and generation for holon.nvim
-- =============================================================================
-- Supports two link formats:
-- 1. Wiki-style: [[UUID|Display Text]] (Foam/Obsidian compatible)
-- 2. Markdown: [title](UUID.md)
-- =============================================================================

local utils = require("holon.utils")

local M = {}

-- UUID pattern for matching
local UUID_PATTERN = "[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+"

--- Extract all wiki-style links from content
--- Pattern: [[UUID|Display Text]]
---@param content string File content
---@return table links List of {uuid, display_text}
local function extract_wiki_links(content)
  local links = {}

  -- Pattern for [[UUID|Display Text]]
  for uuid, display_text in content:gmatch("%[%[(" .. UUID_PATTERN .. ")|([^%]]+)%]%]") do
    table.insert(links, {
      uuid = uuid,
      display_text = display_text,
      format = "wiki",
    })
  end

  -- Also match [[UUID]] without display text
  for uuid in content:gmatch("%[%[(" .. UUID_PATTERN .. ")%]%]") do
    -- Check if this UUID wasn't already captured with display text
    local found = false
    for _, link in ipairs(links) do
      if link.uuid == uuid then
        found = true
        break
      end
    end
    if not found then
      table.insert(links, {
        uuid = uuid,
        display_text = uuid,
        format = "wiki",
      })
    end
  end

  return links
end

--- Extract all markdown links to local files
--- Pattern: [title](UUID.md)
---@param content string File content
---@return table links List of {uuid, title}
local function extract_markdown_links(content)
  local links = {}

  -- Pattern for [title](UUID.md)
  for title, uuid in content:gmatch("%[([^%]]+)%]%((" .. UUID_PATTERN .. ")%.md%)") do
    table.insert(links, {
      uuid = uuid,
      display_text = title,
      format = "markdown",
    })
  end

  return links
end

--- Extract all links (both formats) from content
---@param content string File content
---@return table links Combined list of links
function M.extract_all_links(content)
  local links = {}

  -- Get wiki-style links
  local wiki_links = extract_wiki_links(content)
  vim.list_extend(links, wiki_links)

  -- Get markdown links
  local md_links = extract_markdown_links(content)
  vim.list_extend(links, md_links)

  return links
end

--- Generate wiki-style link
---@param uuid string Note UUID
---@param display_text string Display text
---@return string link Formatted link [[UUID|Display Text]]
local function wiki_link(uuid, display_text)
  if display_text and display_text ~= "" and display_text ~= uuid then
    return string.format("[[%s|%s]]", uuid, display_text)
  else
    return string.format("[[%s]]", uuid)
  end
end

--- Generate markdown link
---@param title string Link title
---@param uuid string Note UUID
---@return string link Formatted link [title](UUID.md)
local function markdown_link(title, uuid)
  return string.format("[%s](%s.md)", title, uuid)
end

--- Generate link in preferred format
---@param uuid string Note UUID
---@param display_text string Display text
---@param format string|nil Link format ("wiki" or "markdown"), uses config default if nil
---@return string link Formatted link
function M.generate_link(uuid, display_text, format)
  local config = require("holon.config")
  format = format or config.get("default_link_format")

  if format == "markdown" then
    return markdown_link(display_text, uuid)
  else
    return wiki_link(uuid, display_text)
  end
end

--- Find link target at cursor position in a line
---@param line string Line content
---@param col number 0-indexed byte offset (from nvim_win_get_cursor)
---@return string|nil target Link target if cursor is on a link
function M.find_link_at_position(line, col)
  -- Wiki: [[target|title]] or [[target]]
  local pos = 1
  while true do
    local s, _, target = line:find("%[%[([^%]|]+)", pos)
    if not s then break end
    local close = line:find("%]%]", s)
    if close and col >= s - 1 and col <= close then
      return target
    end
    pos = s + 1
  end

  -- Markdown: [title](target) — skip external URLs
  pos = 1
  while true do
    local s = line:find("%[", pos)
    if not s then break end
    local _, close, target = line:find("%]%(([^%)]+)%)", s)
    if close and target and col >= s - 1 and col <= close then
      if not target:match("^https?://") then
        return target
      end
    end
    pos = s + 1
  end

  return nil
end

--- Resolve a link target to full file path
--- Handles UUIDs, filenames, and relative paths
---@param target string Link target (UUID, filename, or relative path)
---@param context_filepath string|nil Current file path for relative resolution
---@return string|nil filepath Full path or nil if not found
function M.resolve_link_target(target, context_filepath)
  local config = require("holon.config")
  local notes_path = config.get("notes_path")
  local extension = config.get("extension")
  local clean = target:gsub("%.md$", "")

  -- 1. Relative to current file
  if context_filepath then
    local dir = vim.fn.fnamemodify(context_filepath, ":h")
    for _, candidate in ipairs({ dir .. "/" .. clean .. extension, dir .. "/" .. target }) do
      if utils.file_exists(candidate) then
        return candidate
      end
    end
  end

  -- 2. Relative to notes_path
  for _, candidate in ipairs({ notes_path .. "/" .. clean .. extension, notes_path .. "/" .. target }) do
    if utils.file_exists(candidate) then
      return candidate
    end
  end

  -- 3. Search configured directories
  for _, subdir in pairs(config.get("directories")) do
    local candidate = notes_path .. "/" .. subdir .. "/" .. clean .. extension
    if utils.file_exists(candidate) then
      return candidate
    end
  end

  -- 4. fd fallback
  local result = vim.fn.systemlist({ "fd", "--type", "f", "--glob", clean .. extension, notes_path })
  if #result > 0 then
    return result[1]
  end

  return nil
end

--- Find all notes that link to a specific UUID
--- Uses ripgrep for performance
---@param target_uuid string UUID to search for
---@param notes_path string|nil Base notes directory
---@return table backlinks List of file paths that link to target
function M.find_backlinks(identifier, notes_path)
  local config = require("holon.config")
  notes_path = notes_path or config.get("notes_path")

  -- Search for both link formats using multiple patterns:
  -- 1. Wiki-style: [[identifier| or [[identifier]]
  -- 2. Markdown: (identifier.md)
  local result = vim.fn.systemlist({
    "rg",
    "--files-with-matches",
    "--glob",
    "*.md",
    "-e",
    "\\[\\[" .. identifier,
    "-e",
    "\\(" .. identifier .. "\\.md\\)",
    notes_path,
  })

  -- Filter out the source file itself
  local backlinks = {}
  for _, filepath in ipairs(result) do
    local filename = vim.fn.fnamemodify(filepath, ":t:r")
    if filename ~= identifier then
      table.insert(backlinks, filepath)
    end
  end

  return backlinks
end

return M
