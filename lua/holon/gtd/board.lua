-- =============================================================================
-- holon/gtd/board: GTD board UI with section-based panel layout
-- =============================================================================

local config = require("holon.config")
local frontmatter_mod = require("holon.frontmatter")
local utils = require("holon.utils")
local gtd_state = require("holon.gtd.state")
local render = require("holon.gtd.render")
local timeline_mod = require("holon.gtd.timeline")

local M = {}

-- Board instance (singleton)
local board = nil

--- Calculate window dimensions from layout config
---@return table dims Dimension data for all panels
local function calc_dimensions()
  local layout = config.get("gtd.layout")
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines

  local total_w = math.floor(editor_w * layout.width)
  local total_h = math.floor(editor_h * layout.height)
  local row = math.floor((editor_h - total_h) / 2)
  local col = math.floor((editor_w - total_w) / 2)

  -- Height split: top panels (tasks + timeline) and bottom panel (preview)
  -- Total visual height = top_h+2 (border) + bottom_h+2 (border) + 1 (helpline) = total_h
  -- So: top_h + bottom_h = total_h - 5
  local available_h = total_h - 5
  local preview_ratio = layout.preview_ratio or 0.30
  local top_h = math.floor(available_h * (1 - preview_ratio))
  local bottom_h = available_h - top_h

  -- Width split: tasks (left) and timeline (right)
  local timeline_w = math.floor(total_w * 0.40)
  local show_timeline = timeline_w >= (layout.timeline_min_width or 30)

  local tasks_w
  if show_timeline then
    tasks_w = total_w - timeline_w - 2 -- -2 for border gap
  else
    tasks_w = total_w
    timeline_w = 0
  end

  return {
    total_width = total_w,
    total_height = total_h,
    row = row,
    col = col,
    tasks_w = tasks_w,
    timeline_w = timeline_w,
    show_timeline = show_timeline,
    top_h = top_h,
    bottom_h = bottom_h,
  }
end

--- Create the board window layout
---@param state table Board state
---@return table board_data Board data with buffers and windows
local function create_layout(state)
  local dims = calc_dimensions()
  local b = {
    state = state,
    bufs = {},
    wins = {},
    dims = dims,
    show_preview = true, -- preview panel visibility toggle
  }

  -- Tasks panel (top-left)
  b.bufs.tasks = utils.create_scratch_buf("gtd-tasks")
  b.wins.tasks = vim.api.nvim_open_win(b.bufs.tasks, true, {
    relative = "editor",
    row = dims.row,
    col = dims.col,
    width = dims.tasks_w,
    height = dims.top_h,
    style = "minimal",
    border = "rounded",
    title = " GTD Board ",
    title_pos = "center",
  })
  vim.wo[b.wins.tasks].cursorline = false
  vim.wo[b.wins.tasks].wrap = false
  vim.wo[b.wins.tasks].winhighlight = "FloatBorder:HolonGtdBoardBorderActive,Normal:Normal"

  -- Timeline panel (top-right, optional)
  if dims.show_timeline then
    b.bufs.timeline = utils.create_scratch_buf("gtd-timeline")
    b.wins.timeline = vim.api.nvim_open_win(b.bufs.timeline, false, {
      relative = "editor",
      row = dims.row,
      col = dims.col + dims.tasks_w + 2,
      width = dims.timeline_w,
      height = dims.top_h,
      style = "minimal",
      border = "rounded",
      title = " Timeline ",
      title_pos = "center",
    })
    vim.wo[b.wins.timeline].cursorline = false
    vim.wo[b.wins.timeline].wrap = false
    vim.wo[b.wins.timeline].winhighlight = "FloatBorder:HolonGtdBoardBorder,Normal:Normal"

    -- Sync scrolling between tasks and timeline
    vim.wo[b.wins.tasks].scrollbind = true
    vim.wo[b.wins.timeline].scrollbind = true
  end

  -- Preview panel (bottom, full width)
  b.bufs.preview = utils.create_scratch_buf("gtd-preview")
  b.wins.preview = vim.api.nvim_open_win(b.bufs.preview, false, {
    relative = "editor",
    row = dims.row + dims.top_h + 2,
    col = dims.col,
    width = dims.total_width,
    height = dims.bottom_h,
    style = "minimal",
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
  })
  vim.wo[b.wins.preview].cursorline = false
  vim.wo[b.wins.preview].winhighlight = "FloatBorder:HolonGtdBoardBorder,Normal:Normal"
  vim.bo[b.bufs.preview].filetype = "markdown"

  -- Helpline (very bottom)
  b.bufs.helpline = utils.create_scratch_buf("gtd-helpline")
  b.wins.helpline = vim.api.nvim_open_win(b.bufs.helpline, false, {
    relative = "editor",
    row = dims.row + dims.top_h + 2 + dims.bottom_h + 2,
    col = dims.col,
    width = dims.total_width,
    height = 1,
    style = "minimal",
    border = "none",
  })

  return b
end

--- Render the timeline panel aligned with tasks panel
local function render_timeline()
  if not board or not board.bufs.timeline then
    return
  end

  local tl_lines, tl_highlights = timeline_mod.render_aligned(
    board.state, board.dims.timeline_w
  )

  utils.buf_set_lines(board.bufs.timeline, tl_lines)

  local ns = vim.api.nvim_create_namespace("holon_gtd_timeline")
  vim.api.nvim_buf_clear_namespace(board.bufs.timeline, ns, 0, -1)
  for _, hl in ipairs(tl_highlights) do
    vim.api.nvim_buf_add_highlight(
      board.bufs.timeline, ns, hl.hl, hl.line, hl.col_start, hl.col_end
    )
  end
end

--- Render the preview panel with selected task's note content
local function render_preview()
  if not board or not board.bufs.preview then
    return
  end

  local task = gtd_state.get_selected_task(board.state)
  local lines = {}

  if task then
    local content = utils.read_file(task.filepath)
    if content then
      lines = vim.split(content, "\n", { plain = true })
    end
  end

  if #lines == 0 then
    lines = { "  (no preview)" }
  end

  utils.buf_set_lines(board.bufs.preview, lines)
end

--- Render all panels
local function render_all()
  if not board then
    return
  end
  render.render_sections(board.bufs.tasks, board.state, board.dims.tasks_w)
  render_timeline()
  render.render_helpline(board.bufs.helpline, board.state)
  render_preview()

  -- Update tasks panel title based on view mode
  local titles = { status = " GTD Board ", horizon = " GTD Board (Horizon) ", inbox = " Inbox ", done = " Done " }
  local title = titles[board.state.view_mode] or " GTD Board "
  vim.api.nvim_win_set_config(board.wins.tasks, { title = title, title_pos = "center" })

  -- Sync cursor to cursor_line
  local state = board.state
  local win = board.wins.tasks
  if win and vim.api.nvim_win_is_valid(win) then
    local line = math.max(1, math.min(state.cursor_line, state.total_lines))
    vim.api.nvim_win_set_cursor(win, { line, 0 })
  end
end

--- Move selection up/down (skips column header at line 1)
---@param direction number -1 for up, 1 for down
local function move_selection(direction)
  if not board then
    return
  end
  local state = board.state
  local new_line = state.cursor_line + direction

  -- Skip column header (line 1)
  if new_line < 2 then
    new_line = 2
  end
  if new_line > state.total_lines then
    new_line = state.total_lines
  end

  state.cursor_line = new_line
  render_all()
end

--- Save current task filepath for cursor restoration after reload
---@return string|nil filepath
local function save_cursor_filepath()
  if not board then
    return nil
  end
  local task = gtd_state.get_selected_task(board.state)
  return task and task.filepath
end

--- Restore cursor to a filepath after reload, or keep current position
---@param filepath string|nil
local function restore_cursor(filepath)
  if filepath then
    board.state.cursor_line = gtd_state.find_cursor_line(board.state, filepath)
  end
end

-- =============================================================================
-- Floating popup helpers
-- =============================================================================

--- Open a floating input prompt centered on the board
---@param title string Popup title
---@param callback fun(value: string|nil) Called with input text or nil on cancel
local function float_input(title, callback)
  local popup_w = 40
  local popup_h = 1
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines
  local popup_row = math.floor((editor_h - popup_h) / 2) - 1
  local popup_col = math.floor((editor_w - popup_w) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"

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

  vim.cmd("startinsert")

  local closed = false
  local function close(value)
    if closed then return end
    closed = true
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    vim.schedule(function() callback(value) end)
  end

  local opts = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("i", "<CR>", function()
    local text = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    if text ~= "" then
      close(text)
    end
  end, opts)
  vim.keymap.set({ "i", "n" }, "<Esc>", function() close(nil) end, opts)
  vim.keymap.set("n", "q", function() close(nil) end, opts)
end

--- Open a floating select list centered on the board
---@param items string[] Items to select from
---@param title string Popup title
---@param highlight_item string|nil Item to highlight as "(current)"
---@param callback fun(choice: string|nil) Called with selected item or nil on cancel
local function float_select(items, title, highlight_item, callback)
  local popup_w = 24
  local popup_h = #items
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines
  local popup_row = math.floor((editor_h - popup_h) / 2) - 1
  local popup_col = math.floor((editor_w - popup_w) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"

  -- Build display lines with number prefix
  local display = {}
  local current_line = 0
  for i, item in ipairs(items) do
    local prefix = string.format(" %d. ", i)
    if item == highlight_item then
      table.insert(display, prefix .. item .. " (current)")
      current_line = i
    else
      table.insert(display, prefix .. item)
    end
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

  -- Place cursor on current item
  if current_line > 0 then
    vim.api.nvim_win_set_cursor(win, { current_line, 0 })
  end

  -- Highlight current item marker
  local ns = vim.api.nvim_create_namespace("holon_gtd_select")
  for i, item in ipairs(items) do
    if item == highlight_item then
      vim.api.nvim_buf_add_highlight(buf, ns, "Comment", i - 1, 0, -1)
    end
  end

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

  -- Number keys for quick selection
  for i = 1, math.min(#items, 9) do
    vim.keymap.set("n", tostring(i), function() close(items[i]) end, opts)
  end
end

--- Show a popup to select a new status for the current task
local function prompt_status()
  if not board then
    return
  end
  local task = gtd_state.get_selected_task(board.state)
  if not task then
    return
  end

  local statuses = config.get("gtd.statuses")
  float_select(statuses, "Status", task.status, function(choice)
    if not choice or choice == task.status then
      return
    end

    local content = utils.read_file(task.filepath)
    if not content then
      return
    end
    content = frontmatter_mod.set_field(content, "status", choice)
    content = frontmatter_mod.set_field(content, "lastmod", utils.iso_timestamp())
    utils.write_file(task.filepath, content)

    local path = task.filepath
    gtd_state.load(board.state)
    restore_cursor(path)
    render_all()
  end)
end


--- Set timeline scale
---@param scale string "w" or "m"
local function set_timeline_scale(scale)
  if not board then
    return
  end
  board.state.timeline_scale = scale
  render_all()
end

--- Prompt for a date using calendar picker
---@param field string "target_date" or "start_date"
local function prompt_date(field)
  if not board then
    return
  end
  local task = gtd_state.get_selected_task(board.state)
  if not task then
    return
  end

  local calendar = require("holon.gtd.calendar")
  local display_name = field == "target_date" and "target date" or "start date"
  calendar.open({ default = task[field], title = display_name }, function(result)
    if result == false then
      return
    end

    local content = utils.read_file(task.filepath)
    if not content then
      return
    end
    content = frontmatter_mod.set_field(content, field, result)
    content = frontmatter_mod.set_field(content, "lastmod", utils.iso_timestamp())
    utils.write_file(task.filepath, content)

    local path = task.filepath
    gtd_state.load(board.state)
    restore_cursor(path)
    render_all()
  end)
end

--- Open the selected task's note
local function open_note()
  if not board then
    return
  end
  local task = gtd_state.get_selected_task(board.state)
  if not task then
    return
  end

  M.close()
  vim.cmd("edit " .. vim.fn.fnameescape(task.filepath))
end

--- Toggle mark on current task (Tab key)
local function toggle_mark()
  if not board then
    return
  end
  local task = gtd_state.get_selected_task(board.state)
  if not task then
    return
  end
  if board.state.marked[task.filepath] then
    board.state.marked[task.filepath] = nil
  else
    board.state.marked[task.filepath] = true
  end
  render_all()
end

--- Move marked tasks to the status section where the cursor is
local function put_marked_tasks()
  if not board then
    return
  end
  if board.state.view_mode ~= "status" then
    utils.notify("Put only works in status view.", "warn")
    return
  end

  local state = board.state
  local target_status = gtd_state.get_section_at_cursor(state)
  if not target_status then
    return
  end

  local marked_paths = {}
  for filepath, _ in pairs(state.marked) do
    table.insert(marked_paths, filepath)
  end

  if #marked_paths == 0 then
    utils.notify("No tasks marked. Use Tab to mark tasks first.", "warn")
    return
  end

  for _, filepath in ipairs(marked_paths) do
    local content = utils.read_file(filepath)
    if content then
      content = frontmatter_mod.set_field(content, "status", target_status)
      content = frontmatter_mod.set_field(content, "lastmod", utils.iso_timestamp())
      utils.write_file(filepath, content)
    end
  end

  state.marked = {}
  local path = save_cursor_filepath()
  gtd_state.load(state)
  restore_cursor(path)
  render_all()
end

--- Set marked tasks as blocked_by for the current task
local function set_blocked_by()
  if not board then
    return
  end
  local task = gtd_state.get_selected_task(board.state)
  if not task then
    return
  end

  local blockers = {}
  for filepath, _ in pairs(board.state.marked) do
    if filepath ~= task.filepath then
      local uuid = vim.fn.fnamemodify(filepath, ":t:r")
      if uuid then
        table.insert(blockers, "[[" .. uuid .. "]]")
      end
    end
  end

  if #blockers == 0 then
    utils.notify("No tasks marked. Use Tab to mark blockers first.", "warn")
    return
  end

  local content = utils.read_file(task.filepath)
  if not content then
    return
  end

  local existing_set = {}
  for _, ref in ipairs(task.blocked_by or {}) do
    existing_set[ref] = true
  end

  for _, ref in ipairs(blockers) do
    if not existing_set[ref] then
      content = frontmatter_mod.add_to_array(content, "blocked_by", ref)
    end
  end
  content = frontmatter_mod.set_field(content, "lastmod", utils.iso_timestamp())
  utils.write_file(task.filepath, content)

  board.state.marked = {}
  local path = task.filepath
  gtd_state.load(board.state)
  restore_cursor(path)
  render_all()
end

--- Add a new task to inbox via wizard prompts
local function add_task()
  if not board then
    return
  end

  local actions = require("holon.zk.actions")

  local function create_task(custom_filename)
    float_input("Title", function(title)
      if not title or title == "" then
        return
      end

      local template = config.get_templates_path() .. "/fleeting.md"
      local filepath = actions.create_note(template, title, custom_filename)
      if not filepath then
        return
      end

    -- Add status: inbox to the fleeting note
    local content = utils.read_file(filepath)
    if content then
      content = frontmatter_mod.set_field(content, "status", "inbox")
      utils.write_file(filepath, content)
    end

    gtd_state.load(board.state)
    render_all()
    end)
  end

  if config.get("filename_style") == "manual" then
    float_input("Filename", function(filename)
      if not filename or filename == "" then
        utils.notify("Filename is required", "warn")
        return
      end
      create_task(filename)
    end)
  else
    create_task(nil)
  end
end

--- Toggle preview panel visibility
local function toggle_preview()
  if not board then
    return
  end

  if board.show_preview then
    -- Hide preview
    if board.wins.preview and vim.api.nvim_win_is_valid(board.wins.preview) then
      vim.api.nvim_win_close(board.wins.preview, true)
    end
    board.show_preview = false
  else
    -- Show preview
    local dims = board.dims
    board.bufs.preview = utils.create_scratch_buf("gtd-preview")
    board.wins.preview = vim.api.nvim_open_win(board.bufs.preview, false, {
      relative = "editor",
      row = dims.row + dims.top_h + 2,
      col = dims.col,
      width = dims.total_width,
      height = dims.bottom_h,
      style = "minimal",
      border = "rounded",
      title = " Preview ",
      title_pos = "center",
    })
    vim.wo[board.wins.preview].cursorline = false
    vim.wo[board.wins.preview].winhighlight = "FloatBorder:HolonGtdBoardBorder,Normal:Normal"
    vim.bo[board.bufs.preview].filetype = "markdown"
    setup_preview_keymaps(board.bufs.preview)
    board.show_preview = true
    render_preview()
  end
end

--- Enable scrollbind on tasks + timeline
local function enable_scrollbind()
  if not board then return end
  for _, name in ipairs({ "tasks", "timeline" }) do
    local win = board.wins[name]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.wo[win].scrollbind = true
    end
  end
end

--- Disable scrollbind on tasks + timeline
local function disable_scrollbind()
  if not board then return end
  for _, name in ipairs({ "tasks", "timeline" }) do
    local win = board.wins[name]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.wo[win].scrollbind = false
    end
  end
end

--- Focus the tasks panel
local function focus_tasks()
  if board and board.wins.tasks and vim.api.nvim_win_is_valid(board.wins.tasks) then
    vim.api.nvim_set_current_win(board.wins.tasks)
    enable_scrollbind()
  end
end

--- Focus the preview panel
local function focus_preview()
  if board and board.show_preview and board.wins.preview and vim.api.nvim_win_is_valid(board.wins.preview) then
    disable_scrollbind()
    vim.api.nvim_set_current_win(board.wins.preview)
  end
end

--- Switch to a specific view mode (or toggle back to status)
---@param mode string "inbox" or "done"
local function switch_view(mode)
  if not board then return end
  local path = save_cursor_filepath()
  if board.state.view_mode == mode then
    board.state.view_mode = "status"
  else
    board.state.view_mode = mode
  end
  board.state.marked = {}
  gtd_state.build_sections(board.state)
  restore_cursor(path)
  render_all()
end

--- Promote inbox task to todo (type select -> dates -> file move)
local function promote_inbox_task()
  if not board or board.state.view_mode ~= "inbox" then
    return
  end
  local task = gtd_state.get_selected_task(board.state)
  if not task then return end

  local calendar = require("holon.gtd.calendar")
  local types = config.get_types()

  float_select(types, "Type", nil, function(selected_type)
    if not selected_type then return end

    calendar.open({ title = "start date" }, function(start_date)
      if start_date == false then return end

      calendar.open({ title = "target date" }, function(target_date)
        if target_date == false then return end

        -- Update frontmatter
        local content = utils.read_file(task.filepath)
        if not content then return end
        content = frontmatter_mod.set_field(content, "status", "todo")
        content = frontmatter_mod.set_field(content, "type", selected_type)
        content = frontmatter_mod.set_field(content, "start_date", start_date or "null")
        content = frontmatter_mod.set_field(content, "target_date", target_date or "null")
        content = frontmatter_mod.set_field(content, "blocked_by", "null")
        content = frontmatter_mod.set_field(content, "lastmod", utils.iso_timestamp())
        utils.write_file(task.filepath, content)

        -- Move file to type directory
        local target_dir = config.get_directory(selected_type)
        utils.ensure_dir(target_dir)
        local filename = vim.fn.fnamemodify(task.filepath, ":t")
        local new_path = target_dir .. "/" .. filename
        if new_path ~= task.filepath then
          vim.fn.rename(task.filepath, new_path)
        end

        gtd_state.load(board.state)
        render_all()
      end)
    end)
  end)
end

--- Restore done task to inprogress
local function restore_done_task()
  if not board or board.state.view_mode ~= "done" then
    return
  end
  local task = gtd_state.get_selected_task(board.state)
  if not task then return end

  local content = utils.read_file(task.filepath)
  if not content then return end
  content = frontmatter_mod.set_field(content, "status", "inprogress")
  content = frontmatter_mod.set_field(content, "lastmod", utils.iso_timestamp())
  utils.write_file(task.filepath, content)

  local path = task.filepath
  gtd_state.load(board.state)
  restore_cursor(path)
  render_all()
end

--- Delete inbox task (with confirmation)
local function delete_inbox_task()
  if not board or board.state.view_mode ~= "inbox" then
    return
  end
  local task = gtd_state.get_selected_task(board.state)
  if not task then return end

  float_select({ "yes", "no" }, "Delete?", nil, function(choice)
    if choice ~= "yes" then return end
    vim.fn.delete(task.filepath)
    gtd_state.load(board.state)
    render_all()
  end)
end

--- Setup keybindings for the tasks buffer
---@param buf number Buffer handle
local function setup_keymaps(buf)
  local opts = { noremap = true, silent = true, buffer = buf }

  -- Navigation
  vim.keymap.set("n", "j", function() move_selection(1) end, opts)
  vim.keymap.set("n", "k", function() move_selection(-1) end, opts)

  -- Panel navigation
  vim.keymap.set("n", "<C-j>", function() focus_preview() end, opts)

  -- View mode toggle
  vim.keymap.set("n", "H", function() switch_view("horizon") end, opts)

  -- Mark / select
  vim.keymap.set("n", "<Tab>", function() toggle_mark() end, opts)

  -- Actions
  vim.keymap.set("n", "<CR>", function() open_note() end, opts)
  vim.keymap.set("n", "p", function()
    if board and board.state.view_mode == "inbox" then
      promote_inbox_task()
    else
      put_marked_tasks()
    end
  end, opts)
  vim.keymap.set("n", "c", function() prompt_status() end, opts)
  vim.keymap.set("n", "b", function() set_blocked_by() end, opts)
  vim.keymap.set("n", "D", function() switch_view("done") end, opts)
  vim.keymap.set("n", "I", function() switch_view("inbox") end, opts)
  vim.keymap.set("n", "r", function() restore_done_task() end, opts)
  vim.keymap.set("n", "dd", function() delete_inbox_task() end, opts)

  -- Date setting
  vim.keymap.set("n", "t", function() prompt_date("target_date") end, opts)
  vim.keymap.set("n", "s", function() prompt_date("start_date") end, opts)

  -- Add task
  vim.keymap.set("n", "a", function() add_task() end, opts)

  -- Insert link
  vim.keymap.set("n", "l", function()
    M.close()
    vim.schedule(function()
      require("holon.zk.pickers").insert_link_picker()
    end)
  end, opts)

  -- Timeline scale
  vim.keymap.set("n", "w", function() set_timeline_scale("w") end, opts)
  vim.keymap.set("n", "m", function() set_timeline_scale("m") end, opts)

  -- Preview toggle
  vim.keymap.set("n", "g", function() toggle_preview() end, opts)

  -- Close
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, opts)

  -- Block window commands
  utils.block_wincmds(buf)
end

--- Setup keybindings for the preview buffer
---@param buf number Buffer handle
local function setup_preview_keymaps(buf)
  local opts = { noremap = true, silent = true, buffer = buf }

  -- Panel navigation
  vim.keymap.set("n", "<C-k>", function() focus_tasks() end, opts)
  vim.keymap.set("n", "<C-j>", "", opts) -- no-op (already at bottom)

  -- Close
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() focus_tasks() end, opts)

  -- Block window commands
  utils.block_wincmds(buf)
end

--- Open the GTD board
function M.open()
  local origin_win = vim.api.nvim_get_current_win()

  if board then
    M.close()
  end

  local state = gtd_state.new()
  gtd_state.load(state)

  board = create_layout(state)
  board.origin_win = origin_win

  -- Setup keymaps
  setup_keymaps(board.bufs.tasks)
  setup_preview_keymaps(board.bufs.preview)

  -- Block window commands on non-interactive panels
  if board.bufs.timeline then
    utils.block_wincmds(board.bufs.timeline)
  end
  utils.block_wincmds(board.bufs.helpline)

  render_all()
end

--- Close the GTD board
function M.close()
  if not board then
    return
  end

  local origin_win = board.origin_win

  utils.close_float_wins(board.wins)

  board = nil

  if origin_win and vim.api.nvim_win_is_valid(origin_win) then
    vim.api.nvim_set_current_win(origin_win)
  end
end

return M
