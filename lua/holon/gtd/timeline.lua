-- =============================================================================
-- holon/gtd/timeline: ASCII timeline for GTD board
-- =============================================================================

local utils = require("holon.utils")

local M = {}

--- Scale definitions: past days shown before today
local SCALE_PAST = {
  w = 7,  -- 7 days before today
  m = 30, -- 30 days before today
}

--- Compute the visible range: start from (today - past_days), extend to fill panel width
---@param scale string "w" or "m"
---@param day_count number Total columns (= panel width in chars)
---@return number range_start os.time
local function compute_range(scale, day_count)
  local today = utils.today_midnight()
  local past = SCALE_PAST[scale] or SCALE_PAST.w
  -- If panel is very narrow, ensure at least past days fit
  if past >= day_count then
    past = math.floor(day_count / 3)
  end
  return today - past * 86400
end

--- Build a line string from a row array and compute byte offset map.
---@param row string[] Array of single-display-width strings
---@param max_cols number Max columns to include
---@return string line Concatenated string
---@return number[] byte_offsets byte_offsets[col] = byte offset (1-based col), sentinel at [n+1]
local function build_line(row, max_cols)
  local n = math.min(#row, max_cols)
  local parts = {}
  local byte_offsets = {}
  local pos = 0
  for i = 1, n do
    byte_offsets[i] = pos
    parts[i] = row[i]
    pos = pos + #row[i]
  end
  byte_offsets[n + 1] = pos
  return table.concat(parts, ""), byte_offsets
end

--- Right-pad a string to width display columns
---@param str string
---@param width number Target display width
---@return string padded
local function rpad(str, width)
  local dw = vim.fn.strdisplaywidth(str)
  if dw >= width then
    return str
  end
  return str .. string.rep(" ", width - dw)
end

-- =============================================================================
-- Section-aligned timeline rendering
-- =============================================================================

--- Render timeline aligned with GTD board sections.
--- Output lines correspond 1:1 with board render output:
---   line 0 = date header (matches column header)
---   section header lines = today marker only
---   task lines = gantt bars + target date label
--- Blocked tasks (incomplete blockers) are rendered with ▒ and HolonGtdBlocked highlight.
--- Bars outside the visible range are clipped (not drawn).
---@param state table Board state (with sections, timeline_scale)
---@param width number Available panel width
---@return string[] lines Rendered lines
---@return table[] highlights Highlight data { line, col_start, col_end, hl }
function M.render_aligned(state, width)
  local scale = state.timeline_scale or "w"
  local today = utils.today_midnight()

  -- Layout: 1 column = 1 day, panel width determines how many days are visible
  local DUE_LABEL_W = 7
  local day_count = math.max(10, width - DUE_LABEL_W)
  local range_start = compute_range(scale, day_count)

  -- 1 col = 1 day (direct mapping)
  local function day_to_col(day_offset)
    return day_offset + 1 -- 1-based
  end

  local today_offset = math.floor((today - range_start) / 86400)
  local today_col = day_to_col(today_offset)

  local lines = {}
  local highlights = {}
  local line_idx = 0

  -- Helper: create empty gantt row
  local function empty_gantt_row()
    local row = {}
    for c = 1, day_count do
      row[c] = " "
    end
    return row
  end

  -- Helper: set today marker on a gantt row
  local function set_today_marker(row)
    if today_col >= 1 and today_col <= day_count then
      row[today_col] = "|"
    end
  end

  -- Helper: register today marker highlight
  local function register_today_hl(li, gantt_bo)
    if today_col >= 1 and today_col <= day_count and gantt_bo[today_col] then
      table.insert(highlights, {
        line = li,
        col_start = gantt_bo[today_col],
        col_end = gantt_bo[today_col + 1] or (gantt_bo[today_col] + 1),
        hl = "HolonGtdTimelineToday",
      })
    end
  end

  -- =========================================================================
  -- Line 0: Date header
  -- =========================================================================
  local header = empty_gantt_row()

  -- Place date labels at regular intervals
  local label_w = 5 -- "MM/DD"
  local label_interval = math.max(label_w + 2, math.floor(day_count / 6))

  for d = 0, day_count - 1, label_interval do
    local col = day_to_col(d)
    local dt = range_start + d * 86400
    local label = os.date("%m/%d", dt)
    -- Skip if label doesn't fully fit within visible range
    if col + #label - 1 <= day_count then
      for ci = 1, #label do
        header[col + ci - 1] = label:sub(ci, ci)
      end
    end
  end

  local header_str = build_line(header, day_count)
  table.insert(lines, rpad(header_str, width))

  table.insert(highlights, { line = 0, col_start = 0, col_end = -1, hl = "HolonGtdTimeline" })
  line_idx = line_idx + 1

  -- =========================================================================
  -- Section rows (aligned with board sections)
  -- =========================================================================
  for _, section in ipairs(state.sections) do
    -- Section header -> dashed separator with today marker
    local row = {}
    for c = 1, day_count do
      row[c] = "-"
    end
    set_today_marker(row)

    local gantt_str, gantt_bo = build_line(row, day_count)

    register_today_hl(line_idx, gantt_bo)
    table.insert(highlights, { line = line_idx, col_start = 0, col_end = -1, hl = "Comment" })

    table.insert(lines, rpad(gantt_str, width))
    line_idx = line_idx + 1

    -- Task lines
    for _, task in ipairs(section.tasks) do
      row = empty_gantt_row()
      set_today_marker(row)

      local sched = utils.parse_date(task.start_date)
      local due = utils.parse_date(task.target_date)
      local due_label = ""
      local is_overdue = false
      local is_blocked = task.blocked_by_numbers and #task.blocked_by_numbers > 0

      if due then
        due_label = os.date("%m/%d", due)
        is_overdue = due < today
      elseif not sched then
        due_label = "--"
      end

      local bar_start_col, bar_end_col
      local is_inverted = sched and due and sched > due
      if sched or due then
        local bar_start_day, bar_end_day

        if sched and due then
          -- Use chronological order for bar rendering (min..max)
          local d1 = math.floor((math.min(sched, due) - range_start) / 86400)
          local d2 = math.floor((math.max(sched, due) - range_start) / 86400)
          bar_start_day = d1
          bar_end_day = d2
        elseif sched then
          bar_start_day = math.floor((sched - range_start) / 86400)
          bar_end_day = bar_start_day + 7
        else -- due only
          if is_overdue then
            bar_start_day = math.floor((due - range_start) / 86400)
          else
            bar_start_day = today_offset
          end
          bar_end_day = math.floor((due - range_start) / 86400)
        end

        -- Clip to visible range; skip entirely if outside
        bar_start_col = day_to_col(bar_start_day)
        bar_end_col = day_to_col(bar_end_day)

        -- Entirely outside visible range -> don't draw
        if bar_end_col < 1 or bar_start_col > day_count then
          bar_start_col = nil
          bar_end_col = nil
        else
          -- Clip to visible bounds
          bar_start_col = math.max(1, bar_start_col)
          bar_end_col = math.min(day_count, bar_end_col)
          if bar_end_col < bar_start_col then
            bar_end_col = bar_start_col
          end

          for c = bar_start_col, bar_end_col do
            if is_inverted then
              row[c] = "!" -- date inversion indicator
            elseif is_blocked then
              row[c] = "\xe2\x96\x92" -- U+2592 ▒ (blocked)
            elseif is_overdue then
              row[c] = "\xe2\x96\x88" -- U+2588 █ (all overdue)
            elseif c < today_col then
              row[c] = "\xe2\x96\x88" -- U+2588 █ (past)
            else
              row[c] = "\xe2\x96\x91" -- U+2591 ░ (future/today)
            end
          end
        end
      end

      -- Build line
      local task_str, task_bo = build_line(row, day_count)

      -- Bar highlight
      if bar_start_col and bar_end_col then
        local hl
        if is_inverted then
          hl = "HolonGtdOverdue"
        elseif is_blocked then
          hl = "HolonGtdBlocked"
        elseif is_overdue then
          hl = "HolonGtdOverdue"
        else
          hl = "HolonGtdTimelineBar"
        end
        table.insert(highlights, {
          line = line_idx,
          col_start = task_bo[bar_start_col],
          col_end = task_bo[bar_end_col + 1],
          hl = hl,
        })
      end

      -- Today marker highlight
      register_today_hl(line_idx, task_bo)

      -- Combine: gantt (padded to chart area) + due label
      local chart_w = math.max(10, width - DUE_LABEL_W)
      task_str = rpad(task_str, chart_w)
      local full_task_line = task_str .. " " .. due_label
      table.insert(lines, rpad(full_task_line, width))
      line_idx = line_idx + 1
    end
  end

  if #lines <= 1 then
    table.insert(lines, rpad("  (no tasks)", width))
  end

  return lines, highlights
end

return M
