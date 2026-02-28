---
phase: 01-foundation
plan: 02
subsystem: infra
tags: [neovim, lua, mini.test, config, util, byte-helpers, nvim_buf_get_offset]

# Dependency graph
requires:
  - phase: 01-01
    provides: "init.lua entry point, mini.test vendor, headless test runner"
provides:
  - "lua/visual-multi/config.lua: defaults table, apply() with unknown-key WARN + type validation + deep-merge, get(), _reset()"
  - "lua/visual-multi/util.lua: is_session dispatch helper, pos2byte via nvim_buf_get_offset, char_at, byte_len, char_len, display_width, deep_equal"
  - "test/spec/config_spec.lua: 7 mini.test specs covering all config module behaviors"
  - "test/spec/util_spec.lua: 12 mini.test specs covering all util module functions including multibyte"
  - "MiniTest.setup() global initialization pattern established in run_spec.lua"
affects: [03-highlight, 04-region-undo, 05-session, 06-keymaps, 07-operators, 08-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "mini.test hooks: use MiniTest.new_set({ hooks = { pre_case = ..., post_case = ... } }) — string key T['before_each'] is not the mini.test API"
    - "mini.test global: MiniTest.setup() sets _G.MiniTest; spec files use the global, not require()"
    - "mini.test find_files: pass { collect = { find_files = function() return paths end } } — the paths key is not the API"
    - "Config module: vim.validate for optional scalars, explicit error() for table fields, KNOWN_KEYS set for unknown-key warning"
    - "Util dispatch: is_session() checks arg._stopped ~= nil — _stopped presence is the session sentinel"
    - "Byte safety: util.pos2byte = nvim_buf_get_offset(buf, line-1) + col-1 (0-indexed offset)"

key-files:
  created:
    - lua/visual-multi/config.lua
    - lua/visual-multi/util.lua
    - test/spec/config_spec.lua
    - test/spec/util_spec.lua
  modified:
    - test/run_spec.lua

key-decisions:
  - "mini.test spec files use global MiniTest (set by MiniTest.setup()) — not require()"
  - "mini.test hooks use new_set({ hooks: { pre_case, post_case } }) API — not string key assignment"
  - "run_spec.lua uses collect.find_files API — not the non-existent paths key"
  - "is_session() uses _stopped sentinel field — any table with _stopped is a session (even stopped ones)"
  - "deep_equal uses vim.deep_equal with vim.inspect fallback for environments without it"

patterns-established:
  - "Notification spy: replace vim.notify in pre_case, restore in post_case with config._reset()"
  - "Buffer tests: nvim_create_buf(false, false) for testable buffers with undo (not scratch)"
  - "Config reset isolation: config._reset() in post_case ensures each test starts from defaults"

requirements-completed: [LUA-02, LUA-03]

# Metrics
duration: 3min
completed: 2026-02-28
---

# Phase 1 Plan 2: Config and Util Modules Summary

**config.lua with deep-merge validation and unknown-key warn, util.lua with nvim_buf_get_offset byte helpers and _stopped-based session dispatch — 19 headless tests pass**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-28T03:35:25Z
- **Completed:** 2026-02-28T03:39:03Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Created `config.lua`: defaults for 8 top-level keys, `apply()` with unknown-key WARN (not error) + `vim.validate` for scalar types + hard `error()` for mappings wrong type + deep-merge via `vim.tbl_deep_extend`, `get()`, `_reset()` for test isolation
- Created `util.lua`: `is_session()` dispatch via `_stopped` sentinel, `pos2byte()` using `nvim_buf_get_offset` (LUA-03 confirmed, no `line2byte`), `char_at()` via `vim.fn.matchstr`, `byte_len/char_len/display_width`, `deep_equal` with fallback
- Created `config_spec.lua` (7 tests) and `util_spec.lua` (12 tests) — all 19 pass headless
- Fixed `run_spec.lua`: added `MiniTest.setup()` call and corrected `collect.find_files` API (two bugs from plan 01 that only became visible when writing actual specs)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement config.lua with validation and mini.test specs** - `05948bc` (feat)
2. **Task 2: Implement util.lua with is_session, byte helpers, and mini.test specs** - `a5c2321` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `lua/visual-multi/config.lua` - Config module: defaults, apply, get, _reset (66 lines)
- `lua/visual-multi/util.lua` - Util module: is_session, pos2byte, char_at, length helpers, deep_equal (66 lines)
- `test/spec/config_spec.lua` - 7 mini.test specs for config module
- `test/spec/util_spec.lua` - 12 mini.test specs for util module
- `test/run_spec.lua` - Fixed: MiniTest.setup() + correct collect.find_files API

## Decisions Made

1. **mini.test hooks API** — The plan's code sample used `T['before_each'] = function()` as a string key, which mini.test does not recognize as a hook. The correct API is `MiniTest.new_set({ hooks = { pre_case = ..., post_case = ... } })`. Fixed in Task 1.

2. **mini.test global pattern** — Spec files use the global `MiniTest` (set by `MiniTest.setup()`), not `require()`. The original plan referenced `require('test.vendor.mini.test')` but that fails due to the dot in the directory name — the same bug fixed in plan 01 for the runner itself.

3. **run_spec.lua collect.find_files** — `MiniTest.run({ paths = spec_files })` is not a valid API call. The correct form is `{ collect = { find_files = function() return spec_files end } }`. Fixed as part of Task 1 (Rule 1 — the runner's spec discovery was broken).

4. **is_session sentinel** — `_stopped` field presence (not value) distinguishes sessions. Both `_stopped=false` (active) and `_stopped=true` (stopped) are valid sessions. Tables without `_stopped` (plain bufnr wrappers) are not.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed mini.test hooks API in spec files**
- **Found during:** Task 1 (Implement config.lua — writing config_spec.lua)
- **Issue:** Plan sample used `T['before_each'] = fn` as string-key assignment. mini.test does not treat string keys named `before_each` as hooks — they are treated as test case functions, causing the spy not to be installed before test cases run
- **Fix:** Changed to `MiniTest.new_set({ hooks = { pre_case = ..., post_case = ... } })` which is the correct mini.test hook registration API
- **Files modified:** `test/spec/config_spec.lua`
- **Verification:** All 7 config_spec tests pass; notification spy correctly captures `vim.notify` calls
- **Committed in:** `05948bc` (Task 1 commit)

**2. [Rule 1 - Bug] Fixed MiniTest.setup() missing in run_spec.lua**
- **Found during:** Task 1 (Running tests — "No cases to execute" diagnostic)
- **Issue:** `run_spec.lua` loaded mini.test via `dofile()` but never called `MiniTest.setup()`. Spec files reference the global `MiniTest`, but `_G.MiniTest` is only set by `setup()`. Without it, spec files had no global to reference
- **Fix:** Added `MiniTest.setup()` call after `dofile()` in `run_spec.lua`
- **Files modified:** `test/run_spec.lua`
- **Verification:** Tests now load and execute
- **Committed in:** `05948bc` (Task 1 commit)

**3. [Rule 1 - Bug] Fixed MiniTest.run() collect.find_files API in run_spec.lua**
- **Found during:** Task 1 (initial "No cases to execute" diagnostic)
- **Issue:** `run_spec.lua` called `MiniTest.run({ paths = spec_files })`. The `paths` key is not a valid mini.test option — `MiniTest.run` takes `{ collect = { find_files = fn } }`. With the wrong key, mini.test used its default `find_files` (looking for `tests/**/test_*.lua`) and found nothing
- **Fix:** Changed to `MiniTest.run({ collect = { find_files = function() return spec_files end } })`
- **Files modified:** `test/run_spec.lua`
- **Verification:** Spec files are discovered and executed
- **Committed in:** `05948bc` (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 - Bug)
**Impact on plan:** All three fixes are necessary for the test suite to function. The plan's code samples contained mini.test API mismatches that only became visible when writing actual spec files. No scope creep — all changes are in the test infrastructure, not application logic.

## Issues Encountered

None beyond what was auto-fixed above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `config.lua` and `util.lua` are implemented and fully tested (19 tests, 0 failures)
- Both modules have zero inter-plugin dependencies — safe for Tier-1 modules to import
- `is_session()` dispatch pattern established for all Tier-1 modules (highlight, region, undo, session)
- `pos2byte()` via `nvim_buf_get_offset` confirmed — no `vim.fn.line2byte()` in the codebase
- mini.test test harness now fully operational — spec files can use global `MiniTest` with correct hooks API
- Plan 03 (highlight module) can now require `visual-multi.util` and write mini.test specs

---
*Phase: 01-foundation*
*Completed: 2026-02-28*

## Self-Check: PASSED

All files present: lua/visual-multi/config.lua, lua/visual-multi/util.lua, test/spec/config_spec.lua, test/spec/util_spec.lua, 01-02-SUMMARY.md
All commits present: 05948bc (Task 1), a5c2321 (Task 2)
Test suite: 19/19 tests pass headless (exit=0)
