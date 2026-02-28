# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-28)

**Core value:** All existing multi-cursor behaviors work identically after the rewrite — users lose no functionality, and configuration becomes ergonomic via setup()
**Current focus:** Phase 1 — Foundation

## Current Position

Phase: 1 of 8 (Foundation)
Plan: 2 of 4 in current phase
Status: In progress
Last activity: 2026-02-28 — Completed 01-02 (config.lua, util.lua, 19 tests pass)

Progress: [██░░░░░░░░] 6%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: 3 min
- Total execution time: 0.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation | 2 | 6 min | 3 min |

**Recent Trend:**
- Last 5 plans: 01-01 (3 min), 01-02 (3 min)
- Trend: stable

*Updated after each plan completion*

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

### Pending Todos

None yet.

### Blockers/Concerns

- [Research]: PITFALL-06 (operator-pending getchar blocking) has no fully specified prevention strategy — needs spike before Phase 4/5. Consider vim.on_key vs <expr> mapping for operator capture.
- [Research]: Interactive behavioral validation cannot be covered by headless unit tests alone — manual test plan for insert mode, operator-pending, and mouse cursors must be written before Phase 8.
- [Research]: Surround integration compatibility boundary not fully specified — clarify during Phase 6.

## Session Continuity

Last session: 2026-02-28
Stopped at: Completed 01-02-PLAN.md (config.lua, util.lua, 19 mini.test specs pass)
Resume file: None
