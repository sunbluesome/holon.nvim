# telescope-loam

Telescope extension for Zettelkasten workflow. Provides note searching, creation, backlink discovery, and index navigation.

## Requirements

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [fd](https://github.com/sharkdp/fd) - Fast file finder
- [ripgrep](https://github.com/BurntSushi/ripgrep) - Fast content search

## Installation

### lazy.nvim

```lua
{
  "your-username/telescope-loam",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  keys = {
    { "<leader>zn", "<cmd>Telescope loam notes<cr>", desc = "Loam: Find notes" },
    { "<leader>zg", "<cmd>Telescope loam grep<cr>", desc = "Loam: Grep notes" },
    { "<leader>zc", "<cmd>Telescope loam new<cr>", desc = "Loam: Create note" },
    { "<leader>zb", "<cmd>Telescope loam backlinks<cr>", desc = "Loam: Backlinks" },
    { "<leader>zi", "<cmd>Telescope loam indexes<cr>", desc = "Loam: Indexes" },
    { "<leader>zj", "<cmd>Telescope loam journal<cr>", desc = "Loam: Journal" },
    { "<leader>zt", "<cmd>Telescope loam tags<cr>", desc = "Loam: Filter by tags" },
    { "<leader>zT", "<cmd>Telescope loam types<cr>", desc = "Loam: Filter by type" },
    { "<leader>zf", "<cmd>LoamFollow<cr>", desc = "Loam: Follow link" },
    { "<leader>zd", "<cmd>LoamToday<cr>", desc = "Loam: Today's journal" },
  },
  opts = {
    notes_path = vim.fn.expand("~/notes"),
  },
  config = function(_, opts)
    require("loam").setup(opts)
    require("telescope").load_extension("loam")
  end,
}
```

### Local Development

```lua
{
  dir = "~/Projects/telescope-loam",
  dev = true,
  -- ... rest of config
}
```

## Configuration

```lua
require("loam").setup({
  -- Path to your Zettelkasten notes directory
  notes_path = vim.fn.expand("~/notes"),

  -- Subdirectory structure (relative to notes_path)
  directories = {
    permanent = "Notes/Permanent",
    fleeting = "Notes/Fleeting",
    literature = "Notes/Literature",
    project = "Notes/Project",
    index = "Notes/Permanent",
    structure = "Notes/Permanent",
    journal = "journal",
  },

  -- Template directory (relative to notes_path)
  templates_path = ".foam/templates",

  -- File extension for notes
  extension = ".md",

  -- Link format: "wiki" for [[UUID|title]] or "markdown" for [title](UUID.md)
  default_link_format = "wiki",

  -- Picker settings
  picker = {
    show_icons = true,
    show_tags = true,
    initial_mode = "insert",
    layout_strategy = "horizontal",
    layout_config = {
      horizontal = { preview_width = 0.5 },
      width = 0.9,
      height = 0.8,
    },
  },
})
```

## Usage

### Telescope Commands

| Command | Description |
|---------|-------------|
| `:Telescope loam notes` | Find and open notes |
| `:Telescope loam grep` | Search note contents |
| `:Telescope loam new` | Create new note from template |
| `:Telescope loam backlinks` | Show notes linking to current note |
| `:Telescope loam indexes` | Browse index-type notes |
| `:Telescope loam journal` | Browse journal entries |
| `:Telescope loam tags` | Filter notes by tag |
| `:Telescope loam types` | Filter notes by type |

### User Commands

| Command | Description |
|---------|-------------|
| `:Loam` | Open notes picker |
| `:LoamNew` | Create new note |
| `:LoamGrep` | Grep notes |
| `:LoamBacklinks` | Show backlinks |
| `:LoamIndexes` | Browse indexes |
| `:LoamJournal` | Browse journal |
| `:LoamTags` | Filter by tags |
| `:LoamTypes` | Filter by type |
| `:LoamFollow` | Follow link under cursor |
| `:LoamToday` | Open/create today's journal |

### Link Navigation with `gd`

Inside notes directory, `gd` is automatically mapped to follow links:

- On a wiki-style link `[[UUID|title]]` - jumps to the linked note
- On a markdown link `[title](UUID.md)` - jumps to the linked note
- Elsewhere - falls back to LSP go-to-definition or normal `gd`

This works like code navigation: place cursor on a link and press `gd` to follow it.

### Picker Keybindings

Inside the notes picker:

| Mode | Key | Action |
|------|-----|--------|
| i/n | `<CR>` | Open note |
| i | `<C-n>` | Create new note |
| i | `<C-b>` | Show backlinks for selected note |
| n | `n` | Create new note |
| n | `b` | Show backlinks |

Inside the indexes picker:

| Mode | Key | Action |
|------|-----|--------|
| i/n | `<CR>` | Open index note |
| i/n | `<Tab>` | Show notes linked from index |

Inside the journal picker:

| Mode | Key | Action |
|------|-----|--------|
| i | `<C-n>` | Create today's journal entry |

## Note Format

Notes should have YAML frontmatter:

```yaml
---
title: Note Title
created: 2024-01-01T12:00:00
lastmod: 2024-01-01T12:00:00
url: null
type: permanent
tags:
    - tag1
    - tag2
---

Note content here...
```

### Multiple Types

Notes can have multiple types using YAML list format:

```yaml
---
title: Project Index
type:
    - project
    - index
tags:
    - data_science
---
```

This note will appear in both project and index searches.

### Supported Types

- `permanent` - Core knowledge notes
- `fleeting` - Quick, temporary notes
- `literature` - Academic papers and publications
- `project` - Project-specific documentation
- `index` - Navigation/entry point notes
- `structure` - Structural organization notes

## Link Formats

telescope-loam supports two link formats:

### Wiki-style (Foam/Obsidian compatible)

```markdown
[[uuid-here|Display Text]]
[[uuid-here]]
```

### Standard Markdown

```markdown
[Display Text](uuid-here.md)
```

## Templates

Place templates in your `templates_path` directory (default: `.foam/templates/`).

Template variables:
- `${UUID}` - Auto-generated UUID v4
- `${CURRENT_YEAR}` - Current year (4 digits)
- `${CURRENT_MONTH}` - Current month (2 digits)
- `${CURRENT_DATE}` - Current day (2 digits)
- `${CURRENT_HOUR}` - Current hour (2 digits)
- `${CURRENT_MINUTE}` - Current minute (2 digits)
- `${CURRENT_SECOND}` - Current second (2 digits)

Example template (`permanent.md`):

```yaml
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

## API

### Lua API

```lua
local loam = require("loam")

-- Access modules
loam.pickers.notes()
loam.pickers.backlinks({ uuid = "...", title = "..." })
loam.actions.create_note(template_path, title)
loam.actions.follow_link_under_cursor()
loam.actions.smart_gd()  -- Follow link or fallback to LSP
loam.utils.generate_uuid()
loam.frontmatter.parse_file(filepath)
loam.frontmatter.has_type(fm, "index")  -- Check for multiple types
loam.links.find_backlinks(uuid)
```

## License

MIT
