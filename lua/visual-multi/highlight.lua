--- vim-visual-multi highlight module
--- Provides: ns, define_groups, draw_cursor, draw_selection, clear, clear_region
--- Tier-0: no requires to any other visual-multi module at module load time.
--- clear() lazy-requires visual-multi.util for is_session dispatch only.

local M = {}

--- Single shared namespace for all VM extmarks (idempotent by name).
---@type integer
M.ns = vim.api.nvim_create_namespace('visual_multi')

--- Define all VM highlight groups with default=true so user colorschemes win.
--- Call once on plugin setup (or lazy on first use).
function M.define_groups()
  vim.api.nvim_set_hl(0, 'VMCursor', { default = true, link = 'Cursor' })
  vim.api.nvim_set_hl(0, 'VMExtend', { default = true, link = 'Visual' })
  vim.api.nvim_set_hl(0, 'VMInsert', { default = true, link = 'DiffChange' })
  vim.api.nvim_set_hl(0, 'VMSearch', { default = true, link = 'Search' })
end

--- Place or update a cursor extmark at (row, col).
--- Pass nil as mark_id on first call; pass the returned id on subsequent calls
--- to update in-place (same mark_id, no delete-and-recreate).
---@param buf integer buffer handle
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@param mark_id integer|nil nil = create new; integer = update in place
---@return integer mark_id the extmark id
function M.draw_cursor(buf, row, col, mark_id)
  return vim.api.nvim_buf_set_extmark(buf, M.ns, row, col, {
    id       = mark_id,
    end_row  = row,
    end_col  = col + 1,
    hl_group = 'VMCursor',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
end

--- Place or update a selection extmark spanning scol to ecol on row.
---@param buf integer buffer handle
---@param row integer 0-indexed row
---@param scol integer 0-indexed start column
---@param ecol integer 0-indexed end column (exclusive)
---@param mark_id integer|nil nil = create new; integer = update in place
---@return integer mark_id the extmark id
function M.draw_selection(buf, row, scol, ecol, mark_id)
  return vim.api.nvim_buf_set_extmark(buf, M.ns, row, scol, {
    id       = mark_id,
    end_row  = row,
    end_col  = ecol,
    hl_group = 'VMExtend',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
end

--- Clear all VM extmarks from a buffer.
--- Accepts either a raw bufnr (integer) or a session table (via is_session dispatch).
--- IMPORTANT: Do NOT require('visual-multi.region') here — that would create a circular
--- dependency (PITFALL-07). util.lua is Tier-0 safe to require.
---@param session_or_buf integer|table bufnr or session with .buf field
function M.clear(session_or_buf)
  local util = require('visual-multi.util')
  local buf = util.is_session(session_or_buf) and session_or_buf.buf
              or session_or_buf
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
end

--- Delete a single extmark by id (pcall-wrapped: safe if already deleted).
---@param buf integer buffer handle
---@param mark_id integer extmark id
function M.clear_region(buf, mark_id)
  pcall(vim.api.nvim_buf_del_extmark, buf, M.ns, mark_id)
end

return M
