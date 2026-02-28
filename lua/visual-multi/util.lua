--- vim-visual-multi utility module
--- Provides: is_session, pos2byte, char_at, byte_len, char_len, display_width, deep_equal
--- No inter-plugin dependencies — safe to require from any module.

local M = {}

--- Sentinel: session tables always carry `_stopped` field (bool). Raw bufnr is an integer.
--- Used by every Tier-1 module to dispatch between (session, ...) and (bufnr, ...) call forms.
---@param arg any
---@return boolean true if arg looks like a session table
function M.is_session(arg)
  return type(arg) == 'table' and arg._stopped ~= nil
end

--- Return the byte length of string s.
--- Named function so callers never use bare `#str` in position math (avoids PITFALL-14).
---@param s string
---@return integer
function M.byte_len(s)
  return #s
end

--- Return the character (codepoint) count of string s.
---@param s string
---@return integer
function M.char_len(s)
  return vim.fn.strcharlen(s)
end

--- Return the display cell width of string s (accounts for wide chars, tabs, etc.).
---@param s string
---@return integer
function M.display_width(s)
  return vim.fn.strdisplaywidth(s)
end

--- Convert 1-indexed (line, col) to a 0-indexed absolute byte offset in buf.
--- Uses nvim_buf_get_offset per LUA-03 (nvim_buf_get_offset is the Neovim-native API).
---@param buf integer buffer handle
---@param line integer 1-indexed line number
---@param col integer 1-indexed column (byte position within the line)
---@return integer 0-indexed byte offset
function M.pos2byte(buf, line, col)
  -- nvim_buf_get_offset(buf, row): row is 0-indexed → byte offset of line start
  return vim.api.nvim_buf_get_offset(buf, line - 1) + col - 1
end

--- Return the character at 1-indexed (lnum, col) in buf.
--- Byte-safe: uses vim.fn.matchstr to extract the character at the given column.
---@param buf integer buffer handle
---@param lnum integer 1-indexed line number
---@param col integer 1-indexed column (character position)
---@return string the character, or '' if out of range
function M.char_at(buf, lnum, col)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, true)[1]
  if not line then return '' end
  return vim.fn.matchstr(line, string.format('\\%%%dc.', col))
end

--- Deep equality check. Uses vim.deep_equal when available (Neovim 0.10+),
--- with a fallback for environments where it may not be present.
--- The undo module uses this instead of vim.deep_equal directly.
M.deep_equal = vim.deep_equal or function(a, b)
  return vim.inspect(a) == vim.inspect(b)
end

return M
