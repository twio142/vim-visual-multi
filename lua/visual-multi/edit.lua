--- vim-visual-multi edit module
--- Phase 4 — Normal-mode operations at all cursors simultaneously.
--- Tier-3: depends on session (Tier-2), highlight/region (Tier-1), undo (Tier-1).
---
--- All exported functions accept a session table as their first argument.
--- session._vm_register: list of {text=string, type=string}, indexed by cursor position order.
--- session._vm_dot:      string — last exec'd keys, replayed by M.dot().
---
--- Load-order note: undo and highlight are required at the top of this file.
--- edit.lua is Tier-3 — it is loaded after session (Tier-2) which is loaded after
--- highlight/region (Tier-1). No circular dependency is introduced by top-level requires here.

local M = {}

local undo = require('visual-multi.undo')
local hl   = require('visual-multi.highlight')

--- Sort active cursor indices bottom-to-top (descending row, then descending col).
--- Reads positions live from extmarks inside the loop — never cache before looping.
--- This order prevents earlier deletions from shifting positions of later-line cursors.
---@param session table
---@return integer[] ordered list of active cursor indices
local function _bottom_to_top(session)
  local order = {}
  for i = 1, #session.cursors do
    if not session.cursors[i]._stopped then
      order[#order + 1] = i
    end
  end
  table.sort(order, function(a, b)
    local ra, ca = session.cursors[a]:pos()
    local rb, cb = session.cursors[b]:pos()
    if ra ~= rb then return ra > rb end
    return ca > cb
  end)
  return order
end

--- Sort active cursor indices top-to-bottom (ascending row).
--- Used only by g<C-a> / g<C-x> where sequential steps go first-to-last visible line.
---@param session table
---@return integer[] ordered list of active cursor indices
local function _top_to_bottom(session)
  local order = {}
  for i = 1, #session.cursors do
    if not session.cursors[i]._stopped then
      order[#order + 1] = i
    end
  end
  table.sort(order, function(a, b)
    local ra, ca = session.cursors[a]:pos()
    local rb, cb = session.cursors[b]:pos()
    if ra ~= rb then return ra < rb end
    return ca < cb
  end)
  return order
end

--- Execute a normal-mode key string at all cursors.
--- Processing order: bottom-to-top (PITFALL: prevents position drift after deletions).
--- Wraps the entire loop in undo.begin_block/end_block for single-undo-entry guarantee.
--- Uses undojoin between cursors to merge per-cursor edits into one undo entry.
--- Brackets vim.o.eventignore='all' around the loop; restores in pcall finally (PITFALL-02).
--- Stores keys in session._vm_dot for dot-repeat.
---@param session table
---@param keys    string  Normal-mode keystrokes (raw; nvim_replace_termcodes applied internally)
function M.exec(session, keys)
  -- Guard: no-op on stopped session or empty cursors list
  if session._stopped or #session.cursors == 0 then return end

  -- Encode termcodes once (reused for every cursor in the loop)
  local encoded = vim.api.nvim_replace_termcodes(keys, true, false, true)

  -- Save eventignore so we can restore it even if the loop errors
  local saved_ei = vim.o.eventignore

  local ok, err = pcall(function()
    vim.o.eventignore = 'all'
    undo.begin_block(session)
    local order = _bottom_to_top(session)
    local first = true
    for _, idx in ipairs(order) do
      local r = session.cursors[idx]
      if not r._stopped then
        local row, col = r:pos()   -- 0-indexed from extmark
        -- PITFALL-04: nvim_win_set_cursor expects 1-indexed row
        pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
        -- Join subsequent cursor edits into the first undo entry so that a single
        -- `u` undoes all cursor changes atomically (FEAT-06 undo grouping contract).
        -- undojoin is wrapped in pcall to handle invalid-context cases (e.g. after redo).
        if not first then
          vim.api.nvim_buf_call(session.buf, function()
            pcall(vim.cmd, 'silent! undojoin')
          end)
        end
        -- PITFALL-03: 'x' mode = execute immediately (synchronous)
        pcall(vim.api.nvim_feedkeys, encoded, 'x', false)
        first = false
      end
    end
    undo.end_block(session)
  end)

  -- PITFALL-02: ALWAYS restore eventignore, even on error
  vim.o.eventignore = saved_ei

  if not ok then
    vim.notify('[vim-visual-multi] exec error: ' .. tostring(err), vim.log.levels.WARN)
  end

  -- Store for dot-repeat
  session._vm_dot = keys

  -- Redraw all cursor highlights to reflect new positions
  hl.redraw(session)
end

--- Yank at all cursors into the per-cursor VM register (session._vm_register).
--- Does NOT use the general exec() loop — captures register content per cursor.
--- Reads unnamed register immediately after each cursor's yank feedkey.
--- Default motion: yiw (word under cursor). Phase 6 adds operator-pending capture.
---@param session table
function M.yank(session)
  -- Guard: no-op on stopped session or empty cursors list
  if session._stopped or #session.cursors == 0 then return end

  local saved_ei = vim.o.eventignore

  pcall(function()
    vim.o.eventignore = 'all'
    session._vm_register = session._vm_register or {}
    local encoded_yiw = vim.api.nvim_replace_termcodes('yiw', true, false, true)
    local order = _bottom_to_top(session)
    for _, idx in ipairs(order) do
      local r = session.cursors[idx]
      if not r._stopped then
        local row, col = r:pos()
        pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
        -- Clear unnamed register so we detect exactly what this cursor yanked
        vim.fn.setreg('"', '')
        pcall(vim.api.nvim_feedkeys, encoded_yiw, 'x', false)
        session._vm_register[idx] = {
          text = vim.fn.getreg('"'),
          type = vim.fn.getregtype('"'),
        }
      end
    end
  end)

  vim.o.eventignore = saved_ei

  -- Store for dot-repeat
  session._vm_dot = 'yiw'

  hl.redraw(session)
end

--- Paste at all cursors using per-cursor VM register with Vim register fallback.
--- If session._vm_register is empty, all cursors paste from the Vim unnamed register.
--- Each cursor injects its own entry into the unnamed register before the paste feedkey.
---@param session table
---@param before  boolean true = P (paste before cursor), false = p (paste after)
function M.paste(session, before)
  -- Guard: no-op on stopped session or empty cursors list
  if session._stopped or #session.cursors == 0 then return end

  local use_vm_reg = session._vm_register and #session._vm_register > 0

  local saved_ei = vim.o.eventignore
  local paste_keys = before and 'P' or 'p'
  local encoded = vim.api.nvim_replace_termcodes(paste_keys, true, false, true)

  local ok, err = pcall(function()
    vim.o.eventignore = 'all'
    undo.begin_block(session)
    local order = _bottom_to_top(session)
    for _, idx in ipairs(order) do
      local r = session.cursors[idx]
      if not r._stopped then
        local row, col = r:pos()
        pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
        -- Inject per-cursor register text if VM register is populated
        if use_vm_reg and session._vm_register[idx] then
          local entry = session._vm_register[idx]
          vim.fn.setreg('"', entry.text, entry.type)
        end
        pcall(vim.api.nvim_feedkeys, encoded, 'x', false)
      end
    end
    undo.end_block(session)
  end)

  vim.o.eventignore = saved_ei

  if not ok then
    vim.notify('[vim-visual-multi] paste error: ' .. tostring(err), vim.log.levels.WARN)
  end

  session._vm_dot = paste_keys

  hl.redraw(session)
end

--- Replay the last exec'd keys (dot-repeat).
--- Reads session._vm_dot; calls M.exec with that string.
---@param session table
function M.dot(session)
  if session._vm_dot then
    M.exec(session, session._vm_dot)
  end
end

--- Delete half of the 'c' (change) operator using a black-hole register.
--- Executes '"_d' .. motion at all cursors via M.exec, avoiding insert-mode entry at
--- each cursor position.
--- Phase 5 will handle insert-mode entry and keystroke replication from the final cursor.
--- Phase 6 keymap wiring will call M.change directly.
---@param session table
---@param motion  string  Normal-mode motion string (e.g. 'w', 'e', '$')
local function _exec_change(session, motion)
  -- Delete half of 'c': uses black-hole register to avoid insert mode at each cursor.
  -- Phase 5 will handle insert-mode entry and keystroke replication from the final cursor.
  -- The 'c' keymap (Phase 6) will call _exec_change; for now it is accessible via:
  M.exec(session, '"_d' .. motion)
end
M.change = _exec_change  -- exported for Phase 6 keymap wiring

--- Sequential increment/decrement at all cursors (g<C-a> / g<C-x>).
--- Top-to-bottom order: cursor on lowest line gets step +1, next gets +2, etc.
--- Each cursor receives `step` repetitions of <C-a> or <C-x> relative to its own value.
---@param session   table
---@param direction integer  1 for increment (g<C-a>), -1 for decrement (g<C-x>)
function M.g_increment(session, direction)
  if session._stopped then return end
  if #session.cursors == 0 then return end

  local saved_ei = vim.o.eventignore
  local ok, err = pcall(function()
    vim.o.eventignore = 'all'
    undo.begin_block(session)

    local order = _top_to_bottom(session)   -- top-to-bottom for sequential steps
    local first = true
    for step, idx in ipairs(order) do
      local r = session.cursors[idx]
      if not r._stopped then
        local row, col = r:pos()
        pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
        -- Join subsequent cursor edits into the first undo entry so that a single
        -- `u` undoes all cursor changes atomically (FEAT-06 undo grouping contract).
        if not first then
          vim.api.nvim_buf_call(session.buf, function()
            pcall(vim.cmd, 'silent! undojoin')
          end)
        end
        -- step = 1, 2, 3... (1-based ipairs); repeat <C-a>/<C-x> 'step' times
        local key_str
        if direction > 0 then
          key_str = string.rep('<C-a>', step)
        else
          key_str = string.rep('<C-x>', step)
        end
        local encoded = vim.api.nvim_replace_termcodes(key_str, true, false, true)
        pcall(vim.api.nvim_feedkeys, encoded, 'x', false)
        first = false
      end
    end

    undo.end_block(session)
  end)

  vim.o.eventignore = saved_ei  -- ALWAYS restore (PITFALL-02)
  if not ok then
    vim.notify('[visual-multi] g_increment error: ' .. tostring(err), vim.log.levels.WARN)
  end
  session._vm_dot = direction > 0 and 'g\x01' or 'g\x18'  -- g<C-a> or g<C-x>
  hl.redraw(session)
end

--- Toggle case at each cursor (~ key).
--- Thin wrapper around M.exec — inherits undo grouping + eventignore.
---@param session table
function M.case_toggle(session)
  M.exec(session, '~')
end

--- Convert to uppercase at each cursor (gU + word motion).
--- Thin wrapper around M.exec.
---@param session table
---@param motion string  e.g. 'iw', 'w', '$'
function M.case_upper(session, motion)
  M.exec(session, 'gU' .. motion)
end

--- Convert to lowercase at each cursor (gu + word motion).
---@param session table
---@param motion string
function M.case_lower(session, motion)
  M.exec(session, 'gu' .. motion)
end

--- Replace character under each cursor with char.
--- Thin wrapper: feedkeys 'r' + char.
---@param session table
---@param char string  single character to replace with
function M.replace_char(session, char)
  M.exec(session, 'r' .. char)
end

return M
