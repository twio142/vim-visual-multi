--- vim-visual-multi edit module
--- Phase 4 — Normal-mode operations at all cursors simultaneously.
--- Tier-3: depends on session (Tier-2), highlight/region (Tier-1), undo (Tier-1).
---
--- All exported functions accept a session table as their first argument.
--- session._vm_register: list of {text=string, type=string}, indexed by cursor position order.
--- session._vm_dot:      string — last exec'd keys, replayed by M.dot().

local M = {}

--- Sort active cursor indices bottom-to-top (descending row, then descending col).
--- Reads positions live from extmarks inside the loop — never cache before looping.
--- This order prevents earlier deletions from shifting positions of later-line cursors.
---@param session table
---@return integer[] ordered list of active cursor indices
local function _bottom_to_top(session)
  -- stub: Plan 02 implements
  return {}
end

--- Sort active cursor indices top-to-bottom (ascending row).
--- Used only by g<C-a> / g<C-x> where sequential steps go first-to-last visible line.
---@param session table
---@return integer[] ordered list of active cursor indices
local function _top_to_bottom(session)
  -- stub: Plan 02 implements
  return {}
end

--- Execute a normal-mode key string at all cursors.
--- Processing order: bottom-to-top (PITFALL: prevents position drift after deletions).
--- Wraps the entire loop in undo.begin_block/end_block for single-undo-entry guarantee.
--- Brackets vim.o.eventignore='all' around the loop; restores in pcall finally (PITFALL-02).
--- Stores keys in session._vm_dot for dot-repeat.
---@param session table
---@param keys    string  Normal-mode keystrokes (raw; nvim_replace_termcodes applied internally)
function M.exec(session, keys)
  -- stub: Plan 02 implements
end

--- Yank at all cursors into the per-cursor VM register (session._vm_register).
--- Does NOT use the general exec() loop — captures register content per cursor.
--- Reads unnamed register immediately after each cursor's yank feedkey.
---@param session table
function M.yank(session)
  -- stub: Plan 02 implements
end

--- Paste at all cursors using per-cursor VM register with Vim register fallback.
--- If session._vm_register is empty, all cursors paste from the Vim unnamed register.
--- Each cursor injects its own entry into the unnamed register before the paste feedkey.
---@param session table
---@param before  boolean true = P (paste before cursor), false = p (paste after)
function M.paste(session, before)
  -- stub: Plan 02 implements
end

--- Replay the last exec'd keys (dot-repeat).
--- Reads session._vm_dot; calls M.exec with that string.
---@param session table
function M.dot(session)
  if session._vm_dot then
    M.exec(session, session._vm_dot)
  end
end

--- Sequential increment/decrement at all cursors (g<C-a> / g<C-x>).
--- Top-to-bottom order: cursor on lowest line gets step +1, next gets +2, etc.
--- Each cursor receives `step` repetitions of <C-a> or <C-x> relative to its own value.
---@param session   table
---@param direction integer  1 for increment (g<C-a>), -1 for decrement (g<C-x>)
function M.g_increment(session, direction)
  -- stub: Plan 03 implements
end

return M
