---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
last_updated: "2026-02-28T19:11:36Z"
progress:
  total_phases: 8
  completed_phases: 2
  total_plans: 7
  completed_plans: 7
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-28)

**Core value:** All existing multi-cursor behaviors work identically after the rewrite — users lose no functionality, and configuration becomes ergonomic via setup()
**Current focus:** Phase 3 — Region and Highlight

## Current Position

Phase: 3 of 8 (Region and Highlight)
Plan: 2 of 2 in current phase (complete)
Status: Phase 3 plan 2 complete
Last activity: 2026-02-28 — Completed 03-02 (highlight.redraw engine, _col_end, toggle_mode anchor wiring, 73 tests pass)

Progress: [██████░░░░] 25%

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: 2.5 min
- Total execution time: 0.2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation | 4 | 10 min | 2.5 min |
| 02-session-lifecycle | 1 | 2 min | 2 min |
| 03-region-and-highlight | 2 | 11 min | 5.5 min |

**Recent Trend:**
- Last 5 plans: 01-04 (2 min), 02-01 (2 min), 03-01 (3 min), 03-02 (8 min)
- Trend: stable

*Updated after each plan completion*
| Phase 01-foundation P03 | 2 | 2 tasks | 4 files |
| Phase 01-foundation P04 | 2 | 2 tasks | 2 files |
| Phase 02-session-lifecycle P01 | 2 | 2 tasks | 2 files |
| Phase 03-region-and-highlight P01 | 3 | 2 tasks | 4 files |
| Phase 03-region-and-highlight P02 | 8 | 2 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-planning]: Start fresh from master (VimL), not from 001-lua-nvim-rewrite branch — prior branch as reference only
- [Pre-planning]: No backward compat with g:VM_xxx — setup() only, clean break
- [Pre-planning]: Drop Python dependency — nvim_buf_get_offset replaces line2byte()
- [Pre-planning]: Neovim 0.10+ minimum — use vim.iter, refined vim.bo/vim.wo, stable hl_mode on extmarks
- [01-01]: Use dofile() to load mini.test — dot in directory name 'mini.test' prevents require() path resolution
- [01-01]: Use debug.getinfo(1,'S').source for script path under nvim -l — vim.fn.expand('<sfile>') returns empty string
- [01-02]: mini.test hooks use new_set({ hooks: { pre_case, post_case } }) API — not string key T['before_each'] assignment
- [01-02]: mini.test spec files use global MiniTest (set by MiniTest.setup()) — not require()
- [01-02]: run_spec.lua uses collect.find_files API — not the non-existent paths key
- [01-02]: is_session() uses _stopped sentinel field presence — both _stopped=false and _stopped=true are valid sessions
- [01-03]: highlight.lua is Tier-0 — never requires region.lua; util is lazy-required only in clear() to prevent load-order circularity
- [01-03]: region.lua lazy-requires highlight inside each method — clean Tier-1 boundary, no load-order issues
- [01-03]: Region:pos() always reads live from extmark API — no cached position field (always authoritative)
- [01-03]: Region tables satisfy util.is_session() via shared _stopped sentinel — intentional duck-typed design
- [01-04]: flush_undo_history uses undojoin not nvim_buf_set_lines no-op — avoids modifying buffer content
- [01-04]: undojoin wrapped in pcall to guard against invalid-context errors (e.g., after redo)
- [01-04]: spec hooks fixed from plan's T['before_each'] to correct MiniTest.new_set({ hooks: { pre_case, post_case } }) API
- [02-01]: guicursor modification deferred to Phase 3 — VimScript source uses matchadd not guicursor; save/restore infra present but modification skipped
- [02-01]: nvim_buf_call wraps maparg call for buffer-local keymap lookup — ensures correct buffer context in headless tests
- [02-01]: sessions[buf] = nil set first in stop() to prevent double-stop race with BufDelete + manual Esc
- [02-01]: Phase 2 scope installs only v keymap; full keymap table deferred to Phase 6
- [03-01]: VM_ prefix chosen for highlight groups — clearer namespace separation vs VMX prefix
- [03-01]: draw_cursor/draw_selection use VM_CursorSecondary/VM_ExtendSecondary by default — redraw() chooses primary/secondary per-cursor
- [03-01]: Region.new mode parameter defaults to 'cursor' — backward compat with 63 existing specs
- [03-01]: anchor_mark_id only created when mode='extend' AND anchor table provided — no unnecessary extmarks in cursor mode
- [03-01]: tip_mark_id=nil reserved for redraw engine — not created by Region.new, set externally by Phase 3 Wave 2
- [03-01]: primary_idx=0 sentinel means no cursors added yet (0 not -1 to avoid off-by-one with 1-indexed Lua arrays)
- [03-02]: Read-then-clear-then-draw order in redraw() — positions must be cached before nvim_buf_clear_namespace to avoid reading stale deleted marks
- [03-02]: No id= in redraw draw helpers — after clear_namespace old IDs are invalid; create new marks, store returned IDs back
- [03-02]: Dual-extmark for extend mode — sel_mark_id = selection span (priority 200), tip_mark_id = cursor-tip overlay (priority 201)
- [03-02]: anchor recreated each redraw with right_gravity=false to preserve position tracking after buffer edits
- [03-02]: toggle_mode() now calls hl.redraw(session); set_mode/set_cursor_mode/set_extend_mode do NOT call redraw (Phase 4+ callers manage)

### Pending Todos

None yet.

### Blockers/Concerns

- [Research]: PITFALL-06 (operator-pending getchar blocking) has no fully specified prevention strategy — needs spike before Phase 4/5. Consider vim.on_key vs <expr> mapping for operator capture.
- [Research]: Interactive behavioral validation cannot be covered by headless unit tests alone — manual test plan for insert mode, operator-pending, and mouse cursors must be written before Phase 8.
- [Research]: Surround integration compatibility boundary not fully specified — clarify during Phase 6.

## Session Continuity

Last session: 2026-02-28
Stopped at: Completed 03-02-PLAN.md (highlight.redraw engine, _col_end, _draw_cursor_region, _draw_extend_region, toggle_mode anchor wiring, 73 mini.test specs pass — Phase 3 plan 2 complete)
Resume file: None
