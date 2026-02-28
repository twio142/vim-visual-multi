# Phase 4: Normal-Mode Operations - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Standard normal-mode operators (d, c, y, p, ~, gu, gU, <C-a>, <C-x>, g<C-a>, g<C-x>, dot-repeat) execute simultaneously at all cursors, wrapped in a single undo block. This is a general executor — any operator+motion combo works, not just a curated list.

Does NOT include: insert mode replication after `c` (Phase 5), search/entry-point keybindings (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Yank/put register model
- **Per-cursor VM register**: `y` stores each cursor's yanked text independently in a VM-internal register list. Entry N corresponds to cursor N (sorted by position).
- **`c` also populates the VM register**: Change operations yank the deleted text into the per-cursor register slot before deleting (consistent with how `c` works in standard Vim).
- **`p` pastes per-cursor**: Each cursor pastes from its own VM register slot. Cursor N pastes entry N.
- **Fallback to Vim register**: If nothing has been yanked during the current VM session (VM register is empty), `p` falls back to the standard Vim unnamed register and pastes the same text at all cursors.
- **Last yank wins per cursor**: Multiple yanks in one session overwrite the per-cursor slot — no accumulation.

### Motion generality scope
- **General executor**: Phase 4 builds a framework that runs any normal-mode operator+motion at all cursors. `d`, `c`, `y`, `p` are entry points but `dw`, `d3j`, `ci"` etc. work naturally.
- **Mechanism — feedkeys per cursor**: For each cursor, move Neovim's real cursor to that position, then `nvim_feedkeys` the operator+motion string so Neovim executes it natively. Reuses all of Neovim's built-in motion logic.
- **Processing order — bottom-to-top**: Cursors are processed from the highest line number to the lowest. This prevents earlier deletions/insertions from shifting the byte positions of cursors on later lines. Required for correctness.
- **Undo grouping**: All feedkeys calls for one user operation are wrapped in a single `undo.begin_block()` / `undo.end_block()` pair (Phase 1 undo.lua).

### Failed operation handling
- **Silent skip per cursor**: If an operation can't apply at a cursor (e.g., `<C-a>` finds no number, `d` at end of file), that cursor silently skips. The cursor remains in the session and other cursors proceed normally.
- **All cursors fail → silent**: Even if every cursor fails, no error or vim.notify message is shown. Matches standard Vim behavior (e.g., `<C-a>` on non-number text is silent).
- **`c` scope**: Phase 4 handles the delete half of `c` (removes text at all cursors in one undo step). The subsequent insert mode replication is Phase 5. Phase 4 may leave cursors in insert mode after `c` but does not implement the keystroke replication.

### g\<C-a\> / g\<C-x\> sequential increment
- **Top-to-bottom line order**: The cursor on the lowest line number gets step +1, next line gets +2, etc. Intuitive — the "first" visible cursor gets the smallest increment.
- **Relative increment**: Each cursor increments from its own current number value (+1 for first, +2 for second, etc.). Not an absolute sequence — cursor on 5 becomes 6, cursor on 10 becomes 12 (if it's the second cursor).
- **g\<C-x\> is symmetric**: Applies -1, -2, -3... in the same top-to-bottom order. Mirrors g\<C-a\> exactly.

### Claude's Discretion
- Exact structure of the executor function (one `M.exec(session, keys)` or per-operation functions)
- How `eventignore=all` is bracketed during feedkeys loops (Phase 2 deferred this to Phase 4)
- Whether dot-repeat is implemented via `vim.o.operatorfunc` or by replaying stored keystrokes
- Exact register storage format (table of strings vs table of {text, type} objects for charwise/linewise distinction)

</decisions>

<specifics>
## Specific Ideas

- The feedkeys executor should suppress autocmds during the multi-cursor loop (`eventignore=all`) then restore after — this was explicitly deferred from Phase 2 as a per-operation concern
- The bottom-to-top ordering is critical: positions must be refreshed from extmarks (via `nvim_buf_get_extmark_by_id`) rather than cached row/col before the loop begins — extmarks auto-update on edits

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-normal-mode-operations*
*Context gathered: 2026-02-28*
