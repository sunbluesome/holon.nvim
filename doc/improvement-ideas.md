# holon.nvim Improvement Ideas

Zettelkasten + GTD hybrid plugin as more refined and user-friendly tool.

---

## Short-term: UX Polish

### 1. Resume board after opening note

Currently `CR` closes the board to open a note. Add the ability to return
to the board (same cursor position) after closing the note or re-running
`:HolonGtd`. This makes quick-check workflows much smoother.

### 2. Journal + GTD integration

When opening today's journal, auto-insert (or show via virtual text) a
summary of today/overdue tasks. Extend to "this week's tasks" for GTD
Weekly Review support.

### 3. Quick Capture (`:HolonCapture`)

Create an inbox task from any buffer with a single command. Prompt for
title only, generate a note with `status: inbox` immediately. An external
equivalent of the board's `a` (add) action.

---

## Mid-term: Deeper Features

### 4. Note promotion workflow (`:HolonPromote`)

Promote a fleeting note to permanent: change `type`, move file to the
correct directory, and auto-update all link references. Completes the
Zettelkasten lifecycle of fleeting -> permanent.

### 5. Project dashboard

When viewing a project-type note, show a floating summary of linked tasks
and their progress (via virtual text or floating window). A per-project
GTD view.

### 6. Recurring tasks

Add `recur: weekly|monthly|...` to frontmatter. When a task is marked
`done`, auto-generate the next instance with updated dates. Essential for
real-world GTD usage.

---

## Long-term: Differentiation

### 7. Link graph visualization

Leverage existing `graph.lua` to render note relationships as an ASCII or
buffer-based graph. Visualizing connections improves Zettelkasten quality.

### 8. Context / energy labels

GTD "contexts" (`@home`, `@office`, `@pc`, etc.) as tags or a dedicated
frontmatter field. Filter the board by context to answer "what can I do
right here, right now?"

---

## Priority Assessment

| Idea | Impact | Effort | Priority |
|------|--------|--------|----------|
| 1. Resume board | High | Low | P1 |
| 3. Quick Capture | High | Low | P1 |
| 2. Journal + GTD | Medium | Medium | P2 |
| 6. Recurring tasks | High | Medium | P2 |
| 4. Note promotion | Medium | Medium | P2 |
| 5. Project dashboard | Medium | High | P3 |
| 8. Context labels | Medium | Medium | P3 |
| 7. Link graph viz | Low | High | P3 |
