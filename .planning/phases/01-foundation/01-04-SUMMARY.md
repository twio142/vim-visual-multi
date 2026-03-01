---
phase: 01-foundation
plan: 04
subsystem: infra
tags: [neovim, lua, mini.test, undo, undo-grouping, bug-regression, BUG-02, BUG-03, BUG-04]

# Dependency graph
requires:
  - phase: 01-02
    provides: "util.lua with deep_equal; mini.test harness; established spec patterns"
provides:
  - "lua/visual-multi/undo.lua: begin_block, end_block, with_undo_block, flush_undo_history"
  - "test/spec/undo_spec.lua: 7 mini.test specs with explicit BUG-02/03/04 regression guards"
  - "Phase 1 complete: all 5 spec files pass (config, util, highlight, region, undo — 39 tests)"
affects: [05-session, 06-keymaps, 07-operators, 08-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Undo block lifecycle: begin_block snapshots seq_cur + lines, end_block compares content before committing undo entry"
    - "BUG-03 guard: always vim.bo[buf].undolevels (buffer-local), NEVER vim.o.undolevels (global)"
    - "BUG-04 guard: deep_equal lines comparison in end_block short-circuits on no-op to prevent spurious undo entry"
    - "BUG-02 guard: test buffers use nvim_create_buf(false, false) not (false, true) so undolevels != -1"
    - "flush_undo_history: save/set undolevels=-1/restore + pcall(vim.cmd, 'silent! undojoin') for redo-safe flush"

key-files:
  created:
    - lua/visual-multi/undo.lua
    - test/spec/undo_spec.lua
  modified: []

key-decisions:
  - "flush_undo_history uses undojoin not nvim_buf_set_lines no-op — avoids modifying buffer content"
  - "undojoin wrapped in pcall to guard against invalid-context errors (e.g., after redo)"
  - "with_undo_block plan code used string-key hooks (T['before_each']) but correct API is MiniTest.new_set({ hooks = { pre_case, post_case } }) — fixed in spec"

patterns-established:
  - "Undo tests: nvim_set_current_buf(buf) in pre_case so vim.fn.undotree() targets the right buffer"
  - "BUG assertion first: test that undo is actually enabled (BUG-02 guard) before testing undo behavior"

requirements-completed: [LUA-02]

# Metrics
duration: 2min
completed: 2026-02-28
---

# Phase 1 Plan 4: Undo Module Summary

**Atomic undo-block grouping for multi-cursor edits with three explicit regression guards preventing BUG-02 (scratch buffer undo silently disabled), BUG-03 (global vs buffer-local undolevels), and BUG-04 (spurious undo entry on no-op)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-28T03:42:23Z
- **Completed:** 2026-02-28T03:44:12Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `undo.lua`: four functions — `begin_block` (snapshot seq_cur + lines), `end_block` (deep_equal short-circuit + seq_after record), `with_undo_block` (wrapper returning fn result), `flush_undo_history` (buffer-local undolevels + pcall undojoin)
- Created `undo_spec.lua`: 7 tests — BUG-02 guard (undolevels != -1), begin_block fields, end_block no-change short-circuit (BUG-04), end_block real-change path, with_undo_block call/return
- Phase 1 complete: all 39 tests pass across 5 spec files (config, util, highlight, region, undo — exit=0)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement undo.lua with all BUG-03/BUG-04 guards** - `cea8fad` (feat)
2. **Task 2: Write undo_spec.lua with explicit bug-regression tests** - `d198b63` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `lua/visual-multi/undo.lua` - Undo grouping: begin_block, end_block, with_undo_block, flush_undo_history (71 lines)
- `test/spec/undo_spec.lua` - 7 mini.test specs with BUG-02/03/04 regression guards (101 lines)

## Decisions Made

1. **flush_undo_history uses undojoin** — The `undojoin` approach was chosen over a no-op `nvim_buf_set_lines` call because undojoin avoids modifying buffer content (cleaner semantics). Wrapped in `pcall(vim.cmd, 'silent! undojoin')` to guard against errors in redo contexts.

2. **spec hooks fixed to mini.test API** — The plan's code sample used `T['before_each'] = fn` string-key assignment. Following the pattern established in plan 02, the spec uses `MiniTest.new_set({ hooks = { pre_case = ..., post_case = ... } })` which is the correct mini.test hook registration API.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed mini.test hooks API in undo_spec.lua**
- **Found during:** Task 2 (Write undo_spec.lua)
- **Issue:** Plan code sample used `T['before_each'] = fn` and `T['after_each'] = fn` string-key assignment. mini.test does not recognize string keys named `before_each` as lifecycle hooks — this was the same bug fixed in plan 02 for config_spec.lua
- **Fix:** Changed to `MiniTest.new_set({ hooks = { pre_case = ..., post_case = ... } })` per established pattern from plan 02
- **Files modified:** `test/spec/undo_spec.lua`
- **Verification:** All 7 undo_spec tests pass; buf is correctly set up and torn down per case
- **Committed in:** `d198b63` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** The mini.test hooks API mismatch is a recurring pattern in the plan's code samples. The fix is correct and consistent with established patterns. No scope creep.

## Issues Encountered

None beyond what was auto-fixed above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `undo.lua` is implemented and fully tested (7 tests, 0 failures)
- Phase 1 complete: all 5 Tier-1 modules implemented and tested (config, util, highlight, region, undo)
- 39 headless tests pass, exit=0
- BUG-02/03/04 regression guards are in the permanent test suite — any future breakage of these invariants will be caught automatically
- Phase 2 (session module) can now require `visual-multi.undo` for undo block management

---
*Phase: 01-foundation*
*Completed: 2026-02-28*

## Self-Check: PASSED

All files present: lua/visual-multi/undo.lua, test/spec/undo_spec.lua, .planning/phases/01-foundation/01-04-SUMMARY.md
All commits present: cea8fad (Task 1), d198b63 (Task 2), dbff29b (docs)
Test suite: 39/39 tests pass headless (exit=0, 5 spec files)
