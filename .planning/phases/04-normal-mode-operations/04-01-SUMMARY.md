---
phase: 04-normal-mode-operations
plan: 01
subsystem: edit
tags: [lua, neovim, multi-cursor, session, undo, extmarks]

# Dependency graph
requires:
  - phase: 03-region-and-highlight
    provides: Region.new, highlight.redraw, extmark namespace
  - phase: 02-session-lifecycle
    provides: session.start/stop, _saved.opts infrastructure
  - phase: 01-foundation
    provides: undo module, test harness (mini.test)
provides:
  - session.lua with Phase 4 options: synmaxcol, textwidth, hlsearch, concealcursor saved/restored
  - edit.lua module skeleton with all 5 exported stubs (exec, yank, paste, dot, g_increment)
  - edit_spec.lua test scaffold with 9 tests (5 passing, 4 pending for Plan 02)
affects: [04-02-normal-mode-exec, 04-03-g-increment, future phases using edit module]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Option save/restore with validity guards (buf_is_valid, win_is_valid) for async teardown safety"
    - "Stub-first module creation: valid Lua exports with no-op bodies, pending tests document intent"
    - "Buffer-local vs window-local vs global option scope — buf for synmaxcol/textwidth, win for concealcursor/conceallevel, vim.o for virtualedit/hlsearch"

key-files:
  created:
    - lua/visual-multi/edit.lua
    - test/spec/edit_spec.lua
  modified:
    - lua/visual-multi/session.lua

key-decisions:
  - "synmaxcol set to 0 (unlimited) during session — prevents syntax engine from truncating long lines during batch edits"
  - "textwidth set to 0 during session — prevents auto-wrap from corrupting multi-cursor deletions/insertions"
  - "hlsearch disabled globally during session — suppresses distracting match highlighting during batch operations"
  - "concealcursor set to empty string — disables concealment at cursor position in concealed-syntax buffers"
  - "edit.lua dot() is the only non-stub export — it delegates to exec(), making the forward reference safe"
  - "Behavior tests in edit_spec.lua are intentionally failing stubs — they document Plan 02 contracts, not Plan 01 output"

patterns-established:
  - "local buf = session.buf at top of option functions — makes buf available for buffer-local option access"
  - "Restore guards: if vim.api.nvim_buf_is_valid(buf) wraps buffer-local restores; win_is_valid wraps window-local restores"

requirements-completed: [FEAT-05, FEAT-06]

# Metrics
duration: 2min
completed: 2026-02-28
---

# Phase 4 Plan 01: Normal-Mode Operations Interface Summary

**session.lua patched with 4 Phase 4 options (synmaxcol/textwidth/hlsearch/concealcursor save+restore); edit.lua skeleton with 5 exports; edit_spec.lua scaffold with 9 tests (5 pass, 4 pending for Plan 02 exec implementation)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-28T23:56:38Z
- **Completed:** 2026-02-28T23:58:57Z
- **Tasks:** 2
- **Files modified:** 3 (1 modified, 2 created)

## Accomplishments

- Patched `_save_and_set_options` and `_restore_options` in session.lua with synmaxcol, textwidth, hlsearch, and concealcursor — all with correct scope (buf-local, buf-local, global, win-local respectively) and validity guards on restore
- Created `edit.lua` with all 5 required exports as valid, callable Lua stubs; `dot()` is fully implemented (delegates to exec when `_vm_dot` is set)
- Created `edit_spec.lua` with 9 tests: 2 structural (module loads, exports verified), 2 no-op guards (stopped session, empty cursors), 5 behavior tests that document Plan 02 contracts (currently failing as expected)

## Task Commits

Each task was committed atomically:

1. **Task 1: Patch session.lua with Phase 4 options** - `37f25b3` (feat)
2. **Task 2: Create edit.lua skeleton and edit_spec.lua scaffold** - `c51e2e3` (feat)

**Plan metadata:** `[docs commit]` (docs: complete plan)

## Files Created/Modified

- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/session.lua` - Added synmaxcol, textwidth, hlsearch, concealcursor to _save_and_set_options/_restore_options; added `local buf = session.buf` to both functions
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/edit.lua` - New: 5 exported stubs (exec, yank, paste, dot[live], g_increment) plus 2 private sort helpers
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/test/spec/edit_spec.lua` - New: 9-test scaffold covering structural + no-op guards + 5 pending behavior tests

## Decisions Made

- `dot()` is the only non-stub: it safely delegates to `exec()` which is a no-op, making the implementation safe for Plan 01 without forward-reference issues
- Behavior tests in edit_spec.lua are intentionally failing — they serve as Plan 02 contracts, documented in the test file header
- Restore guards use `nvim_buf_is_valid` for buffer-local options and `nvim_win_is_valid` for window-local options — consistent with existing conceallevel restore pattern

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02 (exec implementation) can proceed immediately: `_save_and_set_options` now zeros textwidth/synmaxcol which prevents auto-wrap and syntax slowdown during batch edits
- edit.lua exports are confirmed callable — Plan 02 replaces stub bodies
- edit_spec.lua behavior tests will pass once Plan 02 implements M.exec bottom-to-top loop with undo block and eventignore bracket
- Pre-existing 73 tests all pass; 4 new pending tests track Plan 02 requirements

## Self-Check: PASSED

- FOUND: lua/visual-multi/session.lua
- FOUND: lua/visual-multi/edit.lua
- FOUND: test/spec/edit_spec.lua
- FOUND: .planning/phases/04-normal-mode-operations/04-01-SUMMARY.md
- FOUND commit: 37f25b3 (feat(04-01): patch session.lua with Phase 4 options)
- FOUND commit: c51e2e3 (feat(04-01): create edit.lua skeleton and edit_spec.lua scaffold)

---
*Phase: 04-normal-mode-operations*
*Completed: 2026-02-28*
