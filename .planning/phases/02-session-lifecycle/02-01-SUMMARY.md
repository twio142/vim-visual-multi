---
phase: 02-session-lifecycle
plan: 01
subsystem: session
tags: [neovim, lua, session-lifecycle, keymaps, options, autocmds, mini.test]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: init._sessions registry, config.get(), highlight.clear(), util.is_session()

provides:
  - "session.start(buf, initial_mode): creates session table, saves/sets options, installs keymaps, emits VMEnter"
  - "session.stop(buf, opts): restores options/keymaps, clears extmarks, emits VMLeave, silent path for BufDelete"
  - "session.toggle_mode / set_mode / set_cursor_mode / set_extend_mode: extend_mode boolean management"
  - "Per-session augroup VM_buf_{bufnr} with BufDelete guard"
  - "Session table shape with all fields locked for Phase 3+ consumption"

affects:
  - 03-cursor-model
  - 04-editing-core
  - 05-insert-mode
  - 06-keymaps

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Lazy require: all sibling module requires inside function bodies (prevents circular deps with init.lua)"
    - "Option save/restore: nvim_win_get_option/set_option for window-local conceallevel, vim.o for global options"
    - "Keymap save/restore: maparg(lhs, mode, false, true) + mapset() round-trip, wrapped in nvim_buf_call for buffer context"
    - "Per-session augroup with clear=true prevents stale accumulation; BufDelete fires silent stop path"
    - "Reentrancy guard: sessions[buf] check + register BEFORE any autocmd-triggering operations"
    - "nil-first teardown: sessions[buf]=nil as first mutation in stop() prevents double-stop race"

key-files:
  created:
    - lua/visual-multi/session.lua
    - test/spec/session_spec.lua
  modified: []

key-decisions:
  - "guicursor modification deferred to Phase 3: Phase 2 save/restore infra present but modification not applied (VimScript source uses matchadd not guicursor for visual feedback)"
  - "nvim_buf_call wraps maparg call to guarantee correct buffer context for buffer-local keymap lookup (RESEARCH.md open question 2)"
  - "sessions[buf] = nil set as FIRST mutation in stop() (not last) to prevent double-stop race with BufDelete + manual Esc"
  - "Phase 2 installs only v keymap; full keymap table (Esc, operators) is Phase 6 scope"

patterns-established:
  - "Session table shape: locked field names (buf, win, _stopped, extend_mode, cursors, _saved, _augroup_name, _undo_*)"
  - "Option whitelist: virtualedit/conceallevel/guicursor — correct scope accessors documented and tested"
  - "Test pattern: nvim_buf_call(buf, fn) for buffer-local maparg queries in headless tests"

requirements-completed:
  - CFG-01
  - FEAT-03

# Metrics
duration: 2min
completed: 2026-02-28
---

# Phase 2 Plan 01: Session Lifecycle Summary

**Per-buffer session start/stop with option save/restore (virtualedit, conceallevel, guicursor), maparg+mapset keymap round-trip, BufDelete guard augroup, and VMEnter/VMLeave User autocmds — 63 tests, 0 failures**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-28T14:10:21Z
- **Completed:** 2026-02-28T14:13:01Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Implemented session.lua as the Tier-2 backbone module — every Phase 3+ feature receives a session table from M.start() and reads/writes it
- 24 new mini.test specs covering all 7 required categories (start, stop, options, reentrancy, mode toggle, lifecycle events, keymap save/restore)
- All success criteria met: CFG-01 (no g:VM references), FEAT-03 (toggle_mode, set_cursor_mode, set_extend_mode), 63 total tests passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement lua/visual-multi/session.lua** - `dcd587d` (feat)
2. **Task 2: Write test/spec/session_spec.lua** - `a4be6d8` (test)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `lua/visual-multi/session.lua` - Tier-2 session lifecycle module: start, stop, toggle_mode, set_mode, set_cursor_mode, set_extend_mode (249 lines)
- `test/spec/session_spec.lua` - 24 mini.test specs across 7 categories (268 lines)

## Decisions Made

- **guicursor modification deferred:** Phase 2 saves and restores guicursor unconditionally but does NOT modify it. VimScript source uses matchadd/highlight_clear rather than guicursor for visual feedback. Actual guicursor modification deferred to Phase 3 when cursor rendering is built.
- **nvim_buf_call for maparg:** `maparg` scans current buffer's keymap table. Wrapping the call in `nvim_buf_call(session.buf, fn)` ensures the correct buffer is current, handling the non-current-buffer case (RESEARCH.md open question 2 resolved).
- **nil-first teardown in stop():** `sessions[buf] = nil` is the first mutation in stop(), before any cleanup. This ensures a second concurrent stop() call (BufDelete race) hits nil immediately and returns.
- **Phase 2 scope for keymaps:** Only the `v` key is installed. Full keymap table (Esc, C-d, C-n, operator keys) is Phase 6 scope, as specified in the plan.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Session table shape is fully locked — Phase 3 can safely read/write all fields
- `sessions[buf] = session` registry is live and queryable via `require('visual-multi').get_state(buf)`
- BufDelete guard ensures no leaked sessions even on force-close
- Phase 3 (cursor model) can call `session_mod.start(buf, false)` and immediately push cursors into `session.cursors`
- guicursor modification hook is ready (save/restore infra present, Phase 3 fills in the modification)

## Self-Check: PASSED

- FOUND: lua/visual-multi/session.lua
- FOUND: test/spec/session_spec.lua
- FOUND: 02-01-SUMMARY.md
- FOUND: commit dcd587d (session.lua)
- FOUND: commit a4be6d8 (session_spec.lua)
- VERIFIED: 63 tests, 0 failures (nvim --headless -u NORC -l test/run_spec.lua)
- VERIFIED: no g:VM references in session.lua

---
*Phase: 02-session-lifecycle*
*Completed: 2026-02-28*
