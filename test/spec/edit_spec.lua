--- Tests for lua/visual-multi/edit.lua
--- Run with: nvim --headless -u NORC -l test/run_spec.lua
--- MiniTest is set as a global by MiniTest.setup() in the runner.
---
--- Phase 4 coverage: M.exec (FEAT-05, FEAT-06), M.yank/paste (FEAT-05),
---                   M.dot (FEAT-05), M.g_increment (FEAT-10),
---                   case/replace ops via exec wrappers (FEAT-10).

local buf
local edit = require('visual-multi.edit')
local region_mod = require('visual-multi.region')
local session_mod = require('visual-multi.session')

--- Helper: create a two-cursor session on buf.
--- cursor 1 at (0,0), cursor 2 at (1,0). primary_idx = 2.
---@param s table session
---@return table session (same reference)
local function _two_cursor_session(s)
  s.cursors[1] = region_mod.new(s.buf, 0, 0)
  s.cursors[2] = region_mod.new(s.buf, 1, 0)
  s.primary_idx = 2
  return s
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- BUG-02: (false, false) for undo to work; NOT scratch
      buf = vim.api.nvim_create_buf(false, false)
      vim.bo[buf].buftype   = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world', 'foo bar baz' })
      vim.api.nvim_set_current_buf(buf)
      require('visual-multi.config')._reset()
      require('visual-multi')._sessions[buf] = nil
    end,
    post_case = function()
      pcall(session_mod.stop, buf)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  },
})

-- ─── Category S: Structural ────────────────────────────────────────────────────

T['edit module loads without error'] = function()
  MiniTest.expect.equality(type(edit), 'table')
end

T['edit exports all required functions'] = function()
  MiniTest.expect.equality(type(edit.exec),        'function')
  MiniTest.expect.equality(type(edit.yank),        'function')
  MiniTest.expect.equality(type(edit.paste),       'function')
  MiniTest.expect.equality(type(edit.dot),         'function')
  MiniTest.expect.equality(type(edit.g_increment), 'function')
end

T['exec is a no-op on stopped session'] = function()
  local session = session_mod.start(buf, false)
  session._stopped = true
  -- Should not error
  edit.exec(session, 'dw')
end

T['exec is a no-op with empty cursors list'] = function()
  local session = session_mod.start(buf, false)
  -- No cursors added; cursors = {}
  edit.exec(session, 'dw')
  -- Buffer unchanged
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], 'hello world')
end

-- ─── Category E: exec (Plan 02 fills these in) ────────────────────────────────
-- Tests marked PENDING: will fail until Plan 02 implements M.exec.

T['exec deletes word at each cursor — dw at hello and foo'] = function()
  local session = session_mod.start(buf, false)
  _two_cursor_session(session)
  edit.exec(session, 'dw')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], 'world')
  MiniTest.expect.equality(lines[2], 'bar baz')
end

T['exec wraps edits in a single undo entry'] = function()
  local session = session_mod.start(buf, false)
  _two_cursor_session(session)
  local before = vim.fn.undotree().seq_cur
  edit.exec(session, 'dw')
  local after = vim.fn.undotree().seq_cur
  -- Exactly one new undo entry for both cursor operations
  MiniTest.expect.equality(after - before, 1)
end

T['exec restores eventignore to original value'] = function()
  vim.o.eventignore = ''
  local session = session_mod.start(buf, false)
  _two_cursor_session(session)
  edit.exec(session, 'dw')
  MiniTest.expect.equality(vim.o.eventignore, '')
end

T['exec stores keys in session._vm_dot for dot-repeat'] = function()
  local session = session_mod.start(buf, false)
  _two_cursor_session(session)
  edit.exec(session, 'dw')
  MiniTest.expect.equality(session._vm_dot, 'dw')
end

T['dot replays last exec keys'] = function()
  local session = session_mod.start(buf, false)
  session.cursors[1] = region_mod.new(buf, 0, 0)
  session.primary_idx = 1
  -- First exec: delete first word on line 1
  edit.exec(session, 'dw')
  -- Line 1 is now 'world'; update cursor to start of remaining
  -- Dot-repeat should delete 'world'
  edit.dot(session)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], '')
end

return T
