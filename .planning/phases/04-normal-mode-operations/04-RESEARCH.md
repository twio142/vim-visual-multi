# Phase 4: Normal-Mode Operations - Research

**Researched:** 2026-02-28
**Domain:** Neovim Lua multi-cursor normal-mode executor — feedkeys-per-cursor loop, undo grouping, eventignore, per-cursor VM register, case/number operations, dot-repeat
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Phase boundary**
Standard normal-mode operators (d, c, y, p, ~, gu, gU, <C-a>, <C-x>, g<C-a>, g<C-x>, dot-repeat) execute simultaneously at all cursors, wrapped in a single undo block. This is a general executor — any operator+motion combo works, not just a curated list.

Does NOT include: insert mode replication after `c` (Phase 5), search/entry-point keybindings (Phase 6).

**Yank/put register model**
- Per-cursor VM register: `y` stores each cursor's yanked text independently in a VM-internal register list. Entry N corresponds to cursor N (sorted by position).
- `c` also populates the VM register: Change operations yank the deleted text into the per-cursor register slot before deleting (consistent with how `c` works in standard Vim).
- `p` pastes per-cursor: Each cursor pastes from its own VM register slot. Cursor N pastes entry N.
- Fallback to Vim register: If nothing has been yanked during the current VM session (VM register is empty), `p` falls back to the standard Vim unnamed register and pastes the same text at all cursors.
- Last yank wins per cursor: Multiple yanks in one session overwrite the per-cursor slot — no accumulation.

**Motion generality scope**
- General executor: Phase 4 builds a framework that runs any normal-mode operator+motion at all cursors. `d`, `c`, `y`, `p` are entry points but `dw`, `d3j`, `ci"` etc. work naturally.
- Mechanism — feedkeys per cursor: For each cursor, move Neovim's real cursor to that position, then `nvim_feedkeys` the operator+motion string so Neovim executes it natively. Reuses all of Neovim's built-in motion logic.
- Processing order — bottom-to-top: Cursors are processed from the highest line number to the lowest. This prevents earlier deletions/insertions from shifting the byte positions of cursors on later lines. Required for correctness.
- Undo grouping: All feedkeys calls for one user operation are wrapped in a single `undo.begin_block()` / `undo.end_block()` pair (Phase 1 undo.lua).

**Failed operation handling**
- Silent skip per cursor: If an operation can't apply at a cursor (e.g., `<C-a>` finds no number, `d` at end of file), that cursor silently skips. The cursor remains in the session and other cursors proceed normally.
- All cursors fail → silent: Even if every cursor fails, no error or vim.notify message is shown. Matches standard Vim behavior (e.g., `<C-a>` on non-number text is silent).
- `c` scope: Phase 4 handles the delete half of `c` (removes text at all cursors in one undo step). The subsequent insert mode replication is Phase 5. Phase 4 may leave cursors in insert mode after `c` but does not implement the keystroke replication.

**g<C-a> / g<C-x> sequential increment**
- Top-to-bottom line order: The cursor on the lowest line number gets step +1, next line gets +2, etc. Intuitive — the "first" visible cursor gets the smallest increment.
- Relative increment: Each cursor increments from its own current number value (+1 for first, +2 for second, etc.). Not an absolute sequence — cursor on 5 becomes 6, cursor on 10 becomes 12 (if it's the second cursor).
- g<C-x> is symmetric: Applies -1, -2, -3... in the same top-to-bottom order. Mirrors g<C-a> exactly.

### Claude's Discretion
- Exact structure of the executor function (one `M.exec(session, keys)` or per-operation functions)
- How `eventignore=all` is bracketed during feedkeys loops (Phase 2 deferred this to Phase 4)
- Whether dot-repeat is implemented via `vim.o.operatorfunc` or by replaying stored keystrokes
- Exact register storage format (table of strings vs table of {text, type} objects for charwise/linewise distinction)

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FEAT-05 | Simultaneous normal mode commands — d, c, y, p, D, C, x, J, and all standard ops | Feedkeys-per-cursor executor with bottom-to-top ordering and extmark position refresh; VimScript `vm#edit#process` is the authoritative reference |
| FEAT-06 | Undo grouping — all-cursor edits within a session undo as a single operation | `undo.begin_block` / `undo.end_block` (Phase 1) wrapped around entire feedkeys loop; `undojoin` pattern confirmed working; BUG-03/04 already guarded |
| FEAT-10 | Case conversion (upper/lower/title/cycle), replace-chars (r), replace mode (R), increase/decrease numbers (C-a/C-x/g-variants) | feedkeys handles `~`, `gu`, `gU` natively; C-a/C-x via feedkeys; g<C-a>/g<C-x> requires sequential-step logic (top-to-bottom sort); `r<char>` via feedkeys |
</phase_requirements>

---

## Summary

Phase 4 builds `edit.lua` — the Tier-3 executor module that drives normal-mode operations at all cursors simultaneously. The core algorithm is a feedkeys-per-cursor loop: for each cursor (bottom-to-top), move Neovim's real cursor to that extmark position, then fire the operation string via `nvim_feedkeys`. Neovim executes the command natively, including all motion logic, text-object parsing, and register handling. No custom range computation is required. Extmarks auto-update during the loop so positions remain valid.

The undo contract is the primary concern. All feedkeys calls within one user keystroke must land in a single undo group. The `undo.begin_block` / `undo.end_block` pair from Phase 1 already implements this with BUG-03 (per-buffer undolevels) and BUG-04 (no spurious entry on no-change) guards. The `eventignore=all` bracketing (deferred from Phase 2) is applied here: save `vim.o.eventignore`, set it to `"all"` before the loop, and restore after `end_block`. This prevents TextChanged, CursorMoved, and similar autocmds from firing for each intermediate cursor move during the batch.

The register model requires a new VM-side data structure: `session._vm_register` — a list of `{text, type}` entries parallel to `session.cursors` (indexed by cursor position order). Yank populates it; paste reads from it (with Vim register fallback). This is isolated from Vim's unnamed register, matching the VimScript `g:Vm.registers` behavior.

**Primary recommendation:** Implement `edit.lua` as a single module with `M.exec(session, keys)` as the general entry point and thin wrappers for the operations that need special handling (`y`, `p`, `c`, `g<C-a>`, `g<C-x>`, dot-repeat). The general executor is 30-40 lines; special cases add another 60-80 lines. One test file (`edit_spec.lua`) covers all behaviors with direct `exec()` calls.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Neovim built-in API | 0.10+ | `nvim_feedkeys`, `nvim_buf_get_extmark_by_id`, `nvim_win_set_cursor`, `nvim_buf_get_lines` | All stable on 0.10; no external dep |
| `undo.lua` (Phase 1) | — | `begin_block(session)` / `end_block(session)` / `with_undo_block(session, fn)` | Already built and tested; BUG-03/04 guards in place |
| `highlight.lua` (Phase 3) | — | `redraw(session)` called after each exec to update extmark highlights | Already built with correct read-clear-draw order |
| `region.lua` (Phase 3) | — | `Region:pos()` reads live extmark position; `sel_mark_id` as cursor position source | Already built; always reads from extmark tree |
| mini.test | vendored | Unit test framework for edit_spec.lua | Already vendored at `test/vendor/mini.test` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `vim.fn.getreg('"')` | built-in | Read unnamed Vim register after yank feedkey | After each cursor's `y` feedkey to capture per-cursor yanked text |
| `vim.fn.getregtype('"')` | built-in | Get register type ('v', 'V', etc.) for per-cursor register storage | Needed to round-trip register type through per-cursor VM register |
| `vim.fn.setreg('"', text, type)` | built-in | Set the unnamed register before a paste feedkey | Used in `p` handler to inject per-cursor text before `p` feedkey |
| `vim.o.eventignore` | built-in | Suppress all autocmds during feedkeys loop | Save before loop, set to `"all"`, restore after end_block |
| `vim.api.nvim_win_set_cursor` | built-in | Reposition real cursor to extmark row/col before feedkeys | Per-cursor loop; 0-indexed row + 1 = 1-indexed for set_cursor |
| `vim.api.nvim_feedkeys` | built-in | Execute operator string natively at current cursor position | Core of the executor loop |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `nvim_feedkeys` per cursor | `nvim_buf_set_text` for custom range ops | feedkeys reuses all of Neovim's built-in motion and operator logic — no reimplementation; set_text requires custom range calculation for every operator type |
| `vim.o.eventignore = "all"` during loop | per-autocmd flag `session._in_batch_edit` | eventignore is simpler for normal-mode ops where we control the entire loop; per-flag is needed for insert-mode (Phase 5) where autocmds fire outside our loop |
| Replaying stored keystrokes for dot-repeat | `vim.o.operatorfunc` g@ hook | Stored keystrokes is simpler and more predictable; operatorfunc is complex to set up and has edge cases with counts |

---

## Architecture Patterns

### Recommended Project Structure

```
lua/
  visual-multi/
    edit.lua          -- NEW: Phase 4 executor module
    init.lua          -- (Phase 1, unchanged)
    session.lua       -- (Phase 2, unchanged)
    highlight.lua     -- (Phase 3, unchanged)
    region.lua        -- (Phase 3, unchanged)
    undo.lua          -- (Phase 1, unchanged)
    config.lua        -- (Phase 1, unchanged)
    util.lua          -- (Phase 1, unchanged)
test/
  spec/
    edit_spec.lua     -- NEW: Phase 4 test suite
```

### Pattern 1: General Feedkeys Executor (Core Loop)

**What:** `M.exec(session, keys)` moves the real cursor to each cursor position (bottom-to-top), fires `nvim_feedkeys(keys, 'x', false)`, then redraws. Wrapped in an undo block.

**When to use:** Every normal-mode operation that runs the same keystroke at all cursors without special per-cursor data.

```lua
-- Source: CONTEXT.md locked decisions + autoload/vm/edit.vim s:Edit.process()
local undo  = require('visual-multi.undo')
local hl    = require('visual-multi.highlight')

local function _sorted_cursors_bottom_to_top(session)
  -- Build an index list sorted by descending row, then descending col.
  -- This prevents earlier deletions from shifting positions of later cursors.
  local order = {}
  for i = 1, #session.cursors do
    if not session.cursors[i]._stopped then
      order[#order + 1] = i
    end
  end
  table.sort(order, function(a, b)
    local ra, ca = session.cursors[a]:pos()
    local rb, cb = session.cursors[b]:pos()
    if ra ~= rb then return ra > rb end
    return ca > cb
  end)
  return order
end

function M.exec(session, keys)
  if session._stopped then return end
  if #session.cursors == 0 then return end

  -- Save/restore options for the batch
  local saved_ei = vim.o.eventignore
  vim.o.eventignore = 'all'

  local order = _sorted_cursors_bottom_to_top(session)

  undo.begin_block(session)

  for _, idx in ipairs(order) do
    local r = session.cursors[idx]
    if not r._stopped then
      local row, col = r:pos()  -- 0-indexed from extmark
      -- nvim_win_set_cursor is 1-indexed row, 0-indexed col
      pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
      -- 'x' mode: execute immediately (not queued); no remap
      pcall(vim.api.nvim_feedkeys,
        vim.api.nvim_replace_termcodes(keys, true, false, true),
        'x', false)
    end
  end

  undo.end_block(session)
  vim.o.eventignore = saved_ei
  hl.redraw(session)
end
```

### Pattern 2: Bottom-to-Top Sort with Extmark Readback

**What:** Before the loop, sort cursor indices by row descending. Read positions from extmarks INSIDE the loop (not before) because extmarks auto-update as earlier cursors' edits shift later lines.

**When to use:** Every place in `edit.lua` that iterates cursors for editing.

```lua
-- Source: CONTEXT.md locked decisions (bottom-to-top ordering)
-- KEY INSIGHT: extmarks update automatically — read pos() per-iteration,
-- not before the loop. The VimScript source called r.shift() to manually
-- update positions; extmarks make this unnecessary.

-- CORRECT:
for _, idx in ipairs(order) do
  local r = session.cursors[idx]
  local row, col = r:pos()  -- reads CURRENT extmark position (auto-updated)
  -- ...
end

-- WRONG:
local positions = {}
for i, r in ipairs(session.cursors) do
  positions[i] = { r:pos() }  -- stale after first edit
end
```

### Pattern 3: eventignore=all Bracket

**What:** Save `vim.o.eventignore`, set it to `"all"` before the feedkeys loop, restore after `undo.end_block`. This prevents TextChanged, CursorMoved, BufLeave and similar autocmds from firing for each intermediate cursor hop.

**When to use:** All `M.exec` calls and all other batch-edit loops in edit.lua.

```lua
-- Source: CONTEXT.md locked decisions (eventignore deferred from Phase 2)
-- VimScript equivalent: let s:v.auto = 1 + Maps.disable() + Maps.unmap_esc_and_toggle()
-- In Phase 4 Lua: we don't have live mappings yet (Phase 6), so eventignore is sufficient.

local saved_ei = vim.o.eventignore
vim.o.eventignore = 'all'
-- ... feedkeys loop ...
undo.end_block(session)
vim.o.eventignore = saved_ei  -- restore AFTER end_block so undo recording is clean
```

### Pattern 4: Per-Cursor VM Register

**What:** `session._vm_register` is a list of `{text=string, type=string}` entries. Index N corresponds to cursor index N (1-based). Yank writes to it; paste reads from it with Vim register fallback.

**When to use:** `M.yank(session)`, `M.paste(session, before)`.

```lua
-- Source: CONTEXT.md locked decisions (per-cursor VM register model)
-- Register type: 'v' = charwise, 'V' = linewise, ctrl-V = blockwise

-- Yank pattern (populate per-cursor register):
local function _exec_yank(session)
  local order = _sorted_cursors_bottom_to_top(session)
  session._vm_register = session._vm_register or {}

  local saved_ei = vim.o.eventignore
  vim.o.eventignore = 'all'

  for _, idx in ipairs(order) do
    local r = session.cursors[idx]
    if not r._stopped then
      local row, col = r:pos()
      vim.api.nvim_win_set_cursor(0, { row + 1, col })
      -- Clear unnamed register so we can detect if yank produced content
      vim.fn.setreg('"', '')
      pcall(vim.api.nvim_feedkeys,
        vim.api.nvim_replace_termcodes('yiw', true, false, true), 'x', false)
      local text = vim.fn.getreg('"')
      local rtype = vim.fn.getregtype('"')
      session._vm_register[idx] = { text = text, type = rtype }
    end
  end

  vim.o.eventignore = saved_ei
end

-- Paste pattern (read per-cursor register with Vim fallback):
local function _exec_paste(session, before)
  local order = _sorted_cursors_bottom_to_top(session)
  local use_vm_reg = session._vm_register and #session._vm_register > 0

  local saved_ei = vim.o.eventignore
  vim.o.eventignore = 'all'
  undo.begin_block(session)

  for _, idx in ipairs(order) do
    local r = session.cursors[idx]
    if not r._stopped then
      local row, col = r:pos()
      vim.api.nvim_win_set_cursor(0, { row + 1, col })

      if use_vm_reg and session._vm_register[idx] then
        -- Per-cursor paste: inject this cursor's text into unnamed register
        local entry = session._vm_register[idx]
        vim.fn.setreg('"', entry.text, entry.type)
      end
      -- else: use whatever is in the Vim unnamed register (fallback)

      local keys = before and 'P' or 'p'
      pcall(vim.api.nvim_feedkeys,
        vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
    end
  end

  undo.end_block(session)
  vim.o.eventignore = saved_ei
  hl.redraw(session)
end
```

### Pattern 5: g<C-a> / g<C-x> Sequential Increment

**What:** Sort cursors TOP-to-BOTTOM (ascending row). Cursor 1 gets +1, cursor 2 gets +2, etc. Each cursor feeds `<C-a>` the appropriate number of times. Uses a gcount approach.

**When to use:** `M.g_increment(session, direction)` where direction is 1 (g<C-a>) or -1 (g<C-x>).

```lua
-- Source: CONTEXT.md locked decisions (g<C-a>/g<C-x> top-to-bottom, relative)
-- VimScript equivalent: s:Edit.process() with gcount option, top-to-bottom

local function _g_increment(session, step_sign)
  -- g<C-a>/<C-x>: top-to-bottom order (opposite of normal edit order)
  local order = {}
  for i = 1, #session.cursors do
    if not session.cursors[i]._stopped then
      order[#order + 1] = i
    end
  end
  -- Sort ascending by row (top-to-bottom)
  table.sort(order, function(a, b)
    local ra = select(1, session.cursors[a]:pos())
    local rb = select(1, session.cursors[b]:pos())
    return ra < rb
  end)

  local saved_ei = vim.o.eventignore
  vim.o.eventignore = 'all'
  undo.begin_block(session)

  for step, idx in ipairs(order) do
    local r = session.cursors[idx]
    if not r._stopped then
      local row, col = r:pos()
      vim.api.nvim_win_set_cursor(0, { row + 1, col })
      -- step_sign: 1 = increment, -1 = decrement
      local count = step  -- +1/+2/+3 relative to current number
      local key = step_sign > 0 and '\x01' or '\x18'  -- <C-a> or <C-x>
      local keys_str = vim.api.nvim_replace_termcodes(
        string.rep('<C-a>', count), true, false, true)
      if step_sign < 0 then
        keys_str = vim.api.nvim_replace_termcodes(
          string.rep('<C-x>', count), true, false, true)
      end
      pcall(vim.api.nvim_feedkeys, keys_str, 'x', false)
    end
  end

  undo.end_block(session)
  vim.o.eventignore = saved_ei
  hl.redraw(session)
end
```

### Pattern 6: Dot-Repeat via Stored Keystrokes

**What:** Store the last operation's key string in `session._vm_dot`. On `.`, replay it by calling the same handler with the stored keys.

**When to use:** `M.dot(session)` called from the `.` keymap.

```lua
-- Source: CONTEXT.md locked decisions (dot-repeat = replay stored keystrokes)
-- VimScript: s:v.dot stores [cmd, recursive_flag]; Edit.dot() replays it

-- Store on every exec call:
function M.exec(session, keys)
  session._vm_dot = keys  -- remember last operation
  -- ... rest of exec ...
end

-- Dot-repeat:
function M.dot(session)
  if session._vm_dot then
    M.exec(session, session._vm_dot)
  end
end
```

### Pattern 7: Options to Save/Restore in Phase 4 Scope

**What:** Phase 4 adds three more options to the save/restore whitelist (from the full VimScript inventory documented in Phase 2 RESEARCH.md).

**When to use:** These are added to `session._saved.opts` in `session.start()` (or lazily on first exec). Research confirms they are needed per the VimScript source `vm#variables#init()`.

| Option | Scope | Save Accessor | Restore Accessor | Set To During Session |
|--------|-------|--------------|-----------------|----------------------|
| `synmaxcol` | buffer | `vim.bo[buf].synmaxcol` | `vim.bo[buf].synmaxcol = saved` | `0` (unlimited) — prevents syntax hl choking during edits |
| `textwidth` | buffer | `vim.bo[buf].textwidth` | `vim.bo[buf].textwidth = saved` | `0` — prevents auto-wrap during cursor operations |
| `concealcursor` | window | `nvim_win_get_option(win, 'concealcursor')` | `nvim_win_set_option(win, 'concealcursor', saved)` | `''` |
| `hlsearch` | global | `vim.o.hlsearch` | `vim.o.hlsearch = saved` | `false` during batch edits |

**Note:** These should be saved in `session.start()` alongside the Phase 2 options, not in `edit.lua`. The planner should add them to the session initialization code if not already present.

### Anti-Patterns to Avoid

- **Reading cursor positions before the loop:** Read `r:pos()` inside the loop on each iteration, never cache all positions before starting. Extmarks auto-update, cached positions go stale after the first edit.
- **Processing top-to-bottom for delete/change/yank:** Always bottom-to-top for ops that modify buffer content. Only g<C-a>/g<C-x> use top-to-bottom.
- **Not restoring eventignore on error:** Wrap the entire loop in `pcall` or use a finally-style guard to ensure `vim.o.eventignore = saved_ei` always executes.
- **Using `vim.cmd('normal! ...')` instead of `nvim_feedkeys`:** `vim.cmd('normal!')` ignores the current cursor position set by `nvim_win_set_cursor` in some contexts; `nvim_feedkeys` with mode `'x'` is authoritative.
- **Setting unnamed register globally for yank:** Yank via feedkeys writes to the unnamed register; always capture it immediately after the feedkey call and before moving to the next cursor.
- **Not pcall-wrapping feedkeys calls:** Individual cursor operations can fail silently (e.g., `<C-a>` with no number under cursor). Wrap in pcall to implement the "silent skip" contract without breaking the loop.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Execute operator at cursor | Custom text-object parser + nvim_buf_set_text | `nvim_feedkeys(keys, 'x', false)` after `nvim_win_set_cursor` | feedkeys reuses all of Neovim's built-in operator/motion logic; custom parser would need to handle `dw`, `d3j`, `ci"`, `dt.`, `da[`, etc. — hundreds of cases |
| Cursor position after edit | Manual byte-delta arithmetic (VimScript `r.shift(change)`) | `nvim_buf_get_extmark_by_id` — extmarks auto-update | Neovim maintains extmark positions through all edits; shift arithmetic was the most bug-prone part of the VimScript source |
| Register type detection | Parsing register content for line/char detection | `vim.fn.getregtype('"')` returns 'v'/'V'/ctrl-V | Built-in; handles all cases including block registers |
| Undo grouping | Custom undolevels manipulation | `undo.begin_block` / `undo.end_block` from Phase 1 | Already implemented, tested, and hardened against BUG-03/04 |
| Case conversion | Custom char-by-char case flip | `nvim_feedkeys('~', 'x', false)` / `gu` / `gU` | Neovim handles multibyte case correctly; custom implementation would fail on non-ASCII |

**Key insight:** The feedkeys-per-cursor executor is deliberately thin. Its value is wiring Neovim's existing execution model to the multi-cursor loop, not reimplementing any editor operations. Every line of custom text manipulation is a line that might get multibyte case or motion semantics wrong.

---

## Common Pitfalls

### Pitfall 1: Stale Position Cache (Most Likely Bug)

**What goes wrong:** All cursor positions are read before the loop, stored in a local table, then used during the loop. After the first cursor's delete removes a line, the second cursor's cached row is now off by 1. Highlight appears in the wrong place; subsequent feedkeys execute at the wrong position.

**Why it happens:** The VimScript source called `r.shift(change, change)` to manually correct positions. Extmarks make this unnecessary but only if positions are read live per-iteration.

**How to avoid:** Call `r:pos()` on each `region` object INSIDE the loop, each iteration. Region:pos() calls `nvim_buf_get_extmark_by_id` which reads the current (post-edit) position. No caching.

**Warning signs:** Works correctly with 2 cursors on different lines but drifts with 3+ cursors. Fails specifically when deletions occur on lines above other cursors.

### Pitfall 2: eventignore Not Restored on Error (PITFALL-02 from PITFALLS.md)

**What goes wrong:** A feedkeys call panics or a cursor operation throws. `vim.o.eventignore` remains `"all"`. From then on, all user autocmds (LSP, completion, syntax highlighting) are silently suppressed. Hard to diagnose.

**Why it happens:** Linear code without error handling — the restore line never runs.

**How to avoid:**
```lua
local saved_ei = vim.o.eventignore
local ok, err = pcall(function()
  vim.o.eventignore = 'all'
  -- ... loop ...
end)
vim.o.eventignore = saved_ei  -- ALWAYS restore
if not ok then vim.notify(err, vim.log.levels.WARN) end
```

**Warning signs:** After a VM crash or error, TextChanged autocmds stop firing; LSP stops updating.

### Pitfall 3: Wrong nvim_feedkeys Mode String

**What goes wrong:** Using `nvim_feedkeys(keys, 'n', false)` (queued mode) instead of `'x'` (execute immediately). The keys are not executed synchronously within the loop iteration. Cursor moves to the next position before the feedkey runs. Operations execute in the wrong order.

**Why it happens:** `'n'` mode appends to the typeahead buffer; `'x'` processes immediately. For the multi-cursor executor, synchronous execution is required.

**How to avoid:** Always use `'x'` mode for the executor loop. Use `'m'` (remappable) or `'n'` only when deliberately deferring.

**Warning signs:** Operations appear to execute at the wrong cursor (one position off); works on single cursor but not multi.

### Pitfall 4: nvim_win_set_cursor Row Indexing

**What goes wrong:** `nvim_buf_get_extmark_by_id` returns 0-indexed row. `nvim_win_set_cursor` requires 1-indexed row. Forgetting the `+1` puts every cursor one line up.

**Why it happens:** Neovim API is inconsistently indexed: extmark API = 0-indexed, window cursor API = 1-indexed.

**How to avoid:** Always: `nvim_win_set_cursor(0, { row_0indexed + 1, col_0indexed })`. Add a comment at every call site. Never use a raw extmark row value without the +1.

**Warning signs:** All operations execute one line above the expected cursor position.

### Pitfall 5: Unnamed Register Contamination

**What goes wrong:** After the yank feedkeys loop populates `session._vm_register`, a subsequent normal-mode operation (e.g., `dw`) overwrites the unnamed register. When `p` is pressed next, `session._vm_register` entries no longer match what Vim's register holds. Paste inserts stale text.

**Why it happens:** The unnamed register is shared with all Vim operations. Any delete, change, or yank will overwrite it.

**How to avoid:** Per-cursor register model is exactly the solution: store the text and type immediately after each yank feedkey (before moving to the next cursor), and inject back into the unnamed register immediately before each paste feedkey. Never rely on the unnamed register persisting between cursor iterations.

**Warning signs:** After multiple operations, `p` pastes the wrong text — pastes what the last `d` deleted rather than what `y` yanked.

### Pitfall 6: operator-pending getchar Blocking (PITFALL-06 from PITFALLS.md)

**What goes wrong:** Phase 4 installs keymaps for `d`, `c`, `y` in normal mode. The user presses `d` — now Phase 4 must read the motion (`w`, `3j`, `iw`, etc.). Using `vim.fn.getchar()` in a Lua keymap callback blocks the event loop.

**Why it happens:** Neovim's Lua keymap callbacks run synchronously. A blocking `getchar()` call inside them prevents the UI from updating.

**How to avoid:** Use `<expr>` mapping + `vim.o.operatorfunc` pattern, OR use a simpler approach: map the operator keys to functions that call `M.exec(session, keys)` where `keys` is a fixed string, and rely on Neovim's native operator-pending mode for the motion. Specifically:

```lua
-- Approach: map operator to set operatorfunc then invoke g@
-- Or: map specific common ops directly (dw, dd, diw, etc.)
-- For general ops: use <expr> + getcharstr() which does NOT block
vim.keymap.set('n', 'd', function()
  -- set up operatorfunc and use g@ to capture motion natively
  vim.o.operatorfunc = "v:lua.require('visual-multi.edit').op_delete"
  return 'g@'
end, { buffer = session.buf, expr = true })
```

**Warning signs:** Neovim freezes briefly when pressing `d`; headless tests hang.

**Research note:** The `<expr>` + `g@` pattern is the standard Neovim solution for custom operators. CONTEXT.md marks "whether dot-repeat is via operatorfunc or stored keystrokes" as Claude's discretion — the `g@` approach naturally provides dot-repeat via `.` for free, which is why it's worth considering. See Open Question 1.

### Pitfall 7: `c` Leaves Cursor in Insert Mode (Phase 4 Scope Limit)

**What goes wrong:** After `c` runs (delete half done), each cursor lands in insert mode. Phase 4 does not implement keystroke replication (Phase 5). The session is left in an inconsistent state — multiple cursors in insert mode with no replication engine active.

**Why it happens:** `c` in Neovim's native mode = delete text and enter insert mode. After feedkeys executes `c` at each cursor, insert mode is active at the last-visited cursor.

**How to avoid:** After the `c` feedkeys loop completes, immediately call `<Esc>` to return all cursors to normal mode and record this as a Phase 4 limitation (insert replication deferred to Phase 5). Alternatively, execute the delete half via `"_d<motion>` (black hole register) which does not enter insert mode, then let Phase 5 handle the insert transition. Document the chosen approach clearly in edit.lua.

**Warning signs:** After `ciw`, the editor stays in insert mode after Phase 4 completes; cursor count in session appears wrong.

---

## Code Examples

### Full General Executor with Error Guard

```lua
-- Source: CONTEXT.md locked decisions + VimScript s:Edit.process() reference

local M = {}
local undo = require('visual-multi.undo')
local hl   = require('visual-multi.highlight')

--- Sort active cursor indices bottom-to-top (highest row first).
--- Reads positions live from extmarks — never cache before loop.
---@param session table
---@return integer[] ordered list of cursor indices
local function _bottom_to_top(session)
  local order = {}
  for i = 1, #session.cursors do
    if not session.cursors[i]._stopped then
      order[#order + 1] = i
    end
  end
  table.sort(order, function(a, b)
    local ra = select(1, session.cursors[a]:pos())
    local rb = select(1, session.cursors[b]:pos())
    if ra ~= rb then return ra > rb end
    local ca = select(2, session.cursors[a]:pos())
    local cb = select(2, session.cursors[b]:pos())
    return ca > cb
  end)
  return order
end

--- Execute a normal-mode key string at all cursors.
--- Bottom-to-top processing, single undo block, eventignore=all bracket.
---@param session table
---@param keys string  Normal-mode keystrokes (passed to nvim_feedkeys)
function M.exec(session, keys)
  if session._stopped then return end
  if #session.cursors == 0 then return end

  -- Encode termcodes once
  local encoded = vim.api.nvim_replace_termcodes(keys, true, false, true)

  -- Save state
  local saved_ei = vim.o.eventignore
  local ok, err = pcall(function()
    vim.o.eventignore = 'all'
    undo.begin_block(session)

    local order = _bottom_to_top(session)
    for _, idx in ipairs(order) do
      local r = session.cursors[idx]
      if not r._stopped then
        local row, col = r:pos()
        -- nvim_win_set_cursor: 1-indexed row, 0-indexed col (PITFALL-04)
        pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
        -- 'x' = execute immediately, not queued (PITFALL-03)
        pcall(vim.api.nvim_feedkeys, encoded, 'x', false)
      end
    end

    undo.end_block(session)
  end)

  -- ALWAYS restore eventignore (PITFALL-02 prevention)
  vim.o.eventignore = saved_ei

  if not ok then
    vim.notify('[visual-multi] exec error: ' .. tostring(err), vim.log.levels.WARN)
  end

  -- Store for dot-repeat
  session._vm_dot = keys
  hl.redraw(session)
end

return M
```

### Minimal edit_spec.lua Test Pattern

```lua
-- Source: existing session_spec.lua / undo_spec.lua patterns
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- BUG-02: (false, false) for undo to work
      buf = vim.api.nvim_create_buf(false, false)
      vim.bo[buf].buftype  = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world', 'foo bar' })
      vim.api.nvim_set_current_buf(buf)
      require('visual-multi.config')._reset()
      require('visual-multi')._sessions[buf] = nil
    end,
    post_case = function()
      pcall(require('visual-multi.session').stop, buf)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  },
})

T['exec deletes word at cursor position'] = function()
  local session = require('visual-multi.session').start(buf, false)
  -- Add cursors manually at 'hello' and 'foo'
  local region = require('visual-multi.region')
  session.cursors[1] = region.new(buf, 0, 0)  -- row 0, col 0
  session.cursors[2] = region.new(buf, 1, 0)  -- row 1, col 0
  session.primary_idx = 2

  require('visual-multi.edit').exec(session, 'dw')

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], 'world')
  MiniTest.expect.equality(lines[2], 'bar')
end

T['exec wraps in single undo block'] = function()
  local session = require('visual-multi.session').start(buf, false)
  local region = require('visual-multi.region')
  session.cursors[1] = region.new(buf, 0, 0)
  session.cursors[2] = region.new(buf, 1, 0)
  session.primary_idx = 2

  local tree_before = vim.fn.undotree().seq_cur
  require('visual-multi.edit').exec(session, 'dw')
  local tree_after = vim.fn.undotree().seq_cur

  -- Exactly one new undo entry for both cursor operations
  MiniTest.expect.equality(tree_after - tree_before, 1)
end
```

### nvim_feedkeys Mode Reference

```lua
-- Source: Neovim :help nvim_feedkeys mode parameter
-- 'n' — append to typeahead (deferred)  ← WRONG for executor
-- 'x' — execute immediately, discard typeahead ← CORRECT for executor
-- 'm' — remap allowed (same as pressing keys interactively)
-- 't' — append to typeahead as if typed (respects 'remaps')
-- 'i' — insert at start of typeahead
-- For the multi-cursor executor: always 'x' (synchronous, no-remap)

vim.api.nvim_feedkeys(
  vim.api.nvim_replace_termcodes(keys, true, false, true),
  'x',    -- execute immediately
  false   -- do not escape K_SPECIAL bytes
)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `r.shift(change, change)` — manual byte-delta arithmetic after each cursor | Read `r:pos()` inside loop — extmarks auto-update | This Lua rewrite | Eliminates entire class of position-drift bugs; simpler code |
| `exe 'normal! '.cmd` in VimScript | `nvim_feedkeys(keys, 'x', false)` in Lua | Since Neovim 0.5 API | Type-safe; no string escaping; synchronous execution |
| `let s:v.eco = 1` eco-mode flag + deferred redraw | `eventignore=all` save/restore bracket | This rewrite | More portable; no custom flag infrastructure needed |
| VimScript `g:Vm.registers` dict keyed by reg char | `session._vm_register` list indexed by cursor position | This rewrite | Per-cursor isolation is native to the data model |
| `silent doautocmd CursorMoved` to force yank callbacks | Not needed with feedkeys 'x' mode | This rewrite | feedkeys 'x' fires synchronously; CursorMoved fires naturally |

**Deprecated/outdated:**
- `vim.cmd('normal! ...')`: Use `nvim_feedkeys` with `'x'` mode for synchronous, position-aware execution.
- VimScript `r.shift()`: Replaced entirely by extmark auto-update. Do not port this function.
- `getchar()` blocking read in operator handlers (PITFALL-06): Use `<expr>` + `operatorfunc` or map specific fixed operations.

---

## Open Questions

1. **Operator key capture: `<expr>+operatorfunc` vs fixed key mappings**
   - What we know: The VimScript source uses a `getchar()` loop in `vm#cursors#operation()` to read operator suffixes (e.g., user presses `d`, then `w`). This blocks in Lua callbacks (PITFALL-06). Two alternatives exist: (a) use `<expr>` mapping + `vim.o.operatorfunc` so Neovim captures the motion natively, or (b) install fixed mappings for common ops (`dw`, `dd`, `diw`, etc.) and route to `M.exec(session, 'dw')`.
   - What's unclear: Whether approach (a) provides a clean dot-repeat path automatically (it does for custom operators in standard Neovim). Whether approach (b) is sufficient given the "general executor" scope goal.
   - Recommendation: Use approach (a) — `operatorfunc` — for `d`, `c`, `y` operators. Map the key to set `vim.o.operatorfunc` and return `'g@'`. This (1) avoids getchar blocking, (2) gives free dot-repeat via `.`, (3) handles all motions naturally. The planner should allocate a Wave 0 spike task to validate this works in headless tests.

2. **`c` delete half: feedkeys `d<motion>` vs feedkeys `c<motion>`**
   - What we know: After `c` feedkeys executes, Neovim enters insert mode at the last cursor. Phase 4 does not implement insert replication. The VimScript source in `cursors.vim:s:change_at_cursors()` converts `cw` → `dw` + enter insert once, not `cw` per cursor.
   - What's unclear: Whether using `d<motion>` (instead of `c<motion>`) for the Phase 4 delete half is the cleanest approach, avoiding multiple insert-mode entries during the loop.
   - Recommendation: In Phase 4, execute `"_d<motion>` (black hole register delete) instead of `c<motion>` for the `c` operator. This does the content removal in one undo block without entering insert mode at each cursor. Phase 5 then handles the insert entry from the final cursor position. The planner should document this contract in edit.lua comments.

3. **Additional session options to save/restore (synmaxcol, textwidth, concealcursor, hlsearch)**
   - What we know: The Phase 2 RESEARCH.md documented the full VimScript option save list. Phase 4 introduces edit operations where `textwidth=0` and `synmaxcol=0` matter (auto-wrap and syntax slowdown during large batch edits).
   - What's unclear: Whether these should be added in `session.start()` (centralized) or lazily on first exec call.
   - Recommendation: Add them to `session.start()` via the existing `_save_and_set_options` function. This keeps option lifecycle centralized. The planner should add a Wave 0 task to patch `session.lua` with the additional options before implementing `edit.lua`.

---

## Validation Architecture

> Not included — `workflow.nyquist_validation` is not set to true in `.planning/config.json`.

---

## Sources

### Primary (HIGH confidence)

- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/edit.vim` — `s:Edit.process()`, `s:Edit.before_commands()`, `s:Edit.after_commands()`, `s:Edit.run_normal()` — authoritative VimScript reference for the executor loop
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/cursors.vim` — `vm#cursors#operation()`, `s:process()`, `s:delete_at_cursors()`, `s:yank_at_cursors()`, `s:change_at_cursors()` — operator dispatch and register model
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/ecmds1.vim` — `s:Edit.yank()`, `s:Edit.paste()`, `s:Edit.block_paste()`, `s:Edit.fill_register()` — register management
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/ecmds2.vim` — `s:Edit._numbers()`, `s:Edit.change()` — sequential number increment logic
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/undo.lua` — confirmed Phase 1 implementation: `begin_block`, `end_block`, `with_undo_block`, `flush_undo_history`
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/session.lua` — confirmed Phase 2 implementation: session table shape, `_saved` structure, `_undo_seq_before` fields
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/highlight.lua` — confirmed Phase 3 implementation: `redraw(session)`, `clear(session)`, `_draw_cursor_region`, `_col_end`
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/region.lua` — confirmed Phase 3 implementation: `Region:pos()` via `nvim_buf_get_extmark_by_id`
- `.planning/research/PITFALLS.md` — PITFALL-02 (noautocmd/eventignore), PITFALL-06 (getchar blocking)
- `.planning/phases/04-normal-mode-operations/04-CONTEXT.md` — all locked decisions

### Secondary (MEDIUM confidence)

- `.planning/phases/02-session-lifecycle/02-RESEARCH.md` — full option save/restore inventory table; confirmed `synmaxcol`, `textwidth`, `concealcursor`, `hlsearch` are Phase 4 scope options
- `.planning/phases/01-foundation/01-RESEARCH.md` — BUG-01 through BUG-05 confirmed; Pattern 6 (undo block with empty-change guard)
- `.planning/STATE.md` — confirmed PITFALL-06 as an open concern requiring spike before Phase 4

### Tertiary (LOW confidence)

- None. All findings are based on confirmed project source code and documentation. No web search was required.

---

## Metadata

**Confidence breakdown:**
- Core executor pattern: HIGH — directly derived from VimScript `s:Edit.process()` + confirmed Phase 1-3 APIs
- eventignore bracket: HIGH — confirmed Neovim API behavior; standard pattern for suppressing autocmds during batch ops
- Per-cursor register model: HIGH — directly derived from VimScript `fill_register` + `block_paste` + CONTEXT.md locked decisions
- g<C-a>/g<C-x> sequential increment: HIGH — locked in CONTEXT.md; confirmed against VimScript `_numbers()` pattern
- Dot-repeat via stored keystrokes: HIGH — locked in CONTEXT.md; simple table field on session
- Operator key capture (getchar vs operatorfunc): MEDIUM — PITFALL-06 is confirmed; operatorfunc approach is standard Neovim but headless testability not verified
- Additional options to save/restore: HIGH — derived from RESEARCH.md Phase 2 full option inventory

**Research date:** 2026-02-28
**Valid until:** 2026-05-28 (90 days — all APIs are Neovim stable; VimScript source is frozen reference)
