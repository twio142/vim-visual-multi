--- vim-visual-multi region module
--- Provides: Region.new (with :pos, :move, :remove methods)
--- Tier-1: depends on visual-multi.highlight (for ns). No reverse dependency allowed.
---
--- Phase-3 data model:
---   sel_mark_id    — extmark tracking the selection tip / cursor cell (integer)
---   anchor_mark_id — extmark tracking the extend-mode anchor (integer or nil)
---   tip_mark_id    — future multi-cell extend tracking (nil by default, Phase 3+)
---   mode           — 'cursor' | 'extend'

local M = {}

local Region = {}
Region.__index = Region

--- Create a new region at (row, col) in buf.
--- row, col are 0-indexed (Neovim API convention).
---
--- Optional parameters (Phase 3 contract):
---   mode   — 'cursor' (default) or 'extend'
---   anchor — {row, col} table for extend-mode anchor; ignored in cursor mode
---
--- The sel_mark_id extmark tracks the cursor tip (right_gravity=true so it moves
--- right on insert). In extend mode an additional anchor_mark_id extmark is placed
--- at anchor position with right_gravity=false (stays left on insert).
---@param buf    integer buffer handle
---@param row    integer 0-indexed row
---@param col    integer 0-indexed column
---@param mode   string|nil 'cursor' or 'extend' (default 'cursor')
---@param anchor table|nil {row, col} for extend-mode anchor
---@return Region
function Region.new(buf, row, col, mode, anchor)
  local hl = require('visual-multi.highlight')
  mode = mode or 'cursor'
  local r = setmetatable({
    buf           = buf,
    _stopped      = false,
    mode          = mode,
    tip_mark_id   = nil,     -- reserved; populated by redraw engine (Phase 3+)
    anchor_mark_id = nil,    -- nil in cursor mode; set below in extend mode
  }, Region)

  -- sel_mark_id: cursor tip / selection highlight. right_gravity=true.
  local sel_hl = (mode == 'extend') and 'VM_ExtendSecondary' or 'VM_CursorSecondary'
  r.sel_mark_id = vim.api.nvim_buf_set_extmark(buf, hl.ns, row, col, {
    end_row       = row,
    end_col       = col + 1,
    hl_group      = sel_hl,
    priority      = 200,
    hl_mode       = 'combine',
    strict        = false,
    right_gravity = true,
  })

  -- anchor_mark_id: invisible tracking mark for extend-mode anchor. right_gravity=false.
  if mode == 'extend' and anchor then
    r.anchor_mark_id = vim.api.nvim_buf_set_extmark(buf, hl.ns, anchor[1], anchor[2], {
      right_gravity = false,
      strict        = false,
    })
  end

  return r
end

--- Return current extmark position as 0-indexed (row, col).
--- Reads back directly from the extmark tree — always current.
---@return integer row, integer col
function Region:pos()
  local hl = require('visual-multi.highlight')
  local info = vim.api.nvim_buf_get_extmark_by_id(
    self.buf, hl.ns, self.sel_mark_id, {}
  )
  return info[1], info[2]
end

--- Move the sel_mark_id extmark to a new (row, col) in place (same id).
--- Uses the id= parameter for O(log n) update — no delete-and-recreate.
--- This is a cursor-mode helper; anchor_mark_id is not touched here.
---@param row integer 0-indexed row
---@param col integer 0-indexed column
function Region:move(row, col)
  local hl = require('visual-multi.highlight')
  vim.api.nvim_buf_set_extmark(self.buf, hl.ns, row, col, {
    id            = self.sel_mark_id,
    end_row       = row,
    end_col       = col + 1,
    hl_group      = 'VM_CursorSecondary',
    priority      = 200,
    hl_mode       = 'combine',
    strict        = false,
    right_gravity = true,
  })
end

--- Remove this region's extmarks from the buffer and mark as stopped.
--- Cleans up sel_mark_id, tip_mark_id (if set), and anchor_mark_id (if set).
--- pcall-wrapped so it is safe to call even if the buffer was wiped.
function Region:remove()
  local hl = require('visual-multi.highlight')
  pcall(vim.api.nvim_buf_del_extmark, self.buf, hl.ns, self.sel_mark_id)
  if self.tip_mark_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, self.buf, hl.ns, self.tip_mark_id)
  end
  if self.anchor_mark_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, self.buf, hl.ns, self.anchor_mark_id)
  end
  self._stopped = true
end

M.new = Region.new
return M
