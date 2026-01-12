-- =============================================================================
-- loam/actions: Custom actions for telescope-loam
-- =============================================================================

local config = require("loam.config")
local utils = require("loam.utils")
local frontmatter = require("loam.frontmatter")
local links = require("loam.links")

local M = {}

--- Create a new note from template
---@param template_path string Path to template file
---@param title string|nil Note title (uses UUID if nil)
---@return string|nil filepath Path to created note or nil on error
function M.create_note(template_path, title)
  -- Read template
  local template_content = utils.read_file(template_path)
  if not template_content then
    utils.notify("Failed to read template: " .. template_path, "error")
    return nil
  end

  -- Generate template variables
  local vars = utils.get_template_vars()
  local uuid = vars.UUID

  -- Set title (use UUID if not provided)
  if title and title ~= "" then
    -- Replace title in template
    template_content = template_content:gsub("title: %${UUID}", "title: " .. title)
  end

  -- Substitute all template variables
  local content = utils.substitute_template_vars(template_content, vars)

  -- Determine note type from template frontmatter
  local fm = frontmatter.parse(content)
  local note_type = frontmatter.get_type(fm) or "permanent"

  -- Get target directory
  local target_dir = config.get_directory(note_type)
  local extension = config.get("extension")

  -- Ensure directory exists
  if not utils.ensure_dir(target_dir) then
    utils.notify("Failed to create directory: " .. target_dir, "error")
    return nil
  end

  -- Create file path
  local filepath = target_dir .. "/" .. uuid .. extension

  -- Write file
  if not utils.write_file(filepath, content) then
    utils.notify("Failed to create note: " .. filepath, "error")
    return nil
  end

  utils.notify("Created note: " .. (title or uuid), "info")
  return filepath
end

--- Insert link to a note at cursor position
---@param uuid string Note UUID
---@param display_text string Display text for link
---@param format string|nil Link format ("wiki" or "markdown")
function M.insert_link(uuid, display_text, format)
  local link = links.generate_link(uuid, display_text, format)

  -- Get current cursor position
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Insert link at cursor
  local new_line = line:sub(1, col) .. link .. line:sub(col + 1)
  vim.api.nvim_set_current_line(new_line)

  -- Move cursor to end of inserted link
  vim.api.nvim_win_set_cursor(0, { row, col + #link })
end

--- Insert link to selected note from picker
---@param prompt_bufnr number Telescope prompt buffer
function M.insert_link_from_picker(prompt_bufnr)
  local action_state = require("telescope.actions.state")
  local actions = require("telescope.actions")

  local selection = action_state.get_selected_entry()
  if not selection then
    return
  end

  actions.close(prompt_bufnr)

  -- Restore original buffer
  vim.schedule(function()
    if selection.uuid and selection.title then
      M.insert_link(selection.uuid, selection.title)
    end
  end)
end

--- Create today's journal entry
---@return string|nil filepath Path to journal entry
function M.create_journal_entry()
  local today = os.date("%Y-%m-%d")
  local journal_dir = config.get("notes_path") .. "/" .. config.get("directories").journal
  local filepath = journal_dir .. "/" .. today .. ".md"

  if utils.file_exists(filepath) then
    return filepath
  end

  -- Ensure directory exists
  if not utils.ensure_dir(journal_dir) then
    utils.notify("Failed to create journal directory", "error")
    return nil
  end

  -- Create journal entry with basic template
  local content = string.format([[---
title: %s
created: %s
lastmod: %s
type: journal
tags: []
---

# %s

]], today, utils.iso_timestamp(), utils.iso_timestamp(), today)

  if not utils.write_file(filepath, content) then
    utils.notify("Failed to create journal entry", "error")
    return nil
  end

  utils.notify("Created journal entry: " .. today, "info")
  return filepath
end

--- Open note by UUID
---@param uuid string Note UUID
---@return boolean success
function M.open_by_uuid(uuid)
  local filepath = links.resolve_uuid(uuid)
  if not filepath then
    utils.notify("Note not found: " .. uuid, "warn")
    return false
  end

  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  return true
end

--- Follow link under cursor
---@param silent boolean|nil If true, don't notify when no link found
---@return boolean success
function M.follow_link_under_cursor(silent)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- Try to find wiki-style link [[UUID|title]] or [[UUID]]
  local start_pos = 1
  while true do
    local link_start, link_end, uuid = line:find("%[%[([a-f0-9%-]+)", start_pos)
    if not link_start then
      break
    end
    -- Find the end of the link ]]
    local close_pos = line:find("%]%]", link_start)
    if close_pos and col >= link_start - 1 and col <= close_pos + 1 then
      return M.open_by_uuid(uuid)
    end
    start_pos = link_end + 1
  end

  -- Try to find markdown link [title](UUID.md)
  start_pos = 1
  while true do
    local link_start = line:find("%[", start_pos)
    if not link_start then
      break
    end
    local link_end, _, uuid = line:find("%]%(([a-f0-9%-]+)%.md%)", link_start)
    if link_end then
      local close_pos = line:find("%)", link_end)
      if close_pos and col >= link_start - 1 and col <= close_pos then
        return M.open_by_uuid(uuid)
      end
    end
    start_pos = link_start + 1
  end

  if not silent then
    utils.notify("No link found under cursor", "warn")
  end
  return false
end

--- Smart gd: follow link if on a link, otherwise fallback to original gd
---@return nil
function M.smart_gd()
  -- Try to follow link first
  if M.follow_link_under_cursor(true) then
    return
  end

  -- Fallback to original gd behavior (LSP go to definition)
  local ok, _ = pcall(vim.lsp.buf.definition)
  if not ok then
    -- If LSP not available, use normal gd
    vim.cmd("normal! gd")
  end
end

--- Get backlinks for current buffer
---@return table backlinks List of filepaths
function M.get_current_backlinks()
  local current_file = vim.fn.expand("%:p")
  local uuid = utils.extract_uuid_from_path(current_file)

  if not uuid then
    return {}
  end

  return links.find_backlinks(uuid)
end

--- Update lastmod in current buffer's frontmatter
function M.update_lastmod()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Check if file has frontmatter
  if not content:match("^%-%-%-\n") then
    return
  end

  local timestamp = utils.iso_timestamp()
  local updated = false

  for i, line in ipairs(lines) do
    if line:match("^lastmod:") then
      lines[i] = "lastmod: " .. timestamp
      updated = true
      break
    end
  end

  if updated then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end
end

return M
