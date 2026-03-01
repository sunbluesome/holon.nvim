# holon.nvim

Zettelkasten note-taking and GTD task management for Neovim. Zero external plugin dependencies.

Fuzzy search, live grep, backlink discovery, index navigation, journal management, and a full GTD board - all built on native float windows. No telescope.nvim required.

## Features

- Fuzzy note search with live preview
- Live grep across notes via ripgrep
- Wiki-style `[[target|title]]` and Markdown `[title](target.md)` link formats
- Backlink detection and navigation
- Index note browsing with drill-down into linked notes
- Tag and type filtering (YAML frontmatter and inline `#tags`)
- Template-based note creation with UUID generation
- Journal management and quick today's entry
- Smart `gd` mapping with LSP fallback for link navigation
- GTD board with status/horizon/inbox/done views and timeline visualization
- Link browser for graph exploration
- Orphan note detection
- `.holonignore` support for excluding files from search

## Screenshots

### Zettelkasten

| `:Holon` - Notes | `:HolonGrep` - Grep |
|---|---|
| ![notes](assets/zk_list.png) | ![grep](assets/zk_grep.png) |

| `:HolonIndexes` - Index drill-down | `:HolonJournal` - Journal |
|---|---|
| ![index](assets/zk_index.png) | ![journal](assets/zk_journal.png) |

| `:HolonOrphans` - Orphan notes | |
|---|---|
| ![orphans](assets/zk_orphan.png) | |

### Link Browser

| Backlinks | Forward links |
|---|---|
| ![backlinks](assets/zk_link_backlink.png) | ![forward](assets/zk_link_forward.png) |

| Shared tags | |
|---|---|
| ![tags](assets/zk_link_tag.png) | |

### GTD

| `:HolonGtd` - Board (status) | Board (horizon) |
|---|---|
| ![board](assets/gtd_board.png) | ![horizon](assets/gtd_board_horizon.png) |

| Inbox - Add task | Inbox - Promote (calendar) |
|---|---|
| ![add](assets/gtd_inbox_add.png) | ![promote](assets/gtd_inbox_promote.png) |

| Done view | |
|---|---|
| ![done](assets/gtd_done.png) | |

## Requirements

- Neovim >= 0.10
- [fd](https://github.com/sharkdp/fd) - file finder
- [ripgrep](https://github.com/BurntSushi/ripgrep) - content search
- Nerd Font (for icons)

## Installation

### lazy.nvim

```lua
{
  "your-username/holon.nvim",
  keys = {
    { "<leader>zn", "<cmd>Holon<cr>", desc = "Holon: Notes" },
    { "<leader>zg", "<cmd>HolonGrep<cr>", desc = "Holon: Grep" },
    { "<leader>zc", "<cmd>HolonNew<cr>", desc = "Holon: New note" },
    { "<leader>zb", "<cmd>HolonBacklinks<cr>", desc = "Holon: Backlinks" },
    { "<leader>zi", "<cmd>HolonIndexes<cr>", desc = "Holon: Indexes" },
    { "<leader>zj", "<cmd>HolonJournal<cr>", desc = "Holon: Journal" },
    { "<leader>zt", "<cmd>HolonTags<cr>", desc = "Holon: Tags" },
    { "<leader>zT", "<cmd>HolonTypes<cr>", desc = "Holon: Types" },
    { "<leader>zf", "<cmd>HolonFollow<cr>", desc = "Holon: Follow link" },
    { "<leader>zd", "<cmd>HolonToday<cr>", desc = "Holon: Today's journal" },
    { "<leader>zG", "<cmd>HolonGtd<cr>", desc = "Holon: GTD board" },
    { "<leader>zl", "<cmd>HolonBrowse<cr>", desc = "Holon: Link browser" },
    { "<leader>zo", "<cmd>HolonOrphans<cr>", desc = "Holon: Orphan notes" },
  },
  opts = {
    notes_path = vim.fn.expand("~/notes"),
  },
  config = function(_, opts)
    require("holon").setup(opts)
  end,
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:Holon` | Find and open notes |
| `:HolonNew` | Create a note from template |
| `:HolonGrep [query]` | Search note contents |
| `:HolonBacklinks` | Show backlinks to current note |
| `:HolonLinks` | Show forward links from current note |
| `:HolonIndexes` | Browse index notes with drill-down |
| `:HolonJournal` | Browse journal entries |
| `:HolonTags` | Filter notes by tag |
| `:HolonTypes` | Filter notes by type |
| `:HolonFollow` | Follow link under cursor |
| `:HolonToday` | Open or create today's journal entry |
| `:HolonGtd` | Open GTD board |
| `:HolonBrowse` | Open link browser |
| `:HolonOrphans` | Find orphan notes |

## Pickers

### Common Keybindings

All pickers share the following keybindings:

| Mode | Key | Action |
|------|-----|--------|
| Insert | `<C-j>` / `<C-n>` | Next item |
| Insert | `<C-k>` / `<C-p>` | Previous item |
| Insert | `<CR>` | Move focus to results list |
| Insert | `<Esc>` | Switch to normal mode (stay in search) |
| Normal | `j` / `k` | Move cursor |
| Normal | `<CR>` | Open selected |
| Normal | `/` or `i` | Switch to insert mode (search) |
| Normal | `<Tab>` | Toggle mark (multi-select) |
| Normal | `<C-d>` / `<C-u>` | Scroll preview |
| Normal | `q` | Close picker |

### Notes Picker (configurable via `mappings`)

| Mode | Key | Action |
|------|-----|--------|
| Insert | `<C-n>` | Create new note from template |
| Insert | `<C-b>` | Show backlinks for selected note |
| Insert | `<C-f>` | Show forward links from selected note |
| Insert | `<C-l>` | Insert link to selected note at cursor |
| Insert | `<C-t>` | Filter by type |
| Insert | `<C-g>` | Filter by tag |
| Normal | `n` | Create new note from template |
| Normal | `b` | Show backlinks for selected note |
| Normal | `f` | Show forward links from selected note |
| Normal | `l` | Insert link to selected note at cursor |
| Normal | `t` | Filter by type |
| Normal | `g` | Filter by tag |
| Normal | `<BS>` | Back to previous filter |

### Index Picker

| Key | Action |
|-----|--------|
| `<Tab>` | Drill down into linked notes |
| `<BS>` | Go back up |

### Journal Picker

| Key | Action |
|-----|--------|
| `<C-n>` | Create today's journal entry |

### Orphans Picker

| Key | Action |
|-----|--------|
| `<Tab>` | Toggle mark |
| `d` | Delete marked notes |

## Link Navigation

Inside `notes_path`, `gd` is automatically mapped in Markdown files to follow links:

- Resolves the link at the cursor
- Supports `[[target|title]]`, `[[target]]`, and `[title](target.md)`
- Skips external URLs (`https://...`)
- Falls back to LSP go-to-definition, then normal `gd`

Link targets can be UUIDs, filenames, or relative paths. The resolver searches in this order:

1. Relative to the current file
2. Relative to `notes_path`
3. Configured subdirectories
4. `fd` fallback search

## Link Browser

A file-browser-style navigator for exploring the link graph between notes. Opens on a selected note and lets you traverse forward links, backlinks, or notes sharing tags.

| Key | Action |
|-----|--------|
| `j` / `k` | Move cursor |
| `<CR>` | Dive into selected note |
| `o` | Open note in editor |
| `f` | Switch to forward links mode |
| `b` | Switch to backlinks mode |
| `t` | Switch to shared tags mode |
| `-` / `<BS>` | Go back in history |
| `<C-d>` / `<C-u>` | Scroll |
| `q` / `<Esc>` | Close |

## GTD Board

A task management board integrated with your note files. Tasks are notes with GTD-specific frontmatter fields.

### Data Model

```yaml
---
title: Task Name
type: project
status: todo
target_date: 2025-01-15
start_date: 2025-01-01
blocked_by:
    - uuid-of-blocker
---
```

Status values: `inbox`, `todo`, `inprogress`, `waiting`, `delegate`, `done`

### Keybindings

| Key | Action |
|-----|--------|
| `j` / `k` | Move cursor |
| `<CR>` | Open note |
| `c` | Change status (picker) |
| `p` | Promote task (inbox view) / Put marked tasks (status view) |
| `b` | Set blocked_by |
| `t` | Set target date (calendar) |
| `s` | Set start date (calendar) |
| `a` | Add new task |
| `dd` | Delete task (inbox view) |
| `I` | Switch to inbox view |
| `H` | Switch to horizon view |
| `D` | Switch to done view |
| `r` | Restore done task |
| `w` / `m` | Timeline scale (week / month) |
| `g` | Toggle preview panel |
| `<Tab>` | Toggle mark |
| `<C-j>` / `<C-k>` | Switch between tasks and preview panels |
| `q` / `<Esc>` | Close |

## Note Format

Notes use YAML frontmatter:

```yaml
---
title: Note Title
created: 2024-01-01T12:00:00
lastmod: 2024-01-01T12:00:00
url: null
type: permanent
tags:
    - topic
    - subtopic
---

Note content here...
```

### Note Types

| Type | Description |
|------|-------------|
| `permanent` | Core knowledge notes |
| `fleeting` | Quick, temporary notes |
| `literature` | Papers and publications |
| `project` | Project documentation |
| `index` | Navigation entry points |
| `structure` | Organizational notes |

Multiple types are supported:

```yaml
type:
    - project
    - index
```

### Tag Formats

All of the following are recognized:

- YAML list in frontmatter: `tags: [topic, subtopic]`
- YAML block in frontmatter: `tags:\n    - topic`
- Inline tags in the note body: `#topic`

## Templates

Place template files in your `templates_path` directory (default: `templates/`). When creating a note with `:HolonNew`, you select a template and the variables are substituted.

### Template Variables

| Variable | Description |
|----------|-------------|
| `${UUID}` | UUID v4 |
| `${CURRENT_YEAR}` | Year (4 digits) |
| `${CURRENT_MONTH}` | Month (2 digits) |
| `${CURRENT_DATE}` | Day (2 digits) |
| `${CURRENT_HOUR}` | Hour (2 digits) |
| `${CURRENT_MINUTE}` | Minute (2 digits) |
| `${CURRENT_SECOND}` | Second (2 digits) |

### Example Template (`permanent.md`)

```markdown
---
title: ${UUID}
created: ${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}T${CURRENT_HOUR}:${CURRENT_MINUTE}:${CURRENT_SECOND}
lastmod: ${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}T${CURRENT_HOUR}:${CURRENT_MINUTE}:${CURRENT_SECOND}
url: null
type: permanent
tags:
    - null
---

```

## Configuration

All options with their defaults:

```lua
require("holon").setup({
  -- Path to notes directory (required)
  notes_path = vim.fn.expand("~/notes"),

  -- Subdirectory structure (relative to notes_path)
  -- Note types are derived from these keys (excluding "journal").
  directories = {
    permanent  = "Notes/Permanent",
    fleeting   = "Notes/Fleeting",
    literature = "Notes/Literature",
    project    = "Notes/Project",
    index      = "Notes/Permanent",
    structure  = "Notes/Permanent",
    journal    = "journal",
  },

  -- Template directory (relative to notes_path)
  templates_path = "templates",

  -- File extension
  extension = ".md",

  -- Filename style: "uuid" (auto-generated UUID) or "manual" (user-specified)
  filename_style = "uuid",

  -- Link format: "wiki" for [[target|title]], "markdown" for [title](target.md)
  default_link_format = "wiki",

  -- Timezone offset from UTC in hours (nil = system local time)
  -- Examples: 9 = JST, -5 = EST, 0 = UTC
  timezone_offset = nil,

  -- Picker display settings
  picker = {
    show_icons = true,
    show_tags = true,
    initial_mode = "insert",
    layout_config = {
      width = 0.9,
      height = 0.8,
      horizontal = {
        preview_width = 0.5,
      },
    },
  },

  -- Nerd Font icons per note type
  icons = {
    permanent  = { icon = "󰆼", hl = "HolonPermanent" },
    fleeting   = { icon = "󱞁", hl = "HolonFleeting" },
    literature = { icon = "󰂺", hl = "HolonLiterature" },
    project    = { icon = "󰳏", hl = "HolonProject" },
    index      = { icon = "󰉋", hl = "HolonIndex" },
    structure  = { icon = "󰙅", hl = "HolonStructure" },
    default    = { icon = "󰈙", hl = "HolonDefault" },
  },

  -- Keybindings inside the notes picker
  -- Available actions: "create_note", "show_backlinks", "show_forward_links",
  --                    "insert_link", "filter_by_type", "filter_by_tag"
  mappings = {
    i = {
      ["<C-n>"] = "create_note",
      ["<C-b>"] = "show_backlinks",
      ["<C-f>"] = "show_forward_links",
      ["<C-l>"] = "insert_link",
      ["<C-t>"] = "filter_by_type",
      ["<C-g>"] = "filter_by_tag",
    },
    n = {
      ["n"] = "create_note",
      ["b"] = "show_backlinks",
      ["f"] = "show_forward_links",
      ["l"] = "insert_link",
      ["t"] = "filter_by_type",
      ["g"] = "filter_by_tag",
    },
  },

  -- GTD board settings
  gtd = {
    statuses = { "inbox", "todo", "inprogress", "waiting", "delegate", "done" },

    -- Icons shown in the board for each status
    status_icons = {
      inbox      = { icon = "󰁔", hl = "HolonGtdInbox" },
      todo       = { icon = "󰝖", hl = "HolonGtdTodo" },
      inprogress = { icon = "󱓻", hl = "HolonGtdProgress" },
      waiting    = { icon = "󰏤", hl = "HolonGtdWaiting" },
      delegate   = { icon = "󰜵", hl = "HolonGtdDelegate" },
      done       = { icon = "󰄲", hl = "HolonGtdDone" },
    },

    -- Blocked indicator
    blocked_icon = "🔒",

    -- Board layout
    layout = {
      width = 0.9,
      height = 0.8,
      timeline_min_width = 30,
      preview_ratio = 0.45,
    },
  },
})
```

### Highlight Groups

Define these in your colorscheme or `init.lua` to customize colors:

| Group | Used for |
|-------|----------|
| `HolonPermanent` | Permanent note icon |
| `HolonFleeting` | Fleeting note icon |
| `HolonLiterature` | Literature note icon |
| `HolonProject` | Project note icon |
| `HolonIndex` | Index note icon |
| `HolonStructure` | Structure note icon |
| `HolonDefault` | Untyped note icon |
| `HolonGtdInbox` | GTD inbox status icon |
| `HolonGtdTodo` | GTD todo status icon |
| `HolonGtdProgress` | GTD in-progress status icon |
| `HolonGtdWaiting` | GTD waiting status icon |
| `HolonGtdDelegate` | GTD delegate status icon |
| `HolonGtdDone` | GTD done status icon |

## .holonignore

Create a `.holonignore` file in your `notes_path` to exclude files from search results. Uses the same syntax as `.gitignore`:

```gitignore
.git/
.obsidian/
.claude/
.cursor/
node_modules/
```

When `.holonignore` exists, it is used as the sole exclusion source for both `fd` and `rg` searches. All default ignore behavior (`.gitignore`, hidden directories) is disabled to give you full control.

## Module Structure

```
lua/holon/
├── init.lua           # Entry point
├── config.lua         # Configuration
├── utils.lua          # Utilities
├── frontmatter.lua    # YAML frontmatter parsing
├── links.lua          # Link extraction and resolution
├── graph.lua          # Link graph
├── file_search.lua    # fd/rg infrastructure
├── picker.lua         # Float window picker
├── zk/                # Zettelkasten
│   ├── finders.lua    # Note queries
│   ├── actions.lua    # Note operations
│   ├── make_entry.lua # Entry formatting
│   ├── pickers.lua    # Picker definitions
│   └── link_browser.lua
└── gtd/               # Getting Things Done
    ├── finders.lua    # Task queries
    ├── state.lua      # Board state
    ├── render.lua     # Panel rendering
    ├── board.lua      # Board UI
    ├── timeline.lua   # Timeline visualization
    └── calendar.lua   # Date picker
```

## License

[MIT](LICENSE)
