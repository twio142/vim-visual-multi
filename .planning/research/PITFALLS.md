# Pitfalls: vim-visual-multi Lua Rewrite

**Written:** 2026-02-28
**Source:** Confirmed bugs from previous Lua port (branch `001-lua-nvim-rewrite`),
static analysis of the VimScript source (`autoload/vm/`), and codebase concerns
audit (`CONCERNS.md`).

---

## Confirmed Bugs (from previous Lua port)

These bugs were discovered and fixed during the earlier `001-lua-nvim-rewrite`
effort. Every one of them is likely to recur in a fresh rewrite unless
explicitly guarded.

---

### BUG-01: Window-local options assigned via `vim.bo`

**Description**
`conceallevel`, `concealcursor`, and `statusline` are window-local options.
Writing them with `vim.bo[buf]` silently fails or affects the wrong scope. The
VimScript source uses `&l:conceallevel` and `&l:concealcursor` (buffer-local
assignment syntax in Vimscript), which in Neovim's Lua API corresponds to
`vim.wo` for the current window, NOT `vim.bo` for the buffer.

**Root cause**
`vim.bo` covers `setlocal` options that are stored per-buffer. Window-local
options are stored per-window (`setlocal` in a given window). Neovim exposes
them separately: `vim.wo` for window-local, `vim.bo` for buffer-local.
`conceallevel` and `concealcursor` are typed `window` in `:help option-list`.
`statusline` is also window-local.

**Fix**
```lua
-- Wrong (silent no-op or runtime error):
vim.bo[buf].conceallevel = 0
vim.bo[buf].concealcursor = ''
vim.bo[buf].statusline = '%!...'

-- Correct (current window):
vim.wo.conceallevel = 0
vim.wo.concealcursor = ''
vim.wo.statusline = '%!...'

-- If you need to target a specific window by handle:
vim.api.nvim_win_set_option(win_id, 'conceallevel', 0)
vim.api.nvim_win_set_option(win_id, 'concealcursor', '')
vim.api.nvim_win_set_option(win_id, 'statusline', '%!...')
```

**Save/restore pattern used by VimScript source**
```vimscript
" vm#variables#init() saves:
let v.conceallevel  = &conceallevel
let v.concealcursor = &concealcursor
let v.statusline    = &statusline

" vm#variables#reset() restores:
let &l:conceallevel  = v.conceallevel
let &l:concealcursor = v.concealcursor
let &l:statusline    = v.statusline   " only if g:VM_set_statusline
```
The Lua equivalent must save `vim.wo.conceallevel` etc. (keyed by `win_id`)
and restore to the same window handle.

**Phase to address:** Option scope save/restore — session start and session
end (wherever `variables.vim` equivalents live).

**Warning signs:** Conceal doesn't toggle off when VM exits; statusline stays
as VM statusline after session ends.

---

### BUG-02: Scratch buffers created with `nvim_create_buf(false, true)` have `undolevels = -1`

**Description**
`nvim_create_buf(false, true)` creates a "scratch" buffer. Neovim sets
`undolevels = -1` on scratch buffers, meaning undo is completely disabled.
Any test that creates a scratch buffer and then checks undo behavior will see
zero undo entries regardless of what edits are made.

**Root cause**
This is documented Neovim behavior: scratch buffers are ephemeral and not
meant to have undo history. The `undolevels = -1` is set automatically.

**Fix**
For tests that exercise undo logic, create a non-scratch buffer:
```lua
-- Wrong (no undo):
local buf = vim.api.nvim_create_buf(false, true)

-- Correct (undo works):
local buf = vim.api.nvim_create_buf(false, false)
-- Then mark it as unlisted/hidden yourself if needed:
vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
```

**Phase to address:** Test infrastructure (Wave 0) and anywhere the
implementation creates temporary buffers for undo grouping tests.

**Warning signs:** `undotree().seq_cur` never advances; `vim.cmd('undo')`
reports "nothing to undo" immediately after edits.

---

### BUG-03: `vim.bo[buf].undolevels` for undo grouping — set per-buffer, not globally

**Description**
The standard undo-grouping trick (set `undolevels` to -1, make a change to
flush, restore `undolevels`) must target the specific buffer being edited, not
the global option. Using `vim.o.undolevels = -1` affects all subsequent
buffers globally and can corrupt undo history in unrelated buffers open at the
same time.

**Root cause**
`undolevels` has both global and buffer-local forms. In Neovim, `vim.o` sets
the global default; `vim.bo[buf].undolevels` (or `nvim_buf_set_option`) sets
per-buffer. The flush trick only works on the buffer you intend.

**The correct undo-grouping pattern**
```lua
-- Flush any partial undo block and start a clean one:
local saved = vim.bo[buf].undolevels
vim.bo[buf].undolevels = -1
-- make a no-op change (required to actually flush):
vim.api.nvim_buf_set_lines(buf, 0, 0, false, {})
vim.bo[buf].undolevels = saved

-- ... now make all your real edits ...

-- After all edits, the whole batch is one undo step
```

**Empty undo block caveat (see BUG-04 below):** The no-op change approach
must be gated on whether `lines_before == lines_after`; otherwise you create
a spurious undo entry.

**Phase to address:** Wherever insert-mode text synchronization across
cursors is implemented (the equivalent of `vm/edit.vim` + `vm/icmds.vim`).

**Warning signs:** Multiple undo steps needed to reverse a single multi-cursor
insert; undo lands on intermediate states between cursor updates.

---

### BUG-04: Empty undo block creates spurious undo entry

**Description**
If you open an undo block, make no net change (lines before == lines after),
and close the block, Neovim still advances `undotree().seq_cur`. This means
the user must press `u` an extra time to get back to the pre-VM state.

**Root cause**
Neovim's undo system records the block open/close as an event even if no
text changed. The VimScript source works around this in the undo grouping
code — the Lua rewrite must replicate this guard.

**Fix**
```lua
local function end_undo_block(buf, lines_before, lines_after)
    if lines_before == lines_after then
        return  -- no change, don't close the undo block
    end
    -- ... close the block normally
end
```

More precisely: capture buffer content (or a hash/tick) before the operation
and after; only finalize the undo group if something changed.

**Phase to address:** Undo block management helpers — written once and used
everywhere that multiple-cursor edits are applied.

**Warning signs:** Pressing `u` after a no-op VM operation (e.g., searching
for a word with no results) reverts real prior edits.

---

### BUG-05: Overloaded function signatures produce duplicate-field warnings

**Description**
Defining two Lua functions with the same name in a table (e.g., `M.fn = ...`
twice, or defining a function for both `fn(session, ...)` and `fn(buf, ...)`)
produces Lua warnings and the second definition silently shadows the first.

**Root cause**
The previous Lua port used a dual API pattern where every module supported
both `fn(session, ...)` and `fn(buf, ...)` call signatures. Implementing
this as two separate definitions of the same table key causes the first to be
overwritten.

**Fix**
Define ONE function with an internal dispatch:
```lua
local function _is_session(arg)
    return type(arg) == 'table' and arg._stopped ~= nil
end

function M.do_thing(session_or_buf, ...)
    local session, buf
    if _is_session(session_or_buf) then
        session = session_or_buf
        buf = session.buf
    else
        buf = session_or_buf
        session = nil
    end
    -- ... use buf and session
end
```

**Phase to address:** Module API design — establish the dispatch convention
in the first module written and apply consistently.

**Warning signs:** Lua linter warnings about duplicate keys; function behaves
as only one of the two intended signatures.

---

## Common VimScript-to-Lua Rewrite Pitfalls

These are patterns observed across the VimScript source that become bugs
when naively transliterated to Lua.

---

### PITFALL-01: `b:VM_Selection` global-per-buffer object → Lua module-local state

**VimScript pattern**
The entire plugin state lives in `b:VM_Selection` — a buffer-local dictionary
that holds all class instances (Global, Funcs, Edit, Insert, etc.). Modules
re-initialize themselves on every call with `let s:V = b:VM_Selection`.

**Why it's a pitfall**
In Lua there is no equivalent of `b:` variables as first-class dictionaries.
A naive port stores session state in a module-level table keyed by `buf`:
```lua
local _sessions = {}  -- keyed by bufnr
```
The pitfall: if you store references to functions or closures inside session
objects that also reference `_sessions`, you get circular references that
prevent garbage collection. More concretely: the session object for buffer N
must be self-contained and not hold a back-reference to the global sessions
table.

**Prevention**
- Keyed by `bufnr` (integer), not buffer handle
- Session objects contain data only; methods live in module scope and receive
  session as first argument
- Use `vim.api.nvim_buf_is_valid(buf)` before accessing any session

---

### PITFALL-02: `noautocmd` suppression does not map to Lua

**VimScript pattern**
The VimScript source has ~43 uses of `noautocmd` and `silent!` across 15
files. These suppress autocommand events during internal state changes (e.g.,
moving the cursor to each secondary cursor position to apply edits).

**Why it's a pitfall**
In Lua, calling `vim.api.nvim_buf_set_lines` does NOT fire `TextChangedI`
by itself — but `vim.cmd('normal! ...')` still fires autocommands. Similarly
`vim.fn.cursor()` fires `CursorMoved`. When the Lua code calls normal-mode
commands to apply edits at each cursor position, it must suppress the same
events the VimScript did.

**Prevention**
```lua
-- For cursor movement that must not fire CursorMoved:
vim.api.nvim_win_set_cursor(0, {line, col})  -- fires CursorMoved
-- vs
vim.cmd('noautocmd call cursor(' .. line .. ',' .. col .. ')')  -- suppressed

-- For text changes during cursor iteration:
-- Prefer nvim_buf_set_lines / nvim_buf_set_text which do NOT fire
-- TextChangedI in headless context, but DO fire in interactive context.
-- Use an autocmd guard flag instead of noautocmd where possible.
```

**Concrete pattern to use**
Set a session flag like `session._in_batch_edit = true` at the start of
multi-cursor text application, clear it at the end. All autocmd handlers check
this flag and early-return:
```lua
autocmd TextChangedI → if session._in_batch_edit then return end
```

---

### PITFALL-03: `s:` script-local variable scope does not exist in Lua

**VimScript pattern**
All class instances (`s:Global`, `s:Insert`, `s:Edit`, etc.) are
script-local variables — shared across all buffer sessions of that module.
`vm#insert#init()` just returns the single `s:Insert` table.

**Why it's a pitfall**
The VimScript design relies on one global singleton per module, re-initialized
per buffer. In Lua, module-level variables ARE shared across all buffers (they
are package-level globals). If you implement sessions as module-level singletons,
operating on two VM buffers simultaneously will corrupt state.

**Prevention**
Every session must be a distinct table allocated at session-start. Modules
must NOT hold mutable per-session state at module level. Only immutable
function definitions and the `_sessions` registry live at module level.

---

### PITFALL-04: Byte offset vs character offset in region tracking

**VimScript pattern**
All region positions are stored as byte offsets (`r.A`, `r.B`) via
`line2byte()` and `byte2line()`. This is VimScript's native coordinate system.

**Why it's a pitfall**
Lua's `nvim_buf_get_text` and `nvim_buf_set_text` use `(row, col)` where
`col` is a byte offset (0-indexed). `vim.fn.line2byte()` is available in Lua
but is 1-indexed and returns -1 for invalid lines. Mixing these systems with
multibyte characters produces silent cursor drift. A character like `é` is 2
bytes; `字` is 3 bytes. If you track positions in characters and apply changes
with byte APIs, positions shift.

**Prevention**
- Establish ONE coordinate system at the module boundary and convert at input/output
- Prefer `(row_0indexed, byte_col_0indexed)` tuples (Neovim API native)
- Do NOT mix `vim.fn.col()` (1-indexed bytes) with `nvim_buf_get_text` (0-indexed)
- For character width: use `vim.fn.strdisplaywidth()` (display columns),
  `vim.fn.strcharlen()` (character count), `vim.fn.strlen()` / `#str` (bytes)
- For every region shift after an edit, use `nvim_buf_get_extmark_by_id` on the
  extmark that tracks the region — let Neovim maintain the position automatically

**The extmark solution**
The primary advantage of the Lua rewrite is extmarks. Store each region's
anchor as an extmark with `right_gravity = false` (tail) and `left_gravity =
true` (head). Neovim adjusts the byte positions automatically as text is
inserted/deleted around them. This eliminates the entire `r.shift()` class of
bugs from the VimScript source.

---

### PITFALL-05: `matchaddpos` highlight → extmarks

**VimScript pattern**
Insert mode cursor highlighting uses `matchaddpos('MultiCursor', ...)` and
`matchdelete()`. Normal mode region highlighting also uses match-based
highlighting in many places.

**Why it's a pitfall**
`matchaddpos` matches are window-local. When cursor position shifts (e.g.,
secondary cursors on the same line during insert), the match must be deleted
and re-added at the new position. In Lua, if you fail to delete stale matches,
ghost highlights accumulate. `vim.fn.matchdelete()` with an invalid match ID
throws an error — use `pcall` or check validity.

**Prevention**
Replace all `matchaddpos` with extmark-based highlights:
```lua
vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
    hl_group = 'MultiCursor',
    end_row = row,
    end_col = col + char_width,
    priority = 100,
})
```
Extmarks update automatically with text changes and are garbage-collected
when the buffer is wiped. No manual delete-and-re-add loop required.

---

### PITFALL-06: `getchar()` blocking in operator-pending handlers

**VimScript pattern**
`vm#cursors#operation()` uses a `while 1` loop calling `getchar()` to read
operator suffixes (e.g., `d2w`, `ci"`, `ys2w(`). This works in VimScript
because it runs in the VimL event loop.

**Why it's a pitfall**
In Lua, calling `vim.fn.getchar()` from within an `nvim_buf_set_keymap`
callback blocks the Neovim event loop. This can cause:
- UI freezes in some Neovim versions
- Interactions with `vim.ui` prompts
- Failure in headless test environments

**Prevention**
Use `vim.on_key` or operator-pending mappings with `<expr>` to capture
operator suffixes incrementally, rather than a blocking read loop.
Alternatively, replicate the VimScript `getchar()` pattern inside
`vim.schedule()` callbacks — but verify this works in your target Neovim
version before committing to it.

---

### PITFALL-07: Silent `pcall` hiding real errors

**VimScript pattern**
`silent!` is used extensively (43 times) to suppress errors during
operations that are expected to sometimes fail (e.g., `silent! nunmap <buffer>
<esc><esc>` when the mapping may not exist).

**Why it's a pitfall**
In Lua the equivalent is `pcall`. Wrapping too much in `pcall` hides real
bugs. The VimScript `silent!` is surgical — it suppresses ONE specific error.
A Lua `pcall(function() ... end)` wraps an entire block and can swallow
unrelated panics.

**Prevention**
- For expected-to-fail operations (e.g., deleting a keymap that may not exist),
  use targeted guards:
  ```lua
  -- Instead of pcall:
  if vim.fn.mapcheck('<Esc>', 'n') ~= '' then
      vim.keymap.del('n', '<Esc>', { buffer = buf })
  end
  ```
- Reserve `pcall` for truly optional operations where the error text is logged
- Never swallow the error silently: `local ok, err = pcall(...); if not ok then
  vim.notify(err, vim.log.levels.WARN) end`

---

### PITFALL-08: Autocommand group lifecycle — orphaned handlers

**VimScript pattern**
`augroup VM_insert` is created at insert-mode start and torn down at
insert-mode end with `autocmd! VM_insert` + `augroup! VM_insert`.

**Why it's a pitfall**
In Lua, `nvim_create_autocmd` returns a numeric ID. If insert mode is exited
abnormally (e.g., `<C-c>` rather than `<Esc>`, or `:stopinsert`, or a crash),
the IDs must still be cleaned up. Failure to clean up means `TextChangedI`
fires for every subsequent keystroke even outside VM, calling stale callbacks
that reference a freed session.

**Prevention**
```lua
-- Store IDs:
session._insert_autocmds = {
    vim.api.nvim_create_autocmd('TextChangedI', {...}),
    vim.api.nvim_create_autocmd('InsertLeave', {...}),
    vim.api.nvim_create_autocmd('InsertCharPre', {...}),
    vim.api.nvim_create_autocmd('CompleteDone', {...}),
}

-- Teardown (call from InsertLeave AND from emergency exit):
local function clear_insert_autocmds(session)
    for _, id in ipairs(session._insert_autocmds or {}) do
        pcall(vim.api.nvim_del_autocmd, id)
    end
    session._insert_autocmds = nil
end
```
Register `clear_insert_autocmds` on the top-level VM exit path so it fires
even when exit is abnormal.

---

### PITFALL-09: `vim.keymap.set` buffer keymaps — del vs set on session end

**VimScript pattern**
`Maps.start()` applies buffer keymaps via `exe` commands (nnoremap `<buffer>`).
`Maps.end()` removes them via `nunmap <buffer>`. Permanent maps are
re-applied after buffer maps are removed.

**Why it's a pitfall in Lua**
`vim.keymap.set('n', key, fn, { buffer = buf })` does NOT replace an
existing buffer keymap atomically. If the user has a pre-existing buffer
keymap for the same key, the previous definition is gone after `vim.keymap.del`.
The VimScript source saves and restores previous maps via `mapcheck()` and
`maparg()`. The Lua rewrite must do the same.

**Prevention**
Before setting any buffer keymap, save the previous definition:
```lua
local prev = vim.fn.maparg(lhs, 'n', false, true)
-- prev is a dict with keys: lhs, rhs, expr, noremap, nowait, silent, ...
-- If prev is non-empty, restore it on session end; otherwise, just delete.
session._saved_maps[lhs] = prev
```
On session end:
```lua
for lhs, prev in pairs(session._saved_maps) do
    if prev and prev.lhs ~= '' then
        vim.fn.mapset('n', false, prev)
    else
        pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
    end
end
```

---

### PITFALL-10: Option save/restore — wrong buffer vs current buffer

**VimScript pattern**
`vm#variables#init()` saves ~20 options at session start.
`vm#variables#reset()` restores them at session end, using `&l:` (local)
assignment for local options.

**Why it's a pitfall**
In Lua, `vim.bo.someopt` reads/writes the CURRENT buffer. If the function
runs while a different buffer is active (e.g., triggered from an autocmd that
fires during a buffer switch), it reads/writes the wrong buffer.

**Prevention**
Always use explicit buffer handle forms:
```lua
-- Unsafe: reads current buffer
local saved_conceallevel = vim.bo.conceallevel

-- Safe: reads specific buffer
local saved_conceallevel = vim.bo[session.buf].conceallevel
```
For window-local options, save by `win_id`:
```lua
local saved_conceallevel = vim.api.nvim_win_get_option(win_id, 'conceallevel')
```

---

### PITFALL-11: `b:visual_multi` guard — reentrancy

**VimScript pattern**
`vm#init_buffer()` checks `exists('b:visual_multi')` to prevent double
initialization. The guard is cleared in `vm#variables#reset_globals()`.

**Why it's a pitfall**
In Lua, if `setup()` is called or a keymap fires while a session is still
being initialized (reentrancy via an autocmd triggered during init), there is
no equivalent guard unless you explicitly implement one. This can result in
two sessions for the same buffer.

**Prevention**
```lua
-- In init path:
if _sessions[buf] then return _sessions[buf] end
_sessions[buf] = { _initializing = true }
-- ... fully initialize ...
_sessions[buf]._initializing = nil
```
Any code that expects a fully-initialized session must check `_initializing`
and bail out or queue the action.

---

### PITFALL-12: `vim.fn.undotree()` and `vim.cmd('silent undo')` target the current buffer

**VimScript pattern**
Undo history inspection (`undotree()`) and manipulation (`undo`, `redo`) are
implicit operations on the current buffer.

**Why it's a pitfall**
In a Lua callback that fires asynchronously (e.g., a scheduled callback), the
current buffer may not be the VM session buffer. `vim.cmd('undo')` will undo
in whatever buffer is currently active.

**Prevention**
Before any undo-related operation, set the current buffer explicitly:
```lua
local prev_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_set_current_buf(session.buf)
vim.cmd('silent undo')
vim.api.nvim_set_current_buf(prev_buf)
```
Or equivalently, use `nvim_buf_call`:
```lua
vim.api.nvim_buf_call(session.buf, function()
    vim.cmd('silent undo')
end)
```

---

### PITFALL-13: `g:Vm` global state → `setup()` config table leaks across instances

**VimScript pattern**
All plugin-wide config lives in `g:Vm` (a global dictionary). This is set
once at startup and mutated throughout the session. `g:Vm.extend_mode`,
`g:Vm.mappings_enabled`, `g:Vm.registers`, etc.

**Why it's a pitfall**
In a Lua `setup(opts)` design, the config table is module-level state. If
`setup()` is called twice (e.g., by two lazy.nvim specs), it overwrites the
previous configuration. More dangerously, mutable runtime state (`extend_mode`,
`mappings_enabled`) that was in `g:Vm` must be per-session state in Lua, NOT
module-level state. Putting them at module level means switching between two
VM sessions corrupts both.

**Prevention**
Separate immutable config (set once by `setup()`) from mutable session state
(allocated per session):
```lua
-- Module level (set once):
local _config = {}
function M.setup(opts) _config = vim.tbl_deep_extend('force', defaults, opts) end

-- Session level (allocated per buffer):
local function new_session(buf)
    return {
        buf = buf,
        extend_mode = false,
        mappings_enabled = false,
        registers = {},
        -- ... etc
    }
end
```

---

### PITFALL-14: `string.len` vs byte length vs character count

**VimScript pattern**
The codebase has a documented FIXME in `vm#icmds#x()`: `strlen()` is used
where `strwidth()` is needed for multibyte. VimScript has `strlen()` (bytes),
`strchars()` (characters), and `strwidth()` (display width). The source mixes
these improperly in several places.

**Why it's a pitfall in Lua**
Lua's `#str` and `string.len(str)` return BYTE counts, not character counts.
When porting VimScript that mixes these (even incorrectly), the Lua port
inherits the same confusion — but now without the VimScript warning that
`strlen()` returns bytes.

**Prevention**
Establish a single helper module with named conversions:
```lua
local M = {}
-- Byte count (= Lua # operator)
function M.byte_len(s) return #s end
-- Character count (Unicode codepoints)
function M.char_len(s) return vim.fn.strcharlen(s) end
-- Display width (handles CJK double-width, tabs)
function M.display_width(s) return vim.fn.strdisplaywidth(s) end
-- Byte length of character at 1-indexed position in string
function M.char_bytes_at(s, char_idx) ... end
```
Never use `#s` directly in position calculations — always name what kind of
length you mean.

---

## Prevention Strategies by Phase

This section maps pitfalls to the phases of a typical rewrite roadmap. The
phases are approximate — adjust phase numbers to match your actual roadmap.

---

### Phase 0 (Foundation, setup, module scaffold)

| Pitfall | Prevention Action |
|---------|-------------------|
| PITFALL-03 (script-local singletons) | Design session object as allocated table; modules hold no mutable state |
| PITFALL-13 (g:Vm config/session mixing) | Define `_config` (immutable) and `new_session()` (mutable) separately from day 1 |
| BUG-05 (duplicate field warnings) | Establish `_is_session()` dispatch convention in first shared utility module |
| PITFALL-14 (byte vs char len) | Write `string_utils.lua` with named length helpers before any position code |

---

### Phase 1 (Session lifecycle — start/stop/exit)

| Pitfall | Prevention Action |
|---------|-------------------|
| BUG-01 (vim.wo vs vim.bo) | Write `options.lua` save/restore with explicit option scope table; mark each option as `window`, `buffer`, or `global` |
| PITFALL-10 (wrong buffer context) | All option reads use `vim.bo[buf]` / `nvim_win_get_option(win_id, ...)` forms |
| PITFALL-11 (reentrancy guard) | Implement `_initializing` flag in session; add assertion in tests |
| PITFALL-09 (keymap save/restore) | Save `vim.fn.maparg(lhs, 'n', false, true)` before applying buffer keymaps |

---

### Phase 2 (Region/extmark system)

| Pitfall | Prevention Action |
|---------|-------------------|
| PITFALL-04 (byte vs char coordinates) | Use extmarks as primary position tracking; store `extmark_id` not raw `{row, col}` |
| PITFALL-05 (matchaddpos → extmarks) | All highlights use `nvim_buf_set_extmark` from the start; no `matchaddpos` |
| BUG-01 (window-local options) | Verify `ns` namespace is buffer-scoped; confirm highlight group names |

---

### Phase 3 (Keymap enable/disable system)

| Pitfall | Prevention Action |
|---------|-------------------|
| PITFALL-09 (keymap lifecycle) | Before `vim.keymap.set`, call `vim.fn.maparg(lhs, mode, false, true)` and cache result |
| PITFALL-07 (silent pcall) | Keymap delete uses guarded form, not bare `pcall` |
| PITFALL-06 (getchar blocking) | Operator-pending handling uses `vim.on_key` or `<expr>` maps instead of `getchar()` loop |

---

### Phase 4 (Insert mode synchronization)

| Pitfall | Prevention Action |
|---------|-------------------|
| PITFALL-02 (noautocmd suppression) | Use `session._in_batch_edit` flag in all TextChangedI handlers |
| PITFALL-08 (orphaned autocmd IDs) | Store all insert-mode autocmd IDs in session; clear on InsertLeave AND on emergency exit |
| BUG-03 (undolevels per buffer) | Undo grouping flush uses `vim.bo[buf].undolevels`, not `vim.o` |
| BUG-04 (empty undo block) | Gate undo block close on content-changed check |
| BUG-02 (scratch buffer undolevels) | Test buffers use `(false, false)` + explicit `buftype = 'nofile'` |
| PITFALL-12 (undo targets current buffer) | Wrap `vim.cmd('undo')` in `vim.api.nvim_buf_call(buf, ...)` |
| PITFALL-14 (byte/char confusion) | All insert-mode column math uses byte offsets consistently; document each variable |

---

### Phase 5 (Normal mode operations — yank, delete, change, paste)

| Pitfall | Prevention Action |
|---------|-------------------|
| PITFALL-04 (coordinate system) | `nvim_buf_get_text` / `nvim_buf_set_text` are byte-based; extmarks auto-update |
| PITFALL-02 (autocommand suppression) | Batch-edit flag covers all `nvim_buf_set_text` calls during region iteration |
| PITFALL-12 (undo targets current buf) | Per-buffer undo grouping uses `nvim_buf_call` |

---

### Phase 6 (Behavioral parity testing)

| Pitfall | Prevention Action |
|---------|-------------------|
| BUG-02 (test buffer undolevels) | Test fixture creates `(false, false)` buffers; add assertion that `undolevels ~= -1` |
| PITFALL-04 (coordinate system) | Tests include multibyte content (CJK, emoji, combining marks) in all position tests |
| PITFALL-08 (orphaned autocmds) | Test that `nvim_get_autocmds({group = 'VM_insert'})` returns empty after VM exit |
| PITFALL-09 (keymap restore) | Test that pre-existing buffer keymaps are restored after VM session ends |
| PITFALL-01 (session state isolation) | Test that opening VM in two buffers simultaneously does not corrupt either session |

**Parity testing pitfall (general)**
The existing Python/pynvim test harness has a documented limitation: `input()`
blocking means 15/18 integration tests falsely fail. These are NOT bugs in the
Lua port — they are test infrastructure failures. When writing new parity
tests, use mini.test (already vendored) for headless Lua tests, and reserve
the pynvim harness only for smoke-testing interactive flows where the
limitation is documented.

---

## Quick Reference: Option Scope Table

Options touched by vim-visual-multi with their correct Lua accessor:

| Option | Scope | Lua accessor |
|--------|-------|-------------|
| `conceallevel` | window | `vim.wo.conceallevel` / `nvim_win_get_option(win, 'conceallevel')` |
| `concealcursor` | window | `vim.wo.concealcursor` / `nvim_win_get_option(win, 'concealcursor')` |
| `statusline` | window | `vim.wo.statusline` / `nvim_win_set_option(win, 'statusline', ...)` |
| `virtualedit` | global+window | `vim.o.virtualedit` (global); `vim.wo.virtualedit` (window-local override) |
| `whichwrap` | global | `vim.o.whichwrap` |
| `hlsearch` | global | `vim.o.hlsearch` |
| `smartcase` | global | `vim.o.smartcase` |
| `ignorecase` | global | `vim.o.ignorecase` |
| `clipboard` | global | `vim.o.clipboard` |
| `lazyredraw` | global | `vim.o.lazyredraw` |
| `cmdheight` | global | `vim.o.cmdheight` |
| `indentkeys` | buffer | `vim.bo[buf].indentkeys` |
| `cinkeys` | buffer | `vim.bo[buf].cinkeys` |
| `synmaxcol` | buffer | `vim.bo[buf].synmaxcol` |
| `textwidth` | buffer | `vim.bo[buf].textwidth` |
| `softtabstop` | buffer | `vim.bo[buf].softtabstop` |
| `undolevels` | global+buffer | `vim.bo[buf].undolevels` (per-session grouping) |
| `foldenable` | window | `vim.wo.foldenable` |

---

## Sources

- VimScript source: `autoload/vm/variables.vim` (option save/restore, lines 1-148)
- VimScript source: `autoload/vm/insert.vim` (insert mode autocommands, lines 540-560; insert tracking, lines 200-280)
- VimScript source: `autoload/vm/icmds.vim` (multibyte FIXME, line 49; backspace logic, lines 22-80)
- VimScript source: `autoload/vm/maps.vim` (keymap enable/disable/save, lines 44-135)
- VimScript source: `autoload/vm/region.vim` (shift() multibyte TODO, lines 177-192)
- VimScript source: `autoload/vm/comp.vim` (plugin compat disable/enable pattern)
- `.planning/codebase/CONCERNS.md` (fragile areas, known bugs, tech debt)
- `.planning/PROJECT.md` (requirements, constraints, key decisions)
- Memory: `001-lua-nvim-rewrite` confirmed bugs (BUG-01 through BUG-05)
- Confidence: HIGH for BUG-01 through BUG-05 (confirmed in prior Lua port)
- Confidence: HIGH for PITFALL-01 through PITFALL-08 (directly traceable to
  VimScript source patterns)
- Confidence: MEDIUM for PITFALL-09 through PITFALL-14 (inferred from source
  analysis; verify when implementing)
