-- =============================================================================
-- loam/finders: Custom finders for telescope-loam
-- =============================================================================

local finders = require("telescope.finders")

local config = require("loam.config")
local frontmatter = require("loam.frontmatter")
local links = require("loam.links")
local make_entry = require("loam.make_entry")
local utils = require("loam.utils")

local M = {}

--- Find all notes in the notes directory
---@param opts table Options
---@return table finder Telescope finder
function M.find_notes(opts)
  opts = opts or {}

  local notes_path = opts.notes_path or config.get("notes_path")
  local extension = config.get("extension")

  -- Use fd for fast file discovery
  local command = {
    "fd",
    "--type",
    "f",
    "--extension",
    extension:gsub("^%.", ""), -- Remove leading dot
    "--exclude",
    ".git",
    "--exclude",
    ".obsidian",
    "--exclude",
    ".foam",
    "--exclude",
    ".claude",
    ".",
    notes_path,
  }

  return finders.new_oneshot_job(command, {
    entry_maker = make_entry.make_note_entry(opts),
  })
end

--- Find notes filtered by type
--- Uses synchronous file discovery + frontmatter filtering
---@param opts table Options including type or types filter
---@return table finder
function M.find_by_type(opts)
  opts = opts or {}

  local notes_path = opts.notes_path or config.get("notes_path")
  local extension = config.get("extension")
  local filter_types = opts.types or (opts.type and { opts.type } or nil)

  if not filter_types then
    return M.find_notes(opts)
  end

  -- Get all markdown files
  local files = vim.fn.systemlist({
    "fd",
    "--type",
    "f",
    "--extension",
    extension:gsub("^%.", ""),
    "--exclude",
    ".git",
    "--exclude",
    ".obsidian",
    ".",
    notes_path,
  })

  -- Filter by frontmatter type (supports notes with multiple types)
  local filtered_files = {}
  for _, filepath in ipairs(files) do
    local fm = frontmatter.parse_file(filepath)

    for _, t in ipairs(filter_types) do
      if frontmatter.has_type(fm, t) then
        table.insert(filtered_files, filepath)
        break
      end
    end
  end

  return finders.new_table({
    results = filtered_files,
    entry_maker = make_entry.make_note_entry(opts),
  })
end

--- Find notes filtered by tags
--- Uses synchronous file discovery + frontmatter filtering
---@param opts table Options including tags filter
---@return table finder
function M.find_by_tags(opts)
  opts = opts or {}

  local filter_tags = opts.tags
  if not filter_tags or #filter_tags == 0 then
    return M.find_notes(opts)
  end

  local notes_path = opts.notes_path or config.get("notes_path")
  local extension = config.get("extension")

  -- Get all markdown files
  local files = vim.fn.systemlist({
    "fd",
    "--type",
    "f",
    "--extension",
    extension:gsub("^%.", ""),
    "--exclude",
    ".git",
    "--exclude",
    ".obsidian",
    ".",
    notes_path,
  })

  -- Filter by frontmatter tags
  local filtered_files = {}
  for _, filepath in ipairs(files) do
    local fm = frontmatter.parse_file(filepath)
    local entry_tags = frontmatter.get_tags(fm)

    -- Check if all filter_tags are present
    local all_match = true
    for _, filter_tag in ipairs(filter_tags) do
      local found = false
      for _, tag in ipairs(entry_tags) do
        if tag == filter_tag then
          found = true
          break
        end
      end
      if not found then
        all_match = false
        break
      end
    end

    if all_match then
      table.insert(filtered_files, filepath)
    end
  end

  return finders.new_table({
    results = filtered_files,
    entry_maker = make_entry.make_note_entry(opts),
  })
end

--- Find backlinks to a specific note
---@param uuid string UUID of the target note
---@param opts table Options
---@return table finder
function M.find_backlinks(uuid, opts)
  opts = opts or {}

  local backlink_files = links.find_backlinks(uuid)

  return finders.new_table({
    results = backlink_files,
    entry_maker = make_entry.make_backlink_entry(opts),
  })
end

--- Find notes linked from an index note
---@param filepath string Path to index note
---@param opts table Options
---@return table finder
function M.find_index_links(filepath, opts)
  opts = opts or {}

  local content = utils.read_file(filepath)
  if not content then
    return finders.new_table({ results = {} })
  end

  local all_links = links.extract_all_links(content)
  local notes_path = config.get("notes_path")

  -- Resolve links to actual files
  local resolved = {}
  for _, link in ipairs(all_links) do
    local resolved_path = links.resolve_uuid(link.uuid, notes_path)
    table.insert(resolved, {
      filepath = resolved_path,
      display_text = link.display_text,
      uuid = link.uuid,
    })
  end

  return finders.new_table({
    results = resolved,
    entry_maker = make_entry.make_index_link_entry(opts),
  })
end

--- Collect all unique tags from notes
---@param opts table Options
---@return table tags List of {tag, count}
function M.collect_tags(opts)
  opts = opts or {}

  local notes_path = opts.notes_path or config.get("notes_path")
  local extension = config.get("extension")

  -- Get all note files
  local files = vim.fn.systemlist({
    "fd",
    "--type",
    "f",
    "--extension",
    extension:gsub("^%.", ""),
    "--exclude",
    ".git",
    "--exclude",
    ".obsidian",
    ".",
    notes_path,
  })

  local tag_counts = {}

  for _, filepath in ipairs(files) do
    local fm = frontmatter.parse_file(filepath)
    local tags = frontmatter.get_tags(fm)

    for _, tag in ipairs(tags) do
      tag_counts[tag] = (tag_counts[tag] or 0) + 1
    end
  end

  -- Convert to sorted list
  local tags = {}
  for tag, count in pairs(tag_counts) do
    table.insert(tags, { tag = tag, count = count })
  end

  table.sort(tags, function(a, b)
    return a.count > b.count
  end)

  return tags
end

--- Create finder for tags
---@param opts table Options
---@return table finder
function M.tags_finder(opts)
  opts = opts or {}

  local tags = M.collect_tags(opts)

  return finders.new_table({
    results = tags,
    entry_maker = make_entry.make_tag_entry(opts),
  })
end

--- Collect all templates from templates directory
---@param opts table Options
---@return table templates List of template info
function M.collect_templates(opts)
  opts = opts or {}

  local templates_path = config.get_templates_path()
  local extension = config.get("extension")

  local files = vim.fn.systemlist({
    "fd",
    "--type",
    "f",
    "--extension",
    extension:gsub("^%.", ""),
    ".",
    templates_path,
  })

  local templates = {}

  for _, filepath in ipairs(files) do
    local filename = vim.fn.fnamemodify(filepath, ":t:r")
    local fm = frontmatter.parse_file(filepath)
    local note_type = frontmatter.get_type(fm)

    table.insert(templates, {
      path = filepath,
      name = filename,
      type = note_type ~= "unknown" and note_type or filename,
      description = "Create new " .. filename .. " note",
    })
  end

  return templates
end

--- Create finder for templates
---@param opts table Options
---@return table finder
function M.templates_finder(opts)
  opts = opts or {}

  local templates = M.collect_templates(opts)

  return finders.new_table({
    results = templates,
    entry_maker = make_entry.make_template_entry(opts),
  })
end

--- Find journal entries
---@param opts table Options
---@return table finder
function M.find_journal(opts)
  opts = opts or {}

  local notes_path = config.get("notes_path")
  local journal_dir = notes_path .. "/" .. config.get("directories").journal

  local command = {
    "fd",
    "--type",
    "f",
    "--extension",
    "md",
    ".",
    journal_dir,
  }

  return finders.new_oneshot_job(command, {
    entry_maker = make_entry.make_journal_entry(opts),
  })
end

--- Find index-type notes
---@param opts table Options
---@return table finder
function M.find_index_notes(opts)
  opts = opts or {}
  return M.find_by_type(vim.tbl_extend("force", opts, {
    types = { "index" },
  }))
end

return M
