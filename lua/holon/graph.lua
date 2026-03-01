-- =============================================================================
-- holon/graph: Directed link graph builder (sparse adjacency list)
-- =============================================================================
-- Builds a graph of inter-note links in a single pass over all files.
-- Used for orphan detection and future graph visualization features.
-- =============================================================================

local links = require("holon.links")
local utils = require("holon.utils")

local M = {}

--- Build a directed link graph from all notes (single pass)
---@param files string[] File paths
---@return table graph { nodes, index, outgoing, incoming }
function M.build(files)
  local graph = {
    nodes = {},     -- [node_id] = filepath
    index = {},     -- [filepath] = node_id, [uuid] = node_id
    outgoing = {},  -- [node_id] = { target_id, ... }
    incoming = {},  -- [node_id] = { source_id, ... }
  }

  -- Phase 1: assign sequential IDs and build UUID index
  for i, filepath in ipairs(files) do
    graph.nodes[i] = filepath
    graph.index[filepath] = i
    local uuid = utils.extract_uuid_from_path(filepath)
    if uuid then
      graph.index[uuid] = i
    end
  end

  -- Phase 2: extract outgoing links and build edges
  for i, filepath in ipairs(files) do
    local content = utils.read_file(filepath)
    if content then
      local out_links = links.extract_all_links(content)
      for _, link in ipairs(out_links) do
        local target = link.uuid
        if target then
          target = target:gsub("%.md$", "")
          local j = graph.index[target]
          if j and j ~= i then
            graph.outgoing[i] = graph.outgoing[i] or {}
            table.insert(graph.outgoing[i], j)
            graph.incoming[j] = graph.incoming[j] or {}
            table.insert(graph.incoming[j], i)
          end
        end
      end
    end
  end

  return graph
end

--- Find orphan node IDs (no outgoing AND no incoming edges)
---@param graph table Graph returned by build()
---@return number[] orphan_ids
function M.find_orphans(graph)
  local orphans = {}
  for i, _ in ipairs(graph.nodes) do
    if not graph.outgoing[i] and not graph.incoming[i] then
      table.insert(orphans, i)
    end
  end
  return orphans
end

return M
