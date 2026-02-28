# Phase 3: Region and Highlight - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Extmark-based tracking of cursor and selection positions, rendered as highlights on screen, with atomic teardown on session exit and no ghost marks. This is the visual layer — what the user sees while VM is active.

Does NOT include: the commands that add/move cursors (Phase 4/6), insert mode rendering (Phase 5), or the entry-point keybindings.

</domain>

<decisions>
## Implementation Decisions

### Cursor appearance model
- **Primary/secondary distinction**: Two visual tiers — the primary cursor looks different (brighter/distinct) from all secondary cursors. Four highlight groups total: `VM_Cursor` (primary, cursor-mode), `VM_CursorSecondary` (others, cursor-mode), `VM_Extend` (primary, extend-mode selection), `VM_ExtendSecondary` (others, extend-mode selection).
- **Primary cursor identity**: Defaults to the last-added cursor. Users can switch the primary cursor with `Goto Next` / `Goto Prev` commands (those commands are Phase 6 — but Phase 3 must track a `primary_idx` field on the session and read it during highlight redraw).
- **Extend mode also has primary/secondary**: The primary selection uses `VM_Extend`, all others use `VM_ExtendSecondary`. Consistent with cursor mode.

### Extend-mode selection style
- **Custom VM highlight groups**: Selections use `VM_Extend` / `VM_ExtendSecondary` (not Neovim's built-in `Visual`). Clearly distinguishes VM regions from a real visual selection.
- **Cursor-within-selection highlight**: In extend mode, the character at the cursor position (the "tip" of each selection) gets an additional `VM_Cursor` / `VM_CursorSecondary` highlight on top. This mirrors the original plugin behavior — the cursor tip is always visible even inside a selection.
- **Zero-width region fallback**: If a region's anchor and cursor are on the same character (zero-width in extend mode), it renders as a cursor-mode single-character highlight — not invisible, not a bar.

### Eco-mode update strategy
- **Clear-all then redraw-all**: `nvim_buf_clear_namespace` followed by a loop setting all extmarks. One screen refresh shows the final state — no stale marks from removed cursors.
- **Explicitly driven**: `highlight.redraw(session)` is called explicitly by operations when they change cursor state. The highlight module is a passive renderer — no CursorMoved autocmd.
- **Teardown**: `session.stop()` calls `highlight.clear(session)` which runs `nvim_buf_clear_namespace` to remove all extmarks atomically. The session's `cursors` list is NOT cleared — only the visual extmarks are removed. (Session already removed from `_sessions` registry by `session.stop()`.)

### Claude's Discretion
- Exact default colors for `VM_Cursor`, `VM_CursorSecondary`, `VM_Extend`, `VM_ExtendSecondary` (should be reasonable defaults that work on both dark and light themes)
- Whether `primary_idx` lives on the session table or is derived as `#session.cursors` (last index)
- Whether highlight groups are defined with `nvim_set_hl` or via `vim.cmd('highlight ...')`
- Exact extmark options (`hl_mode`, `priority`, `strict` settings)

</decisions>

<specifics>
## Specific Ideas

- The `VM_Cursor` highlight should feel like a block cursor sitting on top of the character — not an underline or foreground-only highlight
- The original plugin used `matchaddpos` for some highlights; the Lua rewrite must use extmarks (`nvim_buf_set_extmark`) exclusively — no `matchadd`
- The `VM_Extend` selection should be visually similar in density to Neovim's `Visual` but in a different hue (e.g., blue-ish if Visual is purple, or configurable via colorscheme link)

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-region-and-highlight*
*Context gathered: 2026-02-28*
