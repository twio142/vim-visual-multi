# Milestones

## v1.0 Lua Rewrite Foundation (Shipped: 2026-03-01)

**Phases completed:** 5 phases (1–4.1), 11 plans
**Timeline:** 2026-02-28 → 2026-03-01 (2 days)
**Stats:** 49 files changed, 9,776 insertions, ~2,639 lines of Lua
**Tests:** 102 passing, 0 failures

**Key accomplishments:**
- Plugin bootstrap: VimScript shim stripped to version guard + require; mini.test vendored; headless test runner works
- Foundation modules: config.lua (deep-merge validation) + util.lua (nvim_buf_get_offset byte helpers, session dispatch) — 19 tests
- Session lifecycle: per-buffer start/stop, option/keymap save/restore, BufDelete guard, VMEnter/VMLeave events — 63 tests
- Extmark rendering engine: multibyte-safe redraw, dual-extmark extend-mode, toggle_mode wiring — 73 tests
- Normal-mode executor: feedkeys-per-cursor with undojoin undo grouping; per-cursor VM register; case/replace/g_increment ops — 89 tests
- Gap closure: VM_ highlight groups registered at setup(); g_increment undojoin for N-cursor single-undo guarantee — 102 tests

**Delivered:** Lua foundation for vim-visual-multi — session lifecycle, extmark rendering, and normal-mode operations at multiple cursors with correct undo semantics.

**Known tech debt (from v1.0 audit):**
- Full keymap table deferred to Phase 6 (only `v` key installed)
- `edit.lua` exports wired but not mapped to user keybindings (Phase 6)
- `config.get()` not consumed by any production code (Phase 5+)

**Archives:**
- `.planning/milestones/v1.0-ROADMAP.md`
- `.planning/milestones/v1.0-REQUIREMENTS.md`
- `.planning/milestones/v1.0-MILESTONE-AUDIT.md`

---

