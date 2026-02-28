--- vim-visual-multi session lifecycle module
--- Provides: start, stop, toggle_mode, set_mode, set_cursor_mode, set_extend_mode
--- Tier-2: all require() calls to sibling modules are inside function bodies (lazy require).
--- This prevents circular dependencies with init.lua and respects Neovim load order.

local M = {}

--- Create a fresh session table.
--- All field names are locked — higher-tier code depends on them.
---@param buf integer buffer handle
---@param initial_mode boolean initial extend_mode value
---@return table session table
local function _new_session(buf, initial_mode)
  local win = vim.api.nvim_get_current_win()
  return {
    -- Identity
    buf       = buf,      -- immutable after creation
    win       = win,      -- window at session start (for win-local option restore)
    _stopped  = false,    -- sentinel: util.is_session() checks this field

    -- Mode state (FEAT-03)
    extend_mode = initial_mode, -- boolean; matches g:Vm.extend_mode semantics

    -- Cursor list (populated by Phase 3+)
    cursors = {},
    -- Index of the primary (most-recently-added) cursor in cursors list.
    -- 0 = no cursors; set to #session.cursors when cursor added (Phase 4+).
    primary_idx = 0,

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

--- Save virtualedit, conceallevel, and guicursor; set session values.
--- CRITICAL: conceallevel is window-local — use nvim_win_get_option/set_option (BUG-01).
---@param session table
local function _save_and_set_options(session)
  local win   = session.win
  local saved = session._saved.opts

  -- virtualedit: global scope
  saved.virtualedit = vim.o.virtualedit
  vim.o.virtualedit = 'onemore'

  -- conceallevel: window-local (BUG-01: NEVER use vim.bo[buf] or vim.o for this)
  saved.conceallevel = vim.api.nvim_win_get_option(win, 'conceallevel')
  vim.api.nvim_win_set_option(win, 'conceallevel', 0)

  -- guicursor: global scope. Save unconditionally; modification deferred to Phase 3
  -- (RESEARCH.md open question 1: VimScript source uses matchadd/highlight, not guicursor)
  saved.guicursor = vim.o.guicursor
  -- Do NOT modify guicursor in Phase 2.
end

--- Restore all three saved options.
--- Guards against invalid window (e.g., BufDelete path called from non-silent stop).
---@param session table
local function _restore_options(session)
  local win   = session.win
  local saved = session._saved.opts

  -- conceallevel: window-local; guard if window was closed
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_option(win, 'conceallevel', saved.conceallevel)
  end

  -- virtualedit: global scope (restore unconditionally)
  vim.o.virtualedit = saved.virtualedit

  -- guicursor: global scope (restore unconditionally, even though we didn't modify it)
  vim.o.guicursor = saved.guicursor
end

--- Install one buffer-local keymap for this session, saving any pre-existing mapping.
--- Calls maparg inside nvim_buf_call to ensure correct buffer context (RESEARCH.md open q 2).
---@param session table
---@param mode string e.g. 'n'
---@param lhs string keymap left-hand side
---@param rhs_fn function Lua callback
---@param opts table|nil extra options for vim.keymap.set
local function _set_vm_keymap(session, mode, lhs, rhs_fn, opts)
  -- Save previous mapping before overwriting (PITFALL-09)
  local prev
  vim.api.nvim_buf_call(session.buf, function()
    prev = vim.fn.maparg(lhs, mode, false, true)
  end)
  -- prev.lhs is set only when a mapping was found
  session._saved.keymaps[lhs] = (prev.lhs ~= nil and prev.lhs ~= '') and prev or false

  vim.keymap.set(mode, lhs, rhs_fn, vim.tbl_extend('force', {
    buffer = session.buf,
    nowait = true,
    silent = true,
  }, opts or {}))
end

--- Install keymaps for Phase 2 scope.
--- Only the `v` key (toggle_mode) is installed here.
--- Full keymap table (Esc, operator keys, etc.) is Phase 6 scope.
---@param session table
local function _save_and_install_keymaps(session)
  _set_vm_keymap(session, 'n', 'v', function()
    M.toggle_mode(session)
  end)
end

--- Restore all keymaps saved at session start.
--- Restores original mapping via mapset, or deletes VM's binding if none existed.
---@param session table
local function _restore_keymaps(session)
  local buf = session.buf
  for lhs, prev in pairs(session._saved.keymaps) do
    if prev then
      -- Restore original mapping atomically (handles Lua callbacks, flags, etc.)
      vim.fn.mapset('n', false, prev)
    else
      -- No prior map existed — remove VM's buffer-local binding
      pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
    end
  end
  session._saved.keymaps = {}
end

--- Create per-session augroup and register BufDelete guard.
--- { clear = true } prevents stale autocmd accumulation (PITFALL-08).
---@param session table
local function _create_augroup(session)
  local name = session._augroup_name  -- 'VM_buf_{bufnr}'
  vim.api.nvim_create_augroup(name, { clear = true })

  -- Emergency teardown: BufDelete fires even on :bdelete!
  -- Silent stop: buffer is already gone, skip option/keymap restore.
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer   = session.buf,
    group    = name,
    once     = true,
    callback = function()
      M.stop(session.buf, { silent = true })
    end,
  })
end

--- Start a multi-cursor session for buf.
--- Six steps in order (RESEARCH.md Pattern 2).
--- Reentrancy guard prevents double-initialization (PITFALL-11).
---@param buf integer|nil buffer handle; defaults to current buffer
---@param initial_mode boolean|nil extend_mode initial value; defaults to false
---@return table session
function M.start(buf, initial_mode)
  buf = buf or vim.api.nvim_get_current_buf()
  local sessions = require('visual-multi')._sessions

  -- PITFALL-11: Reentrancy guard — return existing session immediately
  if sessions[buf] then return sessions[buf] end

  local session = _new_session(buf, initial_mode or false)

  -- Register FIRST (before autocmd-triggering operations) so reentrancy returns this session
  sessions[buf] = session

  -- Step 1: Save and set options
  _save_and_set_options(session)

  -- Step 2: Save and install keymaps
  _save_and_install_keymaps(session)

  -- Step 3: Create augroup with BufDelete guard
  _create_augroup(session)

  -- Step 4: Emit VMEnter (after full initialization — listeners may call get_state())
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'VMEnter',
    data    = { bufnr = session.buf, extend_mode = session.extend_mode },
  })

  return session
end

--- Stop a multi-cursor session for buf, cleaning up options, keymaps, and augroup.
--- opts.silent = true skips option/keymap restore (BufDelete path).
---@param buf integer buffer handle
---@param opts table|nil { silent = bool }
function M.stop(buf, opts)
  opts = opts or {}
  local sessions = require('visual-multi')._sessions
  local session  = sessions[buf]

  -- Guard: already stopped or never started
  if not session then return end

  -- Set nil FIRST — prevents double-stop race (PITFALL-06 variant)
  sessions[buf] = nil
  session._stopped = true

  if not opts.silent then
    -- Restore keymaps before options (user navigation unblocked first)
    _restore_keymaps(session)
    _restore_options(session)
  end

  -- Clear all extmarks (safe even if no cursors were created)
  require('visual-multi.highlight').clear(session)

  -- Delete augroup (also deletes BufDelete autocmd); pcall: may already be deleted
  pcall(vim.api.nvim_del_augroup_by_name, session._augroup_name)

  -- Emit VMLeave
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'VMLeave',
    data    = { bufnr = buf },
  })
end

--- Flip extend_mode boolean.
--- Phase 2: mode flip only. Cursor shape/selection collapse deferred to Phase 3.
---@param session table
function M.toggle_mode(session)
  session.extend_mode = not session.extend_mode
end

--- Set extend_mode unconditionally.
---@param session table
---@param extend boolean
function M.set_mode(session, extend)
  session.extend_mode = extend
end

--- Ensure cursor mode (extend_mode = false). Idempotent.
---@param session table
function M.set_cursor_mode(session)
  if session.extend_mode then M.toggle_mode(session) end
end

--- Ensure extend mode (extend_mode = true). Idempotent.
---@param session table
function M.set_extend_mode(session)
  if not session.extend_mode then M.toggle_mode(session) end
end

return M
