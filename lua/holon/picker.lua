-- =============================================================================
-- holon/picker: Reusable float window picker component
-- =============================================================================

local utils = require("holon.utils")
local config = require("holon.config")

local M = {}

-- Picker instance (singleton)
local picker = nil

-- Autocmd group for picker-specific autocmds
local augroup = vim.api.nvim_create_augroup("holon_picker", { clear = true })

-- =============================================================================
-- Layout
-- =============================================================================

local function calc_layout(has_preview)
  local picker_config = config.get("picker") or {}
  local layout = picker_config.layout_config or {}
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines

  local total_w = math.floor(editor_w * (layout.width or 0.9))
  local total_h = math.floor(editor_h * (layout.height or 0.8))
  local row = math.floor((editor_h - total_h) / 2)
  local col = math.floor((editor_w - total_w) / 2)

  local prompt_h = 1
  local helpline_h = 1
  -- borders: prompt(2) + results(2) + helpline(0) = 4, plus gap between prompt and results
  local results_h = total_h - prompt_h - helpline_h - 5

  local results_w, preview_w
  if has_preview then
    local preview_ratio = (layout.horizontal and layout.horizontal.preview_width) or 0.5
    preview_w = math.floor(total_w * preview_ratio)
    results_w = total_w - preview_w - 2 -- border gap
  else
    results_w = total_w
    preview_w = 0
  end

  return {
    row = row,
    col = col,
    total_w = total_w,
    total_h = total_h,
    prompt_h = prompt_h,
    results_w = results_w,
    results_h = results_h,
    preview_w = preview_w,
    helpline_h = helpline_h,
  }
end

-- =============================================================================
-- Fuzzy filtering
-- =============================================================================

local function filter_items(items, query, get_ordinal)
  if not query or query == "" then
    return items
  end

  local ordinals = {}
  for i, item in ipairs(items) do
    ordinals[i] = get_ordinal(item)
  end

  local matched_strs = vim.fn.matchfuzzy(ordinals, query)
  local matched_set = {}
  for _, s in ipairs(matched_strs) do
    matched_set[s] = true
  end

  -- Preserve matchfuzzy order but handle duplicate ordinals
  local result = {}
  local used = {}
  for _, s in ipairs(matched_strs) do
    for i, ord in ipairs(ordinals) do
      if ord == s and not used[i] then
        used[i] = true
        table.insert(result, items[i])
        break
      end
    end
  end

  return result
end

-- =============================================================================
-- Rendering
-- =============================================================================

local function render_results(state, cfg)
  if not state.bufs.results or not vim.api.nvim_buf_is_valid(state.bufs.results) then
    return
  end

  local lines = {}
  local all_highlights = {}
  local ns = vim.api.nvim_create_namespace("holon_picker_results")

  for i, item in ipairs(state.filtered) do
    local text, highlights = cfg.format_item(item)
    local prefix = ""
    if cfg.multi_select then
      prefix = state.marked[i] and "* " or "  "
    end
    table.insert(lines, prefix .. text)

    local offset = #prefix
    for _, hl in ipairs(highlights or {}) do
      table.insert(all_highlights, {
        line = i - 1,
        col_start = hl.col_start + offset,
        col_end = hl.col_end + offset,
        hl = hl.hl,
      })
    end
  end

  if #lines == 0 then
    lines = { "  (no results)" }
  end

  utils.buf_set_lines(state.bufs.results, lines)

  vim.api.nvim_buf_clear_namespace(state.bufs.results, ns, 0, -1)
  for _, hl in ipairs(all_highlights) do
    vim.api.nvim_buf_add_highlight(state.bufs.results, ns, hl.hl, hl.line, hl.col_start, hl.col_end)
  end

  -- Cursor highlight
  local cursor = math.max(1, math.min(state.cursor, #state.filtered))
  if #state.filtered == 0 then
    cursor = 1
  end
  state.cursor = cursor

  if state.wins.results and vim.api.nvim_win_is_valid(state.wins.results) then
    pcall(vim.api.nvim_win_set_cursor, state.wins.results, { cursor, 0 })
  end
end

local function render_preview(state, cfg)
  if not cfg.preview then
    return
  end
  if not state.bufs.preview or not vim.api.nvim_buf_is_valid(state.bufs.preview) then
    return
  end

  local item = state.filtered[state.cursor]
  local lines = {}

  if item then
    lines = cfg.preview(item)
  end
  if not lines or #lines == 0 then
    lines = { "  (no preview)" }
  end

  utils.buf_set_lines(state.bufs.preview, lines)

  -- Scroll to matched line if item has lnum
  if item and item.lnum and state.wins.preview and vim.api.nvim_win_is_valid(state.wins.preview) then
    local lnum = math.max(1, math.min(item.lnum, #lines))
    pcall(vim.api.nvim_win_set_cursor, state.wins.preview, { lnum, 0 })
    vim.api.nvim_win_call(state.wins.preview, function()
      vim.cmd("normal! zz")
    end)
  end

  -- Highlight search query in preview (for grep mode)
  local ns_hl = vim.api.nvim_create_namespace("holon_picker_preview_hl")
  vim.api.nvim_buf_clear_namespace(state.bufs.preview, ns_hl, 0, -1)
  if cfg.dynamic_source and state.query and state.query ~= "" then
    local query_lower = state.query:lower()
    for i, line in ipairs(lines) do
      local start = 0
      while true do
        local s, e = line:lower():find(query_lower, start + 1, true)
        if not s then
          break
        end
        vim.api.nvim_buf_add_highlight(state.bufs.preview, ns_hl, "Search", i - 1, s - 1, e)
        start = e
      end
    end
  end
end

local function render_helpline(state, cfg)
  if not state.bufs.helpline or not vim.api.nvim_buf_is_valid(state.bufs.helpline) then
    return
  end

  local help = cfg.helpline or " /:search  j/k:select  CR:open  q:close"

  utils.buf_set_lines(state.bufs.helpline, { help })

  local ns = vim.api.nvim_create_namespace("holon_picker_help")
  vim.api.nvim_buf_clear_namespace(state.bufs.helpline, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(state.bufs.helpline, ns, "Comment", 0, 0, -1)
end

local function render_prompt_prefix(state)
  if not state.bufs.prompt or not vim.api.nvim_buf_is_valid(state.bufs.prompt) then
    return
  end
  local ns = vim.api.nvim_create_namespace("holon_picker_prompt")
  vim.api.nvim_buf_clear_namespace(state.bufs.prompt, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(state.bufs.prompt, ns, 0, 0, {
    virt_text = { { "> ", "DiagnosticInfo" } },
    virt_text_pos = "inline",
    right_gravity = false,
  })
end

local function render_count(state, cfg)
  if not state.wins.results or not vim.api.nvim_win_is_valid(state.wins.results) then
    return
  end
  local total = #state.items
  local filtered = #state.filtered
  local count_str = filtered == total
    and string.format(" %s (%d) ", cfg.title or "Picker", total)
    or string.format(" %s (%d/%d) ", cfg.title or "Picker", filtered, total)
  vim.api.nvim_win_set_config(state.wins.results, { title = count_str, title_pos = "center" })
end

local function render_all(state, cfg)
  render_results(state, cfg)
  render_preview(state, cfg)
  render_helpline(state, cfg)
  render_count(state, cfg)
end

-- =============================================================================
-- Navigation
-- =============================================================================

local function move_cursor(state, cfg, dir)
  local max = #state.filtered
  if max == 0 then
    return
  end
  local new = state.cursor + dir
  if new < 1 then
    new = 1
  end
  if new > max then
    new = max
  end
  state.cursor = new

  if state.wins.results and vim.api.nvim_win_is_valid(state.wins.results) then
    pcall(vim.api.nvim_win_set_cursor, state.wins.results, { new, 0 })
  end
  render_preview(state, cfg)
end

-- =============================================================================
-- Prompt setup
-- =============================================================================

local function setup_prompt(state, cfg)
  local buf = state.bufs.prompt
  local opts = { noremap = true, silent = true, buffer = buf }

  -- Move focus to results list
  local function focus_results()
    vim.cmd("stopinsert")
    vim.schedule(function()
      if state.wins.results and vim.api.nvim_win_is_valid(state.wins.results) then
        vim.api.nvim_set_current_win(state.wins.results)
      end
    end)
  end

  -- CR in insert mode: move focus to results
  vim.keymap.set("i", "<CR>", focus_results, opts)

  -- CR in normal mode: move focus to results
  vim.keymap.set("n", "<CR>", focus_results, opts)

  -- Close from prompt normal mode
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, opts)

  -- Navigation in insert mode
  vim.keymap.set("i", "<C-j>", function() move_cursor(state, cfg, 1) end, opts)
  vim.keymap.set("i", "<C-k>", function() move_cursor(state, cfg, -1) end, opts)
  vim.keymap.set("i", "<C-n>", function() move_cursor(state, cfg, 1) end, opts)
  vim.keymap.set("i", "<C-p>", function() move_cursor(state, cfg, -1) end, opts)

  -- Tab in insert mode for multi-select
  if cfg.multi_select then
    vim.keymap.set("i", "<Tab>", function()
      local idx = state.cursor
      state.marked[idx] = not state.marked[idx] or nil
      move_cursor(state, cfg, 1)
      render_results(state, cfg)
    end, opts)
  end

  -- Custom insert-mode mappings
  if cfg.mappings and cfg.mappings.i then
    for key, handler in pairs(cfg.mappings.i) do
      -- Don't override C-j/C-k/C-n/C-p (navigation) if user tries to bind them
      vim.keymap.set("i", key, function() handler(state) end, opts)
    end
  end

  -- Debounce timer for dynamic_source
  local DEBOUNCE_MS = 150

  -- Real-time filtering
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      local query = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
      state.query = query

      if cfg.dynamic_source then
        -- Dynamic mode: debounce and call source function
        if state.debounce_timer then
          state.debounce_timer:stop()
          state.debounce_timer:close()
        end
        state.debounce_timer = vim.uv.new_timer()
        state.debounce_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
          if not picker then return end
          state.filtered = cfg.dynamic_source(query)
          state.cursor = 1
          state.marked = {}
          render_all(state, cfg)
        end))
      else
        -- Static mode: fuzzy filter
        local get_ordinal = cfg.get_ordinal or function(item) return item.ordinal or "" end
        state.filtered = filter_items(state.items, query, get_ordinal)
        state.cursor = 1
        state.marked = {}
        render_all(state, cfg)
      end
    end,
  })

  render_prompt_prefix(state)
  utils.block_wincmds(buf)
end

-- =============================================================================
-- Results keymaps
-- =============================================================================

local function setup_results_keymaps(state, cfg)
  local opts = { noremap = true, silent = true, buffer = state.bufs.results }

  vim.keymap.set("n", "j", function() move_cursor(state, cfg, 1) end, opts)
  vim.keymap.set("n", "k", function() move_cursor(state, cfg, -1) end, opts)

  vim.keymap.set("n", "<CR>", function()
    local item = state.filtered[state.cursor]
    if item and cfg.on_select then
      M.close()
      vim.schedule(function()
        cfg.on_select(item)
      end)
    end
  end, opts)

  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, opts)

  -- Return to prompt for searching
  for _, key in ipairs({ "i", "I", "a", "A", "/" }) do
    vim.keymap.set("n", key, function()
      if state.wins.prompt and vim.api.nvim_win_is_valid(state.wins.prompt) then
        vim.api.nvim_set_current_win(state.wins.prompt)
        vim.cmd("startinsert!")
      end
    end, opts)
  end

  -- Multi-select
  if cfg.multi_select then
    vim.keymap.set("n", "<Tab>", function()
      local idx = state.cursor
      state.marked[idx] = not state.marked[idx] or nil
      move_cursor(state, cfg, 1)
      render_results(state, cfg)
    end, opts)
  end

  -- Page scroll
  vim.keymap.set("n", "<C-d>", "<C-d>", opts)
  vim.keymap.set("n", "<C-u>", "<C-u>", opts)

  -- Custom normal-mode mappings (nowait to avoid timeoutlen delay)
  if cfg.mappings and cfg.mappings.n then
    local nowait_opts = vim.tbl_extend("force", opts, { nowait = true })
    for key, handler in pairs(cfg.mappings.n) do
      vim.keymap.set("n", key, function() handler(state) end, nowait_opts)
    end
  end

  utils.block_wincmds(state.bufs.results)
end

-- =============================================================================
-- Public API
-- =============================================================================

--- File preview helper: returns lines from a file
---@param item table Item with value or path field
---@return string[] lines
function M.file_preview(item)
  local filepath = item.value or item.path
  if not filepath then
    return { "  (no file)" }
  end
  local content = utils.read_file(filepath)
  if not content then
    return { "  (file not found)" }
  end
  return vim.split(content, "\n", { plain = true })
end

--- Get the currently selected item
---@return table|nil item
function M.get_selected()
  if not picker then
    return nil
  end
  return picker.filtered[picker.cursor]
end

--- Get all marked items (for multi-select)
---@return table[] items
function M.get_marked()
  if not picker then
    return {}
  end
  local result = {}
  for idx, _ in pairs(picker.marked) do
    if picker.filtered[idx] then
      table.insert(result, picker.filtered[idx])
    end
  end
  return result
end

--- Close the picker
function M.close()
  if not picker then
    return
  end

  -- Clean up autocmds
  vim.api.nvim_clear_autocmds({ group = augroup })

  -- Clean up debounce timer
  if picker.debounce_timer then
    picker.debounce_timer:stop()
    picker.debounce_timer:close()
  end

  local origin_win = picker.origin_win

  utils.close_float_wins(picker.wins)

  picker = nil

  if origin_win and vim.api.nvim_win_is_valid(origin_win) then
    vim.api.nvim_set_current_win(origin_win)
  end
end

--- Open a picker
---@param cfg table Picker configuration
---  title: string - window title
---  items: table[] - list of items
---  format_item: fn(item) -> string, table[] - format for display
---  get_ordinal: fn(item) -> string - text for fuzzy matching
---  on_select: fn(item) - callback on CR
---  preview: fn(item) -> string[] - optional preview content
---  mappings: table<string, table<string, fn(state)>> - extra keymaps
---  multi_select: boolean - enable Tab marking
---  dynamic_source: fn(query) -> table[] - dynamic item source (for grep)
---  helpline: string - help text
function M.open(cfg)
  local origin_win = vim.api.nvim_get_current_win()

  if picker then
    M.close()
  end

  local has_preview = cfg.preview ~= nil
  local dims = calc_layout(has_preview)

  local state = {
    items = cfg.items or {},
    filtered = cfg.items or {},
    query = "",
    cursor = 1,
    marked = {},
    bufs = {},
    origin_win = origin_win,
    wins = {},
  }

  -- Prompt buffer (top-left)
  state.bufs.prompt = utils.create_scratch_buf("picker-prompt")
  vim.bo[state.bufs.prompt].modifiable = true
  state.wins.prompt = vim.api.nvim_open_win(state.bufs.prompt, true, {
    relative = "editor",
    row = dims.row,
    col = dims.col,
    width = dims.results_w,
    height = dims.prompt_h,
    style = "minimal",
    border = "rounded",
    title = " " .. (cfg.title or "Picker") .. " ",
    title_pos = "center",
  })

  -- Results buffer (below prompt, left side)
  state.bufs.results = utils.create_scratch_buf("picker-results")
  state.wins.results = vim.api.nvim_open_win(state.bufs.results, false, {
    relative = "editor",
    row = dims.row + dims.prompt_h + 2, -- +2 for prompt border
    col = dims.col,
    width = dims.results_w,
    height = dims.results_h,
    style = "minimal",
    border = "rounded",
    title = string.format(" %s (%d) ", cfg.title or "Picker", #state.items),
    title_pos = "center",
  })
  vim.wo[state.wins.results].cursorline = true
  vim.wo[state.wins.results].wrap = false

  -- Preview buffer (right side, spanning prompt + results height)
  if has_preview then
    state.bufs.preview = utils.create_scratch_buf("picker-preview")
    local preview_h = dims.prompt_h + dims.results_h + 2 -- span both
    state.wins.preview = vim.api.nvim_open_win(state.bufs.preview, false, {
      relative = "editor",
      row = dims.row,
      col = dims.col + dims.results_w + 2,
      width = dims.preview_w,
      height = preview_h,
      style = "minimal",
      border = "rounded",
      title = " Preview ",
      title_pos = "center",
    })
    vim.wo[state.wins.preview].cursorline = false
    vim.wo[state.wins.preview].wrap = true
    vim.wo[state.wins.preview].number = true
    vim.bo[state.bufs.preview].filetype = "markdown"
    utils.block_wincmds(state.bufs.preview)
  end

  -- Helpline (bottom)
  state.bufs.helpline = utils.create_scratch_buf("picker-helpline")
  local helpline_row = dims.row + dims.prompt_h + 2 + dims.results_h + 2
  state.wins.helpline = vim.api.nvim_open_win(state.bufs.helpline, false, {
    relative = "editor",
    row = helpline_row,
    col = dims.col,
    width = dims.total_w,
    height = 1,
    style = "minimal",
    border = "none",
  })
  utils.block_wincmds(state.bufs.helpline)

  picker = state

  -- Setup keymaps and rendering
  setup_prompt(state, cfg)
  setup_results_keymaps(state, cfg)
  render_all(state, cfg)

  -- Initial mode
  local initial_mode = config.get("picker.initial_mode") or "insert"
  if initial_mode == "insert" then
    vim.cmd("startinsert")
  else
    vim.cmd("stopinsert")
    if state.wins.results and vim.api.nvim_win_is_valid(state.wins.results) then
      vim.api.nvim_set_current_win(state.wins.results)
    end
  end
end

return M
