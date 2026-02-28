--- vim-visual-multi region module
--- Provides: Region.new (with :pos, :move, :remove methods)
--- Tier-1: depends on visual-multi.highlight (for ns). No reverse dependency allowed.

local M = {}

local Region = {}
Region.__index = Region

--- Create a new cursor-mode region at (row, col) in buf.
--- row, col are 0-indexed (Neovim API convention).
--- The extmark is stored on the region and used for in-place updates.
---@param buf integer buffer handle
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@return Region
function Region.new(buf, row, col)
  local hl = require('visual-multi.highlight')
  local r = setmetatable({ buf = buf, _stopped = false }, Region)
  r.mark_id = vim.api.nvim_buf_set_extmark(buf, hl.ns, row, col, {
    end_row  = row,
    end_col  = col + 1,
    hl_group = 'VMCursor',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
  return r
end

--- Return current extmark position as 0-indexed (row, col).
--- Reads back directly from the extmark tree — always current.
---@return integer row, integer col
function Region:pos()
  local hl = require('visual-multi.highlight')
  local info = vim.api.nvim_buf_get_extmark_by_id(
    self.buf, hl.ns, self.mark_id, {}
  )
  return info[1], info[2]
end

--- Move the extmark to a new (row, col) in place (same mark_id).
--- Uses the id= parameter for O(log n) update — no delete-and-recreate.
---@param row integer 0-indexed row
---@param col integer 0-indexed column
function Region:move(row, col)
  local hl = require('visual-multi.highlight')
  vim.api.nvim_buf_set_extmark(self.buf, hl.ns, row, col, {
    id       = self.mark_id,
    end_row  = row,
    end_col  = col + 1,
    hl_group = 'VMCursor',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
end

--- Remove this region's extmark from the buffer and mark as stopped.
--- pcall-wrapped so it is safe to call even if the buffer was wiped.
function Region:remove()
  local hl = require('visual-multi.highlight')
  pcall(vim.api.nvim_buf_del_extmark, self.buf, hl.ns, self.mark_id)
  self._stopped = true
end

M.new = Region.new
return M
