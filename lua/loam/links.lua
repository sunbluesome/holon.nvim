-- =============================================================================
-- loam/links: Link parsing and generation for telescope-loam
-- =============================================================================
-- Supports two link formats:
-- 1. Wiki-style: [[UUID|Display Text]] (Foam/Obsidian compatible)
-- 2. Markdown: [title](UUID.md)
-- =============================================================================

local utils = require("loam.utils")

local M = {}

-- UUID pattern for matching
local UUID_PATTERN = "[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+"

--- Extract all wiki-style links from content
--- Pattern: [[UUID|Display Text]]
---@param content string File content
---@return table links List of {uuid, display_text}
function M.extract_wiki_links(content)
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
function M.extract_markdown_links(content)
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
  local wiki_links = M.extract_wiki_links(content)
  vim.list_extend(links, wiki_links)

  -- Get markdown links
  local md_links = M.extract_markdown_links(content)
  vim.list_extend(links, md_links)

  return links
end

--- Generate wiki-style link
---@param uuid string Note UUID
---@param display_text string Display text
---@return string link Formatted link [[UUID|Display Text]]
function M.wiki_link(uuid, display_text)
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
function M.markdown_link(title, uuid)
  return string.format("[%s](%s.md)", title, uuid)
end

--- Generate link in preferred format
---@param uuid string Note UUID
---@param display_text string Display text
---@param format string|nil Link format ("wiki" or "markdown"), uses config default if nil
---@return string link Formatted link
function M.generate_link(uuid, display_text, format)
  local config = require("loam.config")
  format = format or config.get("default_link_format")

  if format == "markdown" then
    return M.markdown_link(display_text, uuid)
  else
    return M.wiki_link(uuid, display_text)
  end
end

--- Resolve UUID to full file path
--- Searches through all configured directories
---@param uuid string Note UUID
---@param notes_path string|nil Base notes directory (uses config if nil)
---@return string|nil filepath Full path or nil if not found
function M.resolve_uuid(uuid, notes_path)
  local config = require("loam.config")
  notes_path = notes_path or config.get("notes_path")
  local extension = config.get("extension")

  -- Search in all configured directories
  local directories = config.get("directories")
  for _, subdir in pairs(directories) do
    local filepath = notes_path .. "/" .. subdir .. "/" .. uuid .. extension
    if utils.file_exists(filepath) then
      return filepath
    end
  end

  -- Try searching with fd for better coverage (handles nested directories)
  local result = vim.fn.systemlist({
    "fd",
    "--type",
    "f",
    "--glob",
    uuid .. extension,
    notes_path,
  })

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
function M.find_backlinks(target_uuid, notes_path)
  local config = require("loam.config")
  notes_path = notes_path or config.get("notes_path")

  -- Search for both link formats using multiple patterns:
  -- 1. Wiki-style: [[UUID| or [[UUID]]
  -- 2. Markdown: (UUID.md)
  local result = vim.fn.systemlist({
    "rg",
    "--files-with-matches",
    "--glob",
    "*.md",
    "-e",
    "\\[\\[" .. target_uuid, -- Wiki-style link
    "-e",
    "\\(" .. target_uuid .. "\\.md\\)", -- Markdown link
    notes_path,
  })

  -- Filter out the source file itself if present
  local backlinks = {}
  for _, filepath in ipairs(result) do
    local file_uuid = utils.extract_uuid_from_path(filepath)
    if file_uuid ~= target_uuid then
      table.insert(backlinks, filepath)
    end
  end

  return backlinks
end

--- Check if content contains a link to specific UUID
---@param content string File content
---@param target_uuid string UUID to check for
---@return boolean has_link
function M.has_link_to(content, target_uuid)
  -- Check wiki-style link
  if content:find("%[%[" .. utils.escape_pattern(target_uuid)) then
    return true
  end

  -- Check markdown link
  if content:find("%(" .. utils.escape_pattern(target_uuid) .. "%.md%)") then
    return true
  end

  return false
end

--- Get all unique UUIDs referenced in content
---@param content string File content
---@return table uuids List of unique UUIDs
function M.get_referenced_uuids(content)
  local links = M.extract_all_links(content)
  local uuids = {}
  local seen = {}

  for _, link in ipairs(links) do
    if not seen[link.uuid] then
      seen[link.uuid] = true
      table.insert(uuids, link.uuid)
    end
  end

  return uuids
end

return M
