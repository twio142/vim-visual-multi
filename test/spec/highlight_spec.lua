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

-- 3. setup() registers VM_ groups so they resolve at runtime (GAP-01 regression guard)
T_hl['setup() defines VM_ highlight groups'] = function()
  require('visual-multi').setup()
  -- nvim_get_hl returns {} for unknown groups and a non-empty table for defined groups.
  local cursor_hl = vim.api.nvim_get_hl(0, { name = 'VM_Cursor' })
  assert(next(cursor_hl) ~= nil,
    'Expected VM_Cursor to be defined after setup(); got empty table')
  local extend_hl = vim.api.nvim_get_hl(0, { name = 'VM_Extend' })
  assert(next(extend_hl) ~= nil,
    'Expected VM_Extend to be defined after setup(); got empty table')
end

-- 4. draw_cursor returns an integer mark_id on first call; subsequent call with same id succeeds
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

-- ─── Phase 3 redraw specs ───────────────────────────────────────────────────

local T_redraw = MiniTest.new_set({
  hooks = {
    pre_case = function()
      buf = vim.api.nvim_create_buf(false, false)
      vim.bo[buf].buftype   = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world', 'second line' })
      vim.api.nvim_set_current_buf(buf)
      require('visual-multi.highlight').define_groups()
    end,
    post_case = function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  },
})

T['redraw'] = T_redraw

--- Build a minimal fake session table for redraw tests.
local function fake_session(buf_handle, regions, primary, extend)
  return {
    buf         = buf_handle,
    _stopped    = false,
    extend_mode = extend or false,
    primary_idx = primary or 1,
    cursors     = regions,
  }
end

-- 1. Primary cursor gets VM_Cursor; secondary gets VM_CursorSecondary
T_redraw['redraw draws primary cursor with VM_Cursor hl_group'] = function()
  local hl     = require('visual-multi.highlight')
  local Region = require('visual-multi.region')

  local r1 = Region.new(buf, 0, 0)   -- secondary (index 1)
  local r2 = Region.new(buf, 0, 6)   -- primary  (index 2)
  local session = fake_session(buf, { r1, r2 }, 2, false)
  hl.redraw(session)

  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, { details = true })
  -- Find marks with hl_groups (anchor-tracking marks have no hl_group)
  local primary_found, secondary_found = false, false
  for _, m in ipairs(marks) do
    local row, col, det = m[2], m[3], m[4]
    if det.hl_group == 'VM_Cursor' then
      MiniTest.expect.equality(row, 0)
      MiniTest.expect.equality(col, 6)
      primary_found = true
    elseif det.hl_group == 'VM_CursorSecondary' then
      MiniTest.expect.equality(row, 0)
      MiniTest.expect.equality(col, 0)
      secondary_found = true
    end
  end
  assert(primary_found,   'Expected mark with hl_group=VM_Cursor at (0,6)')
  assert(secondary_found, 'Expected mark with hl_group=VM_CursorSecondary at (0,0)')
end

-- 2. Three cursors: only primary gets VM_Cursor; others get VM_CursorSecondary
T_redraw['redraw draws secondary cursors with VM_CursorSecondary hl_group'] = function()
  local hl     = require('visual-multi.highlight')
  local Region = require('visual-multi.region')

  local r1 = Region.new(buf, 0, 0)   -- primary (index 1)
  local r2 = Region.new(buf, 0, 4)
  local r3 = Region.new(buf, 0, 8)
  local session = fake_session(buf, { r1, r2, r3 }, 1, false)
  hl.redraw(session)

  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, { details = true })
  local primary_count, secondary_count = 0, 0
  for _, m in ipairs(marks) do
    local det = m[4]
    if det.hl_group == 'VM_Cursor'          then primary_count   = primary_count   + 1 end
    if det.hl_group == 'VM_CursorSecondary' then secondary_count = secondary_count + 1 end
  end
  MiniTest.expect.equality(primary_count,   1)
  MiniTest.expect.equality(secondary_count, 2)
end

-- 3. clear(session) after redraw leaves no extmarks
T_redraw['clear after redraw leaves no extmarks'] = function()
  local hl     = require('visual-multi.highlight')
  local Region = require('visual-multi.region')

  local r = Region.new(buf, 0, 0)
  local session = fake_session(buf, { r }, 1, false)
  hl.redraw(session)
  hl.clear(session)
  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, {})
  MiniTest.expect.equality(marks, {})
end

-- 4. redraw on stopped session is a no-op
T_redraw['redraw on stopped session is a no-op'] = function()
  local hl      = require('visual-multi.highlight')
  local Region  = require('visual-multi.region')
  local r       = Region.new(buf, 0, 0)
  local session = { buf = buf, _stopped = true, cursors = { r }, primary_idx = 1, extend_mode = false }
  hl.redraw(session)
  -- stopped guard should mean nothing new drawn beyond the initial Region.new mark
  -- clear and check
  vim.api.nvim_buf_clear_namespace(buf, hl.ns, 0, -1)
  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, {})
  MiniTest.expect.equality(marks, {})
end

-- 5. redraw on empty cursors list is a no-op
T_redraw['redraw on empty cursors list is a no-op'] = function()
  local hl      = require('visual-multi.highlight')
  local session = fake_session(buf, {}, 1, false)
  hl.redraw(session)
  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, {})
  MiniTest.expect.equality(marks, {})
end

-- 6. extend-mode: primary region gets VM_Extend span and VM_Cursor tip at priority 201
T_redraw['extend-mode redraw: primary region has VM_Extend span and VM_Cursor tip'] = function()
  local hl     = require('visual-multi.highlight')
  local Region = require('visual-multi.region')

  -- Region at tip=(0,3), anchor=(0,0) → selection spans col 0..4 (ASCII 'h','e','l','l')
  local r = Region.new(buf, 0, 3, 'extend', {0, 0})
  local session = fake_session(buf, { r }, 1, true)
  hl.redraw(session)

  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, { details = true })
  local extend_found, cursor_tip_found = false, false
  for _, m in ipairs(marks) do
    local det = m[4]
    if det.hl_group == 'VM_Extend' then
      extend_found = true
    end
    if det.hl_group == 'VM_Cursor' and det.priority == 201 then
      MiniTest.expect.equality(m[2], 0)  -- row
      MiniTest.expect.equality(m[3], 3)  -- col (tip position)
      cursor_tip_found = true
    end
  end
  assert(extend_found,     'Expected mark with hl_group=VM_Extend')
  assert(cursor_tip_found, 'Expected mark with hl_group=VM_Cursor at priority 201 at (0,3)')
end

-- 7. zero-width extend region (anchor == tip) falls back to cursor-mode single char
T_redraw['zero-width extend region falls back to cursor-mode single char'] = function()
  local hl     = require('visual-multi.highlight')
  local Region = require('visual-multi.region')

  -- Anchor == tip at (0,2)
  local r = Region.new(buf, 0, 2, 'extend', {0, 2})
  local session = fake_session(buf, { r }, 1, true)
  hl.redraw(session)

  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, { details = true })
  local extend_found, cursor_found = false, false
  for _, m in ipairs(marks) do
    local det = m[4]
    if det.hl_group and det.hl_group:find('Extend') then
      extend_found = true
    end
    if det.hl_group == 'VM_Cursor' then
      MiniTest.expect.equality(m[2], 0)
      MiniTest.expect.equality(m[3], 2)
      cursor_found = true
    end
  end
  assert(not extend_found, 'Expected NO Extend mark for zero-width region')
  assert(cursor_found,     'Expected VM_Cursor mark at (0,2)')
end

return T
