-- =============================================================================
-- loam/pickers: Telescope pickers for Zettelkasten operations
-- =============================================================================

local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local config = require("loam.config")
local loam_finders = require("loam.finders")
local loam_actions = require("loam.actions")
local utils = require("loam.utils")

local M = {}

--- Main notes picker - find and open notes
---@param opts table|nil Picker options
function M.notes(opts)
  opts = opts or {}

  local picker_config = config.get("picker")
  opts = vim.tbl_deep_extend("force", {
    layout_strategy = picker_config.layout_strategy,
    layout_config = picker_config.layout_config,
    initial_mode = picker_config.initial_mode,
  }, opts)

  pickers
    .new(opts, {
      prompt_title = "Loam: Notes",
      finder = loam_finders.find_notes(opts),
      sorter = conf.generic_sorter(opts),
      previewer = conf.file_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        -- Default action: open note
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
          end
        end)

        -- Custom mappings
        map("i", "<C-n>", function()
          actions.close(prompt_bufnr)
          M.templates()
        end)

        map("i", "<C-b>", function()
          local selection = action_state.get_selected_entry()
          if selection and selection.uuid then
            actions.close(prompt_bufnr)
            M.backlinks({ uuid = selection.uuid, title = selection.title })
          end
        end)

        map("n", "n", function()
          actions.close(prompt_bufnr)
          M.templates()
        end)

        map("n", "b", function()
          local selection = action_state.get_selected_entry()
          if selection and selection.uuid then
            actions.close(prompt_bufnr)
            M.backlinks({ uuid = selection.uuid, title = selection.title })
          end
        end)

        return true
      end,
    })
    :find()
end

--- Live grep through note contents
---@param opts table|nil Picker options
function M.grep_notes(opts)
  opts = opts or {}

  local notes_path = config.get("notes_path")

  require("telescope.builtin").live_grep(vim.tbl_extend("force", {
    prompt_title = "Loam: Grep Notes",
    cwd = notes_path,
    glob_pattern = "*.md",
    additional_args = function()
      return {
        "--glob",
        "!.git",
        "--glob",
        "!.obsidian",
        "--glob",
        "!.foam",
      }
    end,
  }, opts))
end

--- Filter by type picker
---@param opts table|nil Picker options
function M.filter_type(opts)
  opts = opts or {}

  local types = config.get("types")
  local type_entries = {}

  for _, note_type in ipairs(types) do
    local icon, hl = config.get_icon(note_type)
    table.insert(type_entries, {
      value = note_type,
      display = icon .. " " .. note_type,
      ordinal = note_type,
      hl = hl,
    })
  end

  pickers
    .new(opts, {
      prompt_title = "Loam: Filter by Type",
      finder = require("telescope.finders").new_table({
        results = type_entries,
        entry_maker = function(entry)
          return entry
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            M.notes({ types = { selection.value } })
          end
        end)
        return true
      end,
    })
    :find()
end

--- Filter by tags picker
---@param opts table|nil Picker options
function M.filter_tags(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = "Loam: Filter by Tag",
      finder = loam_finders.tags_finder(opts),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            M.notes({ tags = { selection.tag } })
          end
        end)
        return true
      end,
    })
    :find()
end

--- Template picker for creating new notes
---@param opts table|nil Picker options
function M.templates(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = "Loam: Select Template",
      finder = loam_finders.templates_finder(opts),
      sorter = conf.generic_sorter(opts),
      previewer = conf.file_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            -- Prompt for title
            vim.ui.input({ prompt = "Note title: " }, function(title)
              if title and title ~= "" then
                local filepath = loam_actions.create_note(selection.value, title)
                if filepath then
                  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
                end
              else
                -- Use UUID as title if no title provided
                local filepath = loam_actions.create_note(selection.value, nil)
                if filepath then
                  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
                end
              end
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

--- Backlinks picker - show notes that link to a specific note
---@param opts table|nil Picker options (uuid required, or uses current buffer)
function M.backlinks(opts)
  opts = opts or {}

  local uuid = opts.uuid
  local title = opts.title

  -- If no UUID provided, try to get from current buffer
  if not uuid then
    local current_file = vim.fn.expand("%:p")
    uuid = utils.extract_uuid_from_path(current_file)
    if uuid then
      local fm = require("loam.frontmatter").parse_file(current_file)
      title = require("loam.frontmatter").get_title(fm) or uuid
    end
  end

  if not uuid then
    utils.notify("No UUID found for current file", "warn")
    return
  end

  local prompt_title = "Loam: Backlinks"
  if title then
    prompt_title = prompt_title .. " to " .. utils.truncate(title, 30)
  end

  pickers
    .new(opts, {
      prompt_title = prompt_title,
      finder = loam_finders.find_backlinks(uuid, opts),
      sorter = conf.generic_sorter(opts),
      previewer = conf.file_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
          end
        end)
        return true
      end,
    })
    :find()
end

--- Index notes picker
---@param opts table|nil Picker options
function M.indexes(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = "Loam: Index Notes",
      finder = loam_finders.find_index_notes(opts),
      sorter = conf.generic_sorter(opts),
      previewer = conf.file_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        -- Default: open index
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
          end
        end)

        -- Tab: show linked notes
        map("i", "<Tab>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            actions.close(prompt_bufnr)
            M.index_links({ filepath = selection.value, title = selection.title })
          end
        end)

        map("n", "<Tab>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            actions.close(prompt_bufnr)
            M.index_links({ filepath = selection.value, title = selection.title })
          end
        end)

        return true
      end,
    })
    :find()
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

  pickers
    .new(opts, {
      prompt_title = "Loam: Links from " .. utils.truncate(title, 30),
      finder = loam_finders.find_index_links(filepath, opts),
      sorter = conf.generic_sorter(opts),
      previewer = conf.file_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.exists then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
          elseif selection then
            utils.notify("Note not found: " .. selection.uuid, "warn")
          end
        end)
        return true
      end,
    })
    :find()
end

--- Journal picker
---@param opts table|nil Picker options
function M.journal(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = "Loam: Journal",
      finder = loam_finders.find_journal(opts),
      sorter = conf.generic_sorter(opts),
      previewer = conf.file_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
          end
        end)

        -- Create today's journal entry
        map("i", "<C-n>", function()
          actions.close(prompt_bufnr)
          local today = os.date("%Y-%m-%d")
          local journal_dir = config.get("notes_path") .. "/" .. config.get("directories").journal
          local filepath = journal_dir .. "/" .. today .. ".md"

          if not utils.file_exists(filepath) then
            utils.ensure_dir(journal_dir)
            local content = string.format("# %s\n\n", today)
            utils.write_file(filepath, content)
          end

          vim.cmd("edit " .. vim.fn.fnameescape(filepath))
        end)

        return true
      end,
    })
    :find()
end

return M
