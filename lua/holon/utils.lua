-- =============================================================================
-- holon/utils: Utility functions for holon.nvim
-- =============================================================================

local M = {}

--- Read file contents
---@param filepath string Absolute path to file
---@return string|nil content File content or nil on error
function M.read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  return content
end

--- Write content to file
---@param filepath string Absolute path to file
---@param content string Content to write
---@return boolean success
function M.write_file(filepath, content)
  local file = io.open(filepath, "w")
  if not file then
    return false
  end

  file:write(content)
  file:close()
  return true
end

--- Extract UUID from filepath
--- Handles both UUID-named files and files with UUID in the name
---@param filepath string File path
---@return string|nil uuid Extracted UUID or nil
function M.extract_uuid_from_path(filepath)
  local filename = vim.fn.fnamemodify(filepath, ":t:r")
  -- UUID v4 pattern: 8-4-4-4-12 hex characters
  local uuid = filename:match("^([a-f0-9]+-[a-f0-9]+-[a-f0-9]+-[a-f0-9]+-[a-f0-9]+)$")
  if uuid then
    return uuid
  end
  -- Try to find UUID anywhere in filename
  return filename:match("([a-f0-9]+-[a-f0-9]+-[a-f0-9]+-[a-f0-9]+-[a-f0-9]+)")
end

--- Generate UUID v4
---@return string uuid
local function generate_uuid()
  local random = math.random
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and random(0, 0xf) or random(8, 0xb)
    return string.format("%x", v)
  end)
end

--- Get current time adjusted for configured timezone
---@return number timestamp Unix timestamp
local function get_local_time()
  local config = require("holon.config")
  local offset = config.get("timezone_offset")
  if offset then
    -- os.time() returns UTC epoch seconds; add offset
    return os.time() + offset * 3600
  end
  return os.time()
end

--- Get current timestamp in ISO 8601 format
---@return string timestamp
function M.iso_timestamp()
  return os.date("%Y-%m-%dT%H:%M:%S", get_local_time())
end

--- Get current date in specified format
---@param format string Date format string (default: "%Y-%m-%d")
---@return string date
function M.local_date(format)
  format = format or "%Y-%m-%d"
  return os.date(format, get_local_time())
end

--- Get template variables for substitution
---@return table vars Template variables
function M.get_template_vars()
  local now = os.date("*t", get_local_time())
  return {
    UUID = generate_uuid(),
    CURRENT_YEAR = string.format("%04d", now.year),
    CURRENT_MONTH = string.format("%02d", now.month),
    CURRENT_DATE = string.format("%02d", now.day),
    CURRENT_HOUR = string.format("%02d", now.hour),
    CURRENT_MINUTE = string.format("%02d", now.min),
    CURRENT_SECOND = string.format("%02d", now.sec),
  }
end

--- Substitute template variables in content
---@param content string Template content
---@param vars table|nil Variables to substitute (uses default if nil)
---@return string result Content with variables substituted
function M.substitute_template_vars(content, vars)
  vars = vars or M.get_template_vars()

  local result = content
  for key, value in pairs(vars) do
    result = result:gsub("%${" .. key .. "}", value)
  end

  return result
end

--- Truncate string to max length with ellipsis (byte-based, ASCII only)
---@param str string Input string
---@param max_len number Maximum length
---@return string truncated
function M.truncate(str, max_len)
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 1) .. "…"
end

-- =============================================================================
-- Display-width-aware string helpers (CJK safe)
-- =============================================================================

--- Get display width of string (handles multibyte characters)
---@param str string Input string
---@return number width Display width
function M.strwidth(str)
  return vim.fn.strdisplaywidth(str)
end

--- Truncate string to max display width with ellipsis (CJK safe)
---@param str string Input string
---@param max_width number Maximum display width
---@return string truncated
function M.display_truncate(str, max_width)
  if M.strwidth(str) <= max_width then
    return str
  end
  local len = vim.fn.strchars(str)
  for i = len, 1, -1 do
    local candidate = vim.fn.strcharpart(str, 0, i)
    if M.strwidth(candidate) <= max_width - 1 then
      return candidate .. "…"
    end
  end
  return "…"
end

--- Pad string to display width with spaces (CJK safe)
---@param str string Input string
---@param width number Target display width
---@return string padded
function M.display_pad(str, width)
  local dw = M.strwidth(str)
  if dw >= width then
    return str
  end
  return str .. string.rep(" ", width - dw)
end

--- Truncate then pad to exact display width (CJK safe)
---@param str string Input string
---@param width number Target display width
---@return string fitted
function M.display_fit(str, width)
  return M.display_pad(M.display_truncate(str, width), width)
end

-- =============================================================================
-- Buffer / window helpers
-- =============================================================================

--- Create a scratch buffer with standard options
---@param name string Buffer name suffix (prefixed with "holon-")
---@return number buf Buffer handle
function M.create_scratch_buf(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "holon-" .. name)
  return buf
end

--- Block <C-w> window commands on a buffer
---@param buf number Buffer handle
function M.block_wincmds(buf)
  local opts = { noremap = true, silent = true, buffer = buf }
  for _, key in ipairs({
    "<C-w>h", "<C-w>j", "<C-w>k", "<C-w>l", "<C-w>w", "<C-w>W",
    "<C-w><C-h>", "<C-w><C-j>", "<C-w><C-k>", "<C-w><C-l>", "<C-w><C-w>",
  }) do
    vim.keymap.set("n", key, "", opts)
  end
end

--- Set lines on a nomodifiable buffer (handles modifiable toggle)
---@param buf number Buffer handle
---@param lines string[] Lines to set
function M.buf_set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Close all windows in a table and clean up
---@param wins table<string, number> Window handles
function M.close_float_wins(wins)
  for _, win in pairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

-- =============================================================================
-- Date helpers
-- =============================================================================

--- Parse YYYY-MM-DD date string to unix timestamp
---@param date_str string Date in YYYY-MM-DD format
---@return number|nil timestamp Unix timestamp or nil if invalid
function M.parse_date(date_str)
  if not date_str then return nil end
  local y, m, d = date_str:match("^(%d+)-(%d+)-(%d+)")
  if not y then return nil end
  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

--- Get today's midnight as unix timestamp
---@return number timestamp
function M.today_midnight()
  local t = os.date("*t")
  return os.time({ year = t.year, month = t.month, day = t.day, hour = 0 })
end

--- Notify user with consistent formatting
---@param msg string Message
---@param level string|nil Log level ("info", "warn", "error"), default "info"
function M.notify(msg, level)
  level = level or "info"
  local levels = {
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
  }
  vim.notify("[Holon] " .. msg, levels[level] or vim.log.levels.INFO)
end

--- Check if file exists
---@param filepath string File path
---@return boolean exists
function M.file_exists(filepath)
  local stat = vim.uv.fs_stat(filepath)
  return stat ~= nil
end

--- Check if directory exists
---@param dirpath string Directory path
---@return boolean exists
local function dir_exists(dirpath)
  local stat = vim.uv.fs_stat(dirpath)
  return stat ~= nil and stat.type == "directory"
end

--- Create directory if it doesn't exist
---@param dirpath string Directory path
---@return boolean success
function M.ensure_dir(dirpath)
  if dir_exists(dirpath) then
    return true
  end
  return vim.fn.mkdir(dirpath, "p") == 1
end

--- Escape special characters for Lua pattern matching
---@param str string Input string
---@return string escaped
function M.escape_pattern(str)
  return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

--- Open a floating selection popup
---@param items string[] List of items to choose from
---@param title string Popup title
---@param callback function(string|nil) Called with selected item or nil
function M.float_select(items, title, callback)
  if #items == 0 then
    callback(nil)
    return
  end

  local popup_w = 24
  for _, item in ipairs(items) do
    popup_w = math.max(popup_w, #item + 6)
  end
  local popup_h = #items
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines
  local popup_row = math.floor((editor_h - popup_h) / 2) - 1
  local popup_col = math.floor((editor_w - popup_w) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"

  local display = {}
  for i, item in ipairs(items) do
    table.insert(display, string.format(" %d. %s", i, item))
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = popup_row,
    col = popup_col,
    width = popup_w,
    height = popup_h,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = true

  local closed = false
  local function close(value)
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    vim.schedule(function() callback(value) end)
  end

  local opts = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    close(items[row])
  end, opts)
  vim.keymap.set("n", "<Esc>", function() close(nil) end, opts)
  vim.keymap.set("n", "q", function() close(nil) end, opts)
  for i = 1, math.min(#items, 9) do
    vim.keymap.set("n", tostring(i), function() close(items[i]) end, opts)
  end
end

return M
