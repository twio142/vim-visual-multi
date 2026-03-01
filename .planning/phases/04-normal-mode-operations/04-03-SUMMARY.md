---
phase: 04-normal-mode-operations
plan: 03
subsystem: editing
tags: [lua, neovim, multi-cursor, undo, feedkeys, sequential-increment]

# Dependency graph
requires:
  - phase: 04-02
    provides: M.exec, M.yank, M.paste, M.dot, M.change in edit.lua; undo begin/end block
  - phase: 04-01
    provides: edit.lua scaffold, _bottom_to_top, session env guards
provides:
  - "M.g_increment: top-to-bottom sequential +1/+2/+3 increment (g<C-a>) and -1/-2/-3 decrement (g<C-x>)"
  - "M.case_toggle, M.case_upper, M.case_lower: thin M.exec wrappers for ~, gUmotion, gumotion"
  - "M.replace_char: thin M.exec wrapper for r<char>"
  - "FEAT-10 behavioral test suite: 11 new tests in edit_spec.lua (Categories G, K, R)"
  - "Phase 4 complete: FEAT-05, FEAT-06, FEAT-10 all have passing implementations and tests"
affects:
  - 05-insert-mode
  - 06-keymap-wiring

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Thin wrapper pattern: case/replace ops delegate to M.exec, inheriting undo grouping and redraw"
    - "Sequential step encoding: string.rep('<C-a>', step) with nvim_replace_termcodes for g_increment"
    - "Top-to-bottom loop via _top_to_bottom for g_increment; bottom-to-top via _bottom_to_top for exec"
    - "Undo flush in tests: undolevels=-1 then restore after nvim_buf_set_lines before measuring seq_cur"

key-files:
  created: []
  modified:
    - "lua/visual-multi/edit.lua"
    - "test/spec/edit_spec.lua"

key-decisions:
  - "M.g_increment uses _top_to_bottom order: step 1 for lowest line, step 2 for next, etc."
  - "string.rep('<C-a>', step) encodes step repetitions; nvim_replace_termcodes applied to whole string"
  - "case/replace wrappers are intentionally thin (one-liners) — M.exec handles all undo/redraw concerns"
  - "Undo count tests require undolevels=-1 flush after nvim_buf_set_lines setup to get accurate seq_cur baseline"

patterns-established:
  - "Thin wrapper: function M.case_toggle(s) M.exec(s, '~') end — no duplication of undo logic"
  - "Flush pattern in tests: local ul = vim.bo[buf].undolevels; vim.bo[buf].undolevels = -1; vim.bo[buf].undolevels = ul"

requirements-completed: [FEAT-10]

# Metrics
duration: 3min
completed: 2026-03-01
---

# Phase 4 Plan 03: Sequential increment and case/replace wrappers

**M.g_increment (g<C-a>/g<C-x>) with top-to-bottom +1/+2/+3 sequential steps; case_toggle/case_upper/case_lower/replace_char thin wrappers; 100 tests passing — Phase 4 complete**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-01T00:12:56Z
- **Completed:** 2026-03-01T00:15:43Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Implemented M.g_increment: top-to-bottom loop using _top_to_bottom (already implemented in Plan 02), string.rep('<C-a>', step) for sequential +1/+2/+3, wrapped in undo.begin_block/end_block + eventignore bracket
- Added four thin wrappers: M.case_toggle (~), M.case_upper (gU+motion), M.case_lower (gu+motion), M.replace_char (r+char) — all delegate to M.exec
- Added 11 FEAT-10 behavioral tests (Categories G, K, R) covering functional behavior and undo count correctness
- Phase 4 complete: all three requirement IDs (FEAT-05, FEAT-06, FEAT-10) have passing implementations and tests; 100 tests, 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement _top_to_bottom and M.g_increment; add case/replace wrappers** - `970bb98` (feat)
2. **Task 2: Add FEAT-10 behavioral tests to edit_spec.lua** - `6a7e222` (test)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `lua/visual-multi/edit.lua` - Replaced M.g_increment stub with full implementation; added case_toggle, case_upper, case_lower, replace_char thin wrappers (302 lines total)
- `test/spec/edit_spec.lua` - Added Categories G (5 tests), K (4 tests), R (2 tests) for FEAT-10 behavioral coverage (399 lines total)

## Decisions Made

- M.g_increment uses top-to-bottom order (ipairs on _top_to_bottom result): step 1 for the first visible cursor, step 2 for second, etc. This matches vim-visual-multi g<C-a> semantics.
- string.rep('<C-a>', step) is the key encoding: step=1 feeds 1x<C-a>, step=2 feeds 2x<C-a>, etc. Applied to whole string via nvim_replace_termcodes once per cursor.
- Case and replace wrappers are intentionally one-liners: all undo grouping, eventignore, and redraw live in M.exec. No duplication.
- Undo count tests in Category G, K, R require the undolevels=-1 flush trick after local nvim_buf_set_lines setup. The pre_case hook only flushes the initial `{'hello world', 'foo bar baz'}` content; tests that set their own content must flush independently.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Undo count tests required undolevels flush after local nvim_buf_set_lines**
- **Found during:** Task 2 (FEAT-10 behavioral tests)
- **Issue:** Three undo-count tests (`g_increment creates exactly one undo entry`, `case_upper creates exactly one undo entry`, `replace_char creates exactly one undo entry`) failed with `after - before == 0` instead of 1. The tests called nvim_buf_set_lines to set up test content without flushing undo first. This caused the feedkeys-based edit to be merged with the set_lines undo entry, producing 0 net advancement in seq_cur.
- **Fix:** Added the `undolevels=-1` flush pattern (identical to pre_case hook and existing undo grouping tests) immediately after each test's nvim_buf_set_lines setup and before measuring `before`. Three tests affected.
- **Files modified:** `test/spec/edit_spec.lua`
- **Verification:** All 100 tests pass; 3 previously-failing undo count tests now report `after - before == 1`
- **Committed in:** `6a7e222` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug in test undo baseline)
**Impact on plan:** Required for test correctness. The pattern is identical to the established flush pattern already used in pre_case and existing undo grouping tests. No scope creep.

## Issues Encountered

The `_top_to_bottom` function was already fully implemented in Plan 02 (not a stub as the plan context suggested it was). The plan's stub replacement action was therefore a no-op — the existing implementation matched exactly what was specified. No issue, just a context mismatch.

## Next Phase Readiness

- Phase 4 complete: edit.lua exports exec, yank, paste, dot, change, g_increment, case_toggle, case_upper, case_lower, replace_char
- All 100 unit tests pass across 7 spec files
- Phase 5 (insert mode) can build on M.exec and M.change for insert-mode replication
- Phase 6 (keymap wiring) has clean API surface: all edit operations accept (session, ...) signatures

---
*Phase: 04-normal-mode-operations*
*Completed: 2026-03-01*
