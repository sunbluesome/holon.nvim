# Architecture

Developer reference for holon.nvim internals.

## Module Layers

```mermaid
graph TD
    subgraph Entry Points
        plugin["plugin/holon.lua"]
    end

    subgraph UI Layer
        zkpickers["zk/pickers.lua"]
        linkbrowser["zk/link_browser.lua"]
        gtdboard["gtd/board.lua"]
    end

    subgraph Service Layer
        zkfinders["zk/finders.lua"]
        zkactions["zk/actions.lua"]
        gtdfinders["gtd/finders.lua"]
        gtdstate["gtd/state.lua"]
    end

    subgraph Domain Layer
        frontmatter["frontmatter.lua"]
        links["links.lua"]
        graph["graph.lua"]
        makeentry["zk/make_entry.lua"]
        gtdrender["gtd/render.lua"]
        gtdtimeline["gtd/timeline.lua"]
    end

    subgraph Infrastructure
        config["config.lua"]
        utils["utils.lua"]
        filesearch["file_search.lua"]
        picker["picker.lua"]
    end

    plugin --> zkpickers
    plugin --> zkactions
    plugin --> linkbrowser
    plugin --> gtdboard

    zkpickers --> zkfinders
    zkpickers --> zkactions
    zkpickers --> makeentry
    zkpickers --> picker

    linkbrowser --> links
    linkbrowser --> frontmatter
    linkbrowser -.->|lazy| zkfinders

    gtdboard --> gtdstate
    gtdboard --> gtdrender
    gtdboard --> gtdtimeline
    gtdboard -.->|lazy| zkactions

    gtdstate --> gtdfinders
    gtdstate --> links

    zkfinders --> filesearch
    gtdfinders --> filesearch

    makeentry --> frontmatter
    zkfinders --> frontmatter
    zkactions --> frontmatter
    zkactions --> links
```

`config.lua` and `utils.lua` are infrastructure modules used by all layers.
`init.lua` is a facade that lazy-loads all modules via metatable.

Each layer only depends on the layers below it. There are no upward or
same-layer dependencies. Dashed arrows indicate lazy (deferred) dependencies.

## Initialization

```mermaid
sequenceDiagram
    participant User
    participant lazy
    participant init
    participant config
    participant plugin

    User->>lazy: Plugin spec with opts
    lazy->>init: holon.setup
    init->>config: config.setup
    config->>config: Merge defaults with user opts
    config->>config: Validate notes_path
    config->>config: Check fd and rg availability
    config->>config: Setup highlight groups

    Note over plugin: Loaded automatically by Neovim
    plugin->>plugin: Register user commands
    plugin->>plugin: Register FileType autocmd
    plugin->>plugin: Register LspAttach autocmd
```

## Note Search

```mermaid
sequenceDiagram
    participant User
    participant pickers as zk/pickers
    participant finders as zk/finders
    participant fd
    participant make_entry as zk/make_entry
    participant fm as frontmatter

    User->>pickers: HolonNotes
    pickers->>finders: find_notes
    finders->>fd: fd type f extension md
    fd-->>finders: File paths

    loop Each file path
        finders->>make_entry: make_note_entry
        make_entry->>fm: parse_file
        fm-->>make_entry: title and type and tags
        make_entry-->>finders: picker item
    end

    finders-->>pickers: item list
    pickers->>User: Display results with preview
```

## Tag and Type Filter with Back Navigation

```mermaid
sequenceDiagram
    participant User
    participant tags as filter_tags picker
    participant notes as notes picker
    participant finders as zk/finders
    participant fm as frontmatter

    User->>tags: HolonTags
    tags->>finders: collect_tags
    finders->>finders: list_files
    loop Each file
        finders->>fm: parse_file and get_tags
    end
    finders-->>tags: tag and count pairs
    tags->>User: Display tag list

    User->>tags: Select tag
    tags->>notes: notes with tags filter
    notes->>finders: find_by_tags
    finders-->>notes: Filtered file list
    notes->>User: Display filtered notes

    User->>notes: BS in normal mode
    notes->>tags: Return to tag picker
```

## Note Creation

```mermaid
sequenceDiagram
    participant User
    participant pickers as zk/pickers
    participant action as zk/actions
    participant utils
    participant config

    User->>pickers: HolonNew
    pickers->>pickers: Show template list
    User->>pickers: Select template
    pickers->>User: Prompt for title

    User-->>pickers: title or empty
    pickers->>action: create_note
    action->>utils: read_file
    action->>utils: get_template_vars and substitute
    Note over utils: Prepare template variables
    action->>config: get_directory
    action->>utils: ensure_dir and write_file
    action-->>pickers: filepath
    pickers->>User: Open new note in buffer
```

## Link Following

```mermaid
sequenceDiagram
    participant User
    participant action as zk/actions
    participant lnk as links

    User->>action: gd or HolonFollow
    action->>lnk: find_link_at_position
    Note over lnk: Match wiki or markdown link
    lnk-->>action: target or nil

    Note over action: If link found
    action->>lnk: resolve_link_target
    Note over lnk: Search relative then notes_path then subdirs then fd
    lnk-->>action: filepath or nil
    action->>User: Open file or show warning

    Note over action: If no link at cursor
    Note over action: Fallback to LSP definition or normal gd
```

## Backlinks Discovery

```mermaid
sequenceDiagram
    participant User
    participant pickers as zk/pickers
    participant finders as zk/finders
    participant lnk as links
    participant rg

    User->>pickers: HolonBacklinks
    pickers->>pickers: Get identifier from current file
    Note over pickers: UUID or filename fallback

    pickers->>finders: find_backlinks
    finders->>lnk: find_backlinks
    lnk->>rg: rg files with matches
    Note over rg: Search wiki and markdown patterns
    rg-->>lnk: Matching file paths
    lnk->>lnk: Filter out self by filename
    lnk-->>finders: backlink paths

    loop Each backlink
        finders->>finders: make_backlink_entry
    end
    finders-->>pickers: item list
    pickers->>User: Display backlinks
```

## Index Navigation

```mermaid
sequenceDiagram
    participant User
    participant idx as indexes picker
    participant sub as index links picker
    participant finders as zk/finders
    participant lnk as links

    User->>idx: HolonIndexes
    idx->>finders: find_index_notes
    finders-->>idx: Index note entries
    idx->>User: Display index notes

    User->>idx: Tab on selected index
    idx->>sub: open index links picker
    sub->>finders: find_index_links
    finders->>lnk: extract_all_links
    loop Each link
        finders->>lnk: resolve_link_target
    end
    finders-->>sub: Resolved link entries
    sub->>User: Display linked notes

    User->>sub: BS in normal mode
    sub->>idx: Return to indexes picker
```

## Insert Link from Picker

```mermaid
sequenceDiagram
    participant User
    participant pickers as zk/pickers
    participant action as zk/actions
    participant lnk as links

    User->>pickers: Open notes picker
    User->>pickers: Ctrl L on selected note
    pickers->>action: insert_link_from_picker
    action->>action: Get selected entry
    action->>action: Close picker

    Note over action: vim schedule to restore buffer
    action->>lnk: generate_link
    lnk-->>action: Formatted link string
    action->>action: Insert at cursor position
    action->>User: Cursor at end of link
```

## GTD Board

```mermaid
sequenceDiagram
    participant User
    participant board as gtd/board
    participant state as gtd/state
    participant gtdfinders as gtd/finders
    participant filesearch as file_search
    participant fm as frontmatter
    participant render as gtd/render
    participant timeline as gtd/timeline

    User->>board: HolonGtd
    board->>state: load
    state->>gtdfinders: find_tasks
    gtdfinders->>filesearch: list_files
    filesearch->>filesearch: fd
    filesearch-->>gtdfinders: File paths
    loop Each file
        gtdfinders->>fm: parse_file
        fm-->>gtdfinders: frontmatter fields
        Note over gtdfinders: Filter by status field
    end
    gtdfinders-->>state: Task list with horizon data
    state->>state: Build sections (group by status and horizon)
    state-->>board: Populated board state

    board->>render: Format task lines
    render-->>board: Rendered task panel
    board->>timeline: Generate ASCII bars
    timeline-->>board: Timeline panel
    board->>User: Layout with tasks panel + timeline panel + preview
```

## Link Browser

```mermaid
sequenceDiagram
    participant User
    participant browser as zk/link_browser
    participant lnk as links
    participant rg
    participant finders as zk/finders

    User->>browser: HolonBrowse
    browser->>browser: open(current_file)
    browser->>lnk: collect_forward_links
    Note over lnk: Extract links from buffer, resolve targets
    lnk-->>browser: Forward link entries
    browser->>rg: collect_backlinks
    Note over rg: rg search for references to current file
    rg-->>browser: Backlink entries
    browser->>finders: collect_tag_notes
    Note over finders: Find notes sharing tags with current file
    finders-->>browser: Tag-related entries
    browser->>User: Display initial view (forward links)

    User->>browser: b (backlinks mode)
    browser->>browser: re-collect + re-render backlinks

    User->>browser: f (forward links mode)
    browser->>browser: re-collect + re-render forward links

    User->>browser: t (tag notes mode)
    browser->>browser: re-collect + re-render tag notes

    User->>browser: CR (dive into note)
    browser->>browser: Push history, navigate to selected note
    browser->>browser: open(selected_file)

    User->>browser: - (go back)
    browser->>browser: Pop history, return to previous note
    browser->>browser: open(previous_file)
```

## gd Mapping Persistence

The `gd` mapping for link-following must survive LSP attachment, which
typically overwrites buffer-local `gd` with `vim.lsp.buf.definition()`.

```mermaid
sequenceDiagram
    participant nvim as Neovim
    participant plugin
    participant lsp as LSP_Plugin

    nvim->>nvim: Open markdown file
    nvim->>plugin: FileType autocmd
    plugin->>plugin: Set gd to smart_gd

    nvim->>lsp: LspAttach synchronous
    lsp->>lsp: Overwrite gd to LSP definition

    nvim->>plugin: LspAttach synchronous
    plugin->>plugin: Schedule setup_gd_mapping
    Note over plugin: Deferred to next event loop tick

    Note over nvim: All synchronous handlers complete

    nvim->>plugin: Execute scheduled callback
    plugin->>plugin: Re-set gd to smart_gd
    Note over plugin: Holon mapping takes priority
```

## File Discovery Strategy

```mermaid
graph LR
    check{holonignore exists?}
    check -->|Yes| withIgnore[Use ignore-file holonignore]
    check -->|No| noIgnore[No ignore rules applied]
    withIgnore --> result[Search results]
    noIgnore --> result
```

Both paths use `fd --hidden --no-ignore` for file discovery and
`rg --hidden --no-ignore-vcs` for content search. The `.holonignore`
file is the sole source of exclusion rules when present.

## Module Directory Structure

```
lua/holon/
├── init.lua           # Entry point (lazy-load registry)
├── config.lua         # Configuration management
├── utils.lua          # Shared utilities
├── frontmatter.lua    # YAML frontmatter parsing
├── links.lua          # Link extraction and resolution
├── graph.lua          # Directed link graph
├── file_search.lua    # fd/rg command infrastructure
├── picker.lua         # Reusable float window picker
├── zk/                # Zettelkasten modules
│   ├── finders.lua    # Note discovery and filtering
│   ├── actions.lua    # Note operations (create, follow, insert link)
│   ├── make_entry.lua # Picker entry formatting
│   ├── pickers.lua    # Picker definitions
│   └── link_browser.lua # Link graph navigator
└── gtd/               # GTD modules
    ├── finders.lua    # Task discovery and horizon computation
    ├── state.lua      # Board state management
    ├── render.lua     # Task panel rendering
    ├── board.lua      # Board UI orchestration
    ├── timeline.lua   # ASCII timeline visualization
    └── calendar.lua   # Date picker component
```
