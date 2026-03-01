-- =============================================================================
-- holon/gtd/calendar: Floating calendar date picker
-- =============================================================================

local M = {}

--- Get days in a month
---@param year number
---@param month number
---@return number
local function days_in_month(year, month)
  -- Day 0 of next month = last day of this month
  return os.date("*t", os.time({ year = year, month = month + 1, day = 0 })).day
end

--- Get weekday of first day (1=Mon, 7=Sun)
---@param year number
---@param month number
---@return number
local function first_weekday(year, month)
  local wday = os.date("*t", os.time({ year = year, month = month, day = 1 })).wday
  -- os.date wday: 1=Sun..7=Sat -> convert to 1=Mon..7=Sun
  return (wday - 2) % 7 + 1
end

--- Build calendar lines and cell map
---@param year number
---@param month number
---@return string[] lines
---@return table cell_map { [line_idx] = { [col_start] = day } } (0-based line)
local function build_calendar(year, month)
  local month_names = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  }

  local lines = {}
  local cell_map = {}

  -- Title line
  local title = string.format("%s %d", month_names[month], year)
  local padding = math.floor((20 - #title) / 2)
  table.insert(lines, string.rep(" ", padding) .. title)

  -- Header line
  table.insert(lines, " Mo Tu We Th Fr Sa Su")

  local dim = days_in_month(year, month)
  local start_wday = first_weekday(year, month)

  local day = 1
  while day <= dim do
    local row = {}
    local row_cells = {}
    for col = 1, 7 do
      if (day == 1 and col < start_wday) or day > dim then
        table.insert(row, "   ")
      else
        local cell = string.format("%3d", day)
        table.insert(row, cell)
        -- byte offset: each cell is 3 chars, 0-based col position
        row_cells[(col - 1) * 3] = day
        day = day + 1
      end
    end
    local line_idx = #lines
    table.insert(lines, table.concat(row, ""))
    cell_map[line_idx] = row_cells
  end

  -- Help line
  table.insert(lines, "")
  table.insert(lines, " h/l:day j/k:week")
  table.insert(lines, " H/L:month t:today")
  table.insert(lines, " CR:ok x:clear q:cancel")

  return lines, cell_map
end

--- Find the line and column for a given day
---@param cell_map table
---@param day number
---@return number line 0-based
---@return number col byte offset
local function find_day_position(cell_map, day)
  for line, cells in pairs(cell_map) do
    for col, d in pairs(cells) do
      if d == day then
        return line, col
      end
    end
  end
  return 2, 0
end

--- Open a calendar picker and call callback with selected date
---@param opts table { default: string|nil "YYYY-MM-DD", title: string|nil }
---@param callback fun(date: string|nil) Called with "YYYY-MM-DD" or nil if cancelled
function M.open(opts, callback)
  opts = opts or {}

  -- Parse default date or use today
  local now = os.date("*t")
  local cur_year, cur_month, cur_day = now.year, now.month, now.day

  if opts.default and opts.default:match("^%d%d%d%d%-%d%d%-%d%d$") then
    local y, m, d = opts.default:match("^(%d+)-(%d+)-(%d+)$")
    cur_year, cur_month, cur_day = tonumber(y), tonumber(m), tonumber(d)
  end

  local today_year, today_month, today_day = now.year, now.month, now.day
  local selected_day = cur_day

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local win = nil
  local cell_map = {}
  local ns = vim.api.nvim_create_namespace("holon_calendar")

  local function render()
    local lines
    lines, cell_map = build_calendar(cur_year, cur_month)

    -- Clamp selected_day
    local dim = days_in_month(cur_year, cur_month)
    if selected_day > dim then
      selected_day = dim
    end
    if selected_day < 1 then
      selected_day = 1
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Highlights
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

    -- Title highlight
    vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, -1)
    -- Header highlight
    vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 1, 0, -1)

    -- Today highlight
    if cur_year == today_year and cur_month == today_month then
      local tl, tc = find_day_position(cell_map, today_day)
      vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticWarn", tl, tc, tc + 3)
    end

    -- Selected day highlight
    local sl, sc = find_day_position(cell_map, selected_day)
    vim.api.nvim_buf_add_highlight(buf, ns, "CursorLine", sl, sc, sc + 3)

    -- Help line highlights
    for li = #lines - 3, #lines - 1 do
      vim.api.nvim_buf_add_highlight(buf, ns, "Comment", li, 0, -1)
    end

    -- Update window title
    if win and vim.api.nvim_win_is_valid(win) then
      local title = opts.title or "Date"
      local date_str = string.format("%04d-%02d-%02d", cur_year, cur_month, selected_day)
      vim.api.nvim_win_set_config(win, {
        title = " " .. title .. ": " .. date_str .. " ",
        title_pos = "center",
      })
    end
  end

  -- Open floating window
  -- Max height: title(1) + header(1) + 6 weeks + empty(1) + help(3) = 12
  local width = 23
  local height = 12
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines
  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((editor_h - height) / 2),
    col = math.floor((editor_w - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Date ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = false

  render()

  -- Keymaps
  local map_opts = { noremap = true, silent = true, buffer = buf }

  local function close(result)
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    callback(result)
  end

  -- Day navigation
  vim.keymap.set("n", "l", function()
    local dim = days_in_month(cur_year, cur_month)
    if selected_day < dim then
      selected_day = selected_day + 1
    end
    render()
  end, map_opts)

  vim.keymap.set("n", "h", function()
    if selected_day > 1 then
      selected_day = selected_day - 1
    end
    render()
  end, map_opts)

  -- Week navigation
  vim.keymap.set("n", "j", function()
    local dim = days_in_month(cur_year, cur_month)
    selected_day = math.min(selected_day + 7, dim)
    render()
  end, map_opts)

  vim.keymap.set("n", "k", function()
    selected_day = math.max(selected_day - 7, 1)
    render()
  end, map_opts)

  -- Month navigation
  vim.keymap.set("n", "L", function()
    cur_month = cur_month + 1
    if cur_month > 12 then
      cur_month = 1
      cur_year = cur_year + 1
    end
    render()
  end, map_opts)

  vim.keymap.set("n", "H", function()
    cur_month = cur_month - 1
    if cur_month < 1 then
      cur_month = 12
      cur_year = cur_year - 1
    end
    render()
  end, map_opts)

  -- Jump to today
  vim.keymap.set("n", "t", function()
    cur_year, cur_month, selected_day = today_year, today_month, today_day
    render()
  end, map_opts)

  -- Clear date
  vim.keymap.set("n", "x", function()
    close(nil)
  end, map_opts)

  -- Select
  vim.keymap.set("n", "<CR>", function()
    local date_str = string.format("%04d-%02d-%02d", cur_year, cur_month, selected_day)
    close(date_str)
  end, map_opts)

  -- Cancel
  vim.keymap.set("n", "q", function()
    close(false)
  end, map_opts)
  vim.keymap.set("n", "<Esc>", function()
    close(false)
  end, map_opts)
end

return M
