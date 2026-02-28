# Target Stack Research: Neovim Lua Plugin (2025/2026)

**Research Date:** 2026-02-28
**Context:** vim-visual-multi Lua rewrite — replacing VimScript autoload + Python + g:VM_xxx globals with pure Lua, setup() API, extmarks highlighting, Neovim-only.
**Confidence notation:** [HIGH] = stable Neovim API, widely adopted; [MED] = community consensus but some variation; [LOW] = evolving, fragmented opinion.

---

## 1. Runtime Requirements

**Minimum Neovim version: 0.10.0** [HIGH]

Rationale:
- `nvim_buf_set_extmark` with full opts (including `hl_group`, `end_row`, `end_col`, `virt_text`, `priority`) has been stable since 0.7, but `hl_mode` and inline virtual text arrived in 0.9.
- `vim.keymap.set` stable since 0.7.
- `vim.api.nvim_create_autocmd` with `callback` (not string) stable since 0.7.
- `nvim_create_user_command` stable since 0.7.
- `vim.tbl_deep_extend` for config merging — stable since early Lua API.
- `vim.validate` for option validation — stable, available since 0.6+.
- Neovim 0.10 is the current stable release as of 2025; targeting 0.10 gives two full LTS generations of headroom and allows using `vim.snippet`, `vim.lsp.*` if needed, and the refined `vim.iter` API (0.10+).
- **Do NOT target 0.9** — 0.10 is already the de facto minimum for new plugins. Targeting older means shipping workarounds for bugs that are fixed.

**Do NOT support Vim (non-Neovim).** The API surface (extmarks, `vim.api.*`, `vim.keymap`, `vim.uv`) is Neovim-only. There is no compatibility shim worth maintaining.

---

## 2. Module Structure Conventions

### 2.1 Directory Layout [HIGH]

```
lua/
  visual-multi/
    init.lua          -- Public entry point: setup(), public commands
    config.lua        -- Default config table, validation, merging
    session.lua       -- Per-buffer session state (replaces b:VM_Selection)
    region.lua        -- Region object: cursor/selection abstraction
    highlight.lua     -- Extmarks-based highlighting
    keymap.lua        -- Buffer-local keymap management
    commands.lua      -- Command dispatch (add cursor, search, etc.)
    edit.lua          -- Normal-mode multi-cursor edit operations
    insert.lua        -- Insert-mode entry and synchronization
    search.lua        -- Pattern search across regions
    case.lua          -- Case conversion operations
    undo.lua          -- Undo grouping logic
    util.lua          -- Shared utilities (byte/pos conversion, etc.)
plugin/
  visual-multi.lua    -- Thin shim: vim.g.loaded_visual_multi guard,
                      -- nvim_create_user_command, etc. No logic here.
```

The `plugin/` file runs at startup unconditionally. Keep it to an absolute minimum:
- Set `vim.g.loaded_visual_multi = true` guard.
- Register user commands that delegate to `require('visual-multi')`.
- Register any permanent (non-session) `<Plug>` mappings.
- No `require()` of heavy modules at this point — lazy load.

### 2.2 Module Loading Pattern [HIGH]

Use a local cached require at the top of each module:

```lua
-- In session.lua
local config   = require('visual-multi.config')
local region   = require('visual-multi.region')
local highlight = require('visual-multi.highlight')
```

Modules are loaded once and cached by Lua's `package.loaded` table. Circular dependencies must be avoided by design — if A requires B and B requires A, restructure so both depend on a shared C (usually `config` or `util`).

**Lazy initialization for session state:** The heavy modules (`session`, `edit`, `insert`, `search`) should only be `require()`d when a session actually starts, not at plugin load time. The `plugin/` shim and `init.lua`'s top-level code must not eagerly pull in the full module graph.

Pattern:

```lua
-- In init.lua
local M = {}

M._session_mod = nil  -- loaded on first use

local function session()
  if not M._session_mod then
    M._session_mod = require('visual-multi.session')
  end
  return M._session_mod
end
```

Alternatively, use `vim.api.nvim_create_autocmd` to trigger real initialization only when the user activates VM.

### 2.3 Module API Shape [HIGH]

Each module exports a table `M`:

```lua
local M = {}

-- Private state at module scope (not in M)
local _state = {}

function M.public_fn(arg1, arg2)
  -- ...
end

return M
```

Never leak private state into `M`. If tests need to inject state, expose a `M._reset()` or `M._sessions` field (as done in the existing `001-lua-nvim-rewrite` branch's `init.lua`).

---

## 3. setup() Config API

### 3.1 Structure [HIGH]

```lua
-- lua/visual-multi/config.lua

local M = {}

M.defaults = {
  -- Keymap prefix for all VM mappings
  leader = '<leader>vm',

  -- Multi-cursor visual feedback
  highlight = {
    cursor   = 'VMCursor',     -- highlight group for cursor columns
    extend   = 'VMExtend',     -- highlight group for extend-mode selections
    insert   = 'VMInsert',     -- highlight group during insert mode
  },

  -- Behavioral options (replaces individual g:VM_xxx vars)
  live_editing       = true,
  case_setting       = 'smart',   -- 'smart' | 'sensitive' | 'insensitive'
  reindent_filetypes = {},

  -- Keymaps (nil = use default, false = disable)
  mappings = {
    basic             = true,
    add_cursor_down   = '<C-Down>',
    add_cursor_up     = '<C-Up>',
    add_cursor_at_pos = '<C-LeftMouse>',
    find_under        = '<C-n>',
    -- ...
  },

  -- File size guard (bytes)
  filesize_limit = 1024 * 1024,  -- 1 MiB

  -- Debug
  debug = false,
}

-- Merges user opts into defaults; returns validated config.
function M.apply(opts)
  opts = opts or {}
  local cfg = vim.tbl_deep_extend('force', M.defaults, opts)
  M._validate(cfg)
  return cfg
end

function M._validate(cfg)
  vim.validate({
    live_editing   = { cfg.live_editing, 'boolean' },
    filesize_limit = { cfg.filesize_limit, 'number' },
    debug          = { cfg.debug, 'boolean' },
    -- Add per-field validation as needed
  })
  -- Custom validations beyond type-checking:
  assert(
    vim.tbl_contains({'smart','sensitive','insensitive'}, cfg.case_setting),
    "visual-multi: case_setting must be 'smart', 'sensitive', or 'insensitive'"
  )
end

return M
```

### 3.2 setup() Entry Point [HIGH]

```lua
-- lua/visual-multi/init.lua
local M = {}

local _cfg = nil   -- set once by setup(), never mutated after

function M.setup(opts)
  if _cfg then
    vim.notify('[visual-multi] setup() called more than once', vim.log.levels.WARN)
    return
  end
  _cfg = require('visual-multi.config').apply(opts)
  require('visual-multi.keymap').register_plugs(_cfg)
  require('visual-multi.highlight').define_groups(_cfg)
  -- Register permanent autocommands (none needed at plugin level for VM)
end

function M.config()
  return _cfg or require('visual-multi.config').defaults
end

return M
```

Key rules:
- `setup()` is idempotent-by-warning: calling it twice warns but does not crash.
- `vim.tbl_deep_extend('force', defaults, opts)` merges nested tables. The `'force'` strategy means user opts win over defaults. Use `'keep'` if you want defaults to win for keys the user didn't set (usually `'force'` is correct).
- `vim.validate` raises errors with useful messages before any state is set.
- Store config in a module-local variable (`_cfg`), not in `vim.g.*`. The module IS the config owner.
- Config must be read-only after `setup()`. Never let individual modules mutate it — pass slices via `M.config()` or dependency-inject the config table.

### 3.3 What NOT To Do [HIGH]

- **Do NOT use `vim.g.VM_xxx` as config in the new plugin.** That is what we are replacing.
- **Do NOT read from `vim.g.*` inside modules** (only the migration shim, if any, would do that — and PROJECT.md says no migration shim).
- **Do NOT use `vim.deepcopy` on defaults unnecessarily** — `vim.tbl_deep_extend` already creates a new table.
- **Do NOT validate in every module** — validate once in `config.apply()`, then trust the config.

---

## 4. Extmarks API for Multi-Cursor Highlighting

### 4.1 Namespace [HIGH]

```lua
-- lua/visual-multi/highlight.lua
local M = {}

-- Single namespace for all VM extmarks in any buffer.
-- Created once; shared across buffers.
M.ns = vim.api.nvim_create_namespace('visual_multi')
```

One namespace for the whole plugin. This enables `nvim_buf_clear_namespace(buf, M.ns, 0, -1)` to atomically remove all VM marks on exit. Do NOT create per-buffer namespaces — there is no benefit and it complicates teardown.

### 4.2 nvim_buf_set_extmark [HIGH]

Full signature (Neovim 0.10 stable):

```lua
local id = vim.api.nvim_buf_set_extmark(
  buf,       -- integer buffer handle
  ns_id,     -- integer namespace
  row,       -- 0-indexed line
  col,       -- 0-indexed byte column
  opts       -- table of options
)
```

Key opts fields for multi-cursor use:

| Field | Type | Purpose |
|---|---|---|
| `id` | integer | Reuse an existing mark ID (update in place) |
| `end_row` | integer | 0-indexed end line (exclusive for ranges) |
| `end_col` | integer | 0-indexed end byte column (exclusive) |
| `hl_group` | string | Highlight group for the mark position |
| `hl_eol` | boolean | Extend highlight to EOL |
| `virt_text` | list of {string,hl} pairs | Inline virtual text |
| `virt_text_pos` | string | `'eol'`, `'overlay'`, `'right_align'`, `'inline'` |
| `priority` | integer | Higher wins when marks overlap (default 4096) |
| `hl_mode` | string | `'replace'` (default), `'combine'`, `'blend'` — controls interaction with other highlights |
| `strict` | boolean | If false, don't error when row/col are out of range (default true) |
| `sign_text` | string | 1-2 chars in the sign column |
| `sign_hl_group` | string | Highlight for sign_text |
| `number_hl_group` | string | Highlight for line number |

### 4.3 Cursor Mark Pattern [HIGH]

For a cursor-mode mark (single character highlight at cursor position):

```lua
local id = vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
  end_row   = row,
  end_col   = col + 1,     -- highlight one character
  hl_group  = 'VMCursor',
  priority  = 200,          -- above treesitter (100), below LSP (300)
  hl_mode   = 'combine',   -- layer over existing syntax highlight
  strict    = false,        -- tolerate marks at EOL on short lines
})
```

For extend-mode (visual selection per cursor):

```lua
local id = vim.api.nvim_buf_set_extmark(buf, ns, start_row, start_col, {
  end_row  = end_row,
  end_col  = end_col,
  hl_group = 'VMExtend',
  priority = 200,
  hl_mode  = 'combine',
  strict   = false,
})
```

### 4.4 Updating vs Recreating Marks [HIGH]

**Prefer updating over recreating.** Store each region's extmark ID and pass `id = existing_id` when calling `nvim_buf_set_extmark`. This is O(log n) per update rather than O(n) for clear-and-recreate.

```lua
-- In region.lua
local Region = {}

function Region.new(buf, row, col)
  local r = { buf = buf, mark_id = nil }
  r.mark_id = vim.api.nvim_buf_set_extmark(buf, highlight.ns, row, col, {
    end_row = row, end_col = col + 1,
    hl_group = 'VMCursor', priority = 200, hl_mode = 'combine', strict = false,
  })
  return r
end

function Region.move(r, row, col)
  -- Update in place by passing the existing id
  vim.api.nvim_buf_set_extmark(r.buf, highlight.ns, row, col, {
    id      = r.mark_id,    -- <-- KEY: reuse the ID
    end_row = row, end_col = col + 1,
    hl_group = 'VMCursor', priority = 200, hl_mode = 'combine', strict = false,
  })
end
```

### 4.5 Reading Back Mark Position [HIGH]

Extmarks move with buffer edits automatically. To recover the current position of a region after edits:

```lua
-- Returns {row, col, details_table}  (0-indexed)
local details = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark_id, { details = true })
local row, col = details[1], details[2]
```

This is the replacement for the VimScript byte-offset synchronization in `autoload/vm/edit.vim`. After any bulk edit, call `get_extmark_by_id` on all live regions to recover their new positions — no manual byte-offset arithmetic needed.

### 4.6 Teardown [HIGH]

```lua
function highlight.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, highlight.ns, 0, -1)
end
```

Call this on session exit. Because we use a single namespace, this removes all VM marks in one call.

### 4.7 Highlight Group Definition [MED]

Define groups in `highlight.define_groups()`, called from `setup()`. Use `vim.api.nvim_set_hl`:

```lua
function M.define_groups(cfg)
  -- Only set if not already defined by user's colorscheme
  -- Use default_override = false so user themes can override
  vim.api.nvim_set_hl(0, 'VMCursor', { default = true, reverse = true })
  vim.api.nvim_set_hl(0, 'VMExtend', { default = true, bg = '#4a4a6a' })
  vim.api.nvim_set_hl(0, 'VMInsert', { default = true, bg = '#2d4a2d' })
end
```

`default = true` means the definition is skipped if the group is already set (e.g., by a colorscheme). Re-apply on `ColorScheme` autocommand:

```lua
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('VMHighlight', { clear = true }),
  callback = function() M.define_groups(cfg) end,
})
```

---

## 5. Keymap Management

### 5.1 Permanent <Plug> Mappings [HIGH]

Register `<Plug>` mappings globally (not buffer-local) in `plugin/visual-multi.lua` or `setup()`. These should exist unconditionally so users can remap them:

```lua
-- plugin/visual-multi.lua (runs at startup)
vim.keymap.set('n', '<Plug>(VM-Find-Under)',     function() require('visual-multi').find_under() end,  { noremap = true })
vim.keymap.set('n', '<Plug>(VM-Add-Cursor-Down)',function() require('visual-multi').add_down() end,   { noremap = true })
vim.keymap.set('n', '<Plug>(VM-Add-Cursor-Up)',  function() require('visual-multi').add_up() end,     { noremap = true })
-- etc.
```

The key insight: the callback uses `require()` lazily. The plugin file itself doesn't load any modules at startup. `<Plug>` mappings are the documented stable API for users who remap keys.

### 5.2 Default User-Facing Mappings [HIGH]

Register concrete key → `<Plug>` mappings in `setup()`, after config is validated:

```lua
function M.register_defaults(cfg)
  if cfg.mappings.basic then
    vim.keymap.set('n', cfg.mappings.find_under, '<Plug>(VM-Find-Under)', { silent = true })
    vim.keymap.set('n', cfg.mappings.add_cursor_down, '<Plug>(VM-Add-Cursor-Down)', { silent = true })
    -- etc.
  end
end
```

The two-layer pattern (`<Plug>` + concrete key) is standard because it lets users remap the concrete key without redefining the action logic.

### 5.3 Session-Local (Buffer-Local) Keymaps [HIGH]

When a VM session starts on a buffer, register buffer-local keymaps for the multi-cursor operations. These must be unregistered on session exit.

```lua
-- In keymap.lua
local M = {}

-- Track session keymaps so we can delete them
local _session_maps = {}   -- buf -> list of {mode, lhs}

function M.enable_session(buf, cfg)
  _session_maps[buf] = {}
  local function map(mode, lhs, rhs)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, noremap = true, silent = true })
    table.insert(_session_maps[buf], { mode, lhs })
  end

  map('n', 'q', function() require('visual-multi.session').exit(buf) end)
  map('n', '<Esc>', function() require('visual-multi.session').exit(buf) end)
  map('n', 'n', function() require('visual-multi.commands').next_region(buf) end)
  -- ... all session-mode keymaps
end

function M.disable_session(buf)
  for _, entry in ipairs(_session_maps[buf] or {}) do
    local ok = pcall(vim.keymap.del, entry[1], entry[2], { buffer = buf })
    -- pcall because buffer may already be deleted
    _ = ok
  end
  _session_maps[buf] = nil
end
```

`vim.keymap.del(mode, lhs, opts)` is the correct API (Neovim 0.7+). Do not use `vim.cmd('unmap')` in Lua plugins.

### 5.4 What NOT To Do [HIGH]

- **Do NOT use `vim.api.nvim_set_keymap`** — use `vim.keymap.set`. The latter handles `<Plug>`, Lua callbacks, and mode normalization correctly.
- **Do NOT set global keymaps from session code** — session keymaps must be buffer-local (`buffer = buf`).
- **Do NOT hardcode keys in session-local maps** — pass them through the config so users can override.

---

## 6. Autocommand Patterns

### 6.1 Augroup Convention [HIGH]

Every plugin should own one or a small number of named augroups. Use `{ clear = true }` so re-sourcing the file does not double-register:

```lua
-- Created once at module level (not inside a function)
local augroup = vim.api.nvim_create_augroup('VisualMulti', { clear = true })
```

Then register all autocmds against this group:

```lua
vim.api.nvim_create_autocmd('BufLeave', {
  group    = augroup,
  callback = function(ev)
    require('visual-multi.session').on_buf_leave(ev.buf)
  end,
})
```

### 6.2 Session Lifecycle Autocmds [HIGH]

VM needs these autocmds during an active session. Use per-session autocmds with an explicit `group` that is cleared when the session ends:

```lua
-- In session.lua
function M.start(buf, cfg)
  local group_name = 'VMSession_' .. buf
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  vim.api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
    group  = group,
    buffer = buf,
    callback = function() M._on_cursor_moved(buf) end,
  })
  vim.api.nvim_create_autocmd({'InsertLeave'}, {
    group  = group,
    buffer = buf,
    callback = function() M._on_insert_leave(buf) end,
  })
  vim.api.nvim_create_autocmd({'BufLeave', 'BufDelete', 'BufUnload'}, {
    group  = group,
    buffer = buf,
    callback = function() M.stop(buf) end,
  })

  -- Store group name for teardown
  _sessions[buf].augroup_name = group_name
end

function M.stop(buf)
  local s = _sessions[buf]
  if not s then return end
  -- Tear down session autocmds atomically
  local ok = pcall(vim.api.nvim_del_augroup_by_name, s.augroup_name)
  _ = ok
  -- ... rest of teardown
  _sessions[buf] = nil
end
```

Key pattern: per-session augroup name is `'VMSession_' .. buf` (buf is a stable integer). `nvim_del_augroup_by_name` removes all autocmds in the group at once.

### 6.3 What NOT To Do [MED]

- **Do NOT use string callbacks** in `nvim_create_autocmd` — Lua function callbacks are type-safe, debuggable, and closures work correctly.
- **Do NOT use `vim.cmd('autocmd ...')`** — the Lua API is more robust and doesn't require string escaping.
- **Do NOT create global autocmds without an augroup** — they accumulate on re-source and are hard to clear.

---

## 7. Test Framework

### 7.1 Recommendation: mini.test [HIGH]

**Use mini.test** (from echasnovski/mini.nvim). This is the correct choice for this project for three reasons:

1. **Already used.** The `001-lua-nvim-rewrite` branch vendored mini.test at `test/vendor/mini.test`. The project already has 94 tests written with it. Switching to busted or plenary would require rewriting the entire test suite.

2. **Headless-native.** mini.test is designed to run under `nvim --headless -u NORC -l test/run_spec.lua`. No external test runner process or pynvim socket needed. This is directly superior to the old Python/pynvim approach for unit tests.

3. **Actively maintained and widely adopted** in the Neovim plugin ecosystem alongside plenary, with a smaller dependency surface (vendorable, no transitive deps).

**Test runner command:**
```bash
nvim --headless -u NORC -l test/run_spec.lua
```

**Spec file structure:**
```lua
-- test/spec/session_spec.lua
local MiniTest = require('test.vendor.mini.test')  -- or standard path
local T = MiniTest.new_set()

T['session starts and stops cleanly'] = function()
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(buf)

  local session = require('visual-multi.session')
  session.start(buf, require('visual-multi.config').defaults)
  MiniTest.expect.no_error(function() session.stop(buf) end)

  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
```

**Assertions available in mini.test:**
- `MiniTest.expect.equality(actual, expected)` — deep equality
- `MiniTest.expect.error(fn, pattern)` — function raises error matching pattern
- `MiniTest.expect.no_error(fn)` — function does not raise
- `MiniTest.expect.truthy(val)`, `MiniTest.expect.falsy(val)`

### 7.2 Do NOT Use Plenary for New Tests [MED]

Plenary.test is popular but has a heavier dependency surface (requires plenary to be installed in the test environment). mini.test is self-contained and vendorable. If we are already on mini.test, stay on it.

**Do NOT use busted** unless the project is packaging for LuaRocks distribution with busted as the runner (which would add CI complexity). mini.test is simpler for Neovim-native tests.

### 7.3 Integration / E2E Tests [MED]

The existing Python/pynvim e2e test harness (`test/test.py`) can be retained for the behavioral integration tests that replay key sequences. These tests are valuable because they catch regressions in the actual multi-cursor edit behavior (byte-for-byte output comparison). The T052 finding confirms they are reliable for parity testing.

**Hybrid approach:**
- mini.test specs: unit tests for individual modules (session, region, highlight, undo grouping, config validation). Fast, headless, no pynvim needed.
- Python/pynvim e2e tests: behavioral integration tests replaying actual keystrokes. Kept for regression coverage of the full user-visible behavior.

---

## 8. Additional API Recommendations

### 8.1 Option Management [HIGH]

Use `vim.bo[buf]` and `vim.wo[win]` (not `vim.o`) for buffer/window-local options. The MEMORY.md already calls this out as a critical bug pattern:

```lua
-- WRONG: vim.bo is only window-local for conceallevel
vim.bo[buf].conceallevel = 0         -- ERROR if conceallevel is window-local

-- CORRECT: use vim.wo for window-local options
vim.wo[win].conceallevel = 0
vim.wo[win].concealcursor = 'nc'

-- CORRECT: use vim.bo for true buffer-local options
vim.bo[buf].undolevels = -1
vim.bo[buf].modifiable = true
```

Window-local options include: `conceallevel`, `concealcursor`, `wrap`, `list`, `cursorline`, `statusline`, `foldcolumn`, `signcolumn`. Always check `:h option-list` for the option's scope.

### 8.2 User Commands [HIGH]

```lua
vim.api.nvim_create_user_command('VMTheme', function(opts)
  require('visual-multi.highlight').set_theme(opts.args)
end, {
  nargs = 1,
  complete = function() return require('visual-multi.highlight').theme_names() end,
  desc = 'Set visual-multi color theme',
})
```

### 8.3 Notify vs print [HIGH]

Use `vim.notify(msg, vim.log.levels.WARN)` instead of `print()` or `vim.cmd('echom ...')`. This integrates with noice.nvim, nvim-notify, and the built-in message system. The existing VimScript plugin had issues with noice.nvim compatibility (see commit `a03b78a`); using `vim.notify` correctly avoids the class of issues caused by raw `echon`/`echo` in operators.

### 8.4 Byte Position Utilities [HIGH]

The Python helper `python/vm.py` handled byte-range operations. In Lua, these are trivially available:

```lua
-- Byte offset of a (1-indexed) line+col position:
local byte = vim.fn.line2byte(lnum) + col - 1

-- Position from byte offset:
local pos = vim.fn.byte2line(byte)    -- returns 1-indexed line
-- (no direct Neovim API for byte→col; use getline + string.len slicing)

-- String byte access (Lua strings are byte arrays):
local line = vim.api.nvim_buf_get_lines(buf, row, row+1, false)[1]
local char = line:sub(col+1, col+1)  -- 1-indexed in Lua strings
local byte_len = #line               -- byte length
```

Extmarks eliminate most of the manual byte-offset arithmetic that vm.py existed to solve (re-centering region positions after edits). The extmark system tracks positions through edits automatically.

### 8.5 vim.schedule and Deferred Execution [MED]

Use `vim.schedule(fn)` when you need to defer execution to the next event loop iteration (e.g., after an insert-mode operation completes and all autocommands have fired):

```lua
vim.api.nvim_create_autocmd('InsertLeave', {
  group = session_group,
  buffer = buf,
  callback = function()
    vim.schedule(function()
      -- Safe to call nvim_buf_set_lines here; insert mode is fully exited
      require('visual-multi.sync').after_insert(buf)
    end)
  end,
})
```

Do not use `vim.defer_fn` (which takes a millisecond delay) for this — `vim.schedule` is the correct zero-delay async deferral.

---

## 9. What NOT To Use

| Avoid | Use Instead | Reason |
|---|---|---|
| `vim.api.nvim_set_keymap` | `vim.keymap.set` | Former doesn't handle `<Plug>`, Lua callbacks, or mode normalization |
| `vim.cmd('autocmd ...')` | `vim.api.nvim_create_autocmd` | String escaping, no Lua callbacks, accumulates on re-source |
| `vim.cmd('highlight ...')` | `vim.api.nvim_set_hl` | Type-safe, no string escaping |
| `vim.g.VM_xxx` for config | `setup()` + module-local `_cfg` | Global pollution, not introspectable |
| `vim.bo[buf]` for window options | `vim.wo[win]` | conceallevel etc. are window-local — wrong scope causes silent failures |
| `print()` for user messages | `vim.notify()` | Integrates with message UI plugins |
| Per-buffer namespaces | Single `nvim_create_namespace` | Unnecessary complexity; one namespace clears all VM marks |
| `vim.cmd('unmap ...')` | `vim.keymap.del` | Type-safe, buffer-local support |
| `nvim_buf_clear_namespace` + recreate all marks | Store IDs, use `id=` param to update | Performance: O(log n) update vs O(n) clear-and-recreate |
| `vim.cmd('echom ...')`, `echon` | `vim.notify` | Compatibility with noice.nvim and modern UIs (see commit a03b78a) |
| `require()` at plugin file top level | Lazy require inside callback/function | Avoids loading heavy modules at Neovim startup |
| busted or plenary test runner | mini.test | Already vendored, no external deps, headless-native |
| scratch buffers `(false, true)` for undo tests | `(false, false)` | Scratch bufs have `undolevels=-1`, undo doesn't work (see MEMORY.md) |

---

## 10. Reference Plugins

These are well-established Neovim Lua plugins whose source code demonstrates the patterns above and are worth reading as architectural references:

| Plugin | Demonstrates |
|---|---|
| `nvim-treesitter/nvim-treesitter` | Module loading, large state management, namespace/extmarks |
| `lewis6991/gitsigns.nvim` | Per-buffer state with session lifecycle, extmarks for line decorations, augroup-per-buffer pattern |
| `echasnovski/mini.nvim` | setup() defaults merging, vim.validate, mini.test itself, clean module boundaries |
| `nvim-telescope/telescope.nvim` | <Plug> mapping pattern, user commands, config deep merge |
| `numToStr/Comment.nvim` | Minimal setup(), buffer-local keymap management, good teardown |

The `gitsigns.nvim` architecture is the closest analog to vim-visual-multi: it manages per-buffer extmark state, handles lifecycle via BufDelete/BufUnload autocmds, and uses a single namespace. Its source is worth reading before designing the session and highlight modules.

---

## 11. Summary Recommendations

| Decision | Recommendation | Confidence |
|---|---|---|
| Minimum Neovim version | 0.10.0 | HIGH |
| Module structure | `lua/visual-multi/*.lua` flat layout | HIGH |
| Config API | `setup(opts)` → `vim.tbl_deep_extend('force', defaults, opts)` → `vim.validate` | HIGH |
| Config storage | Module-local variable, not `vim.g.*` | HIGH |
| Extmarks | Single `nvim_create_namespace('visual_multi')`, store IDs, update with `id=` param | HIGH |
| Keymap API | `vim.keymap.set` + `vim.keymap.del`; `<Plug>` layer for user-remappable actions | HIGH |
| Session keymaps | Buffer-local (`buffer = buf`), cleaned up on exit via `vim.keymap.del` | HIGH |
| Autocmds | `nvim_create_augroup` + `nvim_create_autocmd`; per-session group, cleared on exit | HIGH |
| Test framework | mini.test (vendored); retain Python/pynvim e2e tests for behavioral regression | HIGH |
| Window options | `vim.wo[win]` for conceallevel/concealcursor/statusline; `vim.bo[buf]` for buffer-local | HIGH |
| User messages | `vim.notify(msg, level)` | HIGH |
| Byte operations | Eliminated by extmark position tracking; `vim.fn.line2byte` for edge cases | HIGH |
| Lazy loading | Heavy modules loaded on first session start, not at plugin file load | MED |
| Highlight groups | `nvim_set_hl` with `default = true`; re-apply on `ColorScheme` autocmd | MED |

---

*Research: 2026-02-28. All APIs verified against Neovim 0.10 stable documentation (knowledge cutoff August 2025). No web search was available; recommendations are based on training data up to August 2025 and direct analysis of the project codebase and MEMORY.md findings.*
