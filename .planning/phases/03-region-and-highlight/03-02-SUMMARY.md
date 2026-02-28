---
phase: 03-region-and-highlight
plan: 02
subsystem: highlight
tags: [extmarks, neovim, lua, multibyte, highlight-groups, redraw-engine]

# Dependency graph
requires:
  - phase: 03-01
    provides: "VM_ highlight groups, Region.new with sel_mark_id/anchor_mark_id/mode, session primary_idx"
  - phase: 02-01
    provides: "session lifecycle (start/stop/toggle_mode stub), augroup, keymaps"
provides:
  - "highlight.redraw(session): read-then-clear-then-draw rendering engine for all regions"
  - "_col_end(buf, row, col): multibyte-safe byte-width helper"
  - "_draw_cursor_region: single-char extmark with VM_Cursor/VM_CursorSecondary"
  - "_draw_extend_region: dual-extmark layout (selection span priority 200 + cursor-tip overlay priority 201)"
  - "session.toggle_mode(): anchor setup on cursor->extend, anchor collapse on extend->cursor, calls redraw"
  - "73 mini.test specs (10 new: 7 highlight, 3 region), 0 failures"
affects:
  - 04-cursor-engine
  - 05-insert-mode
  - 06-operators

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Read-then-clear-then-draw: always read extmark positions before nvim_buf_clear_namespace to avoid stale ID reads"
    - "Temp fields pattern: store _tip_row/_tip_col/_anc_row/_anc_col on region in Phase 1 of redraw, consumed by draw helpers"
    - "Priority layering: selection span at 200, cursor-tip overlay at 201 for correct visual stacking"
    - "Zero-width extend fallback: anchor==tip renders as cursor-mode (not invisible)"
    - "right_gravity=false for anchor marks: stays left on insert-before, preserving selection start"

key-files:
  created:
    - test/spec/highlight_spec.lua (T_redraw set with 7 new specs)
    - test/spec/region_spec.lua (3 new extend-mode specs)
  modified:
    - lua/visual-multi/highlight.lua (added _col_end, _draw_cursor_region, _draw_extend_region, M.redraw)
    - lua/visual-multi/session.lua (expanded toggle_mode with anchor setup/collapse + hl.redraw call)

key-decisions:
  - "Read-then-clear-then-draw order in redraw(): positions must be cached in _tip_row/_tip_col before nvim_buf_clear_namespace to avoid reading from deleted marks"
  - "No id= in redraw draw helpers: after clear_namespace old IDs are gone; always create new marks and store returned IDs back"
  - "Dual-extmark for extend mode: sel_mark_id tracks selection span (priority 200), tip_mark_id tracks cursor-tip overlay (priority 201)"
  - "anchor recreated each redraw with right_gravity=false to preserve position tracking after inserts"
  - "toggle_mode now calls hl.redraw(session); set_mode/set_cursor_mode/set_extend_mode do NOT call redraw (callers manage at Phase 4+)"

patterns-established:
  - "Read-then-clear-then-draw: canonical order for all redraw operations on the VM namespace"
  - "is_primary = (i == session.primary_idx): simple index comparison, no search needed"

requirements-completed: [FEAT-07]

# Metrics
duration: 8min
completed: 2026-02-28
---

# Phase 3 Plan 02: Redraw Engine Summary

**Read-then-clear-then-draw rendering engine with multibyte-safe _col_end, dual-extmark extend-mode layout, and toggle_mode() anchor wiring — 73 specs, 0 failures**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-02-28T19:03:00Z
- **Completed:** 2026-02-28T19:11:36Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Implemented `highlight.redraw(session)` with the read-positions-first pattern: Phase 1 caches all extmark positions into temp fields `_tip_row/_tip_col/_anc_row/_anc_col`, Phase 2 atomically clears the namespace, Phase 3 redraws all regions
- Added `_col_end(buf, row, col)` multibyte-safe helper using `vim.fn.matchstr` to get correct byte widths for CJK, accented, and ASCII characters (guards against PITFALL-14)
- Implemented `_draw_extend_region` with dual-extmark layout: selection span at priority 200 and cursor-tip overlay at priority 201, with zero-width anchor==tip fallback to cursor-mode render
- Expanded `session.toggle_mode()` to pin anchor extmarks on cursor->extend and collapse them on extend->cursor, then call `hl.redraw(session)` — completing the mode-transition wire
- Added 10 new specs: 7 in `T_redraw` covering primary/secondary distinction, extend-mode, zero-width fallback, stopped/empty no-ops; 3 in region_spec covering extend-mode `Region.new` fields and `anchor_mark_id` cleanup on remove

## Task Commits

1. **Task 1: Implement highlight.redraw() with _col_end, _draw_cursor_region, _draw_extend_region** - `d33fda0` (feat)
2. **Task 2: Wire toggle_mode() redraw call; add highlight and region specs** - `5143529` (feat)

## Files Created/Modified

- `lua/visual-multi/highlight.lua` - Added `_col_end`, `_draw_cursor_region`, `_draw_extend_region`, `M.redraw`; updated Provides doc comment
- `lua/visual-multi/session.lua` - Expanded `toggle_mode()` with anchor setup/collapse + `hl.redraw(session)` call; added comments to set_mode/set_cursor_mode/set_extend_mode
- `test/spec/highlight_spec.lua` - Added `T_redraw` set with 7 new specs (primary/secondary distinction, extend-mode, zero-width, stopped/empty no-ops, clear invariant)
- `test/spec/region_spec.lua` - Added 3 new extend-mode specs (anchor_mark_id field presence, nil in cursor mode, cleanup on remove)

## Decisions Made

- **Read-then-clear-then-draw order**: `nvim_buf_get_extmark_by_id` must be called before `nvim_buf_clear_namespace` because the clear deletes all marks. Positions are cached as temp fields on the region table (`_tip_row`, `_tip_col`, `_anc_row`, `_anc_col`).
- **No `id=` in draw helpers**: After `clear_namespace`, old extmark IDs are invalid. Creating new marks (no `id=`) and storing returned IDs back is both semantically correct and avoids Neovim's behavior of assigning server-assigned IDs when a stale `id=` is passed.
- **anchor recreated each redraw**: The anchor tracking mark must be recreated with `right_gravity=false` in each `_draw_extend_region` call so the anchor position is correctly tracked for subsequent redraws (especially after text edits shift positions).
- **toggle_mode() only calls redraw**: `set_mode`/`set_cursor_mode`/`set_extend_mode` deliberately do not call redraw — Phase 4+ callers manage redraw timing for batch operations.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `highlight.redraw(session)` is the primary rendering entry point for Phase 4+
- Phase 4 (cursor engine) can now add cursors to `session.cursors` and call `hl.redraw(session)` to see them rendered with correct primary/secondary groups
- `session.toggle_mode()` is fully wired and ready for use with actual cursors
- All 73 specs pass; no regressions from prior phases

## Self-Check: PASSED

- FOUND: lua/visual-multi/highlight.lua
- FOUND: lua/visual-multi/session.lua
- FOUND: test/spec/highlight_spec.lua
- FOUND: test/spec/region_spec.lua
- FOUND: .planning/phases/03-region-and-highlight/03-02-SUMMARY.md
- FOUND commit d33fda0 (Task 1)
- FOUND commit 5143529 (Task 2)

---
*Phase: 03-region-and-highlight*
*Completed: 2026-02-28*
