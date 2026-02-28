-- test/run_spec.lua — headless mini.test runner
-- Usage: nvim --headless -u NORC -l test/run_spec.lua

-- Resolve paths relative to this file's location (the repo root).
-- NOTE: When invoked via `nvim -l`, vim.fn.expand('<sfile>') is empty because
-- the file is not sourced via :source. Use debug.getinfo instead.
local script_path = debug.getinfo(1, 'S').source:sub(2) -- strip leading '@'
local repo_root = vim.fn.fnamemodify(script_path, ':h:h')

-- Add repo root to runtimepath so `require('visual-multi')` resolves
vim.opt.runtimepath:prepend(repo_root)

-- Load mini.test directly via dofile since the module name contains a dot
-- which cannot be used as a Lua module path component.
local mini_test_path = repo_root .. '/test/vendor/mini.test/init.lua'
local MiniTest = dofile(mini_test_path)

-- Collect spec files
local spec_pattern = repo_root .. '/test/spec/*_spec.lua'
local spec_files = vim.fn.glob(spec_pattern, false, true)

if #spec_files == 0 then
  -- No specs yet is acceptable; exit 0 during bootstrap
  vim.cmd('qa!')
end

-- Run all specs. MiniTest.run exits the process with appropriate code.
MiniTest.run({ paths = spec_files })
