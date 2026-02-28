---
phase: 01-foundation
plan: 03
subsystem: rendering
tags: [neovim, lua, extmarks, highlight, region, mini.test, namespace]

# Dependency graph
requires:
  - phase: 01-02
    provides: "util.lua (is_session dispatch), mini.test harness, correct hooks API"
provides:
  - "lua/visual-multi/highlight.lua: ns, define_groups, draw_cursor, draw_selection, clear, clear_region"
  - "lua/visual-multi/region.lua: Region.new with :pos, :move, :remove methods"
  - "test/spec/highlight_spec.lua: 7 mini.test specs for highlight module"
  - "test/spec/region_spec.lua: 6 mini.test specs for region module"
affects: [04-region-undo, 05-session, 06-keymaps, 07-operators, 08-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Extmark namespace: vim.api.nvim_create_namespace('visual_multi') at module level — idempotent by name"
    - "In-place extmark update: pass id=mark_id to nvim_buf_set_extmark — no delete-and-recreate (O(log n))"
    - "Highlight groups: nvim_set_hl with default=true so user colorschemes always win"
    - "Dual-form clear: util.is_session dispatch — single function handles both bufnr and session table"
    - "Region OOP: setmetatable + __index — Region:pos/move/remove as method syntax"
    - "Circular require guard: region.lua requires highlight.lua; highlight.lua never requires region.lua (PITFALL-07)"

key-files:
  created:
    - lua/visual-multi/highlight.lua
    - lua/visual-multi/region.lua
    - test/spec/highlight_spec.lua
    - test/spec/region_spec.lua
  modified: []

key-decisions:
  - "highlight.lua is Tier-0: no runtime require of any other visual-multi module at load time; util is lazy-required only in clear()"
  - "region.lua lazy-requires highlight inside each method — avoids load-order issues while preventing circular dep"
  - "Region:pos() reads extmark live from API — no cached position field (always authoritative)"
  - "Region tables satisfy util.is_session() because they carry _stopped — intentional shared sentinel design"

# Metrics
duration: 2min
completed: 2026-02-28
---

# Phase 1 Plan 3: Highlight and Region Modules Summary

**Extmark namespace with draw/clear, OOP region cursor tracking using in-place id= update — 39 headless tests pass (0 failures)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-28T03:42:03Z
- **Completed:** 2026-02-28T03:43:54Z
- **Tasks:** 2
- **Files modified:** 4 (all new)

## Accomplishments

- Created `highlight.lua`: single `M.ns` namespace at module level, `define_groups()` with `default=true` for all four VM highlight groups, `draw_cursor`/`draw_selection` with `id=` param for O(log n) in-place extmark update, `clear()` with `is_session` dispatch (single function, no duplicate — BUG-05 guard), `clear_region()` with pcall safety
- Created `region.lua`: OOP Region via `setmetatable` + `__index`, `Region.new` creates extmark and stores `mark_id`, `Region:pos()` reads position live from extmark API, `Region:move()` updates in place (same `mark_id`, no delete-and-recreate), `Region:remove()` deletes extmark and sets `_stopped=true`
- Created `highlight_spec.lua` (7 tests) and `region_spec.lua` (6 tests) — all pass headless
- Full suite: 39/39 tests pass (exit=0); includes pre-existing config, util, and undo specs

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement highlight.lua and its spec** - `e42ef45` (feat)
2. **Task 2: Implement region.lua and its spec** - `022aa93` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `lua/visual-multi/highlight.lua` - Highlight module: ns, define_groups, draw_cursor, draw_selection, clear, clear_region (72 lines)
- `lua/visual-multi/region.lua` - Region module: Region.new with :pos, :move, :remove (66 lines)
- `test/spec/highlight_spec.lua` - 7 mini.test specs for highlight module
- `test/spec/region_spec.lua` - 6 mini.test specs for region module

## Decisions Made

1. **Tier-0 constraint enforced** — `highlight.lua` does not require any other `visual-multi` module at load time. `util` is lazy-required only inside `clear()` where `is_session` dispatch is needed. This prevents any load-order circularity.

2. **Region lazy-requires highlight** — Each Region method lazy-requires `visual-multi.highlight` rather than storing `hl` at module load time. This avoids any load-ordering issues and keeps the Tier-1 boundary clean.

3. **Region:pos() always live** — No `row`/`col` cache field on the Region table. `pos()` always reads from `nvim_buf_get_extmark_by_id`. This ensures the position is always authoritative even if Neovim's extmark tracking moves the mark due to buffer edits.

4. **Shared _stopped sentinel** — Region tables satisfy `util.is_session(region) == true` because they carry `_stopped`. This is intentional by design: the session discriminant is duck-typed via `_stopped` presence, not by class/type. Test 6 of region_spec explicitly validates this.

## Deviations from Plan

None — plan executed exactly as written. The mini.test hooks API lessons from Plan 02 were already applied from the start (`MiniTest.new_set({ hooks = { pre_case, post_case } })`), so no hook API fixes were needed.

## Issues Encountered

None beyond what was anticipated. The pre-existing `undo.lua` and `undo_spec.lua` were already present in the working tree (7 tests) and continued to pass cleanly after adding highlight and region specs.

## User Setup Required

None.

## Next Phase Readiness

- `highlight.lua` and `region.lua` are implemented and fully tested (13 new tests, 0 failures)
- Circular dependency boundary confirmed: `grep -n 'require.*region' lua/visual-multi/highlight.lua` returns only a comment, no actual require call
- In-place extmark update pattern (`id=mark_id`) confirmed via region_spec test 3 (same mark_id after move)
- Region `_stopped` sentinel confirmed to satisfy `is_session()` discriminant
- Plan 04 (undo module) can now use `highlight.ns` and `Region.new` safely

---
*Phase: 01-foundation*
*Completed: 2026-02-28*

## Self-Check: PASSED

All files present: lua/visual-multi/highlight.lua, lua/visual-multi/region.lua, test/spec/highlight_spec.lua, test/spec/region_spec.lua, 01-03-SUMMARY.md
All commits present: e42ef45 (Task 1), 022aa93 (Task 2)
Test suite: 39/39 tests pass headless (exit=0)
