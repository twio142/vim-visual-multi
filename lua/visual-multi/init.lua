--- vim-visual-multi public entry point
--- require('visual-multi') loads this module.
--- Internal modules (visual-multi.config, .util, etc.) are private.

local M = {}

-- Active sessions keyed by bufnr.
-- Exposed for test injection: M._sessions = _sessions
local _sessions = {}
M._sessions = _sessions

--- Configure the plugin. May be called multiple times; subsequent calls
--- deep-merge over the existing config (no warning — supports lazy.nvim
--- modular init patterns).
---@param opts table|nil
function M.setup(opts)
  require('visual-multi.config').apply(opts)
end

--- Return the current session state for a buffer, or nil if no session is active.
---@param bufnr integer|nil  defaults to current buffer
---@return table|nil
function M.get_state(bufnr)
  local buf = bufnr or vim.api.nvim_get_current_buf()
  return _sessions[buf]
end

return M
