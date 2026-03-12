-- =============================================================================
-- holon/zk/pickers: Zettelkasten picker definitions
-- =============================================================================

local picker = require("holon.picker")
local config = require("holon.config")
local finders = require("holon.zk.finders")
local make_entry = require("holon.zk.make_entry")
local actions = require("holon.zk.actions")
local utils = require("holon.utils")

local M = {}

--- Build picker items from raw data and entry maker
---@param raw_data table[] Raw data list
---@param entry_maker function Entry maker function
---@return table[] items Picker items
local function build_items(raw_data, entry_maker)
  local items = {}
  for _, data in ipairs(raw_data) do
    table.insert(items, entry_maker(data))
  end
  return items
end

--- Common format_item function for all pickers
---@param item table Picker item with display_text and highlights
---@return string text Display text
---@return table[] highlights Highlight segments
local function format_item(item)
  return item.display_text, item.highlights
end

--- Common file preview function
---@param item table Picker item with value (filepath)
---@return string[] lines File content lines
local function file_preview(item)
  return picker.file_preview(item)
end

-- =============================================================================
-- Pickers
-- =============================================================================

--- Main notes picker - find and open notes
---@param opts table|nil Options (tags, types filters)
function M.notes(opts)
  opts = opts or {}

  local title = "Holon: Notes"
  if opts.tags then
    title = "Holon: Notes [" .. table.concat(opts.tags, ", ") .. "]"
  elseif opts.types then
    title = "Holon: Notes [" .. table.concat(opts.types, ", ") .. "]"
  end

  local raw
  if opts.tags then
    raw = finders.find_by_tags(opts)
  elseif opts.types then
    raw = finders.find_by_type(opts)
  else
    raw = finders.find_notes(opts)
  end

  local entry_maker = make_entry.make_note_entry(opts)
  local items = build_items(raw, entry_maker)

  -- Build extra mappings
  local extra_mappings = { n = {}, i = {} }

  -- Back navigation: return to unfiltered notes
  if opts.tags or opts.types then
    extra_mappings.n["<BS>"] = function()
      picker.close()
      M.notes()
    end
  end

  -- Configurable mappings
  local action_handlers = {
    create_note = function()
      picker.close()
      M.templates()
    end,
    show_backlinks = function()
      local sel = picker.get_selected()
      if sel and sel.uuid then
        picker.close()
        M.backlinks({ uuid = sel.uuid, title = sel.title, back = opts })
      end
    end,
    show_forward_links = function()
      local sel = picker.get_selected()
      if sel and sel.value then
        picker.close()
        M.forward_links({ filepath = sel.value, title = sel.title, back = opts })
      end
    end,
    insert_link = function()
      local sel = picker.get_selected()
      if sel then
        picker.close()
        vim.schedule(function()
          actions.insert_link(sel.uuid, sel.title)
        end)
      end
    end,
    filter_by_type = function()
      picker.close()
      local types = config.get_types()
      utils.float_select(types, "Filter by type", function(selected)
        if selected then
          M.notes({ types = { selected } })
        else
          M.notes()
        end
      end)
    end,
    filter_by_tag = function()
      picker.close()
      M.filter_tags()
    end,
  }

  local mappings_config = config.get("mappings")
  for mode, mode_maps in pairs(mappings_config) do
    for key, action_name in pairs(mode_maps) do
      if action_handlers[action_name] then
        extra_mappings[mode] = extra_mappings[mode] or {}
        extra_mappings[mode][key] = function() action_handlers[action_name]() end
      end
    end
  end

  -- Build helpline
  local helpline
  if opts.tags or opts.types then
    helpline = " BS:back  n:new  b:backlinks  f:forward  l:link"
  else
    helpline = " n:new  b:backlinks  f:forward  l:link  t:type  g:tag"
  end

  picker.open({
    title = title,
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      vim.cmd("edit " .. vim.fn.fnameescape(item.value))
    end,
    preview = file_preview,
    mappings = extra_mappings,
    helpline = helpline,
  })
end

--- Live grep through note contents
---@param opts table|nil Options
function M.grep_notes(opts)
  opts = opts or {}
  local notes_path = config.get("notes_path")
  local rg_args = finders.get_rg_args()

  picker.open({
    title = "Holon: Grep Notes",
    items = {},
    dynamic_source = function(query)
      if not query or query == "" then
        return {}
      end
      local cmd = { "rg", "--vimgrep", "--glob", "*.md" }
      vim.list_extend(cmd, rg_args)
      table.insert(cmd, "--")
      table.insert(cmd, query)
      table.insert(cmd, notes_path)

      local output = vim.fn.systemlist(cmd)
      local items = {}
      for _, line in ipairs(output) do
        local filepath, lnum, col_num, text = line:match("^(.+):(%d+):(%d+):(.*)$")
        if filepath then
          local fname = vim.fn.fnamemodify(filepath, ":t")
          local display = fname .. ":" .. lnum .. " " .. vim.trim(text)
          table.insert(items, {
            ordinal = text,
            display_text = display,
            highlights = {
              { col_start = 0, col_end = #fname + 1 + #lnum, hl = "Comment" },
            },
            value = filepath,
            path = filepath,
            lnum = tonumber(lnum),
            col = tonumber(col_num),
          })
        end
      end
      return items
    end,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      vim.cmd("edit +" .. item.lnum .. " " .. vim.fn.fnameescape(item.value))
    end,
    preview = file_preview,
    helpline = " CR:open  q:close",
  })
end

--- Filter by type picker
---@param opts table|nil Options
function M.filter_type(opts)
  opts = opts or {}
  local types = config.get_types()
  local items = {}

  for _, note_type in ipairs(types) do
    local icon, hl = config.get_icon(note_type)
    table.insert(items, {
      ordinal = note_type,
      display_text = icon .. " " .. note_type,
      highlights = { { col_start = 0, col_end = #icon, hl = hl } },
      value = note_type,
    })
  end

  picker.open({
    title = "Holon: Filter by Type",
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      M.notes({ types = { item.value } })
    end,
    helpline = " CR:select  q:close",
  })
end

--- Filter by tags picker
---@param opts table|nil Options
function M.filter_tags(opts)
  opts = opts or {}
  local tags = finders.collect_tags(opts)
  local entry_maker = make_entry.make_tag_entry(opts)
  local items = build_items(tags, entry_maker)

  picker.open({
    title = "Holon: Filter by Tag",
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      M.notes({ tags = { item.tag } })
    end,
    helpline = " CR:select  q:close",
  })
end

--- Template picker for creating new notes
---@param opts table|nil Options
function M.templates(opts)
  opts = opts or {}
  local templates = finders.collect_templates(opts)
  local entry_maker = make_entry.make_template_entry(opts)
  local items = build_items(templates, entry_maker)

  picker.open({
    title = "Holon: Select Template",
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      local function create_with_title(custom_filename)
        vim.ui.input({ prompt = "Note title: " }, function(title)
          local note_title = (title and title ~= "") and title or nil
          local filepath = actions.create_note(item.value, note_title, custom_filename)
          if filepath then
            vim.cmd("edit " .. vim.fn.fnameescape(filepath))
          end
        end)
      end

      if config.get("filename_style") == "manual" then
        vim.ui.input({ prompt = "Filename: " }, function(filename)
          if not filename or filename == "" then
            utils.notify("Filename is required", "warn")
            return
          end
          create_with_title(filename)
        end)
      else
        create_with_title(nil)
      end
    end,
    preview = file_preview,
  })
end

--- Insert link picker - find a note and insert its wikilink at the current cursor position
---@param opts table|nil Options
function M.insert_link_picker(opts)
  opts = opts or {}
  local raw = finders.find_notes(opts)
  local entry_maker = make_entry.make_note_entry(opts)
  local items = build_items(raw, entry_maker)

  picker.open({
    title = "Holon: Insert Link",
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      actions.insert_link(item.uuid, item.title)
    end,
    preview = file_preview,
    helpline = " CR:insert link  q:close",
  })
end

--- Backlinks picker - show notes that link to a specific note
---@param opts table|nil Options (uuid/identifier, or uses current buffer)
function M.backlinks(opts)
  opts = opts or {}

  local identifier = opts.uuid
  local title = opts.title

  if not identifier then
    local current_file = vim.fn.expand("%:p")
    identifier = utils.extract_uuid_from_path(current_file)
      or vim.fn.fnamemodify(current_file, ":t:r")
    local fm = require("holon.frontmatter").parse_file(current_file)
    title = require("holon.frontmatter").get_title(fm) or identifier
  end

  local prompt_title = "Holon: Backlinks"
  if title then
    prompt_title = prompt_title .. " to " .. utils.truncate(title, 30)
  end

  local raw = finders.find_backlinks(identifier, opts)
  local entry_maker = make_entry.make_backlink_entry(opts)
  local items = build_items(raw, entry_maker)

  local bl_mappings = nil
  local helpline = " CR:open  q:close"
  if opts.back then
    local back_opts = opts.back
    bl_mappings = {
      n = {
        ["<BS>"] = function()
          picker.close()
          M.notes(back_opts)
        end,
      },
    }
    helpline = " CR:open  BS:back  q:close"
  end

  picker.open({
    title = prompt_title,
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      vim.cmd("edit " .. vim.fn.fnameescape(item.value))
    end,
    preview = file_preview,
    mappings = bl_mappings,
    helpline = helpline,
  })
end

--- Forward links picker - show notes that a specific note links to
---@param opts table|nil Options (filepath, title, back)
function M.forward_links(opts)
  opts = opts or {}

  local filepath = opts.filepath
  if not filepath then
    filepath = vim.fn.expand("%:p")
  end

  local title = opts.title
  if not title then
    local fm = require("holon.frontmatter").parse_file(filepath)
    title = require("holon.frontmatter").get_title(fm)
      or vim.fn.fnamemodify(filepath, ":t:r")
  end

  local prompt_title = "Holon: Links from " .. utils.truncate(title, 30)

  local raw = finders.find_forward_links(filepath, opts)
  local entry_maker = make_entry.make_note_entry(opts)
  local items = build_items(raw, entry_maker)

  local fl_mappings = nil
  local helpline = " CR:open  q:close"
  if opts.back then
    local back_opts = opts.back
    fl_mappings = {
      n = {
        ["<BS>"] = function()
          picker.close()
          M.notes(back_opts)
        end,
      },
    }
    helpline = " CR:open  BS:back  q:close"
  end

  picker.open({
    title = prompt_title,
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      vim.cmd("edit " .. vim.fn.fnameescape(item.value))
    end,
    preview = file_preview,
    mappings = fl_mappings,
    helpline = helpline,
  })
end

--- Index notes picker
---@param opts table|nil Options
function M.indexes(opts)
  opts = opts or {}
  local raw = finders.find_index_notes(opts)
  local entry_maker = make_entry.make_note_entry(opts)
  local items = build_items(raw, entry_maker)

  local tab_handler = function()
    local sel = picker.get_selected()
    if sel then
      picker.close()
      M.index_links({ filepath = sel.value, title = sel.title })
    end
  end

  picker.open({
    title = "Holon: Index Notes",
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      vim.cmd("edit " .. vim.fn.fnameescape(item.value))
    end,
    preview = file_preview,
    mappings = {
      n = { ["<Tab>"] = tab_handler },
      i = { ["<Tab>"] = tab_handler },
    },
    helpline = " CR:open  Tab:links  q:close",
  })
end

--- Index links picker - show notes linked from an index
---@param opts table Options (filepath required)
function M.index_links(opts)
  opts = opts or {}
  local filepath = opts.filepath
  if not filepath then
    utils.notify("No index file specified", "warn")
    return
  end

  local title = opts.title or vim.fn.fnamemodify(filepath, ":t:r")

  local raw = finders.find_index_links(filepath, opts)
  local entry_maker = make_entry.make_index_link_entry(opts)
  local items = build_items(raw, entry_maker)

  picker.open({
    title = "Holon: Links from " .. utils.truncate(title, 30),
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      if item.exists then
        vim.cmd("edit " .. vim.fn.fnameescape(item.value))
      else
        utils.notify("Note not found: " .. item.uuid, "warn")
      end
    end,
    preview = file_preview,
    mappings = {
      n = {
        ["<BS>"] = function()
          picker.close()
          M.indexes()
        end,
      },
    },
    helpline = " CR:open  BS:back  q:close",
  })
end

--- Journal picker
---@param opts table|nil Options
function M.journal(opts)
  opts = opts or {}
  local raw = finders.find_journal(opts)
  local entry_maker = make_entry.make_journal_entry(opts)
  local items = build_items(raw, entry_maker)

  picker.open({
    title = "Holon: Journal",
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      vim.cmd("edit " .. vim.fn.fnameescape(item.value))
    end,
    preview = file_preview,
    mappings = {
      i = {
        ["<C-n>"] = function()
          picker.close()
          local fp = actions.create_journal_entry()
          if fp then
            vim.cmd("edit " .. vim.fn.fnameescape(fp))
          end
        end,
      },
    },
    helpline = " CR:open  C-n:today  q:close",
  })
end

--- Orphan notes picker - find notes with no links
---@param opts table|nil Options
function M.orphans(opts)
  opts = opts or {}
  local raw = finders.find_orphan_notes(opts)
  local entry_maker = make_entry.make_note_entry(opts)
  local items = build_items(raw, entry_maker)

  picker.open({
    title = "Holon: Orphan Notes",
    items = items,
    format_item = format_item,
    get_ordinal = function(item) return item.ordinal end,
    on_select = function(item)
      vim.cmd("edit " .. vim.fn.fnameescape(item.value))
    end,
    preview = file_preview,
    multi_select = true,
    mappings = {
      n = {
        ["d"] = function()
          local marked = picker.get_marked()
          if #marked == 0 then
            local sel = picker.get_selected()
            if sel then
              marked = { sel }
            end
          end
          if #marked == 0 then
            return
          end

          local names = {}
          for _, item in ipairs(marked) do
            table.insert(names, "  " .. vim.fn.fnamemodify(item.value, ":t"))
          end
          local msg = string.format(
            "Delete %d note(s)?\n%s\n(y/N): ",
            #marked,
            table.concat(names, "\n")
          )

          picker.close()
          vim.ui.input({ prompt = msg }, function(input)
            if not input or input:lower() ~= "y" then
              return
            end
            for _, item in ipairs(marked) do
              os.remove(item.value)
            end
            utils.notify(string.format("Deleted %d orphan note(s)", #marked), "info")
            M.orphans()
          end)
        end,
      },
    },
    helpline = " CR:open  Tab:mark  d:delete  q:close",
  })
end

return M
