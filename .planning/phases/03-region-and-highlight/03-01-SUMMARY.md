---
phase: 03-region-and-highlight
plan: "01"
subsystem: data-model
tags: [highlight, region, session, data-model, phase3-contracts]
dependency_graph:
  requires: []
  provides:
    - highlight.VM_Cursor
    - highlight.VM_CursorSecondary
    - highlight.VM_Extend
    - highlight.VM_ExtendSecondary
    - highlight.VM_Insert
    - highlight.VM_Search
    - region.sel_mark_id
    - region.anchor_mark_id
    - region.tip_mark_id
    - region.mode
    - session.primary_idx
  affects:
    - lua/visual-multi/highlight.lua
    - lua/visual-multi/region.lua
    - lua/visual-multi/session.lua
    - test/spec/region_spec.lua
tech_stack:
  added: []
  patterns:
    - "VM_ prefix for highlight group namespacing"
    - "right_gravity=true on sel_mark_id (tip moves right on insert)"
    - "right_gravity=false on anchor_mark_id (anchor stays left on insert)"
    - "mode field on Region for cursor/extend dispatch"
key_files:
  created: []
  modified:
    - lua/visual-multi/highlight.lua
    - lua/visual-multi/region.lua
    - lua/visual-multi/session.lua
    - test/spec/region_spec.lua
decisions:
  - "VM_ prefix chosen over VMX prefix for highlight groups — clearer namespace separation and matches Phase 3 contract spec"
  - "draw_cursor/draw_selection use VM_CursorSecondary/VM_ExtendSecondary by default — redraw() (Wave 2) will choose primary vs secondary per-cursor"
  - "Region.new mode parameter defaults to 'cursor' — backward compat with existing 63 specs that call Region.new(buf, row, col)"
  - "anchor_mark_id only created when mode='extend' AND anchor table provided — avoids unnecessary extmarks in cursor mode"
  - "tip_mark_id=nil reserved for redraw engine — not created in Region.new, set externally by Phase 3 Wave 2"
  - "primary_idx=0 sentinel means no cursors added yet — 0 not -1 to avoid off-by-one confusion with 1-indexed Lua arrays"
metrics:
  duration: "3 min"
  completed_date: "2026-02-28"
  tasks_completed: 2
  files_modified: 4
---

# Phase 3 Plan 01: Data Model Migration Summary

Migrated Phase 1 data model to Phase 3 contracts — VM_ prefix highlight groups, expanded Region with sel_mark_id/anchor_mark_id/tip_mark_id/mode fields, primary_idx added to session, all 63 Phase 1+2 specs continue to pass.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Expand highlight.define_groups() to 6 Phase-3 groups | 5b7ea10 | highlight.lua |
| 2 | Expand Region data model + primary_idx + spec updates | 46bec29 | region.lua, session.lua, region_spec.lua |

## Verification Results

- Test suite: 63 tests, 0 failures (same count as before plan execution)
- VM_Cursor highlight group: `{ default = true, link = "Visual" }` — confirmed via nvim CLI
- Region sel_mark_id: integer 1, mark_id: nil — confirmed via nvim CLI
- session primary_idx: 0 — confirmed via nvim CLI

## What Was Built

### highlight.lua

Replaced the 4 old groups (VMCursor, VMExtend, VMInsert, VMSearch) with 6 Phase-3 groups using VM_ prefix:

- `VM_Cursor` → links Visual (primary cursor in cursor mode)
- `VM_CursorSecondary` → links Cursor (secondary cursors)
- `VM_Extend` → links PmenuSel (primary selection in extend mode)
- `VM_ExtendSecondary` → links PmenuSbar (secondary selections)
- `VM_Insert` → links DiffChange (reserved for Phase 5)
- `VM_Search` → links Search (reserved for Phase 6)

`draw_cursor` and `draw_selection` updated to use VM_CursorSecondary and VM_ExtendSecondary respectively — these low-level helpers produce secondary-level highlights; the Wave 2 redraw engine will choose primary/secondary per-cursor.

### region.lua

Region data model expanded from single `mark_id` field to Phase 3 contract:

- `sel_mark_id` — extmark tracking cursor tip / selection highlight (right_gravity=true)
- `anchor_mark_id` — invisible tracking extmark for extend-mode anchor (right_gravity=false, nil in cursor mode)
- `tip_mark_id` — reserved for multi-cell extend tracking by redraw engine (always nil from Region.new)
- `mode` — 'cursor' or 'extend'

`Region.new` signature expanded to `(buf, row, col, mode, anchor)` with backward-compatible defaults (`mode='cursor'`, `anchor=nil`). All existing call sites (63 specs) pass `(buf, row, col)` and continue to work unchanged.

`Region:remove()` now cleans up all three mark IDs (sel_mark_id, tip_mark_id, anchor_mark_id) with pcall-wrapping for each.

### session.lua

`_new_session()` return table gains `primary_idx = 0` (zero means no cursors yet; Phase 4+ sets it to `#session.cursors` when a cursor is added).

### test/spec/region_spec.lua

All `r.mark_id` references renamed to `r.sel_mark_id`. Test names updated accordingly. No test logic changed — extmark behavior is identical.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

Files exist:
- FOUND: lua/visual-multi/highlight.lua
- FOUND: lua/visual-multi/region.lua
- FOUND: lua/visual-multi/session.lua
- FOUND: test/spec/region_spec.lua

Commits exist:
- FOUND: 5b7ea10 (Task 1)
- FOUND: 46bec29 (Task 2)
