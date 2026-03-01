-- =============================================================================
-- holon/zk/finders: Zettelkasten data queries
-- =============================================================================

local config = require("holon.config")
local file_search = require("holon.file_search")
local frontmatter = require("holon.frontmatter")
local links = require("holon.links")
local utils = require("holon.utils")

local M = {}

--- Find all notes in the notes directory
---@param opts table|nil Options
---@return string[] files List of file paths
function M.find_notes(opts)
  opts = opts or {}
  local notes_path = opts.notes_path or config.get("notes_path")
  return file_search.list_files(notes_path)
end

--- Find notes filtered by type
---@param opts table Options including type or types filter
---@return string[] files Filtered file paths
function M.find_by_type(opts)
  opts = opts or {}

  local filter_types = opts.types or (opts.type and { opts.type } or nil)
  if not filter_types then
    return M.find_notes(opts)
  end

  local notes_path = opts.notes_path or config.get("notes_path")
  local files = file_search.list_files(notes_path)

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

  return filtered_files
end

--- Find notes filtered by tags
---@param opts table Options including tags filter
---@return string[] files Filtered file paths
function M.find_by_tags(opts)
  opts = opts or {}

  local filter_tags = opts.tags
  if not filter_tags or #filter_tags == 0 then
    return M.find_notes(opts)
  end

  local notes_path = opts.notes_path or config.get("notes_path")
  local files = file_search.list_files(notes_path)

  local filtered_files = {}
  for _, filepath in ipairs(files) do
    local content = utils.read_file(filepath)
    local fm = content and frontmatter.parse(content) or nil
    local entry_tags = frontmatter.get_tags(fm, content)

    local all_match = true
    for _, filter_tag in ipairs(filter_tags) do
      if not vim.tbl_contains(entry_tags, filter_tag) then
        all_match = false
        break
      end
    end

    if all_match then
      table.insert(filtered_files, filepath)
    end
  end

  return filtered_files
end

--- Find backlinks to a specific note
---@param uuid string UUID of the target note
---@param opts table|nil Options
---@return string[] files List of file paths with backlinks
function M.find_backlinks(uuid, opts)
  opts = opts or {}
  return links.find_backlinks(uuid)
end

--- Find notes linked from a given note (forward links)
---@param filepath string Path to source note
---@param opts table|nil Options
---@return table[] resolved List of { filepath, display_text, uuid }
function M.find_forward_links(filepath, opts)
  opts = opts or {}

  local content = utils.read_file(filepath)
  if not content then
    return {}
  end

  local all_links = links.extract_all_links(content)

  local resolved = {}
  for _, link in ipairs(all_links) do
    local resolved_path = links.resolve_link_target(link.uuid, filepath)
    if resolved_path then
      table.insert(resolved, resolved_path)
    end
  end

  return resolved
end

--- Find notes linked from an index note
---@param filepath string Path to index note
---@param opts table|nil Options
---@return table[] resolved List of { filepath, display_text, uuid }
function M.find_index_links(filepath, opts)
  opts = opts or {}

  local content = utils.read_file(filepath)
  if not content then
    return {}
  end

  local all_links = links.extract_all_links(content)

  local resolved = {}
  for _, link in ipairs(all_links) do
    local resolved_path = links.resolve_link_target(link.uuid, filepath)
    table.insert(resolved, {
      filepath = resolved_path,
      display_text = link.display_text,
      uuid = link.uuid,
    })
  end

  return resolved
end

--- Collect all unique tags from notes
---@param opts table|nil Options
---@return table[] tags List of {tag, count}
function M.collect_tags(opts)
  opts = opts or {}

  local notes_path = opts.notes_path or config.get("notes_path")
  local files = file_search.list_files(notes_path)

  local tag_counts = {}

  for _, filepath in ipairs(files) do
    local content = utils.read_file(filepath)
    local fm = content and frontmatter.parse(content) or nil
    local tags = frontmatter.get_tags(fm, content)

    for _, tag in ipairs(tags) do
      tag_counts[tag] = (tag_counts[tag] or 0) + 1
    end
  end

  local tags = {}
  for tag, count in pairs(tag_counts) do
    table.insert(tags, { tag = tag, count = count })
  end

  table.sort(tags, function(a, b)
    return a.count > b.count
  end)

  return tags
end

--- Collect all templates from templates directory
---@param opts table|nil Options
---@return table[] templates List of template info
function M.collect_templates(opts)
  opts = opts or {}

  local templates_path = config.get_templates_path()
  local files = file_search.list_files(templates_path)

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

--- Find journal entries
---@param opts table|nil Options
---@return string[] files List of journal file paths
function M.find_journal(opts)
  opts = opts or {}
  local notes_path = config.get("notes_path")
  local journal_dir = notes_path .. "/" .. config.get("directories").journal
  return file_search.list_files(journal_dir)
end

--- Find index-type notes
---@param opts table|nil Options
---@return string[] files List of index note file paths
function M.find_index_notes(opts)
  opts = opts or {}
  return M.find_by_type(vim.tbl_extend("force", opts, {
    types = { "index" },
  }))
end

--- Get additional rg args for .holonignore support (used by pickers)
---@return string[] args
function M.get_rg_args()
  return file_search.build_rg_args()
end

--- Find orphan notes (no incoming or outgoing links)
---@param opts table|nil Options
---@return string[] paths List of orphan note file paths
function M.find_orphan_notes(opts)
  opts = opts or {}
  local notes_path = opts.notes_path or config.get("notes_path")
  local journal_dir = config.get("directories.journal")

  -- Build graph with ALL files (ignore .holonignore) for accurate link resolution
  local all_files = file_search.list_files(notes_path, { no_ignore = true })
  local non_journal = vim.tbl_filter(function(f)
    return not (journal_dir and f:find(journal_dir, 1, true))
  end, all_files)

  local graph_mod = require("holon.graph")
  local graph = graph_mod.build(non_journal)
  local orphan_ids = graph_mod.find_orphans(graph)

  -- Filter results: only show orphans that are NOT in .holonignore
  local visible_files = file_search.list_files(notes_path)
  local visible_set = {}
  for _, f in ipairs(visible_files) do
    visible_set[f] = true
  end

  local orphan_paths = {}
  for _, id in ipairs(orphan_ids) do
    local path = graph.nodes[id]
    if visible_set[path] then
      table.insert(orphan_paths, path)
    end
  end

  return orphan_paths
end

return M
