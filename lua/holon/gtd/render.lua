-- =============================================================================
-- holon/gtd/render: Panel rendering for GTD board
-- =============================================================================

local config = require("holon.config")
local utils = require("holon.utils")

local M = {}

-- =============================================================================
-- Target date helper
-- =============================================================================

--- Compute days until target date from today
---@param target_str string|nil YYYY-MM-DD format
---@return string display Display string (e.g., "-3d", "0d", "5d")
---@return string|nil hl Highlight group if special
local function days_until_target(target_str)
  if not target_str then
    return "--", nil
  end
  local y, m, d = target_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
  if not y then
    return "--", nil
  end

  local now = os.date("*t")
  local today = os.time({ year = now.year, month = now.month, day = now.day, hour = 0 })
  local due = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
  local diff = math.floor((due - today) / 86400)

  if diff < 0 then
    return string.format("%dd", diff), "HolonGtdOverdue"
  elseif diff == 0 then
    return "today", "HolonGtdOverdue"
  else
    return string.format("%dd", diff), nil
  end
end

-- =============================================================================
-- Section-based tasks panel
-- =============================================================================

-- Fixed column widths (display columns, excluding title)
local COL_NUM = 4       -- "#1  "
local COL_BLOCKED = 10  -- "#1,#2     "
local COL_ATTR = 10     -- "status    " (horizon view only)
local COL_DUE = 6       -- "-3d   "
local COL_TYPE = 16     -- "literature      "
local COL_SEP = 5       -- spaces between columns (max, without attr: 4)
local COL_FIXED_WITH_ATTR = COL_NUM + COL_BLOCKED + COL_ATTR + COL_DUE + COL_TYPE + COL_SEP
local COL_FIXED_NO_ATTR = COL_NUM + COL_BLOCKED + COL_DUE + COL_TYPE + (COL_SEP - 1)
local TITLE_MIN = 12

--- Format a single task line for the tasks panel.
--- Uses display-width-aware padding to align columns correctly with CJK text.
---@param task table Task data
---@param state table Board state
---@param title_width number Available display width for title column
---@return string line Formatted line
---@return table[] highlights Highlight segments { col_start, col_end, hl }
local function format_task_line(task, state, title_width)
  local num = state.number_map[task.filepath] or 0
  local mark = state.marked[task.filepath] and "*" or " "
  local num_str = utils.display_pad(mark .. string.format("#%d", num), COL_NUM + 1)

  -- Title (truncated + padded to exact display width)
  local title_raw = task.title or "(untitled)"
  local title = utils.display_fit(title_raw, title_width)

  -- Blocked by: progress + incomplete blocker numbers
  local blocked_raw = ""
  if task.blocked_by_total > 0 then
    local progress = string.format("[%d/%d]", task.blocked_by_done, task.blocked_by_total)
    if #task.blocked_by_numbers > 0 then
      local nums = {}
      for _, n in ipairs(task.blocked_by_numbers) do
        table.insert(nums, "#" .. n)
      end
      blocked_raw = progress .. table.concat(nums, ",")
    else
      blocked_raw = progress
    end
  end
  local blocked = utils.display_fit(blocked_raw, COL_BLOCKED)

  -- Complementary attribute (only in horizon view: show status)
  local show_attr = state.view_mode ~= "status"
  local attr
  if show_attr then
    local attr_raw = task.status or ""
    attr = utils.display_fit(attr_raw, COL_ATTR)
  end

  -- Days until target date
  local due_raw, due_hl = days_until_target(task.target_date)
  local due = utils.display_fit(due_raw, COL_DUE)

  local type_str = task.note_type or ""

  -- Build line with single-space separators
  local line = num_str .. " " .. title .. " " .. blocked
  if show_attr then
    line = line .. " " .. attr
  end
  line = line .. " " .. due .. " " .. type_str

  -- Calculate byte positions for highlights
  local hl_segments = {}
  local pos = 0

  -- Number highlight
  local num_bytes = #num_str
  table.insert(hl_segments, { col_start = pos, col_end = pos + num_bytes, hl = "Comment" })
  pos = pos + num_bytes + 1 -- +1 for separator

  -- Skip title
  local title_bytes = #title
  pos = pos + title_bytes + 1

  -- Blocked highlight
  local blocked_bytes = #blocked
  if task.blocked_by_total > 0 then
    local blocked_hl = (task.blocked_by_done == task.blocked_by_total) and "HolonGtdProgressDone" or "HolonGtdBlocked"
    table.insert(hl_segments, {
      col_start = pos,
      col_end = pos + #blocked_raw,
      hl = blocked_hl,
    })
  end
  pos = pos + blocked_bytes + 1

  -- Skip attr (only in horizon view)
  if show_attr then
    pos = pos + #attr + 1
  end

  -- Due highlight (overdue/today)
  if due_hl then
    table.insert(hl_segments, {
      col_start = pos,
      col_end = pos + #due_raw,
      hl = due_hl,
    })
  end

  return line, hl_segments
end

--- Render the section-based tasks panel
---@param buf number Buffer handle
---@param state table Board state
---@param panel_width number Available panel width in characters
function M.render_sections(buf, state, panel_width)
  local col_mark = 1 -- "*" or " " prefix
  local show_attr = state.view_mode ~= "status"
  local col_fixed = show_attr and COL_FIXED_WITH_ATTR or COL_FIXED_NO_ATTR
  local title_width = math.max(TITLE_MIN, panel_width - col_fixed - col_mark)

  local lines = {}
  local all_highlights = {}

  -- Column header line (line 1)
  local col_header = utils.display_pad(" #", COL_NUM + col_mark) .. " "
    .. utils.display_pad("Title", title_width) .. " "
    .. utils.display_pad("Blocked", COL_BLOCKED)
  if show_attr then
    col_header = col_header .. " " .. utils.display_pad("Status", COL_ATTR)
  end
  col_header = col_header .. " " .. utils.display_pad("Due", COL_DUE) .. " " .. "Type"
  table.insert(lines, col_header)
  table.insert(all_highlights, { line = 0, hl = "Comment" })

  local flat_idx = 0

  for _, section in ipairs(state.sections) do
    -- Section header line
    local header_text = string.format("-- %s (%d) ", section.label, #section.tasks)
    local dash_fill = math.max(0, panel_width - utils.strwidth(header_text))
    local header_line = header_text .. string.rep("-", dash_fill)
    table.insert(lines, header_line)

    local line_idx = #lines -- 1-based

    -- Cursor highlight (works on headers too, for empty sections)
    if line_idx == state.cursor_line then
      table.insert(all_highlights, { line = line_idx - 1, hl = "HolonGtdBoardActive" })
    end

    -- Highlight entire header as Comment
    table.insert(all_highlights, { line = line_idx - 1, hl = "Comment" })

    -- Highlight the section label with status-specific color (status view only)
    if state.view_mode == "status" then
      local icon_config = config.get("gtd.status_icons")
      local cfg = icon_config and icon_config[section.label]
      if cfg then
        local label_start = 3 -- "-- " is 3 bytes
        local label_end = label_start + #section.label
        table.insert(all_highlights, {
          line = line_idx - 1,
          col_start = label_start,
          col_end = label_end,
          hl = cfg.hl,
        })
      end
    end

    -- Task lines
    for _, task in ipairs(section.tasks) do
      flat_idx = flat_idx + 1
      local line, hl_segments = format_task_line(task, state, title_width)
      table.insert(lines, line)

      local task_line_idx = #lines

      -- Cursor highlight
      if task_line_idx == state.cursor_line then
        table.insert(all_highlights, { line = task_line_idx - 1, hl = "HolonGtdBoardActive" })
      end

      -- Per-segment highlights
      for _, seg in ipairs(hl_segments) do
        table.insert(all_highlights, {
          line = task_line_idx - 1,
          col_start = seg.col_start,
          col_end = seg.col_end,
          hl = seg.hl,
        })
      end
    end
  end

  -- Empty state fallback
  if #lines == 0 then
    lines = { "  (no tasks)" }
  end

  utils.buf_set_lines(buf, lines)

  local ns = vim.api.nvim_create_namespace("holon_gtd_tasks")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(all_highlights) do
    if hl.col_start then
      vim.api.nvim_buf_add_highlight(buf, ns, hl.hl, hl.line, hl.col_start, hl.col_end)
    else
      vim.api.nvim_buf_add_highlight(buf, ns, hl.hl, hl.line, 0, -1)
    end
  end
end

-- =============================================================================
-- Helpline
-- =============================================================================

--- Render the helpline panel
---@param buf number Buffer handle
---@param state table Board state
function M.render_helpline(buf, state)
  local scale_label = state.timeline_scale == "w" and "w/m:month" or "w/m:week"
  local help
  if state.view_mode == "inbox" then
    help = " j/k:select  C-j/k:panel  CR:open  p:promote  dd:delete  a:add  I:back  H:horizon  D:done  q:close"
  elseif state.view_mode == "done" then
    help = " j/k:select  C-j/k:panel  CR:open  r:restore  I:inbox  H:horizon  D:back  q:close"
  elseif state.view_mode == "horizon" then
    help = " j/k:select  C-j/k:panel  Tab:mark  p:move  b:block  CR:open  c:status  t:target  s:start  a:add  " .. scale_label .. "  g:preview  H:back  I:inbox  D:done  q:close"
  else
    help = " j/k:select  C-j/k:panel  Tab:mark  p:move  b:block  CR:open  c:status  t:target  s:start  a:add  " .. scale_label .. "  g:preview  H:horizon  I:inbox  D:done  q:close"
  end

  utils.buf_set_lines(buf, { help })

  local ns = vim.api.nvim_create_namespace("holon_gtd_help")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 0, 0, -1)
end

return M
