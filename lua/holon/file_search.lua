-- =============================================================================
-- holon/file_search: Shared file search infrastructure (fd/rg)
-- =============================================================================

local config = require("holon.config")

local M = {}

--- Get .holonignore file path if it exists
---@return string|nil path Path to .holonignore or nil
local function get_ignore_file()
  local notes_path = config.get("notes_path")
  local ignore_path = notes_path .. "/.holonignore"
  if vim.uv.fs_stat(ignore_path) then
    return ignore_path
  end
  return nil
end

--- Build fd command for finding files
---@param search_path string Directory to search in
---@param opts table|nil Options: { extension: string, no_ignore: boolean }
---@return string[] command fd command as argument list
local function build_fd_command(search_path, opts)
  opts = opts or {}
  local extension = opts.extension or config.get("extension"):gsub("^%.", "")

  local cmd = { "fd", "--type", "f", "--extension", extension, "--hidden", "--no-ignore" }

  if not opts.no_ignore then
    local ignore_file = get_ignore_file()
    if ignore_file then
      table.insert(cmd, "--ignore-file")
      table.insert(cmd, ignore_file)
    end
  end

  table.insert(cmd, ".")
  table.insert(cmd, search_path)
  return cmd
end

--- Collect file paths using fd (synchronous)
---@param search_path string Directory to search in
---@param opts table|nil Options passed to build_fd_command
---@return string[] files List of file paths
function M.list_files(search_path, opts)
  return vim.fn.systemlist(build_fd_command(search_path, opts))
end

--- Build additional args for rg (ripgrep) matching the same ignore strategy
---@return string[] args Additional arguments for ripgrep
function M.build_rg_args()
  local args = { "--hidden", "--no-ignore-vcs" }

  local ignore_file = get_ignore_file()
  if ignore_file then
    table.insert(args, "--ignore-file")
    table.insert(args, ignore_file)
  else
    table.insert(args, "--no-ignore")
  end

  return args
end

return M
