-- =============================================================================
-- loam/utils: Utility functions for telescope-loam
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
function M.generate_uuid()
  local random = math.random
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and random(0, 0xf) or random(8, 0xb)
    return string.format("%x", v)
  end)
end

--- Get current timestamp in ISO 8601 format
---@return string timestamp
function M.iso_timestamp()
  return os.date("%Y-%m-%dT%H:%M:%S")
end

--- Get template variables for substitution
---@return table vars Template variables
function M.get_template_vars()
  local now = os.date("*t")
  return {
    UUID = M.generate_uuid(),
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

--- Truncate string to max length with ellipsis
---@param str string Input string
---@param max_len number Maximum length
---@return string truncated
function M.truncate(str, max_len)
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 1) .. "…"
end

--- Pad string to specified length
---@param str string Input string
---@param len number Target length
---@param align string|nil Alignment ("left", "right", "center"), default "left"
---@return string padded
function M.pad(str, len, align)
  align = align or "left"
  local pad_len = len - vim.fn.strdisplaywidth(str)

  if pad_len <= 0 then
    return str
  end

  if align == "right" then
    return string.rep(" ", pad_len) .. str
  elseif align == "center" then
    local left = math.floor(pad_len / 2)
    local right = pad_len - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
  else
    return str .. string.rep(" ", pad_len)
  end
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
  vim.notify("[Loam] " .. msg, levels[level] or vim.log.levels.INFO)
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
function M.dir_exists(dirpath)
  local stat = vim.uv.fs_stat(dirpath)
  return stat ~= nil and stat.type == "directory"
end

--- Create directory if it doesn't exist
---@param dirpath string Directory path
---@return boolean success
function M.ensure_dir(dirpath)
  if M.dir_exists(dirpath) then
    return true
  end
  return vim.fn.mkdir(dirpath, "p") == 1
end

--- Get title from note path (reads frontmatter or uses filename)
---@param filepath string File path
---@return string title
function M.get_title_from_path(filepath)
  -- This is a simple version, will be enhanced when frontmatter module is available
  local filename = vim.fn.fnamemodify(filepath, ":t:r")
  return filename
end

--- Escape special characters for Lua pattern matching
---@param str string Input string
---@return string escaped
function M.escape_pattern(str)
  return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

return M
