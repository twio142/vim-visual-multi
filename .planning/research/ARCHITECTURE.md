# Architecture Research: Lua Rewrite of vim-visual-multi

**Research Date:** 2026-02-28
**Dimension:** Architecture
**Milestone:** Subsequent — Lua/Neovim rewrite from VimScript source

---

## Summary

This document provides concrete architectural guidance for rewriting vim-visual-multi from VimScript to Lua. It covers recommended module layout, per-buffer state management, keymap lifecycle, undo block management, extmarks namespace strategy, and the Lua replacement for the Python byte operations helper. Build-order dependencies are called out explicitly.

---

## 1. Recommended Lua Module Structure

The VimScript autoload hierarchy maps cleanly onto a `lua/visual-multi/` tree. The primary design principle: **one module = one responsibility**. Modules expose a plain table; init functions return the live instance for the session to hold.

### Proposed layout

```
lua/visual-multi/
├── init.lua          -- setup(opts) entry point; owns _sessions table
├── config.lua        -- options schema, defaults, validation
├── session.lua       -- per-buffer session factory & lifecycle (init / reset)
├── region.lua        -- Region objects: create / update / remove / sort
├── global.lua        -- cross-region ops: mode changes, merge, highlight refresh
├── maps.lua          -- keymap enable / disable lifecycle
├── search.lua        -- pattern matching, @/ sync
├── edit.lua          -- run_normal / run_visual / run_ex at all regions
├── insert.lua        -- insert mode lifecycle (start / track / finish)
├── case.lua          -- case conversion operators
├── operators.lua     -- text-object select in extend mode
├── highlight.lua     -- extmark-based highlight (namespace, draw, clear)
├── undo.lua          -- undo block API (begin_block / end_block / restore)
├── util.lua          -- byte<->pos conversion, char helpers, register ops
└── commands.lua      -- user-facing entry points (add cursor, search init, etc.)
```

### Key mapping from VimScript to Lua

| VimScript file | Lua module | Notes |
|---|---|---|
| `autoload/vm.vim` | `session.lua` + `init.lua` | Split: factory in session, plugin bootstrap in init |
| `autoload/vm/global.vim` | `global.lua` | |
| `autoload/vm/region.vim` | `region.lua` | |
| `autoload/vm/maps.vim` | `maps.lua` | |
| `autoload/vm/search.vim` | `search.lua` | |
| `autoload/vm/edit.vim` + `ecmds1.vim` + `ecmds2.vim` | `edit.lua` | Merge the three VimScript files |
| `autoload/vm/insert.vim` + `icmds.vim` | `insert.lua` | |
| `autoload/vm/funcs.vim` | `util.lua` | |
| `autoload/vm/themes.vim` | `highlight.lua` | Extmarks replace matchadd/matchdelete |
| `autoload/vm/variables.vim` | `session.lua` (init/reset sections) | Variable init/reset fold into session lifecycle |
| `autoload/vm/commands.vim` | `commands.lua` | |
| `autoload/vm/operators.vim` | `operators.lua` | |
| `autoload/vm/special/case.vim` | `case.lua` | |
| `python/vm.py` | `util.lua` (two functions) | See Section 6 |
| `plugin/visual-multi.vim` | `init.lua` (setup) + `plugin/visual-multi.lua` | Thin plugin shim; bulk logic in init |

---

## 2. Per-Buffer State Management

### Core pattern: module-level `_sessions` table keyed by bufnr

The VimScript plugin used `b:VM_Selection` (buffer-local variable holding the entire session dict) and `g:Vm` (plugin-wide state). In Lua the idiomatic equivalent is a **module-level table** in `init.lua` keyed by buffer number:

```lua
-- lua/visual-multi/init.lua
local M = {}

-- Session registry: bufnr -> session table
local _sessions = {}

-- Expose for tests (see MEMORY.md pattern)
M._sessions = _sessions

function M.get_session(buf)
  return _sessions[buf]
end

function M.has_session(buf)
  return _sessions[buf] ~= nil
end
```

**Why not `vim.b[buf].visual_multi`?** Buffer variables survive buffer wipes poorly and cannot hold Lua function references. A module-level table is simpler, faster, and fully testable without touching any buffer.

### Session table shape

```lua
-- Created by session.lua:new(buf)
local session = {
  buf     = buf,           -- buffer number (immutable)
  regions = {},            -- list of region tables, sorted by start offset
  vars    = {},            -- mutable session variables (index, direction, etc.)
  cfg     = {},            -- resolved config (copy of setup() opts)
  -- class references populated during init:
  global  = nil,           -- global.lua instance
  search  = nil,           -- search.lua instance
  edit    = nil,           -- edit.lua instance
  insert  = nil,           -- insert.lua instance
  -- undo state:
  undo    = {
    first  = 0,    -- undotree().seq_cur at session start
    ticks  = {},   -- seq_cur values after each VM edit
    last   = 0,    -- last applied tick
  },
  -- highlight:
  ns      = nil,   -- extmark namespace id (shared plugin namespace)
  -- saved settings to restore on exit:
  saved   = {},
}
```

### Plugin-wide state

Only truly global things (config defaults, the namespace id) live at module level in `init.lua` / `highlight.lua`. Everything per-buffer is in `_sessions[buf]`.

```lua
-- highlight.lua
local M = {}
M.ns = vim.api.nvim_create_namespace('visual_multi')  -- one ns, shared
```

---

## 3. Keymap Enable / Disable Lifecycle

### Pattern

The VimScript plugin used a two-tier system: permanent maps (active even between sessions) and buffer maps (active only during a session). The Lua port should follow the same structure using `vim.keymap.set` and `vim.keymap.del`.

```lua
-- maps.lua
local M = {}

-- Permanent maps: set once at plugin load, survive across sessions.
-- These are the entry-point keys: Ctrl-N, leader-combinations, etc.
function M.set_permanent(cfg)
  -- Example: the "start" keybinding
  vim.keymap.set('n', cfg.maps['Find Under'], function()
    require('visual-multi.commands').find_under()
  end, { desc = 'VM: Find word under cursor' })
end

-- Buffer-local session maps: set when session starts, removed on exit.
-- Stored so they can be systematically removed.
local _buf_maps = {}   -- bufnr -> list of {mode, lhs}

function M.enable(session)
  local buf = session.buf
  _buf_maps[buf] = {}
  local function map(mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, fn, {
      buffer  = buf,
      nowait  = true,
      silent  = true,
      desc    = 'VM: ' .. desc,
    })
    table.insert(_buf_maps[buf], { mode, lhs })
  end

  -- motion keys, edit keys, exit, etc.
  map('n', '<Esc>', function() require('visual-multi.session').stop(buf) end, 'Exit')
  -- ... all buffer-session maps ...
end

function M.disable(buf)
  for _, entry in ipairs(_buf_maps[buf] or {}) do
    pcall(vim.keymap.del, entry[1], entry[2], { buffer = buf })
  end
  _buf_maps[buf] = nil
end
```

**Key differences from VimScript:**
- `vim.keymap.set` with `buffer = buf` replaces `nmap <buffer>`.
- Collect `{mode, lhs}` pairs at enable time so `disable` does not need to know the full map list again.
- `pcall` around `vim.keymap.del` so stale-buffer cleanup never errors.
- The `nowait = true` flag is critical: without it, a prefix key (like `c`) waits for more input.

### Session start / stop autocmds

```lua
-- session.lua
function M.start(buf, cmd_type)
  if _sessions[buf] then return _sessions[buf] end  -- idempotent

  local session = build_session(buf, cmd_type)
  _sessions[buf] = session

  require('visual-multi.maps').enable(session)
  require('visual-multi.highlight').setup_session(session)

  -- BufLeave/BufEnter for suspend/resume:
  session._augroup = vim.api.nvim_create_augroup('VM_buf_' .. buf, { clear = true })
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer  = buf,
    group   = session._augroup,
    callback = function() M.suspend(buf) end,
  })
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer  = buf,
    group   = session._augroup,
    callback = function() M.stop(buf, true) end,
  })
  return session
end

function M.stop(buf, silent)
  local s = _sessions[buf]
  if not s then return end
  require('visual-multi.maps').disable(buf)
  require('visual-multi.highlight').clear_session(s)
  require('visual-multi.undo').restore_settings(s)
  vim.api.nvim_del_augroup_by_id(s._augroup)
  _sessions[buf] = nil
  if not silent then vim.notify('Exited Visual-Multi.', vim.log.levels.INFO) end
end
```

---

## 4. Undo Block Management

### The problem

A multi-cursor edit touches N positions in sequence. Without grouping, each cursor's edit is a separate undo step. The VimScript plugin solved this by:
1. Recording `undotree().seq_cur` before each batch of cursor edits (`backup_regions`).
2. Storing that tick in `b:VM_Backup.ticks[]`.
3. On `u`, jumping to the tick before the current one via `exe "undo" ticks[index-1]`.

### Lua approach: `nvim_buf_call` + `undojoin`

For operations where all cursor edits happen in one Lua call frame, `undojoin` is the right primitive:

```lua
-- undo.lua
local M = {}

-- Begin an undo block: record seq_cur before edits.
-- Call this before the cursor-loop in edit.lua.
function M.begin_block(session)
  local tree = vim.fn.undotree()
  local tick  = tree.seq_cur
  -- Trim any "future" ticks if redo happened mid-session
  local idx = find_index(session.undo.ticks, session.undo.last)
  if idx < #session.undo.ticks then
    session.undo.ticks = vim.list_slice(session.undo.ticks, 1, idx)
  end
  -- Record what was before this batch
  table.insert(session.undo.ticks, tick)
  session.undo.last = tick
end

-- End an undo block: merge all changes since begin_block into one undo entry.
-- Uses undojoin so the N cursor edits appear as one step.
function M.end_block(session)
  -- undojoin: the next buffer change joins the undo history of the previous
  -- This is only valid when buffer was actually changed.
  local tree_after = vim.fn.undotree()
  if tree_after.seq_cur ~= session.undo.last then
    -- Changes happened; record new tick
    session.undo.last = tree_after.seq_cur
  end
end

-- The critical primitive: run fn() inside the buffer's context,
-- joining all its changes into one undo entry.
-- Use for edit.lua's region loop.
function M.with_undo_block(session, fn)
  -- nvim_buf_call ensures the buffer is current (needed for undojoin).
  vim.api.nvim_buf_call(session.buf, function()
    M.begin_block(session)
    -- Apply first edit normally; subsequent edits use undojoin.
    local first = true
    fn(function(region_fn)
      if not first then
        vim.cmd('undojoin')
      end
      region_fn()
      first = false
    end)
    M.end_block(session)
  end)
end
```

**Usage in `edit.lua`:**
```lua
function Edit.run_normal(session, cmd)
  require('visual-multi.undo').with_undo_block(session, function(apply)
    for _, r in ipairs(session.regions) do
      apply(function()
        vim.api.nvim_win_set_cursor(0, {r.l, r.a - 1})
        vim.cmd('normal! ' .. cmd)
        r:update_cursor_pos()
      end)
    end
  end)
end
```

### VM-level undo (u key inside a session)

The VimScript plugin intercepts `u` during a session to undo per-VM-operation (not per-cursor). In Lua:

```lua
-- commands.lua
function M.vm_undo(session)
  local undo_state = session.undo
  local idx = find_index(undo_state.ticks, undo_state.last)

  vim.api.nvim_buf_call(session.buf, function()
    if idx <= 1 then
      -- Undo back to before the session started
      if vim.fn.undotree().seq_cur ~= undo_state.first then
        vim.cmd('silent undo ' .. undo_state.first)
        require('visual-multi.global').restore_regions(session, 0)
      end
    else
      vim.cmd('silent undo ' .. undo_state.ticks[idx - 1])
      require('visual-multi.global').restore_regions(session, idx - 1)
      undo_state.last = undo_state.ticks[idx - 1]
    end
  end)
end
```

### Important Neovim undo API facts (verified)

- `vim.fn.undotree()` returns `{ seq_cur = N, ... }` — identical to VimScript `undotree()`.
- `vim.cmd('undojoin')` joins the next change to the previous undo block. It must be called while the relevant buffer is current — hence the need for `nvim_buf_call`.
- `vim.cmd('silent undo N')` undoes to sequence number N. Must run with target buffer current.
- `vim.bo[buf].undolevels` can be set to `-1` to clear undo history (useful for scratch buffers in tests). Restore with a positive value before applying edits.
- **Gotcha**: `undojoin` must not be the very first change in a buffer — it errors if there is no previous change. Guard with `if not first then ... end`.
- **Gotcha**: `nvim_create_buf(false, true)` (scratch=true) sets `undolevels=-1`, disabling undo. For test buffers that need undo, use `nvim_create_buf(false, false)`.

---

## 5. Extmarks Namespace Management

### VimScript approach

The VimScript plugin used `matchadd`/`matchaddpos` and `matchdelete` for highlights. These are window-local and survive buffer changes, causing ghost highlights on buffer switches. Extmarks are buffer-local and automatically cleaned up.

### Lua approach

```lua
-- highlight.lua
local M = {}

-- One shared namespace for the entire plugin.
-- All VM extmarks live here; nvim_buf_clear_namespace clears them all at once.
M.ns = vim.api.nvim_create_namespace('visual_multi')

-- Draw cursor highlight for a region in cursor mode.
function M.draw_cursor(session, region)
  local buf = session.buf
  -- row is 0-indexed in extmark API; region.l is 1-indexed
  vim.api.nvim_buf_set_extmark(buf, M.ns, region.l - 1, region.a - 1, {
    hl_group   = 'VMCursor',
    end_col    = region.a,   -- highlight exactly one character width
    priority   = 200,
  })
end

-- Draw selection highlight for a region in extend mode.
function M.draw_selection(session, region)
  local buf = session.buf
  for lnum = region.l, region.L do
    local start_col = (lnum == region.l) and (region.a - 1) or 0
    local end_col   = (lnum == region.L) and region.b or -1  -- -1 = EOL
    vim.api.nvim_buf_set_extmark(buf, M.ns, lnum - 1, start_col, {
      hl_group   = 'VMExtend',
      end_row    = lnum - 1,
      end_col    = end_col,
      priority   = 150,
    })
  end
  -- Overlay cursor head
  local cursor_ln  = region.dir and region.L or region.l
  local cursor_col = region.dir and region.b or region.a
  vim.api.nvim_buf_set_extmark(buf, M.ns, cursor_ln - 1, cursor_col - 1, {
    hl_group   = 'VMCursor',
    end_col    = cursor_col,
    priority   = 200,
  })
end

-- Clear all VM extmarks in a buffer.
function M.clear_session(session)
  vim.api.nvim_buf_clear_namespace(session.buf, M.ns, 0, -1)
end

-- Clear extmarks for a single region (used during per-region update).
-- Store extmark ids on the region to allow selective deletion.
function M.clear_region(session, region)
  for _, id in ipairs(region._extmarks or {}) do
    pcall(vim.api.nvim_buf_del_extmark, session.buf, M.ns, id)
  end
  region._extmarks = {}
end

function M.setup_session(session)
  -- Nothing to do at session start; extmarks are created lazily per-region.
end
```

### Storing extmark ids on regions

```lua
-- In region.lua, after drawing:
function Region:highlight(session)
  self._extmarks = {}
  -- draw_cursor or draw_selection returns the extmark id:
  local id = vim.api.nvim_buf_set_extmark(...)
  table.insert(self._extmarks, id)
end

function Region:update_highlight(session)
  require('visual-multi.highlight').clear_region(session, self)
  self:highlight(session)
end
```

### Highlight group definitions

Defined once at `setup()` time (replacing `plugin/visual-multi.vim` highlight definitions):

```lua
-- init.lua, called from setup()
local function define_highlights(cfg)
  -- Default links; user can override in their colorscheme.
  vim.api.nvim_set_hl(0, 'VMCursor',  { link = 'Cursor',   default = true })
  vim.api.nvim_set_hl(0, 'VMExtend', { link = 'Visual',   default = true })
  vim.api.nvim_set_hl(0, 'VMInsert', { link = 'Cursor',   default = true })
  vim.api.nvim_set_hl(0, 'VMSearch', { link = 'Search',   default = true })
end
```

---

## 6. Replacing the Python Byte Operations (`python/vm.py`)

The Python helper contains exactly two functions:

| Python function | Purpose | Lua replacement |
|---|---|---|
| `py_rebuild_from_map()` | Rebuild regions from a bytes map (dict of byte offset -> count) after bulk edits | `util.rebuild_from_map(session, byte_map, range)` |
| `py_lines_with_regions()` | Group region indices by line number, sorted | `util.lines_with_regions(session, specific_line, reverse)` |

### Lua implementations

```lua
-- util.lua

local M = {}

-- Replace py_rebuild_from_map.
-- byte_map: table {[byte_offset] = count}
-- range: optional {A, B} to restrict reconstruction
function M.rebuild_from_map(session, byte_map, range)
  -- Collect and sort byte offsets
  local bys = {}
  for b in pairs(byte_map) do
    b = tonumber(b)
    if not range or (b >= range[1] and b <= range[2]) then
      table.insert(bys, b)
    end
  end
  table.sort(bys)

  if #bys == 0 then return end

  -- Erase existing regions
  require('visual-multi.global').erase_regions(session)

  -- Reconstruct contiguous runs as single regions
  local start_b = bys[1]
  local end_b   = bys[1]
  for i = 2, #bys do
    if bys[i] == end_b + 1 then
      end_b = bys[i]
    else
      require('visual-multi.region').new_from_offsets(session, start_b, end_b)
      start_b = bys[i]
      end_b   = bys[i]
    end
  end
  require('visual-multi.region').new_from_offsets(session, start_b, end_b)
end

-- Replace py_lines_with_regions.
-- Returns table {[lnum] = {region_index, ...}} sorted by index.
function M.lines_with_regions(session, specific_line, reverse)
  local lines = {}
  for _, r in ipairs(session.regions) do
    local lnum = r.l
    if not specific_line or lnum == specific_line then
      if not lines[lnum] then lines[lnum] = {} end
      table.insert(lines[lnum], r.index)
    end
  end
  -- Sort each line's indices (ascending or descending)
  for lnum, indices in pairs(lines) do
    table.sort(indices, reverse and function(a, b) return a > b end or nil)
  end
  return lines
end

-- Byte offset <-> position conversion (replaces s:Funcs.pos2byte, byte2pos, curs2byte)
function M.pos2byte(buf, line, col)
  -- line: 1-indexed, col: 1-indexed byte column
  return vim.api.nvim_buf_get_offset(buf, line - 1) + col - 1
end

function M.byte2pos(buf, byte_offset)
  -- Binary search: nvim_buf_get_offset(buf, row) gives offset of row start.
  -- For simplicity, use vim.fn.byte2line which works on current buffer.
  -- Must be called with buf as current (wrap in nvim_buf_call).
  local line = vim.fn.byte2line(byte_offset)
  local col  = byte_offset - vim.fn.line2byte(line) + 1
  return line, col
end

function M.cursor2byte(buf, line, col)
  return vim.api.nvim_buf_get_offset(buf, line - 1) + col - 1
end

function M.char_at(buf, lnum, col)
  -- col: 1-indexed byte column
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, true)[1]
  if not line then return '' end
  -- Extract one character starting at col (byte-safe via vim.fn.matchstr)
  return vim.fn.matchstr(line, string.format('\\%%%dc.', col))
end
```

**Note on `nvim_buf_get_offset`**: This is the canonical Neovim API for byte offsets. It returns the byte offset of the start of line `row` (0-indexed). Adding the 0-indexed column gives the buffer-absolute byte offset. This replaces the VimScript `line2byte(line) + col - 1` pattern exactly.

---

## 7. Module Build Order

The dependency graph determines which modules must be built (and tested) before others can be written.

### Dependency tiers

```
Tier 0 — No internal deps (build first):
  config.lua       (only uses vim.validate, no other vm modules)
  util.lua         (only uses vim.api / vim.fn; no session needed)
  highlight.lua    (only uses vim.api; creates namespace)

Tier 1 — Depends on Tier 0:
  region.lua       (uses util.lua for pos2byte / byte2pos)
  undo.lua         (uses vim.fn.undotree; no other vm modules)

Tier 2 — Depends on Tier 1:
  global.lua       (uses region.lua, highlight.lua)
  search.lua       (uses region.lua, util.lua)

Tier 3 — Depends on Tier 2:
  maps.lua         (uses config.lua; references session module via require)
  edit.lua         (uses global.lua, region.lua, undo.lua, util.lua)
  insert.lua       (uses global.lua, edit.lua, region.lua)
  operators.lua    (uses global.lua, region.lua)
  case.lua         (uses edit.lua)

Tier 4 — Assembles everything:
  session.lua      (creates session; calls all Tier 0-3 init functions)
  commands.lua     (all user-facing entry points; depends on session.lua)
  init.lua         (setup(); depends on all modules for highlight defs + maps)
```

### Implied build order for phases

1. `config.lua` + `util.lua` + `highlight.lua` (foundation — write + full unit tests)
2. `region.lua` + `undo.lua` (core data model — write + tests)
3. `global.lua` + `search.lua` (cross-region ops — write + tests)
4. `maps.lua` + `edit.lua` + `insert.lua` + `operators.lua` + `case.lua` (operations — write + tests)
5. `session.lua` + `commands.lua` + `init.lua` (wiring + entry points — integration tests)

---

## 8. Module Boundary Definitions

### `config.lua`
- **Input:** user-supplied opts table from `setup(opts)`
- **Output:** resolved config table stored in plugin-level `M._cfg` and copied into each session
- **Owns:** default values for all options; option validation
- **Does not own:** any Neovim state

### `util.lua`
- **Owns:** byte/position conversion, character extraction, register save/restore
- **Does not own:** session state; all functions take explicit `buf` / raw values

### `highlight.lua`
- **Owns:** the single `vim.api.nvim_create_namespace('visual_multi')` call; extmark draw/clear functions; highlight group definitions
- **Does not own:** region state (receives region fields as arguments)

### `region.lua`
- **Owns:** Region table shape; constructor (`Region.new`); position update methods; `remove`
- **Does not own:** highlight drawing (calls `highlight.lua`); session management

### `global.lua`
- **Owns:** multi-region operations: `erase_regions`, `merge_cursors`, `update_indices`, `change_mode`, `backup_regions`, `restore_regions`
- **Does not own:** individual region construction; undo mechanics

### `undo.lua`
- **Owns:** `begin_block`, `end_block`, `with_undo_block`, `vm_undo`, `vm_redo`, `restore_settings`
- **Does not own:** region state; highlight state

### `maps.lua`
- **Owns:** `enable(session)`, `disable(buf)`, `set_permanent(cfg)`; the `_buf_maps` registry
- **Does not own:** what happens when a key is pressed (delegates to commands/edit)

### `session.lua`
- **Owns:** `_sessions` table; `start(buf)`, `stop(buf)`, `suspend(buf)`, `resume(buf)`; settings save/restore; autocmd group lifecycle
- **Does not own:** region operations; highlight; undo mechanics (delegates to respective modules)

### `commands.lua`
- **Owns:** user-facing entry points called from maps (`add_cursor_at_pos`, `find_under`, `find_all`, `vm_undo`, `vm_redo`, etc.)
- **Does not own:** region internals; directly calls session, global, search, edit

### `init.lua`
- **Owns:** `setup(opts)`, the public `require('visual-multi')` API surface; permanent map installation at plugin load
- **Does not own:** any session or buffer state

---

## 9. Cross-Cutting Concerns

### Window-local options via `vim.wo` not `vim.bo`

When saving/restoring options at session start/end:
- `conceallevel`, `concealcursor`, `statusline` are **window-local** (`vim.wo`), not buffer-local.
- `virtualedit`, `whichwrap`, `lazyredraw`, `clipboard` are **global** (`vim.o`).
- Use `vim.bo[buf]` only for genuinely buffer-local options: `indentkeys`, `cinkeys`, `synmaxcol`, `textwidth`, `softtabstop`, `undolevels`.

### Event system: no circular requires

The VimScript plugin used `b:VM_Selection.Edit.run_normal(...)` from within map callbacks — i.e., the session object held direct class references. In Lua, map callbacks should call `require('visual-multi.commands').some_fn()` rather than closing over session fields, to avoid circular require chains. The session is retrieved from `_sessions[buf]` inside the callback.

### `nvim_buf_call` for buffer-contextual operations

Many Neovim APIs that depend on the "current buffer" (undo operations, `vim.fn` calls like `undotree()`, `byte2line()`) must be called with the target buffer as current. Wrap these in:
```lua
vim.api.nvim_buf_call(session.buf, function()
  -- operations here run with session.buf as current buffer
end)
```

### Region sorting invariant

Regions must always be sorted ascending by `A` (start byte offset). After any insert/delete that shifts offsets, re-sort or maintain order by careful insertion. The edit loop processes regions **in order** and shifts subsequent regions by the accumulated byte delta — this only works if sorted.

### Eco mode (`s:v.eco`)

The VimScript plugin skips highlight updates during bulk cursor loops (`eco = 1`), then redraws at the end. In Lua this maps to passing a `no_redraw = true` flag to region update functions, or batching all `nvim_buf_set_extmark` calls after the loop completes.

---

## 10. Key Decisions for Lua Architecture

| Decision | Rationale |
|---|---|
| Module-level `_sessions` table | Avoids buffer-variable limitations; fully testable; matches prior Lua branch (MEMORY.md) |
| Single extmark namespace | `nvim_buf_clear_namespace` clears all VM marks atomically; simpler than per-region namespaces |
| `with_undo_block` wrapper | Encapsulates the `undojoin` sequencing so `edit.lua` does not need to know undo internals |
| `util.lua` for Python ops | Two small functions; no external dependency; pure Lua table operations |
| Tier-based build order | Prevents writing integration code before unit-testable foundations exist |
| `vim.keymap.set` with stored lhs list | Systematic enable/disable without maintaining parallel "unmap" lists like VimScript |
| `nvim_buf_call` for undo ops | Ensures `undotree()` and `undo N` target the correct buffer regardless of window focus |

---

*Research complete: 2026-02-28*
