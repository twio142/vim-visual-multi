# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Lua Rewrite Foundation

**Shipped:** 2026-03-01
**Phases:** 5 (1–4.1) | **Plans:** 11 | **Timeline:** 2 days

### What Was Built
- Plugin bootstrap: VimScript shim stripped to version guard, mini.test vendored, headless runner
- Foundation modules: config.lua (deep-merge), util.lua (byte helpers), highlight.lua, region.lua, undo.lua
- Session lifecycle: per-buffer start/stop, option/keymap save/restore, BufDelete guard, events
- Extmark rendering engine: multibyte-safe redraw, dual-extmark extend-mode, toggle_mode wiring
- Normal-mode executor: feedkeys-per-cursor with undojoin undo grouping; VM register; case/replace/g_increment
- Gap closure: VM_ groups at startup, g_increment undojoin — 102 tests passing, 0 failures

### What Worked
- **Interface-first planning:** writing the spec stubs (Phase 4 plan 01) before implementation caught contract mismatches early
- **Audit-then-fix pattern:** running `/gsd:audit-milestone` before completion caught 2 real wiring gaps (GAP-01, GAP-02) that would have been silent bugs
- **Incremental verification:** each plan confirming 0 failures before the next plan made root-cause isolation trivial
- **Pitfall documentation in STATE.md:** the 11-decision accumulation in Accumulated Context gave each new phase instant access to all prior gotchas
- **mini.test headless runner:** extremely fast feedback loop — plans completed in 2-8 minutes each

### What Was Inefficient
- **ROADMAP plan checkboxes not updated automatically:** the plan `[ ]` checkboxes in ROADMAP.md required manual updates after each plan completion — a source of drift
- **Two audit cycles:** initial audit found gaps, required inserting Phase 4.1, then re-auditing — avoidable if audit happened before Phase 4 execution was committed as "done"
- **STATE.md "current focus" field:** became stale (still said "Phase 4.1 — Gap Closure" after completion); not updated until milestone close

### Patterns Established
- **undojoin-for-all-feedkeys-loops:** every multi-cursor feedkeys loop must use the first/undojoin pattern for FEAT-06 compliance — canonical in edit.lua M.exec
- **define_groups() in setup():** highlight groups must be registered at plugin load, not lazily — canonical in init.lua
- **nvim_create_buf(false, false) for test buffers:** scratch buffers silently disable undo; all test buffers that test undo must use false,false
- **Tier-0 highlight.lua:** highlight module must never require region.lua to avoid circular dependency at load time

### Key Lessons
1. **Audit before shipping, not after:** running audit before marking phases complete (not after) would have caught GAP-01/GAP-02 and avoided Phase 4.1 entirely
2. **Headless unit tests can't catch integration wiring gaps:** `define_groups()` not being called from `setup()` was invisible to module-level tests — only integration-style tests catch it
3. **feedkeys undo semantics require explicit undojoin:** Vim's undo system doesn't auto-group feedkeys calls even within the same function — must be deliberate
4. **Dot in directory names blocks require():** `mini.test/` requires `dofile()` not `require()` — document this immediately when encountered

### Cost Observations
- Sessions: ~6 (planning, 11 plans, audit, gap closure, re-audit)
- Model: Claude Sonnet 4.6 throughout
- Notable: very low cost per plan due to tight plan scope and fast headless test feedback

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | ~6 | 5 (1-4.1) | First milestone — baseline established |

### Cumulative Quality

| Milestone | Tests | Zero-Dep Additions |
|-----------|-------|-------------------|
| v1.0 | 102 | 0 |

### Top Lessons (Verified Across Milestones)

1. Audit before marking phases complete — not after — to avoid correction phases
2. Headless unit tests cannot catch integration wiring gaps; need integration-level assertions
