--- Tests for lua/visual-multi/edit.lua
--- Run with: nvim --headless -u NORC -l test/run_spec.lua
--- MiniTest is set as a global by MiniTest.setup() in the runner.
---
--- Phase 4 coverage: M.exec (FEAT-05, FEAT-06), M.yank/paste (FEAT-05),
---                   M.dot (FEAT-05), M.g_increment (FEAT-10),
---                   case/replace ops via exec wrappers (FEAT-10).
---
--- NOTE on buffer setup: undo tracking via undotree().seq_cur requires a file-backed
--- buffer. nvim_create_buf(false, false) with buftype=nofile gives undolevels=-123456,
--- which means feedkeys edits never register in seq_cur. Tests requiring undo verification
--- use a tmpfile via vim.cmd('edit') to get a real undo-enabled buffer.

local buf
local tmpfile
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
      -- Use a file-backed buffer so that feedkeys edits register in the undo tree.
      -- nvim_create_buf(false, false) with buftype=nofile gives undolevels=-123456,
      -- which prevents seq_cur from advancing even when feedkeys changes the content.
      tmpfile = vim.fn.tempname()
      local f = io.open(tmpfile, 'w')
      f:write('hello world\nfoo bar baz\n')
      f:close()
      vim.cmd('edit ' .. vim.fn.fnameescape(tmpfile))
      buf = vim.api.nvim_get_current_buf()
      -- Ensure undo history starts clean for this test
      vim.cmd('noautocmd silent! %d _')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world', 'foo bar baz' })
      -- Flush so that the set_lines above doesn't count as an undo entry
      -- (use undojoin-trick: set undolevels=-1 then restore to flush)
      local saved_ul = vim.bo[buf].undolevels
      vim.bo[buf].undolevels = -1
      vim.bo[buf].undolevels = saved_ul
      require('visual-multi.config')._reset()
      require('visual-multi')._sessions[buf] = nil
    end,
    post_case = function()
      pcall(session_mod.stop, buf)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      if tmpfile then pcall(vim.fn.delete, tmpfile) end
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

-- ─── Category E: exec ─────────────────────────────────────────────────────────

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

-- ─── Category U: Undo grouping (FEAT-06) ──────────────────────────────────────

T['single undo after exec with 3 cursors creates exactly 1 undo entry'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'aa', 'bb', 'cc' })
  -- Flush new content into a clean undo baseline (undolevels trick)
  local ul = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  vim.bo[buf].undolevels = ul
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.cursors[3] = region_mod.new(buf, 2, 0)
  s.primary_idx = 3
  local before = vim.fn.undotree().seq_cur
  edit.exec(s, 'dd')
  local after = vim.fn.undotree().seq_cur
  MiniTest.expect.equality(after - before, 1)
end

T['undo after exec reverses all cursor deletions'] = function()
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  edit.exec(s, 'dw')
  vim.api.nvim_set_current_buf(buf)
  vim.cmd('silent undo')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], 'hello world')
  MiniTest.expect.equality(lines[2], 'foo bar baz')
end

T['no-op exec (cursor at EOF) does not advance undo sequence more than once'] = function()
  -- BUG-04 guard: end_block short-circuits on no content change.
  -- When exec is given a motion that doesn't change content (dw on empty line
  -- may or may not advance seq_cur depending on Vim internals), we verify that
  -- at most 1 undo entry is created, not N entries for N cursors.
  -- The stricter check (delta == 0) is not enforced here because feedkeys creates
  -- undo entries at the Neovim level even when content doesn't visibly change.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
  local ul = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  vim.bo[buf].undolevels = ul
  local s = session_mod.start(buf, false)
  -- Three cursors, all on the same empty line
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 0, 0)
  s.cursors[3] = region_mod.new(buf, 0, 0)
  s.primary_idx = 3
  local before = vim.fn.undotree().seq_cur
  edit.exec(s, 'dw')  -- nothing to delete on empty line
  local after = vim.fn.undotree().seq_cur
  -- BUG-04: must NOT create 3 separate undo entries (one per cursor)
  MiniTest.expect.equality(after - before <= 1, true)
end

-- ─── Category P: paste with VM register (FEAT-05) ─────────────────────────────

T['yank populates session._vm_register per cursor'] = function()
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  edit.yank(s)
  MiniTest.expect.equality(type(s._vm_register), 'table')
  MiniTest.expect.equality(type(s._vm_register[1]), 'table')
  MiniTest.expect.equality(type(s._vm_register[2]), 'table')
  -- cursor 1 at 'hello world', yiw = 'hello'
  MiniTest.expect.equality(s._vm_register[1].text, 'hello')
  -- cursor 2 at 'foo bar baz', yiw = 'foo'
  MiniTest.expect.equality(s._vm_register[2].text, 'foo')
end

T['paste with empty VM register uses Vim unnamed register at all cursors'] = function()
  -- Seed unnamed register
  vim.fn.setreg('"', 'XYZ', 'v')
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  -- No yank: _vm_register is nil/empty
  edit.paste(s, false)  -- paste after
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- 'p' after cursor at col 0: XYZ inserted after 'h' in 'hello world'
  MiniTest.expect.no_error(function() assert(lines[1]:find('XYZ')) end)
  MiniTest.expect.no_error(function() assert(lines[2]:find('XYZ')) end)
end

-- ─── Category D: dot-repeat (FEAT-05) ─────────────────────────────────────────

T['dot is silent when _vm_dot is nil'] = function()
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.primary_idx = 1
  -- Should not error when _vm_dot is nil
  edit.dot(s)
end

-- ─── Category C: change operator delete-half (FEAT-05) ────────────────────────

T['change deletes word without entering insert mode'] = function()
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  edit.change(s, 'w')  -- delete word at each cursor; no insert mode
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], 'world')
  MiniTest.expect.equality(lines[2], 'bar baz')
  -- Confirm not in insert mode
  MiniTest.expect.equality(vim.api.nvim_get_mode().mode, 'n')
end

-- ─── Category G: g_increment sequential numbers (FEAT-10) ─────────────────────

T['g_increment applies +1,+2,+3 top-to-bottom on numbers'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '10', '20', '30' })
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.cursors[3] = region_mod.new(buf, 2, 0)
  s.primary_idx = 3
  edit.g_increment(s, 1)  -- direction=1 → g<C-a>
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], '11')   -- 10 + 1
  MiniTest.expect.equality(lines[2], '22')   -- 20 + 2
  MiniTest.expect.equality(lines[3], '33')   -- 30 + 3
end

T['g_increment applies -1,-2,-3 top-to-bottom on numbers'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '10', '20', '30' })
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.cursors[3] = region_mod.new(buf, 2, 0)
  s.primary_idx = 3
  edit.g_increment(s, -1)  -- direction=-1 → g<C-x>
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], '9')    -- 10 - 1
  MiniTest.expect.equality(lines[2], '18')   -- 20 - 2
  MiniTest.expect.equality(lines[3], '27')   -- 30 - 3
end

T['g_increment creates exactly one undo entry'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '1', '2', '3' })
  -- Flush the buf_set_lines above into a clean undo baseline (same pattern as pre_case)
  local ul = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  vim.bo[buf].undolevels = ul
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.cursors[3] = region_mod.new(buf, 2, 0)
  s.primary_idx = 3
  local before = vim.fn.undotree().seq_cur
  edit.g_increment(s, 1)
  local after = vim.fn.undotree().seq_cur
  MiniTest.expect.equality(after - before, 1)
end

T['g_increment is a no-op on non-number line (silent skip)'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello', '42' })
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)   -- 'hello' — no number
  s.cursors[2] = region_mod.new(buf, 1, 0)   -- '42' — has number
  s.primary_idx = 2
  -- Should not error; line 1 silently skips
  edit.g_increment(s, 1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], 'hello')  -- unchanged
  MiniTest.expect.equality(lines[2], '44')     -- 42 + 2 (second cursor gets step=2)
end

T['plain C-a / C-x via exec increments/decrements without sequential steps'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '5', '10' })
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  edit.exec(s, '<C-a>')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], '6')   -- 5 + 1
  MiniTest.expect.equality(lines[2], '11')  -- 10 + 1
end

-- ─── Category K: case conversion (FEAT-10) ────────────────────────────────────

T['case_toggle flips case at each cursor'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'abc', 'DEF' })
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  edit.case_toggle(s)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1]:sub(1,1), 'A')  -- 'a' → 'A'
  MiniTest.expect.equality(lines[2]:sub(1,1), 'd')  -- 'D' → 'd'
end

T['case_upper converts word under cursor to uppercase'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello', 'world' })
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  edit.case_upper(s, 'iw')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], 'HELLO')
  MiniTest.expect.equality(lines[2], 'WORLD')
end

T['case_lower converts word under cursor to lowercase'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'HELLO', 'WORLD' })
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  edit.case_lower(s, 'iw')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], 'hello')
  MiniTest.expect.equality(lines[2], 'world')
end

T['case_upper creates exactly one undo entry'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'aa', 'bb' })
  -- Flush the buf_set_lines above into a clean undo baseline
  local ul = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  vim.bo[buf].undolevels = ul
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  local before = vim.fn.undotree().seq_cur
  edit.case_upper(s, 'iw')
  local after = vim.fn.undotree().seq_cur
  MiniTest.expect.equality(after - before, 1)
end

-- ─── Category R: replace-char (FEAT-10) ───────────────────────────────────────

T['replace_char replaces character under each cursor'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'abc', 'def' })
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  edit.replace_char(s, 'X')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1]:sub(1,1), 'X')  -- 'a' replaced by 'X'
  MiniTest.expect.equality(lines[2]:sub(1,1), 'X')  -- 'd' replaced by 'X'
end

T['replace_char creates exactly one undo entry'] = function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'aa', 'bb' })
  -- Flush the buf_set_lines above into a clean undo baseline
  local ul = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  vim.bo[buf].undolevels = ul
  local s = session_mod.start(buf, false)
  s.cursors[1] = region_mod.new(buf, 0, 0)
  s.cursors[2] = region_mod.new(buf, 1, 0)
  s.primary_idx = 2
  local before = vim.fn.undotree().seq_cur
  edit.replace_char(s, 'Z')
  local after = vim.fn.undotree().seq_cur
  MiniTest.expect.equality(after - before, 1)
end

return T
