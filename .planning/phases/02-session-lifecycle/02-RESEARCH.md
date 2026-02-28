# Phase 2: Session Lifecycle - Research

**Researched:** 2026-02-28
**Domain:** Neovim Lua plugin session lifecycle — start/stop, option save/restore, keymap management, reentrancy guard, User autocmds
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Keymap conflict policy**
- **Save-and-restore**: On session start, capture any existing buffer-local keymap on each VM key before installing VM's binding. On session exit, restore the original mapping (or remove VM's if there was none).
- **Buffer-local only**: All VM session keymaps use `vim.keymap.set(..., { buffer = bufnr })`. No global keymaps during sessions.
- Leader prefix is preserved and sourced from the `mappings` key in `setup(opts)` config (see Phase 1 config.lua). Keymap installation reads config — no hardcoded leader in session.lua.

**Mode model**
- **Single mode per session**: Mode is `session.extend_mode` (boolean), matching the original `g:Vm.extend_mode`. All cursors share the same mode.
- **Initial mode depends on trigger**: The session start function accepts an `initial_mode` argument.
  - `<C-n>` / word-search entry → `extend_mode = true`
  - `<C-Up>` / `<C-Down>` / line-cursor entry → `extend_mode = false`
- **Mode resets on toggle**: Pressing `v` calls `session.toggle_mode()` — flips `extend_mode`, resets each cursor's selection to its current position. No per-cursor selection memory across mode switches.
- **No insert-mode enum in Phase 2**: Insert mode is handled separately in Phase 5 via its own autocommands. Phase 2 only tracks `extend_mode` (boolean).

**Session lifecycle hooks**
- **VMEnter / VMLeave** User autocmds emitted on session start/stop with a data payload:
  ```lua
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'VMEnter',
    data = { bufnr = session.buf, extend_mode = session.extend_mode }
  })
  ```
- **Just VMEnter/VMLeave for now**: Finer-grained events (cursor count change, mode change, etc.) are added in later phases as features are built.
- **Per-session augroup**: Each session creates a unique augroup (`VM_buf_{bufnr}`) on start and deletes it with `nvim_del_augroup_by_name` on exit. Zero risk of stale autocmds from prior sessions.

**Option/state save-restore scope**
- **Hardcoded whitelist** (not user-configurable): The session snapshots and restores these options:
  - `virtualedit` (global) → set to `'onemore'` during session
  - `conceallevel` (window-local, use `vim.wo`) → set to `0` during session
  - `guicursor` (global) → modified in extend mode for visual feedback; restored on exit
- **`eventignore` is NOT a session-level option**: Setting `eventignore=all` is a per-operation concern (Phase 4, during edit loops), not a session-wide setting.
- Research should confirm the complete list — there may be additional options (e.g., `scrollbind`, `cursorbind`, `lazyredraw`) the original plugin modifies.

### Claude's Discretion
- Exact structure of the session table fields (beyond `buf`, `extend_mode`, `_stopped`, `cursors`)
- Whether `session.start()` and `session.stop()` are module-level functions or method-style calls
- How the save/restore snapshot is stored (flat fields on session vs nested `_saved_opts` table)
- Exact augroup naming scheme

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CFG-01 | `setup(opts)` is the sole config entry point — no g:VM_xxx support | Phase 1 config.lua already implements setup(opts); session.lua reads from `require('visual-multi.config').get()` — no g:VM_xxx read or write anywhere in Phase 2 |
| FEAT-03 | Cursor mode and extend mode with switching between them (v key) | session.extend_mode boolean field matches g:Vm.extend_mode semantics; toggle_mode() flips it; global.vim change_mode() pattern confirmed as the authoritative reference; v keymap installed during session start |
</phase_requirements>

---

## Summary

Phase 2 builds `session.lua` — the Tier-2 module that owns the complete lifecycle of a per-buffer multi-cursor session. This module is the bridge between the Phase 1 foundation (config, util, highlight, region, undo) and all higher-tier feature code. It has no novel algorithmic complexity — the design is fully specified by the locked decisions in CONTEXT.md and the authoritative VimScript source in `autoload/vm/variables.vim` and `autoload/vm/global.vim`.

The research surface is unusually clean: the complete list of options to save/restore is readable directly from `vm#variables#init()` and `vm#variables#reset()`, and the mode-switching pattern is directly readable from `s:Global.change_mode()`. The key translation work is mapping VimScript's `&l:conceallevel` (buffer-local assignment in VimScript, but window-local in Neovim) to the correct Lua accessor (`vim.wo` not `vim.bo`), which is BUG-01 from Phase 1 research — already confirmed and documented.

The three hardest implementation concerns in Phase 2 are: (1) correct option-scope classification for each saved/restored option, (2) the save-and-restore keymap pattern using `vim.fn.maparg()` + `vim.fn.mapset()`, and (3) the reentrancy guard preventing double-initialization. All three are well-documented in the project's existing PITFALLS.md with exact Lua code patterns.

**Primary recommendation:** Write `session.lua` as a module with `M.start(buf, initial_mode)` and `M.stop(buf)` functions. Store the session in `_sessions[buf]` in `init.lua` (already the Phase 1 registry). Use a nested `_saved` table on the session for all saved state (opts, keymaps, cursor position). Mirror the `vm#variables#init()` / `vm#variables#reset()` structure directly.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Neovim built-in API | 0.10+ | `vim.api.nvim_create_augroup`, `nvim_del_augroup_by_name`, `nvim_exec_autocmds`, `vim.keymap.set`, `vim.fn.maparg`, `vim.fn.mapset` | No external dep; all APIs stable on 0.10 |
| `config.lua` (Phase 1) | — | Read-only config access via `config.get()` | Already built; session reads mappings table from here |
| `util.lua` (Phase 1) | — | `is_session()` dispatch helper | Already built |
| `highlight.lua` (Phase 1) | — | `highlight.clear(session)` on session stop | Already built; clear all extmarks atomically |
| `region.lua` (Phase 1) | — | Store cursor objects in `session.cursors` | Already built |
| `undo.lua` (Phase 1) | — | `undo.begin_block` / `end_block` on operations | Already built |
| mini.test | vendored | Unit test framework for session_spec.lua | Already vendored at `test/vendor/mini.test` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `vim.fn.maparg(lhs, mode, false, true)` | built-in | Capture existing buffer keymap before overwriting | Called in `_save_keymap()` for every VM key at session start |
| `vim.fn.mapset(mode, false, dict)` | built-in | Restore a previously captured keymap dict | Called in `_restore_keymaps()` at session stop |
| `vim.api.nvim_exec_autocmds` | built-in | Fire VMEnter/VMLeave User autocmds | Session start and stop |
| `vim.api.nvim_win_get_option` | built-in | Read window-local option by win_id | Saving conceallevel, guicursor |
| `vim.api.nvim_win_set_option` | built-in | Write window-local option by win_id | Restoring conceallevel |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `vim.fn.maparg` + `vim.fn.mapset` | Manual keymap recreation | `mapset` restores the full dict atomically including noremap, nowait, expr flags — rebuilding manually misses edge cases |
| `nvim_del_augroup_by_name` | `nvim_del_augroup_by_id` | Both work; by-name is more debuggable; augroup name `VM_buf_{bufnr}` is unique per session |
| Nested `_saved` table | Flat `session._saved_virtualedit`, etc. | Nested `_saved = { opts={}, keymaps={} }` is cleaner and avoids polluting the session namespace |

---

## Architecture Patterns

### Recommended Project Structure

```
lua/
  visual-multi/
    init.lua          -- (Phase 1) Public entry: setup(), get_state(), _sessions
    session.lua       -- (Phase 2) NEW: start/stop, option save/restore, keymap save/restore
    config.lua        -- (Phase 1) Config module
    util.lua          -- (Phase 1) Helpers
    highlight.lua     -- (Phase 1) Extmark namespace and draw/clear
    region.lua        -- (Phase 1) Region objects
    undo.lua          -- (Phase 1) Undo block management
test/
  spec/
    session_spec.lua  -- (Phase 2 Wave 0) New spec file
```

### Pattern 1: Session Table Shape

**What:** The session table is the central data object. All Phase 2 code reads/writes it. Fields are set at start and cleared at stop.

**When to use:** Created in `session.start(buf, initial_mode)` and registered in `init._sessions[buf]`.

```lua
-- Source: CONTEXT.md locked decisions + ARCHITECTURE.md §2 + variables.vim
local function _new_session(buf, initial_mode)
  local win = vim.api.nvim_get_current_win()
  return {
    -- Identity
    buf         = buf,           -- immutable after creation
    win         = win,           -- window at session start (for win-local opt restore)
    _stopped    = false,         -- sentinel: is_session() checks this field

    -- Mode state (FEAT-03)
    extend_mode = initial_mode,  -- boolean; matches g:Vm.extend_mode semantics

    -- Cursor list (populated by Phase 3+)
    cursors     = {},

    -- Saved state for restoration
    _saved = {
      opts    = {},   -- { virtualedit=..., conceallevel=..., guicursor=... }
      keymaps = {},   -- { [lhs] = maparg_dict_or_false }
    },

    -- Augroup handle (deleted on stop)
    _augroup_name = 'VM_buf_' .. buf,

    -- Undo state (used by Phase 4+)
    _undo_seq_before   = nil,
    _undo_lines_before = nil,
    _undo_seq_after    = nil,
  }
end
```

### Pattern 2: Session Start — Full Initialization Sequence

**What:** `session.start()` performs six actions in order. This mirrors `vm#variables#init()` + `vm#maps#init()` in VimScript.

**When to use:** Called from the entry-point keymaps (Phase 6). For Phase 2 testing, called directly.

```lua
-- Source: CONTEXT.md decisions + variables.vim vm#variables#init() + PITFALLS.md PITFALL-11
local M = {}
local config = require('visual-multi.config')

function M.start(buf, initial_mode)
  buf = buf or vim.api.nvim_get_current_buf()
  local sessions = require('visual-multi')._sessions

  -- PITFALL-11: Reentrancy guard — do not double-initialize
  if sessions[buf] then return sessions[buf] end

  local session = _new_session(buf, initial_mode or false)
  sessions[buf] = session

  -- Step 1: Save and set options (CONTEXT.md whitelist: virtualedit, conceallevel, guicursor)
  _save_and_set_options(session)

  -- Step 2: Save and install keymaps (PITFALL-09: save-and-restore, not just del)
  _save_and_install_keymaps(session)

  -- Step 3: Create per-session augroup with BufDelete guard
  _create_augroup(session)

  -- Step 4: Emit VMEnter User autocmd (CONTEXT.md hook decision)
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'VMEnter',
    data    = { bufnr = session.buf, extend_mode = session.extend_mode },
  })

  return session
end
```

### Pattern 3: Option Save and Restore (BUG-01 + PITFALL-10 Prevention)

**What:** Save each option with the correct scope accessor. Set session values. Restore on stop.

**When to use:** `_save_and_set_options(session)` at start; `_restore_options(session)` at stop.

```lua
-- Source: variables.vim vm#variables#init() + vm#variables#reset() + PITFALLS.md BUG-01 + PITFALL-10
-- CRITICAL: conceallevel is window-local (vim.wo), NOT buffer-local (vim.bo)
--           virtualedit is global (vim.o)
--           guicursor is global (vim.o)

local function _save_and_set_options(session)
  local win = session.win
  local saved = session._saved.opts

  -- virtualedit: global scope
  saved.virtualedit = vim.o.virtualedit
  vim.o.virtualedit = 'onemore'

  -- conceallevel: window-local (BUG-01: use nvim_win_get_option, NOT vim.bo[buf])
  saved.conceallevel = vim.api.nvim_win_get_option(win, 'conceallevel')
  vim.api.nvim_win_set_option(win, 'conceallevel', 0)

  -- guicursor: global scope; only modified in extend mode
  saved.guicursor = vim.o.guicursor
  if session.extend_mode then
    -- modify guicursor to show block cursor for visual feedback
    -- (exact modification TBD based on guicursor format; restore unconditionally on stop)
  end
end

local function _restore_options(session)
  local win = session.win
  local saved = session._saved.opts

  -- Guard: window may have been closed (e.g., BufDelete fired)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_option(win, 'conceallevel', saved.conceallevel)
  end
  vim.o.virtualedit = saved.virtualedit
  vim.o.guicursor   = saved.guicursor
end
```

### Pattern 4: Keymap Save and Restore (PITFALL-09)

**What:** Before installing any VM buffer keymap, capture the existing definition with `vim.fn.maparg(lhs, mode, false, true)`. On stop, restore with `vim.fn.mapset()` or delete if none existed.

**When to use:** `_save_and_install_keymaps(session)` at start; `_restore_keymaps(session)` at stop.

```lua
-- Source: PITFALLS.md PITFALL-09 + maps.vim save pattern
-- maparg returns {} (empty table) if no mapping exists for that lhs.
-- maparg with fourth arg = true returns a dict with all keymap attributes.

local function _set_vm_keymap(session, mode, lhs, rhs_fn, opts)
  -- Save previous mapping before overwriting (PITFALL-09)
  local prev = vim.fn.maparg(lhs, mode, false, true)
  -- prev is {} if no prior map; prev.lhs is set if prior map exists
  session._saved.keymaps[lhs] = (prev.lhs ~= nil) and prev or false

  vim.keymap.set(mode, lhs, rhs_fn, vim.tbl_extend('force', {
    buffer = session.buf,
    nowait = true,
    silent = true,
  }, opts or {}))
end

local function _restore_keymaps(session)
  local buf = session.buf
  for lhs, prev in pairs(session._saved.keymaps) do
    if prev then
      -- Restore original mapping
      vim.fn.mapset('n', false, prev)
    else
      -- No prior map existed — just delete VM's binding
      pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
    end
  end
  session._saved.keymaps = {}
end
```

### Pattern 5: Per-Session Augroup (PITFALL-08 Prevention)

**What:** Create `VM_buf_{bufnr}` augroup on session start. Register `BufDelete` guard so session cleans up even if the buffer is force-closed. Delete augroup on session stop.

**When to use:** Part of `session.start()`. Deletion is the first thing `session.stop()` does.

```lua
-- Source: CONTEXT.md augroup decision + PITFALLS.md PITFALL-08 + ARCHITECTURE.md §3
local function _create_augroup(session)
  local name = session._augroup_name  -- 'VM_buf_{bufnr}'
  vim.api.nvim_create_augroup(name, { clear = true })

  -- Emergency teardown: BufDelete fires even on :bdelete!
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer   = session.buf,
    group    = name,
    once     = true,
    callback = function()
      -- Silent stop: buffer is gone, skip option/keymap restore
      M.stop(session.buf, { silent = true })
    end,
  })
end
```

### Pattern 6: Session Stop — Full Teardown Sequence

**What:** `session.stop()` is the mirror of `session.start()`. Order matters: keymaps first (so user can still navigate), then options, then augroup, then VMLeave.

**When to use:** Called from Esc keymap (Phase 6), BufDelete autocmd, or directly in tests.

```lua
-- Source: CONTEXT.md decisions + variables.vim vm#variables#reset()
function M.stop(buf, opts)
  opts = opts or {}
  local sessions = require('visual-multi')._sessions
  local session  = sessions[buf]
  if not session then return end

  session._stopped = true

  -- Step 1: Restore keymaps (before options — user navigation unblocked first)
  if not opts.silent then
    _restore_keymaps(session)
  end

  -- Step 2: Restore options
  if not opts.silent then
    _restore_options(session)
  end

  -- Step 3: Clear all extmarks (highlight.clear accepts session)
  require('visual-multi.highlight').clear(session)

  -- Step 4: Delete augroup (also deletes BufDelete autocmd)
  pcall(vim.api.nvim_del_augroup_by_name, session._augroup_name)

  -- Step 5: Remove session from registry
  sessions[buf] = nil

  -- Step 6: Emit VMLeave User autocmd
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'VMLeave',
    data    = { bufnr = buf },
  })
end
```

### Pattern 7: Mode Toggle (FEAT-03)

**What:** `session.toggle_mode(session)` flips `extend_mode`. This mirrors `s:Global.change_mode()` in `autoload/vm/global.vim`. In Phase 2 (no cursors yet), just flip the boolean and update guicursor.

**When to use:** Called from the `v` buffer keymap installed at session start.

```lua
-- Source: global.vim s:Global.change_mode() + s:Global.cursor_mode() / extend_mode()
-- Phase 2 simplified version (cursor collapse/expand deferred to Phase 3 when regions exist)
function M.toggle_mode(session)
  session.extend_mode = not session.extend_mode

  -- Update guicursor for visual feedback (mirror what global.vim does)
  -- Full cursor collapse/expand handled in Phase 3 when region.lua is integrated
end

-- Convenience: set mode unconditionally (mirrors cursor_mode() / extend_mode())
function M.set_mode(session, extend)
  session.extend_mode = extend
end
```

### Anti-Patterns to Avoid

- **`vim.bo[buf].conceallevel = 0`:** Silent wrong-scope write. `conceallevel` is window-local. Always use `vim.api.nvim_win_set_option(win_id, 'conceallevel', 0)` or `vim.wo.conceallevel` (BUG-01).
- **`vim.o.conceallevel`:** Does not exist — `conceallevel` has no global scope. Setting `vim.o` would silently fail or error.
- **`vim.keymap.del` without prior save:** Destroys user keymaps permanently. Always `maparg` before `keymap.set` (PITFALL-09).
- **Module-level mutable session state:** Session fields like `extend_mode` must live on the per-session table, NOT as module-level variables. Two simultaneous VM buffers would corrupt each other (PITFALL-13).
- **`vim.api.nvim_del_augroup_by_name` without pcall:** If the augroup was already deleted (BufDelete fired and stop() was called from there), a second stop() call would error. Wrap in pcall.
- **Firing VMEnter before full initialization:** VMEnter must fire AFTER options are set, keymaps installed, and augroup created — external listeners may call `get_state()` immediately.
- **Not restoring guicursor in cursor mode:** The CONTEXT.md says guicursor is only modified in extend mode, but it must be saved unconditionally and restored unconditionally — mode may change during session.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Capture existing keymap | Manual string parsing of `:nmap <buffer>` output | `vim.fn.maparg(lhs, mode, false, true)` | Returns a complete dict with all attributes (noremap, nowait, expr, silent, callback); string parsing would miss Lua callbacks |
| Restore a keymap | Reconstruct `vim.keymap.set` call from saved fields | `vim.fn.mapset(mode, false, dict)` | Atomic; handles all edge cases including `<expr>` maps, Lua callbacks, `<script>` scope |
| Delete augroup safely | Manual autocmd ID tracking | `nvim_del_augroup_by_name(name)` or `nvim_del_augroup_by_id(id)` | Deletes ALL autocmds in the group atomically; no ID bookkeeping |
| Fire User autocmds | `vim.cmd('doautocmd User VMEnter')` | `vim.api.nvim_exec_autocmds('User', { pattern='VMEnter', data={...} })` | `data=` table is Neovim-native; `doautocmd` string form cannot pass structured data |
| Option scope lookup | Trial-and-error | Use the Option Scope Quick Reference table from Phase 1 RESEARCH.md | Options are typed window/buffer/global in the Neovim source; wrong scope = silent misbehavior |

**Key insight:** `vim.fn.maparg` + `vim.fn.mapset` is the idiomatic Neovim keymap save/restore pair. The VimScript plugin uses `mapcheck` + `maparg` + string `exe` reconstruction — the Lua versions are strictly cleaner.

---

## Common Pitfalls

### Pitfall 1: Window-Local Option via vim.bo (BUG-01 — most likely regression)

**What goes wrong:** `vim.bo[buf].conceallevel = 0` is a silent no-op (or in some Neovim versions, an error). Conceallevel is not changed. On session exit, restoring `vim.bo[buf].conceallevel` also has no effect. The user's buffer keeps whatever conceallevel was set before.

**Why it happens:** `conceallevel` is `window`-scoped in `:help option-list`. It is accessible via `vim.wo` (current window) or `nvim_win_get_option(win_id, ...)`. There is no per-buffer conceallevel.

**How to avoid:** Before setting any option in session.lua, check the Option Scope Quick Reference. Save with `nvim_win_get_option(win_id, 'conceallevel')`, restore with `nvim_win_set_option(win_id, 'conceallevel', saved_val)`.

**Warning signs:** Markdown concealment doesn't toggle off when VM is active; or stays off after VM exits.

### Pitfall 2: Missing Reentrancy Guard (PITFALL-11)

**What goes wrong:** An autocmd fires during session initialization (e.g., `VMEnter` listener calls `get_state()` which triggers another `start()` call). Two session tables exist for the same buffer. Options are saved twice (and the second save captures the already-modified value). On exit, the wrong values are restored.

**Why it happens:** No guard prevents `start()` from being called while `start()` is already running.

**How to avoid:** First line of `start()`: `if sessions[buf] then return sessions[buf] end`. Register the session in `sessions[buf]` BEFORE calling `_save_and_set_options` or `_create_augroup`.

**Warning signs:** After `<Esc>`, `conceallevel` or `virtualedit` has the wrong value.

### Pitfall 3: Keymap Restoration Destroys User Maps (PITFALL-09)

**What goes wrong:** `vim.keymap.del('n', '<Esc>', { buffer = buf })` on session exit. If the user had a buffer-local `<Esc>` binding (e.g., from a LSP plugin or a filetype plugin), it is permanently deleted rather than restored.

**Why it happens:** `keymap.del` does not know about the prior binding. It just removes whatever is currently there.

**How to avoid:** Before every `keymap.set`, call `vim.fn.maparg(lhs, 'n', false, true)`. If the result has a non-empty `.lhs` field, the user had a prior binding — save the full dict. On stop, call `vim.fn.mapset('n', false, saved_dict)` to restore it.

**Warning signs:** After VM exits, LSP code-action shortcut stops working in that buffer.

### Pitfall 4: Augroup Name Collision Between Sessions (PITFALL-08 variation)

**What goes wrong:** If `nvim_create_augroup('VM_buf_42', { clear = false })` is called when a stale augroup already exists (e.g., a crashed prior session that didn't clean up), the old autocmds accumulate. Two BufDelete handlers fire on next delete. Two VMLeave events fire.

**Why it happens:** `clear = false` does not delete existing autocmds in the group.

**How to avoid:** Always use `{ clear = true }` in `nvim_create_augroup`. This deletes any stale group of the same name atomically.

**Warning signs:** VMLeave fires twice; `nvim_get_autocmds({group='VM_buf_42'})` shows duplicate entries.

### Pitfall 5: `nvim_exec_autocmds` data Table Not Supported in Older Neovim

**What goes wrong:** `vim.api.nvim_exec_autocmds('User', { pattern='VMEnter', data={...} })` — the `data` field is not available in Neovim < 0.8.

**Why it happens:** `data` was added to `nvim_exec_autocmds` in Neovim 0.8. We target 0.10+, so this is fine.

**How to avoid:** No action needed — 0.10 is the minimum. Document the constraint.

**Warning signs:** None at 0.10+. If backporting ever occurs, `data` must be removed.

### Pitfall 6: Stopping a Session Twice (BufDelete + Manual Stop Race)

**What goes wrong:** User presses `<Esc>` while BufDelete is also firing (e.g., `:bdelete` from a keymap). `session.stop()` is called twice. Second call finds `sessions[buf] = nil` and returns early — correct. But if the early return is after `_restore_keymaps` already ran, second call might try to `nvim_del_augroup_by_name` an already-deleted group, raising an error.

**Why it happens:** `sessions[buf] = nil` is set mid-sequence in stop(), not at the top.

**How to avoid:** Set `sessions[buf] = nil` as the FIRST mutation in `stop()`, before any cleanup. Then all subsequent calls to `stop()` see nil and return immediately. Order: (1) check nil, (2) set `session._stopped = true`, (3) remove from registry, (4) cleanup.

**Warning signs:** Error `"invalid augroup name"` appearing in edge-case tests.

### Pitfall 7: Guicursor Option Format

**What goes wrong:** Attempting to modify `guicursor` by concatenating strings produces malformed option values and a Neovim error or unexpected cursor shapes.

**Why it happens:** `guicursor` is a comma-separated list of `mode:block-shape` entries with complex format. Partial modification is fragile.

**How to avoid:** Save the entire `vim.o.guicursor` string at session start. On stop, restore it unconditionally. For Phase 2, only save/restore guicursor; the actual modification for extend-mode visual feedback is a LOW priority and can be deferred to Phase 3 (when rendering is built). If modification is needed, replace the entire string with the known-good extend-mode value.

**Warning signs:** Cursor shape stays wrong after VM exit; Neovim error about invalid guicursor format.

---

## Complete Option Save/Restore Inventory

This is the authoritative list derived from `vm#variables#init()` and `vm#variables#reset()` in `autoload/vm/variables.vim`.

### Phase 2 Whitelist (locked in CONTEXT.md)

| Option | Scope | Save Accessor | Restore Accessor | Set To |
|--------|-------|--------------|-----------------|--------|
| `virtualedit` | global | `vim.o.virtualedit` | `vim.o.virtualedit = saved` | `'onemore'` |
| `conceallevel` | window | `nvim_win_get_option(win, 'conceallevel')` | `nvim_win_set_option(win, 'conceallevel', saved)` | `0` |
| `guicursor` | global | `vim.o.guicursor` | `vim.o.guicursor = saved` | (extend mode only; see CONTEXT.md) |

### Full VimScript List (all options vm#variables#init() saves — for later phases)

These are documented here so future phases can reference the complete picture. Not all are Phase 2 scope.

| Option | Scope | Phase | VimScript var name |
|--------|-------|-------|--------------------|
| `hlsearch` | global | Phase 4+ | `v.oldhls` |
| `virtualedit` | global | Phase 2 | `v.oldvirtual` |
| `whichwrap` | global | Phase 4+ | `v.oldwhichwrap` |
| `lazyredraw` | global | Phase 4+ | `v.oldlz` |
| `cmdheight` | global | Phase 7 | `v.oldch` |
| `smartcase` | global | Phase 6 | `v.oldcase[0]` |
| `ignorecase` | global | Phase 6 | `v.oldcase[1]` |
| `clipboard` | global | Phase 5 | `v.clipboard` |
| `indentkeys` | buffer | Phase 5 | `v.indentkeys` |
| `cinkeys` | buffer | Phase 5 | `v.cinkeys` |
| `synmaxcol` | buffer | Phase 4 | `v.synmaxcol` |
| `textwidth` | buffer | Phase 4 | `v.textwidth` |
| `softtabstop` | buffer | Phase 5 | `v.softtabstop` |
| `conceallevel` | window | Phase 2 | `v.conceallevel` |
| `concealcursor` | window | Phase 4 | `v.concealcursor` |
| `statusline` | window | Phase 7 | `v.statusline` |
| `foldenable` | window | Phase 3 | (implicit — vm#variables#set disables folding) |
| register `"` | N/A | Phase 5 | `v.oldreg`, `v.def_reg` |
| `/` register | N/A | Phase 6 | `v.oldsearch` |
| matches | N/A | Phase 3 | `v.oldmatches` |
| visual marks `<`, `>` | N/A | Phase 6 | `v.vmarks` |

---

## Code Examples

Verified patterns from official sources:

### Keymap Save with maparg (PITFALL-09 prevention)

```lua
-- Source: PITFALLS.md PITFALL-09 + Neovim :help vim.fn.maparg()
-- maparg(lhs, mode, false, true) returns a dict when the 4th arg is true.
-- Returns {} (empty table) if no mapping exists.
-- The returned dict contains: lhs, rhs, expr, noremap, nowait, silent, script,
--   callback (for Lua maps), buffer, mode, sid, lnum, abbr

local function _save_keymap(buf, mode, lhs)
  -- Buffer-local check: pass buf option would filter to buf, but maparg only
  -- checks current buffer local maps. We must be in the right buffer context.
  local prev = vim.fn.maparg(lhs, mode, false, true)
  -- prev.lhs is set only if a mapping was found
  if prev.lhs ~= nil and prev.lhs ~= '' then
    return prev   -- save the full dict
  end
  return false    -- sentinel: no prior map existed
end

-- Restore:
local function _restore_keymap(buf, mode, lhs, saved)
  if saved then
    vim.fn.mapset(mode, false, saved)
  else
    pcall(vim.keymap.del, mode, lhs, { buffer = buf })
  end
end
```

### Per-Session Augroup with BufDelete Guard

```lua
-- Source: CONTEXT.md decisions + ARCHITECTURE.md §3 + PITFALLS.md PITFALL-08
local function _create_session_augroup(session)
  -- { clear = true }: deletes any stale augroup of same name (prevents accumulation)
  vim.api.nvim_create_augroup(session._augroup_name, { clear = true })

  vim.api.nvim_create_autocmd('BufDelete', {
    buffer   = session.buf,
    group    = session._augroup_name,
    once     = true,  -- fire at most once; auto-deletes itself
    callback = function()
      -- Buffer gone: skip keymap/option restore, just clean registry
      require('visual-multi.session').stop(session.buf, { silent = true })
    end,
  })
end
```

### VMEnter / VMLeave User Autocmd with data Payload

```lua
-- Source: CONTEXT.md locked decisions
-- nvim_exec_autocmds data= field available since Neovim 0.8 (we target 0.10+)
vim.api.nvim_exec_autocmds('User', {
  pattern = 'VMEnter',
  data    = { bufnr = session.buf, extend_mode = session.extend_mode },
})

-- Listener pattern (for external plugins):
vim.api.nvim_create_autocmd('User', {
  pattern  = 'VMEnter',
  callback = function(ev)
    local bufnr      = ev.data.bufnr
    local extend     = ev.data.extend_mode
    -- ...
  end,
})
```

### Mode Toggle (FEAT-03) — global.vim change_mode() in Lua

```lua
-- Source: autoload/vm/global.vim s:Global.change_mode()
-- Phase 2 simplified: no regions to collapse/expand yet (that's Phase 3)
function M.toggle_mode(session)
  -- Mirror change_mode() semantics:
  -- cursor mode → extend mode: no pre-action needed
  -- extend mode → cursor mode: in Phase 3 this calls merge_cursors()
  session.extend_mode = not session.extend_mode
  -- Cursor shape update deferred to Phase 3 (highlight integration)
end

-- Idempotent set helpers (mirrors cursor_mode() / extend_mode()):
function M.set_cursor_mode(session)
  if session.extend_mode then M.toggle_mode(session) end
end

function M.set_extend_mode(session)
  if not session.extend_mode then M.toggle_mode(session) end
end
```

### Reentrancy Guard Pattern (PITFALL-11)

```lua
-- Source: PITFALLS.md PITFALL-11
function M.start(buf, initial_mode)
  local sessions = require('visual-multi')._sessions

  -- Check BEFORE allocating: if session exists, return it immediately.
  -- This handles both the idempotent case (user pressed C-n twice)
  -- and the reentrancy case (VMEnter listener triggers start()).
  if sessions[buf] then return sessions[buf] end

  -- Register BEFORE any autocmd-triggering operations.
  -- This means VMEnter itself sees the session as already registered
  -- if it calls get_state().
  local session = _new_session(buf, initial_mode or false)
  sessions[buf] = session  -- <-- register first

  _save_and_set_options(session)   -- may trigger autocmds via option changes
  _save_and_install_keymaps(session)
  _create_session_augroup(session)

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'VMEnter',
    data    = { bufnr = buf, extend_mode = session.extend_mode },
  })

  return session
end
```

### Test Buffer Pattern for session_spec.lua

```lua
-- Source: existing spec files (undo_spec.lua, config_spec.lua patterns)
-- IMPORTANT: Use (false, false) not (false, true) — BUG-02 (undo must work in Phase 4+)

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, false)
  vim.bo[buf].buftype  = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world' })
  return buf
end

-- Fake session for unit tests (matches is_session() sentinel):
local function fake_session(buf)
  return {
    buf         = buf,
    win         = vim.api.nvim_get_current_win(),
    _stopped    = false,
    extend_mode = false,
    cursors     = {},
    _saved      = { opts = {}, keymaps = {} },
    _augroup_name = 'VM_buf_' .. buf,
  }
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `b:VM_Selection` dict as session store | Module-level `_sessions[buf]` table | This rewrite | Testable without buffer state; GC-safe; multi-buffer safe (PITFALL-03) |
| `g:Vm.extend_mode` global boolean | `session.extend_mode` per-session boolean | This rewrite | Two simultaneous VM sessions don't corrupt each other (PITFALL-13) |
| `vm#maps#init()` + `vm#maps#reset()` string `exe` maps | `vim.keymap.set + maparg/mapset` | This rewrite | Lua callbacks work; `<Plug>` mappings handled natively |
| `augroup VM_insert ... autocmd!` string commands | `nvim_create_augroup + nvim_create_autocmd` | Since Neovim 0.7 | Type-safe; Lua callbacks; no string escaping |
| `silent doautocmd User visual_multi_mappings` | `nvim_exec_autocmds` with `data=` | Since Neovim 0.8 | Structured payload; no global variable side-channel |
| VimScript `maparg()` + `exe` to restore | `vim.fn.maparg(..., true)` + `vim.fn.mapset()` | Available in Neovim 0.10 | Full dict round-trip; Lua callbacks preserved |

**Deprecated/outdated:**
- `vim.api.nvim_buf_set_option` / `nvim_win_set_option`: Deprecated in Neovim 0.10+. Use `vim.bo[buf].opt`, `vim.wo.opt`, or the win/buf option API. However, `nvim_win_get_option(win_id, ...)` and `nvim_win_set_option(win_id, ...)` are still the only way to target a non-current window by ID — use them for window-local option save/restore.
- `vim.cmd('augroup ... autocmd! ... augroup END')`: Use `nvim_create_augroup` + `nvim_create_autocmd`.
- `vim.cmd('doautocmd User VMEnter')`: Use `nvim_exec_autocmds` with `data=` for structured payload.

---

## Open Questions

1. **guicursor modification format in extend mode**
   - What we know: The CONTEXT.md says guicursor is "modified in extend mode for visual feedback". The VimScript source does not appear to modify guicursor directly (it uses `matchadd` and `highlight clear MultiCursor` for visual feedback, not cursor shape).
   - What's unclear: What the exact guicursor modification should be. The prior Lua branch (`001-lua-nvim-rewrite`) may have details.
   - Recommendation: In Phase 2, save and restore guicursor unconditionally but DO NOT modify it yet. Defer the actual guicursor modification to Phase 3 when cursor rendering is built. This is safe — the save/restore infrastructure is what matters for Phase 2.

2. **maparg buffer-local behavior**
   - What we know: `vim.fn.maparg(lhs, mode, false, true)` scans the current buffer's keymap table first, then global. If a buffer-local map exists in the current buffer for `lhs`, it is returned.
   - What's unclear: Whether `maparg` returns buffer-local maps from a NON-current buffer. Based on Neovim docs, maparg always checks the current buffer.
   - Recommendation: Call `_save_keymap` inside `vim.api.nvim_buf_call(session.buf, ...)` to ensure the correct buffer is current when `maparg` scans. This is consistent with the `nvim_buf_call` pattern used throughout the codebase.

3. **Whether `_sessions` in init.lua should be moved to session.lua**
   - What we know: Phase 1 put `_sessions` in `init.lua` with `M._sessions = _sessions` for test injection. `session.lua` would need to `require('visual-multi')._sessions` to access it.
   - What's unclear: Whether circular require is a risk (`init.lua` requiring `session.lua` requiring `init.lua`).
   - Recommendation: Keep `_sessions` in `init.lua`. `session.lua` accesses it via `require('visual-multi')._sessions` inside function bodies (not at module top-level). This is the same lazy-require pattern used in `highlight.lua` and `region.lua` — safe because `init.lua` is fully loaded before any session function runs.

---

## Sources

### Primary (HIGH confidence)

- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/variables.vim` — Complete option save/restore inventory (lines 46-148); VimScript ground truth for `init()` and `reset()` functions
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/global.vim` — `change_mode()`, `cursor_mode()`, `extend_mode()` implementation (lines 102-140); authoritative mode model
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/maps.vim` — `enable()`, `disable()`, `start()`, `map_esc_and_toggle()` (lines 46-130); keymap lifecycle reference
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/.planning/research/PITFALLS.md` — BUG-01 (window-local options), PITFALL-08 (augroup orphans), PITFALL-09 (keymap save/restore), PITFALL-10 (wrong buffer context), PITFALL-11 (reentrancy), PITFALL-13 (global vs session state)
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/.planning/research/ARCHITECTURE.md` — §2 session table shape, §3 keymap lifecycle, §8 module boundary definitions
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/.planning/phases/02-session-lifecycle/02-CONTEXT.md` — All locked decisions; authoritative for Phase 2 scope
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/` — All Phase 1 modules (config, util, highlight, region, undo, init) and their specs — confirmed actual API surface

### Secondary (MEDIUM confidence)

- `.planning/research/STACK.md` — §2 module structure conventions, §3 keymap pattern; confirmed against actual Phase 1 code
- `.planning/research/ARCHITECTURE.md` §9 — Window-local options via `vim.wo` not `vim.bo`; cross-cutting concerns

### Tertiary (LOW confidence)

- None. No web search was required — all findings are based on project documentation and VimScript source code that is part of the repository.

---

## Metadata

**Confidence breakdown:**
- Session table shape: HIGH — directly derived from ARCHITECTURE.md §2 + locked CONTEXT.md decisions
- Option save/restore: HIGH — read directly from `variables.vim` vm#variables#init() / reset(); scope confirmed against PITFALLS.md BUG-01 Quick Reference
- Keymap save/restore: HIGH — PITFALLS.md PITFALL-09 provides exact `maparg`+`mapset` code; VimScript source confirms the save-restore contract
- Augroup lifecycle: HIGH — CONTEXT.md locked (VM_buf_{bufnr}); `nvim_create_augroup` + `nvim_del_augroup_by_name` are stable 0.7+ APIs
- Mode model: HIGH — `global.vim` `change_mode()` / `cursor_mode()` / `extend_mode()` read directly; boolean `session.extend_mode` matches `g:Vm.extend_mode` semantics
- Test spec patterns: HIGH — existing spec files (undo_spec.lua, config_spec.lua) provide exact template to follow

**Research date:** 2026-02-28
**Valid until:** 2026-05-28 (90 days — all APIs are Neovim stable; VimScript source is frozen reference)
