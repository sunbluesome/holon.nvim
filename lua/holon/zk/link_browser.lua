-- =============================================================================
-- holon/zk/link_browser: File-browser-style link navigator
-- =============================================================================

local config = require("holon.config")
local links = require("holon.links")
local frontmatter = require("holon.frontmatter")
local utils = require("holon.utils")

local M = {}

-- Browser instance (singleton)
local browser = nil

-- =============================================================================
-- Data collection
-- =============================================================================

--- Collect forward links from a note
---@param filepath string Note file path
---@return table[] links { { filepath, title, note_type }, ... }
local function collect_forward_links(filepath)
  local content = utils.read_file(filepath)
  if not content then
    return {}
  end

  local raw_links = links.extract_all_links(content)
  local result = {}
  local seen = {}

  for _, link in ipairs(raw_links) do
    local target = links.resolve_link_target(link.uuid, filepath)
    if target and not seen[target] then
      seen[target] = true
      local fm = frontmatter.parse_file(target)
      local title = fm and frontmatter.get_title(fm) or vim.fn.fnamemodify(target, ":t:r")
      local note_type = fm and frontmatter.get_type(fm) or ""
      table.insert(result, { filepath = target, title = title, note_type = note_type })
    end
  end

  return result
end

--- Collect backlinks to a note
---@param filepath string Note file path
---@return table[] links { { filepath, title, note_type }, ... }
local function collect_backlinks(filepath)
  local uuid = utils.extract_uuid_from_path(filepath)
  if not uuid then
    return {}
  end

  local backlink_paths = links.find_backlinks(uuid)
  local result = {}

  for _, bp in ipairs(backlink_paths) do
    local fm = frontmatter.parse_file(bp)
    local title = fm and frontmatter.get_title(fm) or vim.fn.fnamemodify(bp, ":t:r")
    local note_type = fm and frontmatter.get_type(fm) or ""
    table.insert(result, { filepath = bp, title = title, note_type = note_type })
  end

  -- Sort by title
  table.sort(result, function(a, b)
    return (a.title or "") < (b.title or "")
  end)

  return result
end

--- Collect notes sharing tags with the current note
---@param filepath string Note file path
---@return table[] links { { filepath, title, note_type, tag }, ... }
---@return string[] tags Tags of the current note
local function collect_tag_notes(filepath)
  local finders = require("holon.zk.finders")
  local fm = frontmatter.parse_file(filepath)
  local tags = fm and frontmatter.get_tags(fm) or {}
  if #tags == 0 then
    return {}, {}
  end

  local files = finders.find_notes()

  local result = {}
  local by_path = {} -- filepath -> result index
  local seen_self = { [filepath] = true }

  for _, fp in ipairs(files) do
    if not seen_self[fp] then
      local f = frontmatter.parse_file(fp)
      local file_tags = f and frontmatter.get_tags(f) or {}
      local matched = {}
      for _, tag in ipairs(tags) do
        if vim.tbl_contains(file_tags, tag) then
          table.insert(matched, tag)
        end
      end
      if #matched > 0 then
        local title = f and frontmatter.get_title(f) or vim.fn.fnamemodify(fp, ":t:r")
        local note_type = f and frontmatter.get_type(f) or ""
        table.insert(result, { filepath = fp, title = title, note_type = note_type, matched_tags = matched })
      end
    end
  end

  return result, tags
end

-- =============================================================================
-- Rendering
-- =============================================================================

--- Render the link list into the buffer
local function render_list()
  if not browser then return end

  local b = browser
  local state = b.state

  -- Get current note title
  local fm = frontmatter.parse_file(state.current_filepath)
  local current_title = fm and frontmatter.get_title(fm) or vim.fn.fnamemodify(state.current_filepath, ":t:r")

  -- Collect links
  if state.mode == "forward" then
    state.links = collect_forward_links(state.current_filepath)
  elseif state.mode == "tags" then
    local tag_notes, tags = collect_tag_notes(state.current_filepath)
    state.links = tag_notes
    state.current_tags = tags
  else
    state.links = collect_backlinks(state.current_filepath)
  end

  -- Build display lines
  local lines = {}
  local type_col_w = 12
  local title_w = math.max(20, b.list_width - type_col_w - 3)

  for _, link in ipairs(state.links) do
    local title = utils.display_truncate(link.title, title_w)
    title = utils.display_pad(title, title_w)
    local bracket
    if state.mode == "tags" and link.matched_tags then
      local first = link.matched_tags[1] or ""
      local rest = #link.matched_tags - 1
      bracket = rest > 0 and ("[" .. first .. " +" .. rest .. "]") or ("[" .. first .. "]")
    else
      bracket = link.note_type ~= "" and ("[" .. link.note_type .. "]") or ""
    end
    table.insert(lines, " " .. title .. " " .. bracket)
  end

  if #lines == 0 then
    local labels = { forward = "forward links", backlinks = "backlinks", tags = "shared tags" }
    table.insert(lines, "  (no " .. (labels[state.mode] or state.mode) .. ")")
  end

  -- Write to buffer
  utils.buf_set_lines(b.bufs.list, lines)

  -- Highlights
  local ns = vim.api.nvim_create_namespace("holon_link_browser")
  vim.api.nvim_buf_clear_namespace(b.bufs.list, ns, 0, -1)

  for i, link in ipairs(state.links) do
    if link.note_type ~= "" then
      -- Highlight type tag
      local line_text = lines[i]
      local bracket_start = line_text:find("%[")
      if bracket_start then
        vim.api.nvim_buf_add_highlight(b.bufs.list, ns, "Comment", i - 1, bracket_start - 1, #line_text)
      end
    end
  end

  -- Update window title
  local mode_labels = { backlinks = "Backlinks", forward = "Forward", tags = "Tags" }
  local mode_label = mode_labels[state.mode] or state.mode
  local count = #state.links
  local title = string.format(" %s: %s (%d) ", mode_label, utils.display_truncate(current_title, 30), count)
  vim.api.nvim_win_set_config(b.wins.list, { title = title, title_pos = "center" })

  -- Restore cursor
  local cursor = math.max(1, math.min(state.cursor_line, #lines))
  state.cursor_line = cursor
  if vim.api.nvim_win_is_valid(b.wins.list) then
    vim.api.nvim_win_set_cursor(b.wins.list, { cursor, 0 })
  end
end

--- Render preview for the currently selected link
local function render_preview()
  if not browser then return end

  local b = browser
  local state = b.state
  local link = state.links[state.cursor_line]
  local lines = {}

  if link then
    local content = utils.read_file(link.filepath)
    if content then
      lines = vim.split(content, "\n", { plain = true })
    end
  end

  if #lines == 0 then
    lines = { "  (no preview)" }
  end

  utils.buf_set_lines(b.bufs.preview, lines)
end

--- Render helpline
local function render_helpline()
  if not browser then return end

  local b = browser
  local depth = #b.state.history
  local back_label = depth > 0 and "-:back(" .. depth .. ")" or ""
  local help = " j/k:select  b:backlinks  f:forward  t:tags  CR:dive  " .. back_label .. "  o:open  l:link  q:close"

  utils.buf_set_lines(b.bufs.helpline, { help })

  local ns = vim.api.nvim_create_namespace("holon_link_browser_help")
  vim.api.nvim_buf_clear_namespace(b.bufs.helpline, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(b.bufs.helpline, ns, "Comment", 0, 0, -1)
end

--- Render all panels
local function render_all()
  if not browser then return end
  render_list()
  render_preview()
  render_helpline()
end

-- =============================================================================
-- Navigation
-- =============================================================================

--- Move cursor up/down
local function move_cursor(dir)
  if not browser then return end
  local state = browser.state
  local new_line = state.cursor_line + dir
  if new_line < 1 then new_line = 1 end
  if new_line > #state.links then new_line = #state.links end
  if new_line < 1 then return end

  state.cursor_line = new_line
  vim.api.nvim_win_set_cursor(browser.wins.list, { new_line, 0 })
  render_preview()
  render_helpline()
end

--- Dive into selected note
local function dive()
  if not browser then return end
  local state = browser.state
  local link = state.links[state.cursor_line]
  if not link then return end

  -- Push current state to history
  table.insert(state.history, {
    filepath = state.current_filepath,
    mode = state.mode,
    cursor_line = state.cursor_line,
  })

  -- Navigate to selected note
  state.current_filepath = link.filepath
  state.cursor_line = 1
  render_all()
end

--- Go back in history
local function go_back()
  if not browser then return end
  local state = browser.state
  if #state.history == 0 then return end

  local prev = table.remove(state.history)
  state.current_filepath = prev.filepath
  state.mode = prev.mode
  state.cursor_line = prev.cursor_line
  render_all()
end

--- Switch to a specific mode
local function switch_mode(mode)
  if not browser then return end
  local state = browser.state
  if state.mode == mode then return end
  state.mode = mode
  state.cursor_line = 1
  render_all()
end

--- Open selected note in editor
local function open_note()
  if not browser then return end
  local state = browser.state
  local link = state.links[state.cursor_line]
  if not link then return end

  M.close()
  vim.cmd("edit " .. vim.fn.fnameescape(link.filepath))
end

-- =============================================================================
-- Layout
-- =============================================================================

--- Open the Link Browser
---@param filepath string|nil Starting file path (default: current buffer)
function M.open(filepath)
  if browser then
    M.close()
  end

  filepath = filepath or vim.fn.expand("%:p")
  if filepath == "" or not utils.read_file(filepath) then
    utils.notify("No note to browse", "warn")
    return
  end

  -- Layout dimensions
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines
  local total_w = math.floor(editor_w * 0.85)
  local total_h = math.floor(editor_h * 0.75)
  local row = math.floor((editor_h - total_h) / 2)
  local col = math.floor((editor_w - total_w) / 2)

  local list_w = math.floor(total_w * 0.45)
  local preview_w = total_w - list_w - 2
  local panel_h = total_h - 3 -- room for helpline

  local b = {
    state = {
      history = {},
      current_filepath = filepath,
      mode = "backlinks",
      links = {},
      cursor_line = 1,
    },
    bufs = {},
    wins = {},
    list_width = list_w,
  }

  -- List panel (left)
  b.bufs.list = utils.create_scratch_buf("browse-list")
  b.wins.list = vim.api.nvim_open_win(b.bufs.list, true, {
    relative = "editor",
    row = row,
    col = col,
    width = list_w,
    height = panel_h,
    style = "minimal",
    border = "rounded",
    title = " Link Browser ",
    title_pos = "center",
  })
  vim.wo[b.wins.list].cursorline = true
  vim.wo[b.wins.list].wrap = false

  -- Preview panel (right)
  b.bufs.preview = utils.create_scratch_buf("browse-preview")
  b.wins.preview = vim.api.nvim_open_win(b.bufs.preview, false, {
    relative = "editor",
    row = row,
    col = col + list_w + 2,
    width = preview_w,
    height = panel_h,
    style = "minimal",
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
  })
  vim.wo[b.wins.preview].cursorline = false
  vim.wo[b.wins.preview].wrap = true
  vim.bo[b.bufs.preview].filetype = "markdown"

  -- Helpline (bottom)
  b.bufs.helpline = utils.create_scratch_buf("browse-helpline")
  b.wins.helpline = vim.api.nvim_open_win(b.bufs.helpline, false, {
    relative = "editor",
    row = row + panel_h + 2,
    col = col,
    width = total_w,
    height = 1,
    style = "minimal",
    border = "none",
  })

  browser = b

  -- Keymaps on list buffer
  local opts = { noremap = true, silent = true, buffer = b.bufs.list }

  vim.keymap.set("n", "j", function() move_cursor(1) end, opts)
  vim.keymap.set("n", "k", function() move_cursor(-1) end, opts)
  vim.keymap.set("n", "<CR>", function() dive() end, opts)
  vim.keymap.set("n", "-", function() go_back() end, opts)
  vim.keymap.set("n", "<BS>", function() go_back() end, opts)
  vim.keymap.set("n", "b", function() switch_mode("backlinks") end, opts)
  vim.keymap.set("n", "f", function() switch_mode("forward") end, opts)
  vim.keymap.set("n", "t", function() switch_mode("tags") end, opts)
  vim.keymap.set("n", "o", function() open_note() end, opts)
  vim.keymap.set("n", "l", function()
    M.close()
    vim.schedule(function()
      require("holon.zk.pickers").insert_link_picker()
    end)
  end, opts)
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, opts)

  -- Page scroll
  vim.keymap.set("n", "<C-d>", "<C-d>", opts)
  vim.keymap.set("n", "<C-u>", "<C-u>", opts)

  utils.block_wincmds(b.bufs.list)
  utils.block_wincmds(b.bufs.preview)
  utils.block_wincmds(b.bufs.helpline)

  render_all()
end

--- Close the Link Browser
function M.close()
  if not browser then return end

  utils.close_float_wins(browser.wins)

  browser = nil
end

return M
