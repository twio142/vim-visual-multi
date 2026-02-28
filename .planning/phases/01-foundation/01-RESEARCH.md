# Phase 1: Foundation - Research

**Researched:** 2026-02-28
**Domain:** Neovim Lua plugin foundation — config, util, highlight, region, undo modules
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Coexistence with VimScript**
- Development happens on a new branch (e.g. `002-lua-rewrite`); the VimScript plugin on `master` stays untouched and fully functional throughout
- No feature flag — on the Lua branch, the Lua side is simply the active entry point
- `plugin/visual-multi.vim` shim: minimal bootstrap only — version guard (Neovim 0.10+) + `require('visual-multi')`. No VimScript logic duplicated there.
- VimScript `autoload/` tree remains on the Lua branch as reference material until Phase 8, when it is deleted after E2E parity is confirmed

**Config Validation**
- **Unknown keys** → `vim.notify` warning (plugin still loads): e.g. `"visual-multi: unknown option 'hightlight_matches' — did you mean 'highlight_matches'?"`
- **Wrong type** → hard error with descriptive message: e.g. `"visual-multi: setup() maps must be a table, got string"`
- **Called twice** → merge/overwrite — second call's opts are deep-merged over the existing config. No warning. Supports incremental config patterns (lazy.nvim, modular init files).
- **Lazy init** → `setup(opts)` stores config immediately but defers heavy initialization (autocommands, keymaps, highlight group registration) until the first buffer is opened. Standard Neovim plugin pattern.

**Public API & Namespace**
- Require path: `require('visual-multi')` — matches the plugin's directory and repo name
- Public surface on `init.lua`:
  - `setup(opts)` — sole config entry point
  - `get_state(bufnr?)` — returns current session state table (or nil if no active session); `bufnr` defaults to current buffer
  - All `<Plug>(VM-xxx)` mappings — exposed for every action so users can remap any key without modifying plugin source
- `vim.b.VM_Selection` — maintained on the buffer variable for backward compatibility with existing statusline configs and external integrations that read it today; `get_state()` is the new idiomatic accessor
- Internal modules (`require('visual-multi.session')`, etc.) are **private** — no public contract, free to refactor

### Claude's Discretion

- Exact structure of the `M` (module) table pattern in each Lua file
- How config defaults are stored (module-level frozen table vs function returning fresh table)
- Test helper design (fake session factory, buffer setup/teardown utilities)
- Highlight namespace initialization timing (module-level `nvim_create_namespace` vs lazy)

### Deferred Ideas (OUT OF SCOPE)

- None — discussion stayed within Phase 1 scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LUA-01 | Plugin runs entirely in Lua — no VimScript autoload files in runtime path | Branch strategy: new branch, VimScript autoload remains as reference only; plugin entry point is pure Lua (`plugin/visual-multi.vim` shim + `require('visual-multi')`) |
| LUA-02 | Targets Neovim 0.10+ only — uses vim.api, vim.keymap.set, extmarks, nvim_create_autocmd | All Tier 0-1 APIs verified stable on 0.10: nvim_create_namespace, nvim_buf_set_extmark, nvim_buf_get_offset, vim.validate, vim.tbl_deep_extend |
| LUA-03 | No Python dependency — byte operations replaced with nvim_buf_get_offset | util.lua implements pos2byte/byte2pos using nvim_buf_get_offset; Python vm.py is fully replaceable in Lua |
</phase_requirements>

---

## Summary

Phase 1 builds the five Tier-0/1 modules — `config`, `util`, `highlight`, `region`, `undo` — that every higher-tier module depends on. These five modules have no inter-plugin dependencies (they call only the Neovim API and each other in a strict acyclic order) and must be hardened against all five confirmed bugs from the prior Lua port before any session or feature code is written on top of them.

The research base is unusually solid for this phase: the project has already executed one Lua port (`001-lua-nvim-rewrite`), confirmed bugs are documented in MEMORY.md and PITFALLS.md, and the prior branch produced 94 unit tests that define the expected API surface. All stack and API knowledge is verified against Neovim 0.10 stable documentation. The main planning task is translating this confirmed knowledge into correctly-scoped tasks with explicit "done" criteria tied to each confirmed bug.

The single most important design decision for this phase is establishing the `_is_session()` dispatch convention (BUG-05 fix) in the first module written, since every subsequent module follows the same pattern. The second most important is ensuring test buffers use `nvim_create_buf(false, false)` and that the undo-grouping helpers short-circuit on no-change (BUG-02, BUG-04 fixes) — these are invisible bugs that produce wrong undo counts and are hard to catch after the fact.

**Primary recommendation:** Write modules in strict Tier 0 → Tier 1 order. Do not start `region.lua` or `undo.lua` until `config.lua`, `util.lua`, and `highlight.lua` each have a passing mini.test spec. Establish the `_is_session()` dispatch helper in `util.lua` so all modules inherit it.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Neovim built-in API | 0.10+ | `vim.api.*`, `vim.keymap`, `vim.bo`, `vim.wo` | No external dep; all APIs stable on 0.10 |
| mini.test | vendored at `test/vendor/mini.test` | Headless unit test framework | Already used in prior branch; 94 tests written; no external runner needed |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `vim.fn.*` | built-in | `undotree()`, `byte2line()`, `matchstr()`, `maparg()`, `strdisplaywidth()` | Only when no equivalent `vim.api.*` call exists |
| `vim.tbl_deep_extend` | built-in | Config merging | Always for merging user opts over defaults |
| `vim.validate` | built-in | Config type checking | Once in `config.apply()` — never in individual modules |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| mini.test | plenary.nvim test | plenary has heavier deps and is not vendorable without external install; mini.test is already vendored |
| mini.test | busted | busted requires luarocks distribution model; adds CI complexity; not worth the switch |
| `nvim_buf_get_offset` | `vim.fn.line2byte()` | `line2byte()` is 1-indexed and returns -1 for invalid lines; `nvim_buf_get_offset` is 0-indexed and unambiguous — use the API form |

**Installation:** No npm/pip installs for Phase 1. mini.test is already vendored. The test runner command is:

```bash
nvim --headless -u NORC -l test/run_spec.lua
```

---

## Architecture Patterns

### Recommended Project Structure

```
lua/
  visual-multi/
    init.lua          -- Public entry: setup(opts), get_state(bufnr?), _sessions registry
    config.lua        -- Defaults table, apply(opts), _validate(cfg), known-keys set
    util.lua          -- pos2byte, byte2pos, char_at, byte_len/char_len/display_width,
                      -- _is_session() dispatch helper, rebuild_from_map, lines_with_regions
    highlight.lua     -- Single namespace (ns), define_groups(cfg), draw_cursor, draw_selection,
                      -- clear(buf), clear_region(region)
    region.lua        -- Region.new(buf, row, col), Region.move(r, row, col), Region.remove(r),
                      -- Region.pos(r) → current {row,col} via extmark readback
    undo.lua          -- begin_block(session), end_block(session, lines_before, lines_after),
                      -- with_undo_block(session, fn), restore_settings(session)
plugin/
  visual-multi.vim    -- Version guard (0.10+), loaded guard, require('visual-multi')
test/
  vendor/mini.test/   -- Already vendored
  spec/
    config_spec.lua
    util_spec.lua
    highlight_spec.lua
    region_spec.lua
    undo_spec.lua
  run_spec.lua
```

### Pattern 1: Module Table (M) with Private State

**What:** Each module exports a plain table `M`. Private state lives at module scope (not in `M`). Tests inject via `M._exposed_field` only when necessary.

**When to use:** Every module in the plugin.

```lua
-- Source: STACK.md / standard Neovim Lua plugin convention
local M = {}

-- Private (not in M):
local _state = {}

function M.public_fn(arg1)
  -- ...
end

-- Exposed for tests only:
M._sessions = _sessions  -- same reference, not a copy

return M
```

### Pattern 2: `_is_session()` Dispatch (BUG-05 Fix)

**What:** Every public function that can be called with either a session table or a raw bufnr uses a single entry point with internal dispatch. No duplicate field definitions.

**When to use:** Any function in `highlight.lua`, `region.lua`, `undo.lua` that needs the session's `.buf` field.

```lua
-- Source: PITFALLS.md BUG-05 / MEMORY.md
local function _is_session(arg)
  return type(arg) == 'table' and arg._stopped ~= nil
end

-- In util.lua — exported for other modules to import
function M.is_session(arg)
  return _is_session(arg)
end

-- Usage in highlight.lua:
function M.clear(session_or_buf)
  local buf = M.is_session(session_or_buf) and session_or_buf.buf or session_or_buf
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
end
```

### Pattern 3: Config Apply with Known-Key Warning

**What:** `config.apply(opts)` deep-merges opts, validates types with `vim.validate`, and warns on unknown top-level keys. Called twice = second call deep-merges over first (no warning).

**When to use:** `init.lua`:`setup()` → delegates to `config.apply()`.

```lua
-- Source: CONTEXT.md locked decisions / STACK.md §3
local KNOWN_KEYS = {
  leader=true, highlight=true, live_editing=true, case_setting=true,
  reindent_filetypes=true, mappings=true, filesize_limit=true, debug=true,
}

function M.apply(opts)
  opts = opts or {}
  -- Warn on unknown keys
  for k in pairs(opts) do
    if not KNOWN_KEYS[k] then
      vim.notify(
        string.format("visual-multi: unknown option '%s'", k),
        vim.log.levels.WARN
      )
    end
  end
  -- Type validation (hard error on wrong type)
  vim.validate({
    live_editing   = { opts.live_editing,   'boolean', true },
    filesize_limit = { opts.filesize_limit,  'number',  true },
    debug          = { opts.debug,           'boolean', true },
  })
  -- Merge over persistent config (second call = overwrite)
  _cfg = vim.tbl_deep_extend('force', _cfg or M.defaults, opts)
  return _cfg
end
```

### Pattern 4: Extmark Namespace — Module-Level, Shared

**What:** One `nvim_create_namespace` call at module-level in `highlight.lua`. All VM extmarks in all buffers use this single namespace.

**When to use:** `highlight.lua` top-level. Referenced by `region.lua` via `require('visual-multi.highlight').ns`.

```lua
-- Source: STACK.md §4.1 / ARCHITECTURE.md §5
local M = {}
M.ns = vim.api.nvim_create_namespace('visual_multi')
-- ...
return M
```

**Why module-level (not lazy):** `nvim_create_namespace` is idempotent by name — calling it again returns the same id. Module-level initialization is simpler, runs once, and never fails.

### Pattern 5: Extmark-Based Region Position — Store ID, Update In Place

**What:** Each region stores its `extmark_id`. Position updates use the `id=` parameter to update in place (O(log n)), not clear-and-recreate (O(n)). Reading back current position uses `nvim_buf_get_extmark_by_id`.

**When to use:** `region.lua` `Region.new` and `Region.move`.

```lua
-- Source: STACK.md §4.4–4.5
function Region.new(buf, row, col)
  local hl = require('visual-multi.highlight')
  local r = { buf = buf }
  r.mark_id = vim.api.nvim_buf_set_extmark(buf, hl.ns, row, col, {
    end_row  = row,
    end_col  = col + 1,
    hl_group = 'VMCursor',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
  return r
end

function Region.pos(r)
  local hl = require('visual-multi.highlight')
  local info = vim.api.nvim_buf_get_extmark_by_id(
    r.buf, hl.ns, r.mark_id, { details = false }
  )
  return info[1], info[2]  -- row (0-indexed), col (0-indexed byte)
end
```

### Pattern 6: Undo Block with Empty-Change Guard (BUG-03 + BUG-04 Fix)

**What:** `undo.begin_block` records `undotree().seq_cur`. `undo.end_block` short-circuits if lines before == lines after (BUG-04). All per-buffer undolevels use `vim.bo[buf].undolevels` not `vim.o` (BUG-03).

**When to use:** `undo.lua` exported API; consumed by `edit.lua` in Phase 2+.

```lua
-- Source: PITFALLS.md BUG-03, BUG-04 / ARCHITECTURE.md §4
function M.begin_block(session)
  vim.api.nvim_buf_call(session.buf, function()
    local tree = vim.fn.undotree()
    session.undo = session.undo or {}
    session.undo.seq_before = tree.seq_cur
  end)
end

function M.end_block(session, lines_before, lines_after)
  -- BUG-04: short-circuit on no-change to avoid spurious undo entry
  if lines_before == lines_after then return end
  vim.api.nvim_buf_call(session.buf, function()
    local tree = vim.fn.undotree()
    session.undo.seq_after = tree.seq_cur
  end)
end
```

### Pattern 7: Test Buffer Creation (BUG-02 Fix)

**What:** All test buffers that exercise undo must use `(false, false)`. Scratch-mode `(false, true)` disables undo silently.

**When to use:** Every spec file that tests undo behavior.

```lua
-- Source: PITFALLS.md BUG-02 / MEMORY.md
-- WRONG — undo is disabled on scratch buffers:
-- local buf = vim.api.nvim_create_buf(false, true)

-- CORRECT:
local buf = vim.api.nvim_create_buf(false, false)
vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
```

### Anti-Patterns to Avoid

- **`vim.bo[buf]` for window-local options:** `conceallevel`, `concealcursor`, `statusline` are window-local — use `vim.wo` or `nvim_win_set_option(win, ...)` (BUG-01).
- **Two definitions of `M.fn`:** Duplicate table keys silently shadow the first. Use `_is_session()` dispatch in a single function (BUG-05).
- **`vim.o.undolevels` for undo grouping:** Affects all buffers globally. Always use `vim.bo[buf].undolevels` (BUG-03).
- **`vim.fn.line2byte()` for byte offsets:** 1-indexed, returns -1 for invalid lines. Use `nvim_buf_get_offset(buf, row_0indexed)` (LUA-03).
- **`require()` at module top-level across circular paths:** `region.lua` requires `highlight.lua`; `highlight.lua` must not require `region.lua`. Check the Tier dependency graph before adding any `require`.
- **`#str` for position math:** Lua `#str` is byte count. For display-column math use `vim.fn.strdisplaywidth()`; for character count use `vim.fn.strcharlen()`. Never use `#str` in column arithmetic (PITFALL-14).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config deep merge | Custom recursive merge | `vim.tbl_deep_extend('force', defaults, opts)` | Handles nested tables, nil, metatables correctly; battle-tested |
| Type validation | Custom type-check loops | `vim.validate({key = {val, type, optional}})` | Produces consistent error messages; one call covers all fields |
| Test assertions | Custom assert helpers | `MiniTest.expect.equality`, `MiniTest.expect.error`, `MiniTest.expect.no_error` | Already vendored; matches existing 94-test suite API |
| Extmark position tracking after edits | Manual byte-delta arithmetic | `nvim_buf_get_extmark_by_id` | Neovim updates extmark positions automatically on text changes |
| Namespace management | Per-buffer namespace tables | Single `nvim_create_namespace('visual_multi')` + `nvim_buf_clear_namespace(buf, ns, 0, -1)` | Atomic clear; simpler lifecycle; no ID bookkeeping |
| Byte offset of line start | `vim.fn.line2byte()` | `vim.api.nvim_buf_get_offset(buf, row_0indexed)` | Type-safe, 0-indexed, returns -1 only for invalid row — easy to guard |

**Key insight:** The Neovim API already solves the three hardest problems from the VimScript version: position tracking after edits (extmarks), byte-offset calculation (nvim_buf_get_offset), and undo state (undotree + undojoin). Do not replicate these with custom logic.

---

## Common Pitfalls

### Pitfall 1: Window-Local Options via `vim.bo` (BUG-01)

**What goes wrong:** `vim.bo[buf].conceallevel = 0` is a silent no-op or writes to the wrong scope. Conceal and statusline don't restore on VM exit.

**Why it happens:** `conceallevel`, `concealcursor`, and `statusline` are typed `window` in `:help option-list`. Neovim exposes them via `vim.wo`, not `vim.bo`.

**How to avoid:** Before setting any option, look up its scope in the Quick Reference table below. Save/restore using the correct accessor keyed by `win_id`.

**Warning signs:** Conceallevel setting doesn't visually take effect; statusline stays as VM statusline after exit.

### Pitfall 2: Scratch Buffers Disable Undo (BUG-02)

**What goes wrong:** Tests that create `nvim_create_buf(false, true)` and then check `undotree().seq_cur` always see 0 changes — undo is silently disabled.

**Why it happens:** Neovim sets `undolevels = -1` on scratch buffers automatically.

**How to avoid:** Use `nvim_create_buf(false, false)` + explicit `buftype = 'nofile'`. Add an assertion in test setup: `assert(vim.bo[buf].undolevels ~= -1, 'undo not enabled on test buffer')`.

**Warning signs:** `undotree().seq_cur` never advances; undo tests pass trivially even with broken undo logic.

### Pitfall 3: Global Undolevels Corruption (BUG-03)

**What goes wrong:** Multiple undo steps required to reverse a single multi-cursor edit. Undo history in unrelated open buffers gets corrupted.

**Why it happens:** `vim.o.undolevels = -1` affects all buffers globally, not just the target buffer.

**How to avoid:** Always use `vim.bo[buf].undolevels` for the undo-grouping flush pattern. Wrap in `nvim_buf_call` to ensure the buffer is current.

**Warning signs:** Undo in an unrelated buffer jumps to unexpected state; multi-cursor undo requires multiple presses.

### Pitfall 4: Spurious Undo Entry on No-Change (BUG-04)

**What goes wrong:** Pressing `u` after a no-op VM operation (e.g., search with no results) reverts a real prior edit.

**Why it happens:** Opening and closing an undo block advances `seq_cur` even if no text changed.

**How to avoid:** `end_block` must compare lines/content before and after and short-circuit if identical.

**Warning signs:** Extra `u` required to reach pre-VM state; undo count in `undotree()` is higher than expected.

### Pitfall 5: Duplicate Function Definitions (BUG-05)

**What goes wrong:** `M.fn` defined twice — second definition silently overwrites first. Lua linter warns; function only works for one of the two intended signatures.

**Why it happens:** Dual API pattern (`fn(session, ...)` and `fn(buf, ...)`) was implemented as two `M.fn =` assignments.

**How to avoid:** Define `_is_session()` in `util.lua` first. Import it in every module. Use a single function body with `if _is_session(arg) then ... else ... end` dispatch.

**Warning signs:** Lua-ls warning: "Duplicate key 'fn'"; function works with session but not buf, or vice versa.

### Pitfall 6: Byte vs Character vs Display Width Confusion (PITFALL-14)

**What goes wrong:** Cursor position drifts on lines with multibyte characters (CJK, emoji, combining marks). Highlights appear one-character off.

**Why it happens:** Lua `#str` is byte count. `nvim_buf_set_extmark` `col` is byte offset. Mixing character counts with byte offsets silently corrupts positions.

**How to avoid:** `util.lua` exports named helpers: `byte_len(s)` (= `#s`), `char_len(s)` (= `vim.fn.strcharlen(s)`), `display_width(s)` (= `vim.fn.strdisplaywidth(s)`). Never use `#str` in column arithmetic.

**Warning signs:** Tests pass on ASCII-only content but fail with `é`, `字`, or emoji in test strings.

### Pitfall 7: Circular `require()` Between Tier 0-1 Modules

**What goes wrong:** `region.lua` requires `highlight.lua` AND `highlight.lua` requires `region.lua` → Lua raises a "module not found" or returns an incomplete table.

**Why it happens:** Circular requires in Lua return `true` (the partial module table) on the second call, not the final table.

**How to avoid:** Strictly follow the Tier dependency graph. `highlight.lua` receives region position fields as arguments — it never imports `region.lua`. If two modules need each other, extract the shared dependency into a lower Tier.

**Warning signs:** Module function is `nil` at call time despite being defined; `require()` returns `true` instead of a table.

---

## Code Examples

Verified patterns from documented sources:

### `config.lua` — apply with unknown-key warning and type validation

```lua
-- Source: CONTEXT.md (config validation decisions) + STACK.md §3
local M = {}

local KNOWN_KEYS = {
  leader=true, highlight=true, live_editing=true, case_setting=true,
  reindent_filetypes=true, mappings=true, filesize_limit=true, debug=true,
}

M.defaults = {
  leader         = '<leader>vm',
  live_editing   = true,
  case_setting   = 'smart',
  reindent_filetypes = {},
  filesize_limit = 1024 * 1024,
  debug          = false,
  highlight = {
    cursor  = 'VMCursor',
    extend  = 'VMExtend',
    insert  = 'VMInsert',
  },
  mappings = {
    basic           = true,
    find_under      = '<C-n>',
    add_cursor_down = '<C-Down>',
    add_cursor_up   = '<C-Up>',
  },
}

local _cfg = nil

function M.apply(opts)
  opts = opts or {}
  for k in pairs(opts) do
    if not KNOWN_KEYS[k] then
      vim.notify(
        string.format("visual-multi: unknown option '%s'", k),
        vim.log.levels.WARN
      )
    end
  end
  vim.validate({
    live_editing   = { opts.live_editing,   'boolean', true },
    filesize_limit = { opts.filesize_limit,  'number',  true },
    debug          = { opts.debug,           'boolean', true },
  })
  if type(opts.mappings) ~= 'nil' and type(opts.mappings) ~= 'table' then
    error(string.format(
      "visual-multi: setup() mappings must be a table, got %s",
      type(opts.mappings)
    ))
  end
  -- Second call merges over existing config (no warning per decision)
  _cfg = vim.tbl_deep_extend('force', _cfg or M.defaults, opts)
  return _cfg
end

function M.get()
  return _cfg or M.defaults
end

return M
```

### `util.lua` — `_is_session` dispatch, byte helpers, `nvim_buf_get_offset`

```lua
-- Source: PITFALLS.md BUG-05 + ARCHITECTURE.md §6 + LUA-03 requirement
local M = {}

function M.is_session(arg)
  return type(arg) == 'table' and arg._stopped ~= nil
end

-- Named length helpers — never use #str in position math
function M.byte_len(s)         return #s end
function M.char_len(s)         return vim.fn.strcharlen(s) end
function M.display_width(s)    return vim.fn.strdisplaywidth(s) end

-- Byte offset of (1-indexed line, 1-indexed byte col)
-- Uses nvim_buf_get_offset — replaces line2byte() per LUA-03
function M.pos2byte(buf, line, col)
  return vim.api.nvim_buf_get_offset(buf, line - 1) + col - 1
end

-- Character at 1-indexed (lnum, col) — byte-safe via vim.fn.matchstr
function M.char_at(buf, lnum, col)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, true)[1]
  if not line then return '' end
  return vim.fn.matchstr(line, string.format('\\%%%dc.', col))
end

return M
```

### `highlight.lua` — single namespace, define_groups with `default = true`

```lua
-- Source: STACK.md §4.1–4.7 / ARCHITECTURE.md §5
local M = {}

-- Module-level: idempotent by name, runs once
M.ns = vim.api.nvim_create_namespace('visual_multi')

function M.define_groups()
  vim.api.nvim_set_hl(0, 'VMCursor', { default = true, link = 'Cursor'  })
  vim.api.nvim_set_hl(0, 'VMExtend', { default = true, link = 'Visual'  })
  vim.api.nvim_set_hl(0, 'VMInsert', { default = true, link = 'Cursor'  })
  vim.api.nvim_set_hl(0, 'VMSearch', { default = true, link = 'Search'  })
end

function M.draw_cursor(buf, row, col, mark_id)
  return vim.api.nvim_buf_set_extmark(buf, M.ns, row, col, {
    id       = mark_id,   -- nil on first call; existing id on update
    end_row  = row,
    end_col  = col + 1,
    hl_group = 'VMCursor',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
end

function M.clear(session_or_buf)
  local util = require('visual-multi.util')
  local buf = util.is_session(session_or_buf) and session_or_buf.buf
              or session_or_buf
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
end

return M
```

### `undo.lua` — begin/end block with BUG-03 and BUG-04 fixes

```lua
-- Source: PITFALLS.md BUG-03, BUG-04 / ARCHITECTURE.md §4
local M = {}

function M.begin_block(session)
  vim.api.nvim_buf_call(session.buf, function()
    session._undo_seq_before = vim.fn.undotree().seq_cur
    session._undo_lines_before = vim.api.nvim_buf_get_lines(
      session.buf, 0, -1, false
    )
  end)
end

function M.end_block(session)
  local lines_after = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
  -- BUG-04: short-circuit if nothing changed
  if vim.deep_equal(session._undo_lines_before, lines_after) then
    session._undo_seq_before = nil
    session._undo_lines_before = nil
    return
  end
  vim.api.nvim_buf_call(session.buf, function()
    session._undo_seq_after = vim.fn.undotree().seq_cur
  end)
  session._undo_lines_before = nil
end

-- Flush undo history for current buffer into a single block.
-- Uses vim.bo[buf] (BUG-03: per-buffer, not vim.o).
function M.flush_undo_history(buf)
  -- BUG-03: use vim.bo[buf], not vim.o
  local saved = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {})  -- no-op change to flush
  vim.bo[buf].undolevels = saved
end

return M
```

### `region.lua` — extmark-based, ID stored for in-place update

```lua
-- Source: STACK.md §4.3–4.5 / ARCHITECTURE.md §3
local M = {}
local Region = {}
Region.__index = Region

function Region.new(buf, row, col)
  local hl = require('visual-multi.highlight')
  local r = setmetatable({ buf = buf, _stopped = false }, Region)
  r.mark_id = vim.api.nvim_buf_set_extmark(buf, hl.ns, row, col, {
    end_row  = row,
    end_col  = col + 1,
    hl_group = 'VMCursor',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
  return r
end

function Region:pos()
  local hl = require('visual-multi.highlight')
  local info = vim.api.nvim_buf_get_extmark_by_id(
    self.buf, hl.ns, self.mark_id, {}
  )
  return info[1], info[2]  -- row (0-indexed), col (0-indexed byte)
end

function Region:move(row, col)
  local hl = require('visual-multi.highlight')
  vim.api.nvim_buf_set_extmark(self.buf, hl.ns, row, col, {
    id       = self.mark_id,  -- update in place
    end_row  = row,
    end_col  = col + 1,
    hl_group = 'VMCursor',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
end

function Region:remove()
  local hl = require('visual-multi.highlight')
  pcall(vim.api.nvim_buf_del_extmark, self.buf, hl.ns, self.mark_id)
  self._stopped = true
end

M.new = Region.new
return M
```

### mini.test spec skeleton — correct buffer creation for undo tests

```lua
-- Source: STACK.md §7.1 / PITFALLS.md BUG-02
local MiniTest = require('test.vendor.mini.test')
local T = MiniTest.new_set()

local function make_buf()
  -- BUG-02: (false, false) so undo is enabled
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  -- Assert undo is actually enabled
  assert(vim.bo[buf].undolevels ~= -1, 'undo must be enabled on test buffer')
  return buf
end

T['undo.begin_block records seq_cur'] = function()
  local buf = make_buf()
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'hello'})

  local session = { buf = buf, _stopped = false }
  require('visual-multi.undo').begin_block(session)
  MiniTest.expect.truthy(session._undo_seq_before ~= nil)

  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
```

### `plugin/visual-multi.vim` — minimal shim (LUA-01)

```vim
" Source: CONTEXT.md locked decisions / STACK.md §2.1
if !has('nvim-0.10')
  echohl WarningMsg
  echom 'vim-visual-multi: Neovim 0.10+ required'
  echohl None
  finish
endif

if exists('g:loaded_visual_multi')
  finish
endif
let g:loaded_visual_multi = 1

lua require('visual-multi')
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `matchadd`/`matchaddpos` for highlights | `nvim_buf_set_extmark` with `hl_group` | Extmarks stable since Neovim 0.7; preferred since 0.9 | Position tracking is automatic; teardown is atomic; no ghost highlights on buffer switch |
| `line2byte()` for byte offsets | `nvim_buf_get_offset(buf, row_0indexed)` | API available since Neovim 0.5 | 0-indexed, buffer-targeted, no current-buffer dependency |
| Python `vm.py` for byte range ops | Pure Lua in `util.lua` + extmarks | LUA-03 decision | No pynvim dependency; faster; headless-testable |
| `g:VM_xxx` globals for config | `setup(opts)` → module-local `_cfg` | LUA-03 / CFG-01 decisions | No global pollution; introspectable; lazy.nvim compatible |
| VimScript `autoload/` OOP dict pattern | Lua module table (`M`) with `_sessions[buf]` keyed by bufnr | This rewrite | True multi-buffer isolation; GC-friendly; fully unit-testable |

**Deprecated/outdated:**
- `vim.api.nvim_set_keymap`: Use `vim.keymap.set` — handles `<Plug>`, Lua callbacks, mode normalization.
- `vim.cmd('autocmd ...')`: Use `nvim_create_autocmd` — type-safe, Lua callbacks, no string escaping.
- `vim.cmd('highlight ...')`: Use `nvim_set_hl` — type-safe, supports `default = true`.
- `vim.cmd('echom ...')` / `echon`: Use `vim.notify` — integrates with noice.nvim (see commit `a03b78a`).
- `vim.api.nvim_buf_set_option` (deprecated in 0.10+): Use `vim.bo[buf].opt = val` form.

---

## Open Questions

1. **`vim.deep_equal` availability**
   - What we know: Used in the `end_block` example above to compare line content; standard Lua does not have it natively; Neovim may provide it via `vim.deep_equal`.
   - What's unclear: Whether `vim.deep_equal` exists in 0.10 or whether `vim.fn.type` + manual comparison is needed.
   - Recommendation: During Wave 0 (test infrastructure setup), write a quick spec that calls `vim.deep_equal({}, {})` and confirm it returns `true`. If it errors, replace with `vim.inspect(a) == vim.inspect(b)` (slower but reliable for short line arrays) or a manual table comparison helper.

2. **`plugin/visual-multi.vim` vs `plugin/visual-multi.lua`**
   - What we know: STACK.md recommends `plugin/visual-multi.lua` (Lua). CONTEXT.md says `plugin/visual-multi.vim` shim.
   - What's unclear: Whether the `.vim` shim is sufficient for the 0.10 version guard, or whether a `.lua` plugin file is cleaner.
   - Recommendation: Use `.vim` for the version guard (`has('nvim-0.10')` is only expressible in VimScript) + the loaded guard + `lua require('visual-multi')`. This satisfies LUA-01 — no VimScript _logic_ is duplicated, only the bootstrap guard.

3. **`_stopped` field as session discriminator for `_is_session()`**
   - What we know: The prior branch used `arg._stopped ~= nil` as the discriminant (PITFALLS.md BUG-05).
   - What's unclear: Whether `_stopped` is the best sentinel for Phase 1 sessions, which are minimal data tables without the full session shape.
   - Recommendation: Accept `_stopped` as the convention. Add it to the fake session factory used in tests: `{ buf = buf, _stopped = false }`. Document it in a comment in `util.lua`.

---

## Option Scope Quick Reference

Options touched by vim-visual-multi with their correct Lua accessor (critical for BUG-01 prevention):

| Option | Scope | Correct Lua Accessor |
|--------|-------|---------------------|
| `conceallevel` | window | `vim.wo.conceallevel` / `nvim_win_get_option(win, 'conceallevel')` |
| `concealcursor` | window | `vim.wo.concealcursor` / `nvim_win_get_option(win, 'concealcursor')` |
| `statusline` | window | `vim.wo.statusline` / `nvim_win_set_option(win, 'statusline', ...)` |
| `virtualedit` | global+window | `vim.o.virtualedit` (global); `vim.wo.virtualedit` (local override) |
| `whichwrap` | global | `vim.o.whichwrap` |
| `hlsearch` | global | `vim.o.hlsearch` |
| `smartcase` | global | `vim.o.smartcase` |
| `ignorecase` | global | `vim.o.ignorecase` |
| `clipboard` | global | `vim.o.clipboard` |
| `lazyredraw` | global | `vim.o.lazyredraw` |
| `cmdheight` | global | `vim.o.cmdheight` |
| `undolevels` | global+buffer | `vim.bo[buf].undolevels` (per-session undo grouping) |
| `indentkeys` | buffer | `vim.bo[buf].indentkeys` |
| `foldenable` | window | `vim.wo.foldenable` |

---

## Sources

### Primary (HIGH confidence)

- `.planning/research/PITFALLS.md` — 5 confirmed bugs (BUG-01 through BUG-05) from `001-lua-nvim-rewrite` branch; 14 common pitfalls from VimScript source analysis
- `.planning/research/STACK.md` — Neovim 0.10 API surface; all APIs cross-referenced against Neovim stable documentation; mini.test API; extmarks patterns
- `.planning/research/ARCHITECTURE.md` — Tier dependency graph; module boundary definitions; undo block design; Python vm.py Lua replacements
- `MEMORY.md` (project memory) — Confirmed bug patterns (BUG-01 through BUG-05) from the prior Lua port; T052 parity finding
- `.planning/phases/01-foundation/01-CONTEXT.md` — Locked user decisions on config validation, public API surface, branch strategy

### Secondary (MEDIUM confidence)

- `.planning/codebase/ARCHITECTURE.md` — VimScript architecture layers; session data flow; used to understand what Tier 0-1 must replace
- `.planning/codebase/STACK.md` — Current VimScript + Python dependencies being replaced

### Tertiary (LOW confidence — none for this phase)

No web search was used. All findings are based on confirmed prior-branch experience and the project's existing research documents.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are Neovim 0.10 stable; mini.test is vendored and already in use
- Architecture: HIGH — Tier dependency graph is confirmed by ARCHITECTURE.md; module boundaries are well-defined
- Pitfalls: HIGH — BUG-01 through BUG-05 are confirmed bugs from the prior port with specific reproduction paths
- Code examples: HIGH — all examples follow documented patterns from the project's own research

**Research date:** 2026-02-28
**Valid until:** 2026-05-28 (90 days — all APIs are in Neovim stable, no fast-moving dependencies)
