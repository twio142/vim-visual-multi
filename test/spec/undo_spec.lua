--- Tests for lua/visual-multi/undo.lua
--- Run with: nvim --headless -u NORC -l test/run_spec.lua
--- MiniTest is set as a global by MiniTest.setup() in the runner.
---
--- Explicit regression guards:
---   BUG-02: Test buffers must be (false, false) — scratch buffers have undolevels=-1
---   BUG-03: flush_undo_history uses vim.bo[buf].undolevels, NOT vim.o.undolevels
---   BUG-04: end_block short-circuits on no content change to avoid spurious undo entry

local buf

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- BUG-02 guard: use (false, false) so undo is enabled; scratch (false, true) sets undolevels=-1
      buf = vim.api.nvim_create_buf(false, false)
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'original line', 'second line' })
      -- Required: vim.fn.undotree() and vim.cmd operate on current buffer
      vim.api.nvim_set_current_buf(buf)
    end,
    post_case = function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  },
})

-- Category A: BUG-02 regression guard
-- Confirm that test buffer setup actually enables undo.
-- If this assertion fails, every undo test below would pass trivially (undo is a no-op).
T['BUG-02: test buffer has undo enabled'] = function()
  -- nvim_create_buf(false, true) = scratch → undolevels=-1 (undo silently disabled)
  -- nvim_create_buf(false, false) = normal nofile → undolevels follows default (>= 0)
  MiniTest.expect.equality(vim.bo[buf].undolevels ~= -1, true)
end

-- Category B: begin_block and end_block behavior

T['begin_block records _undo_seq_before as number'] = function()
  local session = { buf = buf, _stopped = false }
  require('visual-multi.undo').begin_block(session)
  MiniTest.expect.equality(type(session._undo_seq_before), 'number')
end

T['begin_block records _undo_lines_before as table'] = function()
  local session = { buf = buf, _stopped = false }
  require('visual-multi.undo').begin_block(session)
  MiniTest.expect.equality(type(session._undo_lines_before), 'table')
end

T['end_block clears state on no-change (BUG-04)'] = function()
  local session = { buf = buf, _stopped = false }
  local undo = require('visual-multi.undo')
  undo.begin_block(session)
  -- Make NO changes to the buffer — end_block should short-circuit
  undo.end_block(session)
  -- State must be cleared (short-circuit path taken)
  MiniTest.expect.equality(session._undo_seq_before, nil)
  MiniTest.expect.equality(session._undo_lines_before, nil)
  -- _undo_seq_after must NOT be set (no undo entry created)
  MiniTest.expect.equality(session._undo_seq_after, nil)
end

T['end_block records _undo_seq_after on real change'] = function()
  local session = { buf = buf, _stopped = false }
  local undo = require('visual-multi.undo')
  undo.begin_block(session)
  -- Make a real change so end_block takes the non-short-circuit path
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'changed line' })
  undo.end_block(session)
  MiniTest.expect.equality(type(session._undo_seq_after), 'number')
  MiniTest.expect.equality(session._undo_lines_before, nil) -- cleared after end_block
end

-- Category C: with_undo_block

T['with_undo_block calls the wrapped function'] = function()
  local session = { buf = buf, _stopped = false }
  local undo = require('visual-multi.undo')
  local called = false
  undo.with_undo_block(session, function(s)
    called = true
    vim.api.nvim_buf_set_lines(s.buf, 0, 1, false, { 'wrapped change' })
  end)
  MiniTest.expect.equality(called, true)
  -- _undo_lines_before cleared by end_block
  MiniTest.expect.equality(session._undo_lines_before, nil)
end

T['with_undo_block returns fn return value'] = function()
  local session = { buf = buf, _stopped = false }
  local undo = require('visual-multi.undo')
  local result = undo.with_undo_block(session, function(s)
    vim.api.nvim_buf_set_lines(s.buf, 0, 1, false, { 'return test' })
    return 42
  end)
  MiniTest.expect.equality(result, 42)
end

return T
