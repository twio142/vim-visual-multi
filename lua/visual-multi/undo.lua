--- vim-visual-multi undo grouping
--- Wraps multi-cursor edits in atomic undo blocks.
--- Bug guard references:
---   BUG-02: Test buffers must be (false, false) — not scratch — for undo to work
---   BUG-03: Use vim.bo[buf].undolevels, NOT vim.o.undolevels
---   BUG-04: Short-circuit end_block if content unchanged to avoid spurious undo entry

local M = {}

--- Begin an undo block for a session.
--- Records the current undo sequence number and buffer content snapshot.
---@param session table  Must have `.buf` (bufnr integer)
function M.begin_block(session)
  vim.api.nvim_buf_call(session.buf, function()
    session._undo_seq_before = vim.fn.undotree().seq_cur
    session._undo_lines_before = vim.api.nvim_buf_get_lines(
      session.buf, 0, -1, false
    )
  end)
end

--- End an undo block for a session.
--- BUG-04: Short-circuits if content is unchanged — avoids advancing seq_cur
--- on no-op operations (e.g., search with no results).
---@param session table
function M.end_block(session)
  local lines_after = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
  local util = require('visual-multi.util')
  if util.deep_equal(session._undo_lines_before, lines_after) then
    -- No content change — clear state, do NOT create undo entry (BUG-04 guard)
    session._undo_seq_before = nil
    session._undo_lines_before = nil
    return
  end
  vim.api.nvim_buf_call(session.buf, function()
    session._undo_seq_after = vim.fn.undotree().seq_cur
  end)
  session._undo_lines_before = nil
end

--- Convenience wrapper: calls begin_block, runs fn(session), then end_block.
--- Returns the return value of fn.
---@param session table
---@param fn function
---@return any
function M.with_undo_block(session, fn)
  M.begin_block(session)
  local result = fn(session)
  M.end_block(session)
  return result
end

--- Flush the undo history of a buffer into a single entry.
--- Used to consolidate all per-cursor edits into one undoable unit.
--- BUG-03: Uses vim.bo[buf].undolevels (buffer-local), NOT vim.o.undolevels (global).
--- Design note: Uses 'silent! undojoin' rather than a no-op nvim_buf_set_lines call —
--- undojoin avoids modifying buffer content. Wrapped in pcall to handle cases where
--- undojoin is invalid (e.g., after a redo), which would otherwise raise an error.
---@param buf integer
function M.flush_undo_history(buf)
  -- BUG-03: buffer-local undolevels, never vim.o.undolevels
  local saved = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  -- Apply undojoin to force undo history flush; pcall guards against redo-context errors
  vim.api.nvim_buf_call(buf, function()
    pcall(vim.cmd, 'silent! undojoin')
  end)
  vim.bo[buf].undolevels = saved
end

return M
