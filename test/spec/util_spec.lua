--- Tests for lua/visual-multi/util.lua
--- Run with: nvim --headless -u NORC -l test/run_spec.lua
--- MiniTest is set as a global by MiniTest.setup() in the runner.

local T = MiniTest.new_set()

local util = require('visual-multi.util')

-- is_session: table with _stopped=false is a session
T['is_session: table with _stopped=false returns true'] = function()
  MiniTest.expect.equality(util.is_session({ buf = 1, _stopped = false }), true)
end

-- is_session: table with _stopped=true is still a session (stopped, but session)
T['is_session: table with _stopped=true returns true'] = function()
  MiniTest.expect.equality(util.is_session({ buf = 1, _stopped = true }), true)
end

-- is_session: integer bufnr is not a session
T['is_session: integer returns false'] = function()
  MiniTest.expect.equality(util.is_session(1), false)
end

-- is_session: table without _stopped field is not a session
T['is_session: table without _stopped returns false'] = function()
  MiniTest.expect.equality(util.is_session({ buf = 1 }), false)
end

-- byte_len: ASCII string
T['byte_len: hello returns 5'] = function()
  MiniTest.expect.equality(util.byte_len('hello'), 5)
end

-- byte_len: multibyte string (é is 2 bytes in UTF-8)
T['byte_len: héllo returns 6'] = function()
  MiniTest.expect.equality(util.byte_len('héllo'), 6)
end

-- char_len: multibyte string has 5 characters
T['char_len: héllo returns 5'] = function()
  MiniTest.expect.equality(util.char_len('héllo'), 5)
end

-- display_width: ASCII string
T['display_width: hello returns 5'] = function()
  MiniTest.expect.equality(util.display_width('hello'), 5)
end

-- pos2byte: line 2 col 1 in 'abc\ndef' → offset 4
T['pos2byte: line2,col1 in abc/def buffer returns 4'] = function()
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'abc', 'def' })
  -- Line 2, col 1: offset = offset_of_line_2_start + 0 = 4 (after 'abc\n')
  MiniTest.expect.equality(util.pos2byte(buf, 2, 1), 4)
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- char_at: first char of first line
T['char_at: buf line1 col1 returns a'] = function()
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'abc', 'def' })
  MiniTest.expect.equality(util.char_at(buf, 1, 1), 'a')
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- deep_equal: equal tables
T['deep_equal: {1,2} equals {1,2}'] = function()
  MiniTest.expect.equality(util.deep_equal({ 1, 2 }, { 1, 2 }), true)
end

-- deep_equal: different tables
T['deep_equal: {1} does not equal {2}'] = function()
  MiniTest.expect.equality(util.deep_equal({ 1 }, { 2 }), false)
end

return T
