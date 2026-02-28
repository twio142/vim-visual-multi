--- Tests for lua/visual-multi/config.lua
--- Run with: nvim --headless -u NORC -l test/run_spec.lua
--- MiniTest is set as a global by MiniTest.setup() in the runner.

-- Notification spy state (shared across hooks)
local notified = {}
local _orig_notify = vim.notify

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      notified = {}
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end
    end,
    post_case = function()
      vim.notify = _orig_notify
      require('visual-multi.config')._reset()
    end,
  },
})

-- apply({}) returns a table with a live_editing field
T['apply({}) returns table with live_editing'] = function()
  local cfg = require('visual-multi.config').apply({})
  MiniTest.expect.equality(type(cfg), 'table')
  MiniTest.expect.equality(cfg.live_editing ~= nil, true)
end

-- apply called twice: second call's values win
T['apply twice: second call values win'] = function()
  local config = require('visual-multi.config')
  config.apply({ debug = false })
  local cfg = config.apply({ debug = true })
  MiniTest.expect.equality(cfg.debug, true)
end

-- Unknown key triggers vim.notify WARN (does NOT raise)
T['unknown key emits WARN notification'] = function()
  MiniTest.expect.no_error(function()
    require('visual-multi.config').apply({ totally_unknown_key = 42 })
  end)
  MiniTest.expect.equality(#notified >= 1, true)
  MiniTest.expect.equality(notified[1].level, vim.log.levels.WARN)
  MiniTest.expect.equality(
    notified[1].msg:find('unknown option') ~= nil,
    true
  )
end

-- Wrong type for live_editing raises a hard error
T['wrong type for live_editing raises error'] = function()
  MiniTest.expect.error(function()
    require('visual-multi.config').apply({ live_editing = 'yes' })
  end)
end

-- Wrong type for mappings raises error with specific message format
T['wrong type for mappings raises error with message'] = function()
  MiniTest.expect.error(function()
    require('visual-multi.config').apply({ mappings = 'basic' })
  end, 'mappings must be a table')
end

-- get() returns applied config after apply()
T['get() returns applied config after apply'] = function()
  local config = require('visual-multi.config')
  config.apply({ debug = true })
  local got = config.get()
  MiniTest.expect.equality(type(got), 'table')
  MiniTest.expect.equality(got.debug, true)
end

-- _reset() causes get() to return defaults again
T['_reset() restores defaults'] = function()
  local config = require('visual-multi.config')
  config.apply({ debug = true })
  config._reset()
  local got = config.get()
  -- After reset, get() returns M.defaults (debug default is false)
  MiniTest.expect.equality(got.debug, false)
end

return T
