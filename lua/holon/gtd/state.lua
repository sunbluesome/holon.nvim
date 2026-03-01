-- =============================================================================
-- holon/gtd/state: Board state management for GTD board
-- =============================================================================

local config = require("holon.config")
local finders = require("holon.gtd.finders")
local links = require("holon.links")

local M = {}

--- Horizon labels in display order
local HORIZON_ORDER = { "overdue", "today", "1w", "2w", "1m", "2m", "later", "no_target" }

--- Create a new board state
---@return table state Board state object
function M.new()
  return {
    -- View mode
    view_mode = "status", -- "status" | "horizon"

    -- Cursor position (1-based buffer line; line 1 = column header, skip it)
    cursor_line = 2,

    -- Data
    all_tasks = {},    -- All tasks with metadata
    sections = {},     -- { { label="inbox", tasks={...} }, ... }
    flat_tasks = {},   -- Flattened task list across all sections

    -- Line info (built by build_sections, used by render and navigation)
    -- line_info[line] = { type="header", label="inbox" } or { type="task", flat_idx=N }
    line_info = {},
    total_lines = 0,

    -- Runtime number maps
    number_map = {},   -- filepath -> runtime number
    reverse_map = {},  -- runtime number -> filepath

    -- Marked tasks for put / blocked_by
    marked = {},       -- filepath -> true

    -- Display options
    timeline_scale = "w", -- "w" (week: ±7d) | "m" (month: ±30d)
  }
end

--- Sort tasks: status order -> target date -> title
---@param tasks table[] Task list
local function sort_tasks(tasks)
  local gtd_statuses = config.get("gtd.statuses")
  local status_order = {}
  for i, s in ipairs(gtd_statuses) do
    status_order[s] = i
  end

  table.sort(tasks, function(a, b)
    local sa = status_order[a.status] or 99
    local sb = status_order[b.status] or 99
    if sa ~= sb then
      return sa < sb
    end

    -- Tasks with target dates come before those without
    if a.target_date and not b.target_date then
      return true
    end
    if not a.target_date and b.target_date then
      return false
    end
    if a.target_date and b.target_date and a.target_date ~= b.target_date then
      return a.target_date < b.target_date
    end

    return (a.title or "") < (b.title or "")
  end)
end

--- Assign runtime numbers to all tasks
---@param state table Board state
local function assign_numbers(state)
  state.number_map = {}
  state.reverse_map = {}
  for i, task in ipairs(state.all_tasks) do
    state.number_map[task.filepath] = i
    state.reverse_map[i] = task.filepath
  end
end

--- Resolve blocked_by references to runtime numbers (only incomplete blockers)
---@param state table Board state
local function resolve_blocked_by(state)
  -- Build lookup maps: filepath -> task, uuid -> filepath
  local task_by_path = {}
  local uuid_to_path = {}
  for _, t in ipairs(state.all_tasks) do
    task_by_path[t.filepath] = t
    local uuid = vim.fn.fnamemodify(t.filepath, ":t:r")
    if uuid then
      uuid_to_path[uuid] = t.filepath
    end
  end

  for _, task in ipairs(state.all_tasks) do
    task.blocked_by_numbers = {}
    task.blocked_by_total = 0
    task.blocked_by_done = 0
    for _, ref in ipairs(task.blocked_by) do
      local target = ref:match("^%[%[([^%]|]+)") or ref
      target = target:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.md$", "")

      local resolved = uuid_to_path[target]
      if not resolved then
        resolved = links.resolve_link_target(target, task.filepath)
      end

      if resolved and state.number_map[resolved] then
        local blocker = task_by_path[resolved]
        if blocker then
          task.blocked_by_total = task.blocked_by_total + 1
          if blocker.status == "done" then
            task.blocked_by_done = task.blocked_by_done + 1
          else
            table.insert(task.blocked_by_numbers, state.number_map[resolved])
          end
        end
      end
    end
    table.sort(task.blocked_by_numbers)
  end
end

--- Build sections from all_tasks based on view_mode, and compute line_info
---@param state table Board state
function M.build_sections(state)
  state.sections = {}
  state.flat_tasks = {}

  if state.view_mode == "status" then
    local gtd_statuses = config.get("gtd.statuses")
    for _, status in ipairs(gtd_statuses) do
      if status == "done" or status == "inbox" then
        goto continue
      end
      local section = { label = status, tasks = {} }
      for _, task in ipairs(state.all_tasks) do
        if task.status == status then
          table.insert(section.tasks, task)
        end
      end
      table.insert(state.sections, section)
      for _, task in ipairs(section.tasks) do
        table.insert(state.flat_tasks, task)
      end
      ::continue::
    end
  elseif state.view_mode == "horizon" then
    for _, horizon in ipairs(HORIZON_ORDER) do
      local section = { label = horizon, tasks = {} }
      for _, task in ipairs(state.all_tasks) do
        if task.status == "done" or task.status == "inbox" then
          goto skip
        end
        if task.horizon == horizon then
          table.insert(section.tasks, task)
        end
        ::skip::
      end
      table.insert(state.sections, section)
      for _, task in ipairs(section.tasks) do
        table.insert(state.flat_tasks, task)
      end
    end
  elseif state.view_mode == "inbox" then
    local section = { label = "inbox", tasks = {} }
    for _, task in ipairs(state.all_tasks) do
      if task.status == "inbox" then
        table.insert(section.tasks, task)
      end
    end
    table.insert(state.sections, section)
    for _, task in ipairs(section.tasks) do
      table.insert(state.flat_tasks, task)
    end
  elseif state.view_mode == "done" then
    -- Group by target_date descending
    local groups = {}
    local group_order = {}
    for _, task in ipairs(state.all_tasks) do
      if task.status == "done" then
        local key = task.target_date or "no date"
        if not groups[key] then
          groups[key] = {}
          table.insert(group_order, key)
        end
        table.insert(groups[key], task)
      end
    end
    table.sort(group_order, function(a, b)
      if a == "no date" then return false end
      if b == "no date" then return true end
      return a > b
    end)
    for _, key in ipairs(group_order) do
      table.insert(state.sections, { label = key, tasks = groups[key] })
      for _, task in ipairs(groups[key]) do
        table.insert(state.flat_tasks, task)
      end
    end
  end

  -- Build line_info (mirrors render output: line 1 = column header, then sections)
  state.line_info = {}
  local line = 1 -- line 1 is column header (not in line_info)
  local flat_idx = 0

  for _, section in ipairs(state.sections) do
    line = line + 1
    state.line_info[line] = { type = "header", label = section.label }

    for _ = 1, #section.tasks do
      flat_idx = flat_idx + 1
      line = line + 1
      state.line_info[line] = { type = "task", flat_idx = flat_idx }
    end
  end
  state.total_lines = line

  -- Clamp cursor_line
  if state.total_lines < 2 then
    state.cursor_line = 1
  elseif state.cursor_line < 2 then
    state.cursor_line = 2
  elseif state.cursor_line > state.total_lines then
    state.cursor_line = state.total_lines
  end
end

--- Load all task data and build state
---@param state table Board state
function M.load(state)
  state.all_tasks = finders.find_tasks()
  sort_tasks(state.all_tasks)
  assign_numbers(state)
  resolve_blocked_by(state)
  M.build_sections(state)
end

--- Get the currently selected task (nil if cursor is on a header)
---@param state table Board state
---@return table|nil task Selected task or nil
function M.get_selected_task(state)
  local info = state.line_info[state.cursor_line]
  if info and info.type == "task" then
    return state.flat_tasks[info.flat_idx]
  end
  return nil
end

--- Get the section label at the current cursor position
--- Walks up from cursor_line to find the nearest section header
---@param state table Board state
---@return string|nil label Section label
function M.get_section_at_cursor(state)
  for line = state.cursor_line, 1, -1 do
    local info = state.line_info[line]
    if info and info.type == "header" then
      return info.label
    end
  end
  return nil
end

--- Find the cursor_line for a given filepath
---@param state table Board state
---@param filepath string File path to find
---@return number cursor_line Line number (defaults to 2 if not found)
function M.find_cursor_line(state, filepath)
  for line, info in pairs(state.line_info) do
    if info.type == "task" then
      local task = state.flat_tasks[info.flat_idx]
      if task and task.filepath == filepath then
        return line
      end
    end
  end
  return 2
end

--- Cycle status forward or backward
---@param state table Board state
---@param direction number 1 for forward, -1 for backward
---@return boolean changed Whether the status was changed
function M.cycle_status(state, direction)
  local task = M.get_selected_task(state)
  if not task then
    return false
  end

  local gtd_statuses = config.get("gtd.statuses")
  local current_idx = nil
  for i, s in ipairs(gtd_statuses) do
    if s == task.status then
      current_idx = i
      break
    end
  end

  if not current_idx then
    return false
  end

  local new_idx = current_idx + direction
  if new_idx < 1 or new_idx > #gtd_statuses then
    return false
  end

  return gtd_statuses[new_idx]
end

return M
