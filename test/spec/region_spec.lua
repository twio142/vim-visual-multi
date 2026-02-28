-- test/spec/region_spec.lua — mini.test specs for visual-multi.region
-- Uses global MiniTest set by MiniTest.setup() in run_spec.lua.

local buf

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      buf = vim.api.nvim_create_buf(false, false)
      vim.bo[buf].buftype  = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world', 'line two' })
    end,
    post_case = function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  },
})

-- 1. Region.new returns a table with integer sel_mark_id and _stopped == false
T['Region.new returns table with sel_mark_id and _stopped=false'] = function()
  local Region = require('visual-multi.region')
  local r = Region.new(buf, 0, 0)
  MiniTest.expect.equality(type(r), 'table')
  MiniTest.expect.equality(type(r.sel_mark_id), 'number')
  assert(r.sel_mark_id > 0, 'Expected sel_mark_id > 0, got ' .. tostring(r.sel_mark_id))
  MiniTest.expect.equality(r._stopped, false)
end

-- 2. After Region.new(buf, 0, 2), region:pos() returns (0, 2)
T['Region:pos returns correct initial position'] = function()
  local Region = require('visual-multi.region')
  local r = Region.new(buf, 0, 2)
  local row, col = r:pos()
  MiniTest.expect.equality(row, 0)
  MiniTest.expect.equality(col, 2)
end

-- 3. After region:move(0, 5), pos() returns (0, 5) with same sel_mark_id
T['Region:move updates position in place (same sel_mark_id)'] = function()
  local Region = require('visual-multi.region')
  local r = Region.new(buf, 0, 0)
  local original_id = r.sel_mark_id
  r:move(0, 5)
  local row, col = r:pos()
  MiniTest.expect.equality(row, 0)
  MiniTest.expect.equality(col, 5)
  -- sel_mark_id must be unchanged (in-place update, not delete-and-recreate)
  MiniTest.expect.equality(r.sel_mark_id, original_id)
end

-- 4. After region:remove(), region._stopped == true
T['Region:remove sets _stopped = true'] = function()
  local Region = require('visual-multi.region')
  local r = Region.new(buf, 0, 0)
  r:remove()
  MiniTest.expect.equality(r._stopped, true)
end

-- 5. After region:remove(), the extmark is gone from the buffer
T['Region:remove deletes the extmark from buffer'] = function()
  local Region = require('visual-multi.region')
  local hl = require('visual-multi.highlight')
  local r = Region.new(buf, 0, 0)
  local id = r.sel_mark_id
  r:remove()
  local info = vim.api.nvim_buf_get_extmark_by_id(buf, hl.ns, id, {})
  MiniTest.expect.equality(info, {})
end

-- 6. util.is_session(region) returns true — regions carry _stopped so they satisfy
--    the session discriminant. This is intentional design: both region tables and
--    session tables share the same _stopped sentinel.
T['util.is_session(region) returns true'] = function()
  local Region = require('visual-multi.region')
  local util = require('visual-multi.util')
  local r = Region.new(buf, 0, 0)
  MiniTest.expect.equality(util.is_session(r), true)
end

return T
