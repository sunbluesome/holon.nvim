-- =============================================================================
-- holon/gtd/finders: GTD data queries
-- =============================================================================

local config = require("holon.config")
local file_search = require("holon.file_search")
local frontmatter = require("holon.frontmatter")
local utils = require("holon.utils")

local M = {}

--- Compute time horizon from target date
---@param target_str string|nil Target date string (YYYY-MM-DD)
---@return string horizon Horizon label
function M.compute_horizon(target_str)
  local due_time = utils.parse_date(target_str)
  if not due_time then
    return "no_target"
  end

  local today = utils.today_midnight()
  local diff_days = math.floor((due_time - today) / 86400)

  if diff_days < 0 then
    return "overdue"
  elseif diff_days == 0 then
    return "today"
  elseif diff_days <= 7 then
    return "1w"
  elseif diff_days <= 14 then
    return "2w"
  elseif diff_days <= 30 then
    return "1m"
  elseif diff_days <= 60 then
    return "2m"
  else
    return "later"
  end
end

--- Find all GTD tasks (notes with a status field)
---@param opts table|nil Options
---@return table[] tasks List of task data tables
function M.find_tasks(opts)
  opts = opts or {}
  local notes_path = opts.notes_path or config.get("notes_path")
  local files = file_search.list_files(notes_path)

  local tasks = {}
  for _, filepath in ipairs(files) do
    local fm = frontmatter.parse_file(filepath)
    if fm and fm.status and fm.status ~= "null" then
      local blocked_by = {}
      if fm.blocked_by and fm.blocked_by ~= "null" then
        if type(fm.blocked_by) == "table" then
          blocked_by = fm.blocked_by
        elseif type(fm.blocked_by) == "string" then
          blocked_by = { fm.blocked_by }
        end
      end

      table.insert(tasks, {
        filepath = filepath,
        title = frontmatter.get_title(fm),
        note_type = frontmatter.get_type(fm),
        status = fm.status,
        target_date = fm.target_date ~= "null" and fm.target_date or nil,
        start_date = fm.start_date ~= "null" and fm.start_date or nil,
        blocked_by = blocked_by,
        tags = frontmatter.get_tags(fm),
        horizon = M.compute_horizon(fm.target_date ~= "null" and fm.target_date or nil),
      })
    end
  end

  return tasks
end

--- Collect task counts per status
---@param opts table|nil Options
---@return table[] statuses List of { status, count }
function M.collect_statuses(opts)
  local tasks = M.find_tasks(opts)
  local exclude_done = opts and opts.exclude_done
  local gtd_statuses = config.get("gtd.statuses")
  local counts = {}
  for _, s in ipairs(gtd_statuses) do
    counts[s] = 0
  end

  for _, task in ipairs(tasks) do
    if not (exclude_done and task.status == "done") then
      if counts[task.status] then
        counts[task.status] = counts[task.status] + 1
      end
    end
  end

  local result = {}
  for _, s in ipairs(gtd_statuses) do
    table.insert(result, { status = s, count = counts[s] })
  end
  return result
end

--- Collect task counts per time horizon
---@param opts table|nil Options (exclude_done: boolean)
---@return table[] horizons List of { horizon, count }
function M.collect_horizons(opts)
  local tasks = M.find_tasks(opts)
  local exclude_done = opts and opts.exclude_done
  local horizon_order = { "overdue", "today", "1w", "2w", "1m", "2m", "later", "no_target" }
  local counts = {}
  for _, h in ipairs(horizon_order) do
    counts[h] = 0
  end

  for _, task in ipairs(tasks) do
    if not (exclude_done and task.status == "done") then
      local h = task.horizon
      if counts[h] then
        counts[h] = counts[h] + 1
      end
    end
  end

  local result = {}
  for _, h in ipairs(horizon_order) do
    table.insert(result, { horizon = h, count = counts[h] })
  end
  return result
end

return M
