--- vim-visual-multi configuration module
--- Provides: defaults table, apply(opts), get(), _reset()
--- No inter-plugin dependencies — safe to require from any module.

local M = {}

--- Default configuration values.
--- All top-level keys must appear in KNOWN_KEYS below.
M.defaults = {
  leader            = '<leader>vm',
  live_editing      = true,
  case_setting      = 'smart',
  reindent_filetypes = {},
  filesize_limit    = 1048576, -- 1 MB
  debug             = false,
  highlight = {
    cursor  = 'Visual',
    extend  = 'Visual',
    insert  = 'IncSearch',
    search  = 'Search',
  },
  mappings = {
    basic           = true,
    find_under      = '<C-d>',
    add_cursor_down = '<C-Down>',
    add_cursor_up   = '<C-Up>',
  },
}

--- Set of all valid top-level option keys.
--- Every key present in M.defaults must also appear here.
local KNOWN_KEYS = {
  leader             = true,
  live_editing       = true,
  case_setting       = true,
  reindent_filetypes = true,
  filesize_limit     = true,
  debug              = true,
  highlight          = true,
  mappings           = true,
}

--- Internal config state (nil until apply() is called).
local _cfg = nil

--- Apply user options, deep-merging over existing config.
--- Unknown keys emit a WARN notification; they do NOT abort loading.
--- Type mismatches for known keys raise a hard error via vim.validate or error().
---@param opts table|nil
---@return table merged config
function M.apply(opts)
  opts = opts or {}

  -- Warn on unknown keys (do not error — plugin still loads)
  for k, _ in pairs(opts) do
    if not KNOWN_KEYS[k] then
      vim.notify(
        "visual-multi: unknown option '" .. k .. "'",
        vim.log.levels.WARN
      )
    end
  end

  -- Validate types for known scalar keys (all optional — may be absent)
  vim.validate({
    live_editing   = { opts.live_editing,   'boolean', true },
    filesize_limit = { opts.filesize_limit,  'number',  true },
    debug          = { opts.debug,           'boolean', true },
    case_setting   = { opts.case_setting,    'string',  true },
    leader         = { opts.leader,          'string',  true },
  })

  -- Hard error for mappings with wrong type (not optional — must be table if provided)
  if opts.mappings ~= nil and type(opts.mappings) ~= 'table' then
    error(string.format(
      'visual-multi: setup() mappings must be a table, got %s',
      type(opts.mappings)
    ))
  end

  -- Deep-merge: start from existing config (or defaults) and overlay opts
  _cfg = vim.tbl_deep_extend('force', _cfg or M.defaults, opts)
  return _cfg
end

--- Return the current config, or defaults if apply() has not been called.
---@return table
function M.get()
  return _cfg or M.defaults
end

--- Reset internal state. For test isolation only — do not call from plugin code.
function M._reset()
  _cfg = nil
end

return M
