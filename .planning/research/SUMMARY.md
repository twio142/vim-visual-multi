# Research Summary: vim-visual-multi Lua Rewrite

**Date:** 2026-02-28
**Project:** vim-visual-multi — complete rewrite from VimScript/Python to pure Lua (Neovim-only)
**Research files synthesized:** STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md

---

## Executive Summary

vim-visual-multi is a complex, stateful Neovim plugin implementing multi-cursor editing. The rewrite replaces ~3,000 lines of VimScript autoload + a Python byte-operations helper with pure Lua using the modern Neovim API. The prior Lua port (`001-lua-nvim-rewrite` branch) reached Phases 1-8 and confirmed behavioral parity with the VimScript plugin (94 unit tests, 0 failures, 3/18 integration tests passing — with failures attributed to pynvim `input()` limitations, not Lua bugs). This is therefore a **completion effort**, not a greenfield rewrite: the architecture, module layout, and test infrastructure are established and validated.

The recommended approach is a tier-based build order that ensures unit-testable foundations before integration code is written. The key architectural insight is that extmarks replace all `matchaddpos`/`matchdelete` highlight management, eliminating an entire class of ghost-highlight bugs. Per-buffer session state lives in a module-level `_sessions` table keyed by bufnr; immutable config is separated from mutable session state from day one. The prior Lua branch already embodies these patterns — the remaining work is completing the deferred tasks (interactive e2e validation, bootstrap shim removal) and hardening against the 14 identified pitfalls.

The primary risks are all known and documented: undo grouping correctness (4 confirmed bugs from the prior port), session lifecycle edge cases (reentrancy, orphaned autocmds), and the byte/character coordinate system confusion inherited from the VimScript source. Every risk has a concrete prevention strategy. The codebase is well-understood; the remaining uncertainty is in interactive behavioral validation, which cannot be covered by headless unit tests alone.

---

## Key Findings

### From STACK.md

| Decision | Recommendation | Confidence |
|----------|----------------|------------|
| Minimum Neovim version | 0.10.0 (current stable; do not target 0.9) | HIGH |
| Module structure | `lua/visual-multi/*.lua` flat layout, 14 modules | HIGH |
| Config API | `setup(opts)` with `vim.tbl_deep_extend('force', defaults, opts)` + `vim.validate` | HIGH |
| Config storage | Module-local `_cfg`, never `vim.g.*` | HIGH |
| Extmarks | Single `nvim_create_namespace('visual_multi')`, store IDs, update with `id=` param | HIGH |
| Keymap API | `vim.keymap.set` + `vim.keymap.del`; `<Plug>` layer for user-remappable actions | HIGH |
| Session keymaps | Buffer-local (`buffer = buf`), cleaned up on exit | HIGH |
| Autocmds | Per-session augroup (`'VMSession_' .. buf`), cleared atomically on exit | HIGH |
| Test framework | mini.test (vendored); retain Python/pynvim e2e for behavioral regression | HIGH |
| Window options | `vim.wo[win]` for `conceallevel`/`concealcursor`/`statusline`; `vim.bo[buf]` for buffer-local | HIGH |
| User messages | `vim.notify(msg, level)` — never `echon`/`print` | HIGH |
| Undo operations | Must run inside `nvim_buf_call(buf, ...)` to target the correct buffer | HIGH |

Critical version requirement: **Neovim 0.10.0 minimum**. The `vim.iter` API, refined `vim.bo`/`vim.wo` semantics, and stable `hl_mode` on extmarks all require 0.10. Do not ship workarounds for bugs fixed in 0.10.

### From FEATURES.md

**Table stakes (9 — plugin is unusable without these):**
- Add cursor at word under cursor (`<C-n>` find-under)
- Add cursor at arbitrary position (keypress or click)
- Add cursors up/down by line
- Exit multi-cursor mode
- Simultaneous insert mode (keystroke replication)
- Simultaneous normal commands (`d`, `c`, `y`, `p`, etc.)
- Undo grouping (all-cursor edits as one undo step)
- Cursor highlighting (visual distinction)
- Keymap configuration (user remapping)

**Differentiators (26 — what makes vim-visual-multi special):**

Top-tier (core identity): cursor mode vs extend mode, pattern-based multi-select, skip/remove region, filter regions, align, number insertion, transpose/rotate, run normal/visual/ex/macro at all cursors, case conversion, per-cursor registers.

Secondary: theming system (15 built-in themes), statusline integration, plugin compatibility hooks, dot-repeat, increase/decrease numbers (`<C-a>/<C-x>`), visual-mode entry points, surround integration, split/duplicate/merge regions.

**What to defer to v2+:** persistent registers (`shada` integration), profiling (T056), bootstrap shim cleanup (T002/T055 — already explicitly deferred in MEMORY.md).

**Full g:VM_xxx catalogue:** 34 distinct configuration variables mapped to a clean `setup(opts)` table with snake_case keys and logical groupings (`insert = {}`, `statusline = {}`, `plugins_compat = {}`).

### From ARCHITECTURE.md

**14-module layout with 5 dependency tiers:**

```
Tier 0 (no internal deps): config.lua, util.lua, highlight.lua
Tier 1 (depends on Tier 0): region.lua, undo.lua
Tier 2 (depends on Tier 1): global.lua, search.lua
Tier 3 (depends on Tier 2): maps.lua, edit.lua, insert.lua, operators.lua, case.lua
Tier 4 (assembles everything): session.lua, commands.lua, init.lua
```

**Key architectural decisions:**
- Module-level `_sessions` table (keyed by bufnr) replaces `b:VM_Selection` — fully testable, no buffer-variable limitations, supports multiple simultaneous VM sessions
- Single extmark namespace (`nvim_create_namespace('visual_multi')`) — atomic clear on session exit, no per-region namespace complexity
- `with_undo_block(session, fn)` wrapper in `undo.lua` — encapsulates `undojoin` sequencing so `edit.lua` does not know undo internals
- `util.lua` absorbs the two Python functions (`py_rebuild_from_map`, `py_lines_with_regions`) — pure Lua, no external dependency
- `nvim_buf_call(buf, fn)` pattern for all undo/cursor operations — ensures correct buffer context regardless of window focus
- Eco mode: `no_redraw = true` flag passed during bulk cursor loops, batch extmark updates after loop completes

**VimScript-to-Lua module mapping:** All 15 VimScript autoload files map directly to the 14 Lua modules. The three `edit*.vim` files merge into one `edit.lua`; `insert.vim` + `icmds.vim` merge into `insert.lua`; `variables.vim` folds into `session.lua`.

**Python replacement:** `nvim_buf_get_offset(buf, row)` is the canonical byte-offset API, replacing `line2byte()`. Extmarks eliminate nearly all manual byte-offset arithmetic that Python existed to solve.

### From PITFALLS.md

**5 confirmed bugs from prior Lua port (HIGH confidence — will recur):**

| ID | Bug | Phase |
|----|-----|-------|
| BUG-01 | Window-local options (`conceallevel`, `concealcursor`, `statusline`) written via `vim.bo` instead of `vim.wo` — silently fails | Phase 1 (session lifecycle) |
| BUG-02 | `nvim_create_buf(false, true)` scratch buffers have `undolevels=-1` — undo tests silently pass but test nothing | Phase 0 (test infra) |
| BUG-03 | Undo grouping flush uses `vim.o.undolevels` (global) instead of `vim.bo[buf].undolevels` — corrupts undo in other open buffers | Phase 4 (insert mode) |
| BUG-04 | Empty undo block (no net change) still advances `seq_cur` — spurious undo step for no-op operations | Phase 4 (insert mode) |
| BUG-05 | Overloaded function signatures (two definitions of same table key) — second definition silently shadows first | Phase 0 (module API design) |

**9 translation pitfalls from VimScript patterns (HIGH/MEDIUM confidence):**

| ID | Pitfall | Severity |
|----|---------|----------|
| PITFALL-01 | `b:VM_Selection` circular refs if session holds back-reference to `_sessions` | HIGH |
| PITFALL-02 | `noautocmd` suppression — `vim.cmd('normal! ...')` still fires autocmds during cursor iteration | HIGH |
| PITFALL-03 | `s:` script-local singletons — module-level state shared across all buffers corrupts multi-session use | HIGH |
| PITFALL-04 | Byte vs character coordinates — `#str` returns bytes; mixing with `nvim_buf_set_text` byte API produces cursor drift | HIGH |
| PITFALL-05 | `matchaddpos` → extmarks migration incomplete — ghost highlights if any `matchaddpos` call is left | HIGH |
| PITFALL-06 | `getchar()` blocking in operator-pending handlers — freezes event loop in Lua | MEDIUM |
| PITFALL-07 | `pcall` swallowing real errors — surgical `silent!` becomes broad exception suppression | MEDIUM |
| PITFALL-08 | Orphaned insert-mode autocmd IDs on abnormal exit (`<C-c>`, `:stopinsert`) | HIGH |
| PITFALL-09 | Keymap save/restore — `vim.keymap.del` destroys pre-existing user buffer maps without restoring | HIGH |
| PITFALL-10 | Option save/restore uses current buffer context instead of explicit `buf` handle | MEDIUM |
| PITFALL-11 | Reentrancy: no guard against double-initialization if autocmd fires during session init | MEDIUM |
| PITFALL-12 | `vim.fn.undotree()` and `vim.cmd('undo')` target current buffer, not session buffer | HIGH |
| PITFALL-13 | `g:Vm` runtime state (extend_mode, etc.) put at module level corrupts multi-buffer sessions | HIGH |
| PITFALL-14 | `string.len` vs byte vs character confusion inherited from VimScript `strlen()` FIXME | MEDIUM |

---

## Implications for Roadmap

The prior Lua port completed Phases 1-8. What remains is completion of deferred items and interactive validation. The phase structure below reflects the **remaining work**, anchored to the existing codebase state described in MEMORY.md.

### Suggested Phase Structure

**Phase 1: Foundation Hardening** (Tier 0-1 modules)

Rationale: BUG-05 and PITFALL-03/13/14 must be prevented at the module API level before any higher-tier code is written. The existing `001-lua-nvim-rewrite` branch already has `config.lua`, `util.lua`, `highlight.lua`, `region.lua`, and `undo.lua` — this phase audits them against the pitfall list and locks in conventions.

Delivers: Confirmed-correct foundations; `_is_session()` dispatch convention; named string-length helpers; immutable config / mutable session separation verified.

Features covered: None user-visible (internal correctness).

Pitfalls to prevent: BUG-05, PITFALL-03, PITFALL-13, PITFALL-14, BUG-02 (test infra).

Research flag: Standard patterns — no phase research needed.

---

**Phase 2: Session Lifecycle and Keymap Management** (session.lua + maps.lua)

Rationale: BUG-01 and PITFALL-09/10/11 are session-boundary bugs. Getting session start/stop correct before building any operations on top prevents subtle state leaks that are hard to diagnose later. The prior branch implemented this; this phase validates the implementation against all 14 pitfalls.

Delivers: Clean session start/stop, correct option save/restore (`vim.wo` for window-local, `vim.bo[buf]` for buffer-local), keymap save/restore (user pre-existing maps preserved), reentrancy guard.

Features covered: Session enter/exit (table stakes #4 — "exit multi-cursor mode").

Pitfalls to prevent: BUG-01, PITFALL-08 (autocmd cleanup), PITFALL-09, PITFALL-10, PITFALL-11.

Research flag: Standard patterns — no phase research needed.

---

**Phase 3: Region and Highlight System** (region.lua + highlight.lua + global.lua)

Rationale: Extmarks are the core innovation of the Lua rewrite. PITFALL-04 and PITFALL-05 (coordinate system and ghost highlights) are eliminated by committing to extmarks as the sole position-tracking mechanism. This phase must be complete before any edit operations.

Delivers: Region create/update/remove with extmark-tracked positions, cursor and extend-mode highlighting, eco mode (batch updates), single-namespace teardown.

Features covered: Cursor highlighting (table stakes #8), cursor mode vs extend mode (differentiator).

Pitfalls to prevent: PITFALL-04, PITFALL-05, PITFALL-01 (no circular session references).

Research flag: Standard patterns — extmark API well-documented.

---

**Phase 4: Normal-Mode Operations** (edit.lua + undo.lua + operators.lua + case.lua)

Rationale: The `with_undo_block` pattern and `nvim_buf_call` wrapping must be correct before insert mode, which has the same undo requirements plus more complexity. BUG-03/04 are undo bugs that surface here.

Delivers: `d`, `c`, `y`, `p`, `~`, `r`, `R`, increase/decrease numbers, case conversion, custom operators at all cursors; all edits undo as single steps.

Features covered: Simultaneous normal commands (table stakes #6), undo grouping (table stakes #7), case conversion (differentiator), increase/decrease (differentiator), dot-repeat (differentiator).

Pitfalls to prevent: BUG-03, BUG-04, PITFALL-02 (autocommand suppression during edit loop), PITFALL-12.

Research flag: May benefit from research — undo grouping across N cursors is the hardest correctness problem in the plugin.

---

**Phase 5: Insert Mode** (insert.lua)

Rationale: Insert-mode synchronization is the most complex component. It depends on all prior phases being correct. PITFALL-08 (orphaned autocmds) is most dangerous here.

Delivers: All cursors enter insert mode simultaneously, keystrokes replicate, single-region mode, Tab/S-Tab cycling, InsertLeave synchronization.

Features covered: Simultaneous insert mode (table stakes #5), single-region mode (differentiator), live editing (differentiator).

Pitfalls to prevent: PITFALL-02, PITFALL-08, BUG-03, BUG-04, PITFALL-06 (operator-pending), PITFALL-12.

Research flag: Phase research recommended — insert-mode event sequencing edge cases benefit from explicit investigation.

---

**Phase 6: Search, Entry Points, and Commands** (search.lua + commands.lua)

Rationale: With operations complete, wire up the user-facing entry points. This is the integration layer.

Delivers: `<C-n>` find-under, select-all, regex search, skip/remove region, filter, align, numbers, transpose, run normal/visual/ex/macro, visual-mode entry points.

Features covered: All differentiator features not covered in earlier phases; completes table stakes #1-3.

Pitfalls to prevent: PITFALL-13 (per-session registers, not module-level), PITFALL-06 (operator capture).

Research flag: Standard patterns — no phase research needed.

---

**Phase 7: Configuration Surface and Plugin API** (config.lua full pass + init.lua + plugin/visual-multi.lua)

Rationale: All 34 `g:VM_xxx` variables must be exposed as `setup(opts)` keys. This is a completeness pass — all earlier phases used a partial config.

Delivers: Full `setup(opts)` API, all g:VM_xxx options mapped, `<Plug>` layer, user commands, ColorScheme autocmd for highlight groups, `VMTheme` command, theming system.

Features covered: Keymap configuration (table stakes #9), theming (differentiator), statusline integration (differentiator), plugin compat hooks (differentiator).

Pitfalls to prevent: PITFALL-07 (targeted pcall, not broad suppression).

Research flag: Standard patterns — no phase research needed.

---

**Phase 8: Interactive E2E Validation** (T002/T055 deferred tasks)

Rationale: The 15/18 integration test failures are pynvim limitations, not bugs. This phase validates interactive behavior through manual testing and the pynvim harness for smoke tests. Bootstrap shim / autoload deletion (T002) happens here.

Delivers: Confirmed behavioral parity with VimScript plugin, bootstrap shim removed, autoload files deleted.

Features covered: Full feature set verification.

Pitfalls to prevent: All phase-level pitfalls verified via test scenarios.

Research flag: Standard — no research needed, but interactive test scenarios should be documented before starting.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs are Neovim 0.10 stable; mini.test already vendored and in use; recommendations confirmed against existing branch |
| Features | HIGH | Complete g:VM_xxx catalogue sourced directly from VimScript files and docs; 34 variables identified; setup() mapping is complete |
| Architecture | HIGH | 5-tier dependency graph is clean and consistent with existing branch layout; module boundaries are explicit; Python replacement is trivial |
| Pitfalls | HIGH (confirmed bugs) / MEDIUM (translation pitfalls) | BUG-01 through BUG-05 were discovered and fixed in prior port — recurrence risk is real. PITFALL-06 through PITFALL-14 are inferred from source analysis; verify during implementation |

**Overall: HIGH**

### Gaps to Address

1. **Interactive behavioral validation is the only unresolved gap.** The pynvim harness cannot reliably test interactive flows due to `input()` blocking. A manual test plan for interactive scenarios (insert mode, operator-pending, mouse cursors) should be written before Phase 8.

2. **PITFALL-06 (operator-pending getchar blocking)** is the one pitfall without a fully specified prevention strategy. `vim.on_key` vs `<expr>` mapping for operator capture needs a spike before Phase 4/5.

3. **Surround integration** depends on vim-surround or nvim-surround being present — the compatibility boundary is not fully specified. This needs clarification during Phase 6.

4. **Filesize limit guard** (`filesize_limit` option, default 0 = disabled) — the VimScript source implements this but the prior Lua branch's implementation status is not confirmed. Verify during Phase 2.

---

## Sources

Aggregated from research files:

- Neovim 0.10 stable API documentation (STACK.md)
- VimScript source: `plugin/visual-multi.vim`, `autoload/vm.vim`, `autoload/vm/maps.vim`, `autoload/vm/maps/all.vim`, `autoload/vm/variables.vim`, `autoload/vm/commands.vim`, `autoload/vm/insert.vim`, `autoload/vm/icmds.vim`, `autoload/vm/cursors.vim`, `autoload/vm/special/case.vim`, `autoload/vm/funcs.vim`, `autoload/vm/themes.vim`, `autoload/vm/comp.vim`, `autoload/vm/plugs.vim`, `autoload/vm/region.vim` (FEATURES.md, ARCHITECTURE.md, PITFALLS.md)
- Documentation: `doc/vm-settings.txt`, `doc/vm-mappings.txt`, `doc/vm-troubleshooting.txt` (FEATURES.md)
- Prior Lua port: `001-lua-nvim-rewrite` branch confirmed bugs BUG-01 through BUG-05 (PITFALLS.md)
- `.planning/codebase/CONCERNS.md` (PITFALLS.md)
- `.planning/PROJECT.md` (PITFALLS.md)
- MEMORY.md: T052 finding (pynvim limitation), confirmed deferred tasks (T002/T055/T056)
- Reference plugins: `gitsigns.nvim` (per-buffer extmark lifecycle), `mini.nvim` (setup/config patterns), `nvim-treesitter` (module loading, namespace), `telescope.nvim` (Plug mapping pattern), `Comment.nvim` (buffer-local keymap lifecycle) (STACK.md)

*Research synthesized: 2026-02-28*
