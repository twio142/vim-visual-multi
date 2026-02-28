-- test/spec/highlight_spec.lua — mini.test specs for visual-multi.highlight
-- Uses global MiniTest set by MiniTest.setup() in run_spec.lua.

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Fresh buffer for each test
    end,
    post_case = function()
    end,
  },
})

-- Buffer created fresh for each test
local buf

local T_hl = MiniTest.new_set({
  hooks = {
    pre_case = function()
      buf = vim.api.nvim_create_buf(false, false)
      vim.bo[buf].buftype  = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world' })
    end,
    post_case = function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  },
})

T['highlight'] = T_hl

-- 1. ns is an integer > 0
T_hl['ns is a valid namespace id'] = function()
  local hl = require('visual-multi.highlight')
  MiniTest.expect.equality(type(hl.ns), 'number')
  assert(hl.ns > 0, 'Expected ns > 0, got ' .. tostring(hl.ns))
end

-- 2. define_groups() does not error
T_hl['define_groups does not error'] = function()
  local hl = require('visual-multi.highlight')
  MiniTest.expect.no_error(function()
    hl.define_groups()
  end)
end

-- 3. draw_cursor returns an integer mark_id on first call; subsequent call with same id succeeds
T_hl['draw_cursor returns integer mark_id'] = function()
  local hl = require('visual-multi.highlight')
  local id = hl.draw_cursor(buf, 0, 0, nil)
  MiniTest.expect.equality(type(id), 'number')
  assert(id > 0, 'Expected mark_id > 0, got ' .. tostring(id))
  -- Second call with returned id should also succeed
  MiniTest.expect.no_error(function()
    hl.draw_cursor(buf, 0, 1, id)
  end)
end

-- 4. After draw_cursor at (0,0), extmark readback returns {0, 0}
T_hl['draw_cursor places extmark at correct position'] = function()
  local hl = require('visual-multi.highlight')
  local id = hl.draw_cursor(buf, 0, 0, nil)
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, hl.ns, id, {})
  MiniTest.expect.equality(pos, { 0, 0 })
end

-- 5. draw_cursor with existing id moves the mark — readback returns new position
T_hl['draw_cursor in-place update moves mark'] = function()
  local hl = require('visual-multi.highlight')
  local id = hl.draw_cursor(buf, 0, 0, nil)
  hl.draw_cursor(buf, 0, 2, id)
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, hl.ns, id, {})
  MiniTest.expect.equality(pos, { 0, 2 })
end

-- 6. clear(buf) after draw: no extmarks remain
T_hl['clear(buf) removes all extmarks'] = function()
  local hl = require('visual-multi.highlight')
  hl.draw_cursor(buf, 0, 0, nil)
  hl.draw_cursor(buf, 0, 3, nil)
  hl.clear(buf)
  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, {})
  MiniTest.expect.equality(marks, {})
end

-- 7. clear(session) where session = {buf=buf, _stopped=false} works same as clear(buf)
T_hl['clear(session) removes all extmarks via is_session dispatch'] = function()
  local hl = require('visual-multi.highlight')
  hl.draw_cursor(buf, 0, 0, nil)
  local session = { buf = buf, _stopped = false }
  hl.clear(session)
  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, {})
  MiniTest.expect.equality(marks, {})
end

return T
