# Phase 2: Session Lifecycle - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Start a multi-cursor session in a buffer, manage its state (mode, keymaps, options, augroup) while active, and cleanly stop it with full teardown — options restored, keymaps removed, autocmds deleted, VMLeave emitted. No state leaks between sessions.

This phase does NOT include: cursor rendering (Phase 3), normal-mode operations (Phase 4), insert mode (Phase 5), or the entry-point keybindings like `<C-n>` that trigger session start (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Keymap conflict policy
- **Save-and-restore**: On session start, capture any existing buffer-local keymap on each VM key before installing VM's binding. On session exit, restore the original mapping (or remove VM's if there was none).
- **Buffer-local only**: All VM session keymaps use `vim.keymap.set(..., { buffer = bufnr })`. No global keymaps during sessions.
- Leader prefix is preserved and sourced from the `mappings` key in `setup(opts)` config (see Phase 1 config.lua). Keymap installation reads config — no hardcoded leader in session.lua.

### Mode model
- **Single mode per session**: Mode is `session.extend_mode` (boolean), matching the original `g:Vm.extend_mode`. All cursors share the same mode.
- **Initial mode depends on trigger**: The session start function accepts an `initial_mode` argument.
  - `<C-n>` / word-search entry → `extend_mode = true`
  - `<C-Up>` / `<C-Down>` / line-cursor entry → `extend_mode = false`
- **Mode resets on toggle**: Pressing `v` calls `session.toggle_mode()` — flips `extend_mode`, resets each cursor's selection to its current position. No per-cursor selection memory across mode switches.
- **No insert-mode enum in Phase 2**: Insert mode is handled separately in Phase 5 via its own autocommands. Phase 2 only tracks `extend_mode` (boolean).

### Session lifecycle hooks
- **VMEnter / VMLeave** User autocmds emitted on session start/stop with a data payload:
  ```lua
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'VMEnter',
    data = { bufnr = session.buf, extend_mode = session.extend_mode }
  })
  ```
- **Just VMEnter/VMLeave for now**: Finer-grained events (cursor count change, mode change, etc.) are added in later phases as features are built.
- **Per-session augroup**: Each session creates a unique augroup (`VM_buf_{bufnr}`) on start and deletes it with `nvim_del_augroup_by_name` on exit. Zero risk of stale autocmds from prior sessions.

### Option/state save-restore scope
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

</decisions>

<specifics>
## Specific Ideas

- The `session.extend_mode` field should match the original `g:Vm.extend_mode` semantics exactly — including the `change_mode()` / `cursor_mode()` / `extend_mode()` helper pattern from `autoload/vm/global.vim`
- Per-session augroup naming: `VM_buf_42` (where 42 is bufnr) makes debugging easy — you can see active VM augroups with `:au VM_buf_*`

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-session-lifecycle*
*Context gathered: 2026-02-28*
