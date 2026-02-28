--- Tests for lua/visual-multi/session.lua
--- Run with: nvim --headless -u NORC -l test/run_spec.lua
--- MiniTest is set as a global by MiniTest.setup() in the runner.
---
--- Covers: start/stop, reentrancy, option save/restore, keymap save/restore,
---         mode toggle helpers, VMEnter/VMLeave autocmds, BufDelete silent stop.

local buf
local session_mod = require('visual-multi.session')

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- BUG-02: use (false, false) — scratch buffers have undolevels=-1
      buf = vim.api.nvim_create_buf(false, false)
      vim.bo[buf].buftype  = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world' })
      -- Required: win-local option ops target the current window
      vim.api.nvim_set_current_buf(buf)
      -- Reset config to defaults and clear any stale sessions
      require('visual-multi.config')._reset()
      require('visual-multi')._sessions[buf] = nil
    end,
    post_case = function()
      -- Ensure session is fully stopped before buffer deletion
      pcall(session_mod.stop, buf)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  },
})

-- ─── Category A: Session start and registry ───────────────────────────────────

T['start returns a session table'] = function()
  local session = session_mod.start(buf, false)
  MiniTest.expect.equality(type(session), 'table')
  MiniTest.expect.equality(session.buf, buf)
end

T['start registers session in init._sessions'] = function()
  local session = session_mod.start(buf, false)
  local registry = require('visual-multi')._sessions
  MiniTest.expect.equality(registry[buf], session)
end

T['start sets extend_mode = true when initial_mode is true'] = function()
  local session = session_mod.start(buf, true)
  MiniTest.expect.equality(session.extend_mode, true)
end

T['start sets extend_mode = false when initial_mode is false'] = function()
  local session = session_mod.start(buf, false)
  MiniTest.expect.equality(session.extend_mode, false)
end

T['start sets extend_mode = false when initial_mode is nil'] = function()
  local session = session_mod.start(buf, nil)
  MiniTest.expect.equality(session.extend_mode, false)
end

-- ─── Category B: Session stop and teardown ────────────────────────────────────

T['stop removes session from registry'] = function()
  session_mod.start(buf, false)
  session_mod.stop(buf)
  MiniTest.expect.equality(require('visual-multi')._sessions[buf], nil)
end

T['stop sets _stopped = true on session table'] = function()
  local session = session_mod.start(buf, false)
  session_mod.stop(buf)
  -- The local ref still points to the (now stopped) table
  MiniTest.expect.equality(session._stopped, true)
end

T['stop is idempotent (second call is a no-op)'] = function()
  session_mod.start(buf, false)
  session_mod.stop(buf)
  -- Should not error on second call
  local ok, err = pcall(session_mod.stop, buf)
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(err, nil)
end

-- ─── Category C: Option save/restore ─────────────────────────────────────────

T['stop restores virtualedit to pre-session value'] = function()
  local original = vim.o.virtualedit
  session_mod.start(buf, false)
  -- Session sets virtualedit = 'onemore'
  MiniTest.expect.equality(vim.o.virtualedit, 'onemore')
  session_mod.stop(buf)
  MiniTest.expect.equality(vim.o.virtualedit, original)
end

T['stop restores conceallevel to pre-session value'] = function()
  local win = vim.api.nvim_get_current_win()
  -- Set a non-zero conceallevel before starting session
  vim.api.nvim_win_set_option(win, 'conceallevel', 2)
  session_mod.start(buf, false)
  -- Session sets conceallevel = 0
  MiniTest.expect.equality(vim.api.nvim_win_get_option(win, 'conceallevel'), 0)
  session_mod.stop(buf)
  MiniTest.expect.equality(vim.api.nvim_win_get_option(win, 'conceallevel'), 2)
end

T['stop restores guicursor to pre-session value'] = function()
  local original = vim.o.guicursor
  session_mod.start(buf, false)
  session_mod.stop(buf)
  MiniTest.expect.equality(vim.o.guicursor, original)
end

-- ─── Category D: Reentrancy guard (PITFALL-11) ────────────────────────────────

T['start on already-active session returns the same session table'] = function()
  local s1 = session_mod.start(buf, false)
  local s2 = session_mod.start(buf, false)
  -- Identity equality: same Lua table reference
  MiniTest.expect.equality(s1 == s2, true)
end

T['double-start does not double-register: one stop fully removes session'] = function()
  session_mod.start(buf, false)
  session_mod.start(buf, false)  -- should be a no-op reentrancy return
  session_mod.stop(buf)
  MiniTest.expect.equality(require('visual-multi')._sessions[buf], nil)
end

-- ─── Category E: Mode toggle (FEAT-03) ───────────────────────────────────────

T['toggle_mode flips extend_mode from false to true'] = function()
  local session = session_mod.start(buf, false)
  session_mod.toggle_mode(session)
  MiniTest.expect.equality(session.extend_mode, true)
end

T['toggle_mode flips extend_mode from true to false'] = function()
  local session = session_mod.start(buf, true)
  session_mod.toggle_mode(session)
  MiniTest.expect.equality(session.extend_mode, false)
end

T['set_cursor_mode sets extend_mode to false when it was true'] = function()
  local session = session_mod.start(buf, true)
  session_mod.set_cursor_mode(session)
  MiniTest.expect.equality(session.extend_mode, false)
end

T['set_cursor_mode is idempotent when extend_mode is already false'] = function()
  local session = session_mod.start(buf, false)
  session_mod.set_cursor_mode(session)
  MiniTest.expect.equality(session.extend_mode, false)
end

T['set_extend_mode sets extend_mode to true when it was false'] = function()
  local session = session_mod.start(buf, false)
  session_mod.set_extend_mode(session)
  MiniTest.expect.equality(session.extend_mode, true)
end

T['set_extend_mode is idempotent when extend_mode is already true'] = function()
  local session = session_mod.start(buf, true)
  session_mod.set_extend_mode(session)
  MiniTest.expect.equality(session.extend_mode, true)
end

T['set_mode sets extend_mode unconditionally'] = function()
  local session = session_mod.start(buf, false)
  session_mod.set_mode(session, true)
  MiniTest.expect.equality(session.extend_mode, true)
  session_mod.set_mode(session, false)
  MiniTest.expect.equality(session.extend_mode, false)
end

-- ─── Category F: Lifecycle events ────────────────────────────────────────────

T['VMEnter fires on start with correct bufnr'] = function()
  local captured_data = nil
  local autocmd_id = vim.api.nvim_create_autocmd('User', {
    pattern  = 'VMEnter',
    once     = true,
    callback = function(ev)
      captured_data = ev.data
    end,
  })

  session_mod.start(buf, false)

  -- Clean up if autocmd wasn't consumed (e.g., test failure path)
  pcall(vim.api.nvim_del_autocmd, autocmd_id)

  MiniTest.expect.equality(type(captured_data), 'table')
  MiniTest.expect.equality(captured_data.bufnr, buf)
end

T['VMLeave fires on stop with correct bufnr'] = function()
  local captured_data = nil
  session_mod.start(buf, false)

  local autocmd_id = vim.api.nvim_create_autocmd('User', {
    pattern  = 'VMLeave',
    once     = true,
    callback = function(ev)
      captured_data = ev.data
    end,
  })

  session_mod.stop(buf)

  pcall(vim.api.nvim_del_autocmd, autocmd_id)

  MiniTest.expect.equality(type(captured_data), 'table')
  MiniTest.expect.equality(captured_data.bufnr, buf)
end

-- ─── Category G: Keymap save/restore (PITFALL-09) ────────────────────────────

T['stop removes v keymap installed by session'] = function()
  session_mod.start(buf, false)
  session_mod.stop(buf)

  -- After stop, no VM v-key binding should exist in this buffer
  local mapping
  vim.api.nvim_buf_call(buf, function()
    mapping = vim.fn.maparg('v', 'n', false, true)
  end)
  -- An empty dict (no lhs) means no mapping — VM's binding was removed
  MiniTest.expect.equality(mapping.lhs == nil or mapping.lhs == '', true)
end

T['stop restores pre-existing v keymap if one existed'] = function()
  -- Install a user mapping for v on this buffer before session
  vim.keymap.set('n', 'v', function() end, {
    buffer = buf,
    desc   = 'user-v-test',
    silent = true,
  })

  -- Capture what was there before
  local before_mapping
  vim.api.nvim_buf_call(buf, function()
    before_mapping = vim.fn.maparg('v', 'n', false, true)
  end)

  session_mod.start(buf, false)  -- VM overwrites v

  -- VM's v mapping is now active
  local during_mapping
  vim.api.nvim_buf_call(buf, function()
    during_mapping = vim.fn.maparg('v', 'n', false, true)
  end)
  -- During session the mapping desc may differ (VM installs its own)
  -- Just verify a mapping exists (VM's)
  MiniTest.expect.equality(during_mapping.lhs ~= nil and during_mapping.lhs ~= '', true)

  session_mod.stop(buf)

  -- After stop, the original user mapping should be restored
  local after_mapping
  vim.api.nvim_buf_call(buf, function()
    after_mapping = vim.fn.maparg('v', 'n', false, true)
  end)
  MiniTest.expect.equality(after_mapping.desc, 'user-v-test')
end

return T
