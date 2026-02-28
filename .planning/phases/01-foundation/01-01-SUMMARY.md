---
phase: 01-foundation
plan: 01
subsystem: infra
tags: [neovim, lua, mini.test, plugin-bootstrap, test-harness]

# Dependency graph
requires: []
provides:
  - "002-lua-rewrite git branch as clean starting point for Lua rewrite"
  - "plugin/visual-multi.vim: minimal Lua bootstrap shim (version guard + loaded guard + require)"
  - "lua/visual-multi/init.lua: public entry point with setup(), get_state(), _sessions"
  - "test/vendor/mini.test/init.lua: vendored mini.test 2489-line framework"
  - "test/run_spec.lua: headless test runner (nvim --headless -u NORC -l test/run_spec.lua, exits 0)"
  - "test/spec/: tracked empty spec directory (.gitkeep) for future specs"
affects: [02-config-util, 03-highlight, 04-region-undo, 05-session, 06-keymaps, 07-operators, 08-integration]

# Tech tracking
tech-stack:
  added: [mini.test (vendored from echasnovski/mini.nvim)]
  patterns:
    - "Plugin bootstrap shim: plugin/*.vim = version guard only, all logic in Lua"
    - "Test runner: nvim --headless -u NORC -l test/run_spec.lua pattern"
    - "mini.test loaded via dofile() due to dot in directory name (mini.test) preventing require()"
    - "debug.getinfo(1,'S').source used for path resolution under nvim -l (sfile expand unavailable)"

key-files:
  created:
    - lua/visual-multi/init.lua
    - test/run_spec.lua
    - test/vendor/mini.test/init.lua
    - test/spec/.gitkeep
  modified:
    - plugin/visual-multi.vim

key-decisions:
  - "Use dofile() to load mini.test instead of require() — dot in directory name 'mini.test' cannot be a Lua module path component"
  - "Use debug.getinfo(1,'S').source for script path resolution under nvim -l — vim.fn.expand('<sfile>') returns empty string when not sourced via :source"

patterns-established:
  - "Plugin shim pattern: only version guard (nvim 0.10+) + loaded guard + require('visual-multi') — no VimScript logic"
  - "Test runner pattern: headless nvim -l, dofile for vendored mini.test, debug.getinfo for path"

requirements-completed: [LUA-01, LUA-02]

# Metrics
duration: 3min
completed: 2026-02-28
---

# Phase 1 Plan 1: Foundation Bootstrap Summary

**Lua plugin bootstrap on branch 002-lua-rewrite: VimScript shim stripped to version guard + require, mini.test vendored, headless test runner exits 0**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-28T03:29:12Z
- **Completed:** 2026-02-28T03:32:42Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Created `002-lua-rewrite` branch — clean separation of Lua rewrite from VimScript master
- Rewrote `plugin/visual-multi.vim` from 117-line VimScript to 17-line bootstrap shim (version guard + loaded guard + `lua require('visual-multi')`)
- Vendored mini.test (2489 lines) from echasnovski/mini.nvim into `test/vendor/mini.test/init.lua`
- Scaffolded `lua/visual-multi/init.lua` with `setup()`, `get_state()`, and `_sessions` exports
- Wired `test/run_spec.lua` headless runner — `nvim --headless -u NORC -l test/run_spec.lua` exits 0

## Task Commits

Each task was committed atomically:

1. **Task 1: Create branch, vendor mini.test, rewrite plugin shim** - `dd7a8e4` (feat)
2. **Task 2: Scaffold init.lua and wire the test runner** - `97c52aa` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `plugin/visual-multi.vim` - Rewritten to minimal Lua bootstrap shim (17 lines, was 117)
- `lua/visual-multi/init.lua` - Public entry point with setup(), get_state(), _sessions exports
- `test/vendor/mini.test/init.lua` - Vendored mini.test framework (2489 lines)
- `test/run_spec.lua` - Headless test runner using dofile + debug.getinfo
- `test/spec/.gitkeep` - Tracks empty spec directory for future test files

## Decisions Made

1. **dofile() for mini.test loading** — `require('test.vendor.mini.test')` fails because Lua translates dots to path separators, making it look for `test/vendor/mini/test.lua` rather than `test/vendor/mini.test/init.lua`. Using `dofile(path)` with an explicit path bypasses this entirely.

2. **debug.getinfo for script path** — `vim.fn.expand('<sfile>')` returns an empty string when a Lua file is run via `nvim -l` (not `:source`). `debug.getinfo(1,'S').source` provides the actual file path reliably.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed `<sfile>` path resolution under `nvim -l`**
- **Found during:** Task 2 (Scaffold init.lua and wire test runner)
- **Issue:** `vim.fn.expand('<sfile>')` returns empty string when script is executed via `nvim -l` rather than `:source`, causing `fnamemodify` to return empty repo_root and the runner to fail with E498
- **Fix:** Replaced `vim.fn.expand('<sfile>')` with `debug.getinfo(1,'S').source:sub(2)` which correctly returns the file path under `-l` execution
- **Files modified:** `test/run_spec.lua`
- **Verification:** `nvim --headless -u NORC -l test/run_spec.lua` exits 0
- **Committed in:** `97c52aa` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed mini.test module resolution via dofile()**
- **Found during:** Task 2 (Scaffold init.lua and wire test runner)
- **Issue:** `require('test.vendor.mini.test')` fails because Lua dot-notation translates to `test/vendor/mini/test.lua`, not `test/vendor/mini.test/init.lua` — the dot in the directory name `mini.test` is the problem
- **Fix:** Replaced `require('test.vendor.mini.test')` with `dofile(repo_root .. '/test/vendor/mini.test/init.lua')` which resolves directly to the file
- **Files modified:** `test/run_spec.lua`
- **Verification:** MiniTest loads and `vim.cmd('qa!')` is reached; runner exits 0
- **Committed in:** `97c52aa` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - Bug)
**Impact on plan:** Both fixes are necessary for the runner to function at all. The plan's code used patterns that don't work under `nvim -l` execution mode. No scope creep.

## Issues Encountered

None beyond what was auto-fixed above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Branch `002-lua-rewrite` is active and clean
- Plugin loads via Lua: `require('visual-multi')` works
- Test harness operational: `nvim --headless -u NORC -l test/run_spec.lua` exits 0
- Plans 02-04 can now write specs in `test/spec/` and implement modules in `lua/visual-multi/`
- No blockers for Phase 1 Plan 2 (config + util modules)

---
*Phase: 01-foundation*
*Completed: 2026-02-28*

## Self-Check: PASSED

All files present: plugin/visual-multi.vim, lua/visual-multi/init.lua, test/vendor/mini.test/init.lua, test/run_spec.lua, test/spec/.gitkeep, 01-01-SUMMARY.md
All commits present: dd7a8e4 (Task 1), 97c52aa (Task 2)
