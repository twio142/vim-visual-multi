---
phase: 03-region-and-highlight
verified: 2026-02-28T20:00:00Z
status: passed
score: 13/13 must-haves verified
re_verification: false
gaps: []
---

# Phase 3: Region and Highlight Verification Report

**Phase Goal:** Regions (cursor and extend-mode selections) are tracked with extmarks and rendered correctly, with atomic teardown on session exit and no ghost highlights
**Verified:** 2026-02-28T20:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Four highlight groups VM_Cursor, VM_CursorSecondary, VM_Extend, VM_ExtendSecondary defined with default=true | VERIFIED | `define_groups()` in highlight.lua lines 23-33: all four groups present with `default = true` and correct link targets |
| 2 | Region objects carry sel_mark_id, anchor_mark_id, tip_mark_id, and mode fields | VERIFIED | region.lua lines 32-64: Region.new populates all four fields; sel_mark_id is integer extmark, anchor_mark_id set in extend mode, tip_mark_id=nil reserved |
| 3 | session._new_session() includes primary_idx = 0 | VERIFIED | session.lua line 28: `primary_idx = 0` present with explanatory comment |
| 4 | Region:pos() and Region:move() and Region:remove() use sel_mark_id internally | VERIFIED | region.lua line 72: pos() uses `self.sel_mark_id`; line 86: move() uses `id = self.sel_mark_id`; line 101: remove() pcall-deletes `self.sel_mark_id`, tip_mark_id, anchor_mark_id |
| 5 | All 63 Phase 1+2 specs continue to pass after field renames | VERIFIED | Test suite: 73 tests, 0 failures — all pre-existing 63 specs pass |
| 6 | highlight.redraw(session) clears all extmarks then redraws each cursor with correct primary/secondary group | VERIFIED | highlight.lua lines 199-234: read-then-clear-then-draw pattern; nvim_buf_clear_namespace line 220 (atomic clear); primary/secondary dispatch lines 226-231 |
| 7 | Cursor-mode regions render as single-char VM_Cursor (primary) or VM_CursorSecondary (others) | VERIFIED | _draw_cursor_region lines 115-128; spec "redraw draws primary cursor with VM_Cursor hl_group" passes |
| 8 | Extend-mode regions render as span extmark (VM_Extend/VM_ExtendSecondary) at priority 200 plus cursor-tip overlay at priority 201 | VERIFIED | _draw_extend_region lines 138-188; sel_mark_id priority 200 (line 165), tip_mark_id priority 201 (line 177); spec "extend-mode redraw" passes |
| 9 | Zero-width extend regions (anchor == tip) fall back to cursor-mode render | VERIFIED | _draw_extend_region lines 145-149: `if tip_row == anc_row and tip_col == anc_col then _draw_cursor_region(...)` ; spec "zero-width extend region falls back" passes |
| 10 | session.toggle_mode() calls hl.redraw() after flipping extend_mode and updating region anchor/mode fields | VERIFIED | session.lua lines 231-264: toggle_mode() pins/collapses anchors per-region, flips extend_mode, then calls `hl.redraw(session)` at line 263 |
| 11 | After session.stop(), nvim_buf_get_extmarks returns empty for the VM namespace | VERIFIED | session.lua line 214: stop() calls `require('visual-multi.highlight').clear(session)` which calls nvim_buf_clear_namespace; spec "clear after redraw leaves no extmarks" confirms behavior |
| 12 | No matchadd or matchaddpos anywhere in lua/ tree | VERIFIED | Grep found zero function calls; only a comment in session.lua line 62 mentioning the VimScript source's use of matchadd — no actual calls |
| 13 | _col_end(buf, row, col) helper exists for multibyte safety (PITFALL-14 guard) | VERIFIED | highlight.lua lines 100-108: local function using vim.fn.matchstr to get char byte width, handles empty lines and EOL positions |

**Score:** 13/13 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lua/visual-multi/highlight.lua` | define_groups() with 4 Phase-3 highlight groups (VM_ prefix); redraw(), _col_end, _draw_cursor_region, _draw_extend_region | VERIFIED | All six exports present; file is 237 lines of substantive code |
| `lua/visual-multi/region.lua` | Region data model with sel_mark_id, anchor_mark_id, tip_mark_id, mode | VERIFIED | 113 lines; all four fields present; Region.new(buf, row, col, mode, anchor) signature correct |
| `lua/visual-multi/session.lua` | _new_session() with primary_idx = 0; toggle_mode() wired with hl.redraw | VERIFIED | 288 lines; primary_idx present on line 28; toggle_mode expanded with anchor setup/collapse and redraw call |
| `test/spec/highlight_spec.lua` | T_redraw set with 7 new redraw specs | VERIFIED | 269 lines; T_redraw set present (lines 99-268) with 7 specs covering all Phase 3 rendering behaviors |
| `test/spec/region_spec.lua` | 3 new extend-mode specs; all r.mark_id references replaced with r.sel_mark_id | VERIFIED | 118 lines; specs 7-9 (lines 83-115) cover extend-mode Region.new; zero r.mark_id references remain |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `region.lua Region:pos()` | `highlight.lua ns` | nvim_buf_get_extmark_by_id using sel_mark_id | WIRED | Line 71-74: `hl.ns, self.sel_mark_id` used in get_extmark_by_id call |
| `test/spec/region_spec.lua` | `region.lua` | r.sel_mark_id assertions | WIRED | Lines 25-26, 43, 49, 65: all assertions use sel_mark_id; zero r.mark_id references |
| `highlight.lua redraw()` | `session.lua toggle_mode()` | require('visual-multi.highlight').redraw(session) | WIRED | session.lua line 232: `local hl = require('visual-multi.highlight')`; line 263: `hl.redraw(session)` |
| `highlight.lua _draw_extend_region()` | `region.lua anchor_mark_id` | nvim_buf_get_extmark_by_id reading anchor position | WIRED | redraw() Phase 1 (lines 210-214) reads anchor_mark_id; _draw_extend_region receives pre-cached _anc_row/_anc_col |
| `highlight.lua _col_end()` | `nvim_buf_set_extmark end_col` | vim.fn.matchstr byte-width calculation | WIRED | _col_end called in _draw_cursor_region line 120, _draw_extend_region lines 155, 158, 175 |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FEAT-07 | 03-01, 03-02 | Extmark-based cursor/selection highlighting with full theming system (15 built-in themes + VMTheme command) | SATISFIED (core) | Extmark-based rendering engine fully implemented: define_groups(), redraw(), primary/secondary groups, extend-mode dual extmarks. Theming system (VMTheme command, 15 themes) is beyond Phase 3 scope — noted as Phase 6 concern. Core FEAT-07 extmark contract is complete. |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| session.lua | 62 | Comment mentions "matchadd" in reference to VimScript source | Info | No impact — comment only, zero actual matchadd/matchaddpos calls anywhere in lua/ tree |

No blockers. No warnings.

---

### Human Verification Required

None — all Phase 3 behaviors are verifiable programmatically via the mini.test suite.

---

### Summary

Phase 3 is fully achieved. Both waves delivered their contracts:

**Wave 1 (03-01 — Data Model):** The highlight group namespace was migrated to VM_ prefix with six groups. Region objects were expanded from single mark_id to a four-field extmark contract (sel_mark_id, anchor_mark_id, tip_mark_id, mode). primary_idx = 0 was added to the session table. All 63 pre-existing specs were updated and continue to pass.

**Wave 2 (03-02 — Redraw Engine):** highlight.redraw(session) implements the read-then-clear-then-draw pattern that prevents ghost marks. The _col_end helper guards against PITFALL-14 (col+1 wrong for multibyte). Cursor-mode renders as a single-char extmark; extend-mode renders as a dual-extmark layout (selection span at priority 200, cursor-tip overlay at priority 201) with zero-width fallback. session.toggle_mode() pins anchor extmarks on cursor→extend and collapses them on extend→cursor, then calls redraw. Ten new specs were added (7 highlight, 3 region), bringing the total from 63 to 73 with zero failures.

All ten phase-specific verification points pass:
1. Test suite exits 0 — 73 specs, 0 failures
2. FEAT-07 extmark contract — sel_mark_id, anchor_mark_id, tip_mark_id all present
3. highlight.redraw() — clear-all then draw-all pattern confirmed
4. _col_end() — multibyte-safe helper confirmed
5. Four canonical highlight groups — VM_Cursor, VM_CursorSecondary, VM_Extend, VM_ExtendSecondary all defined with default=true
6. primary_idx field on session — present in _new_session()
7. Dual-extmark extend regions — priority 200 span + priority 201 cursor-tip overlay
8. Zero-width extend fallback — anchor==tip delegates to _draw_cursor_region
9. toggle_mode() calls hl.redraw() — wired at session.lua line 263
10. No matchadd or matchaddpos — zero function calls in lua/ tree

---

_Verified: 2026-02-28T20:00:00Z_
_Verifier: Claude (gsd-verifier)_
