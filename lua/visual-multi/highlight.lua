--- vim-visual-multi highlight module
--- Provides: ns, define_groups, draw_cursor, draw_selection, clear, clear_region, redraw
--- Tier-0: no requires to any other visual-multi module at module load time.
--- clear() lazy-requires visual-multi.util for is_session dispatch only.
---
--- Phase-3 highlight groups (VM_ prefix):
---   VM_Cursor          — primary cursor (cursor mode)
---   VM_CursorSecondary — secondary cursors (cursor mode)
---   VM_Extend          — primary selection (extend mode)
---   VM_ExtendSecondary — secondary selections (extend mode)
---   VM_Insert          — insert mode indicator (Phase 5+)
---   VM_Search          — search match highlight (Phase 6+)

local M = {}

--- Single shared namespace for all VM extmarks (idempotent by name).
---@type integer
M.ns = vim.api.nvim_create_namespace('visual_multi')

--- Define all VM highlight groups with default=true so user colorschemes win.
--- Call once on plugin setup (or lazy on first use).
--- Groups use VM_ prefix (Phase 3 contract) for namespacing and clarity.
function M.define_groups()
  -- Cursor mode
  vim.api.nvim_set_hl(0, 'VM_Cursor',          { default = true, link = 'Visual'    })
  vim.api.nvim_set_hl(0, 'VM_CursorSecondary', { default = true, link = 'Cursor'    })
  -- Extend mode
  vim.api.nvim_set_hl(0, 'VM_Extend',          { default = true, link = 'PmenuSel'  })
  vim.api.nvim_set_hl(0, 'VM_ExtendSecondary', { default = true, link = 'PmenuSbar' })
  -- Reserved for Phase 5 and Phase 6 (defined now so colorscheme links work)
  vim.api.nvim_set_hl(0, 'VM_Insert',          { default = true, link = 'DiffChange'})
  vim.api.nvim_set_hl(0, 'VM_Search',          { default = true, link = 'Search'    })
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
    hl_group = 'VM_CursorSecondary',
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
    hl_group = 'VM_ExtendSecondary',
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

--- Return the byte offset of the character AFTER the character at (row, col).
--- Handles empty lines, EOL positions, and multibyte characters (CJK, accented, etc.).
--- PITFALL-14: `col + 1` is wrong for multibyte — always use this for single-char spans.
---@param buf integer buffer handle
---@param row integer 0-indexed row
---@param col integer 0-indexed byte column
---@return integer end_col (exclusive, safe as nvim_buf_set_extmark end_col)
local function _col_end(buf, row, col)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line or #line == 0 or col >= #line then
    return col + 1  -- EOL or empty: strict=false handles out-of-bounds
  end
  local char = vim.fn.matchstr(line, '.', col)  -- char at byte offset col (multibyte-aware)
  local bw = #char
  return col + (bw > 0 and bw or 1)
end

--- Draw a single-char highlight for a cursor-mode region.
--- Uses temp fields _tip_row/_tip_col pre-loaded by redraw() before the clear.
--- Stores new extmark id back on region.sel_mark_id.
---@param region table Region object (with ._tip_row, ._tip_col, .buf, .sel_mark_id)
---@param is_primary boolean true = VM_Cursor; false = VM_CursorSecondary
local function _draw_cursor_region(region, is_primary)
  local hl_group = is_primary and 'VM_Cursor' or 'VM_CursorSecondary'
  local row, col = region._tip_row, region._tip_col
  region.sel_mark_id = vim.api.nvim_buf_set_extmark(region.buf, M.ns, row, col, {
    end_row       = row,
    end_col       = _col_end(region.buf, row, col),
    hl_group      = hl_group,
    priority      = 200,
    hl_mode       = 'combine',
    strict        = false,
    right_gravity = true,
  })
  region.tip_mark_id = nil
end

--- Draw extend-mode dual-extmark layout for a region.
--- Uses temp fields _tip_row/_tip_col/_anc_row/_anc_col pre-loaded by redraw().
--- Zero-width fallback: if anchor == tip, delegates to _draw_cursor_region.
--- Selection span: anchor→tip (or reverse if backwards), priority 200.
--- Cursor-tip overlay: single-char at tip position, priority 201.
--- Recreates anchor tracking mark (right_gravity=false) to preserve position tracking.
---@param region table Region object (with temp position fields, .buf)
---@param is_primary boolean true = VM_Extend/VM_Cursor; false = VM_ExtendSecondary/VM_CursorSecondary
local function _draw_extend_region(region, is_primary)
  local sel_hl = is_primary and 'VM_Extend'  or 'VM_ExtendSecondary'
  local tip_hl = is_primary and 'VM_Cursor'  or 'VM_CursorSecondary'

  local tip_row, tip_col = region._tip_row, region._tip_col
  local anc_row, anc_col = region._anc_row, region._anc_col

  -- Zero-width fallback: anchor == tip → render as cursor (not invisible)
  if tip_row == anc_row and tip_col == anc_col then
    _draw_cursor_region(region, is_primary)
    return
  end

  -- Selection span: always from min(anchor, tip) to max(anchor, tip)
  local start_row, start_col, end_row, end_col
  if anc_row < tip_row or (anc_row == tip_row and anc_col <= tip_col) then
    start_row, start_col = anc_row, anc_col
    end_row,   end_col   = tip_row, _col_end(region.buf, tip_row, tip_col)
  else
    start_row, start_col = tip_row, tip_col
    end_row,   end_col   = anc_row, _col_end(region.buf, anc_row, anc_col)
  end

  region.sel_mark_id = vim.api.nvim_buf_set_extmark(region.buf, M.ns,
    start_row, start_col, {
      end_row  = end_row,
      end_col  = end_col,
      hl_group = sel_hl,
      priority = 200,
      hl_mode  = 'combine',
      strict   = false,
    })

  -- Cursor-tip overlay at priority 201 so it appears on top of the selection span
  region.tip_mark_id = vim.api.nvim_buf_set_extmark(region.buf, M.ns,
    tip_row, tip_col, {
      end_row  = tip_row,
      end_col  = _col_end(region.buf, tip_row, tip_col),
      hl_group = tip_hl,
      priority = 201,
      hl_mode  = 'combine',
      strict   = false,
    })

  -- Recreate anchor tracking mark (right_gravity=false: stays left on insert-before)
  region.anchor_mark_id = vim.api.nvim_buf_set_extmark(region.buf, M.ns,
    anc_row, anc_col, {
      right_gravity = false,
      strict        = false,
    })
end

--- Redraw all regions in a session with correct primary/secondary highlight groups.
--- Uses read-then-clear-then-draw order to avoid reading stale IDs after clear_namespace.
---
--- Phase 1: Read all current extmark positions (marks still valid).
--- Phase 2: Atomic clear of the entire VM namespace (one call, no ghost marks).
--- Phase 3: Redraw each active region (cursor or extend mode).
---
--- primary_idx selects which cursor gets VM_Cursor (primary) vs VM_CursorSecondary (others).
---@param session table session table with .buf, ._stopped, .cursors, .primary_idx, .extend_mode
function M.redraw(session)
  if session._stopped then return end
  if #session.cursors == 0 then return end

  -- Phase 1: Read all current positions BEFORE clearing (marks are still valid)
  for _, region in ipairs(session.cursors) do
    if not region._stopped then
      local tip_info = vim.api.nvim_buf_get_extmark_by_id(
        region.buf, M.ns, region.sel_mark_id, {})
      region._tip_row = tip_info[1]
      region._tip_col = tip_info[2]
      if session.extend_mode and region.anchor_mark_id then
        local anc_info = vim.api.nvim_buf_get_extmark_by_id(
          region.buf, M.ns, region.anchor_mark_id, {})
        region._anc_row = anc_info[1]
        region._anc_col = anc_info[2]
      end
    end
  end

  -- Phase 2: Atomic clear (one call; no ghost marks possible)
  vim.api.nvim_buf_clear_namespace(session.buf, M.ns, 0, -1)

  -- Phase 3: Redraw each region with correct primary/secondary group
  local primary_idx = session.primary_idx
  for i, region in ipairs(session.cursors) do
    if not region._stopped then
      local is_primary = (i == primary_idx)
      if session.extend_mode and region.mode == 'extend' then
        _draw_extend_region(region, is_primary)
      else
        _draw_cursor_region(region, is_primary)
      end
    end
  end
end

return M
