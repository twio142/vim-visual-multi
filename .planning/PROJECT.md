# vim-visual-multi Lua Rewrite

## What This Is

vim-visual-multi is a Neovim plugin for multiple cursor editing. This project is a clean rewrite of the existing VimScript implementation into idiomatic Lua, targeting Neovim 0.10+ only, with a conventional `setup()` configuration API replacing all `g:VM_xxx` global variables.

**v1.0 shipped:** Core infrastructure — session lifecycle, extmark rendering, normal-mode multi-cursor operations with correct undo semantics. 102 tests, 0 failures.

## Core Value

All existing multi-cursor behaviors work identically after the rewrite — users lose no functionality, and configuration becomes ergonomic via setup().

## Requirements

### Validated

- ✓ Pure Lua plugin loads without errors on Neovim 0.10+ — v1.0 (LUA-01)
- ✓ Targets Neovim 0.10+ only — extmarks, vim.api, vim.keymap.set, nvim_create_autocmd — v1.0 (LUA-02)
- ✓ No Python dependency — byte operations replaced with nvim_buf_get_offset — v1.0 (LUA-03)
- ✓ setup(opts) is the sole config entry point — no g:VM_xxx read or written — v1.0 (CFG-01)
- ✓ Cursor mode and extend mode with switching via `v` key — v1.0 (FEAT-03)
- ✓ Simultaneous normal-mode commands (d, c, y, p, D, C, x, and standard ops) — v1.0 (FEAT-05)
- ✓ Undo grouping — all-cursor edits within a session undo as a single operation — v1.0 (FEAT-06)
- ✓ Extmark-based cursor/selection highlighting with VM_ highlight groups — v1.0 (FEAT-07)
- ✓ Case conversion, replace-chars, number increment/decrement (C-a/C-x/g-variants) — v1.0 (FEAT-10)

### Active

- [ ] Simultaneous insert mode — i/a/I/A/o/O replicated across all cursors (FEAT-04)
- [ ] Per-cursor register management — VM unnamed register (FEAT-12)
- [ ] Add cursor at word, arbitrary position, up/down by line (FEAT-01)
- [ ] Pattern-based multi-select: VM-/, find-under (C-n), select-all, visual entry (FEAT-02)
- [ ] Region lifecycle — skip (q), remove (Q), filter, one-per-line (FEAT-08)
- [ ] Alignment, number insertion, transpose, rotate, split, duplicate (FEAT-09)
- [ ] Run-normal, run-visual, run-ex, run-macro, dot-repeat (FEAT-11)
- [ ] Mouse support, file size guard (FEAT-15)
- [ ] Statusline integration — VMInfos() (FEAT-13)
- [ ] Plugin compatibility hooks (FEAT-14)
- [ ] All 34 g:VM_xxx options exposed as setup(opts) keys (CFG-02 through CFG-10)
- [ ] mini.test suite covering all 14 Lua modules (TEST-01)
- [ ] Behavioral parity confirmed via pynvim regression harness (TEST-02)

### Out of Scope

- Vim 8 compatibility — Neovim-only from now on
- Backward compatibility with `g:VM_xxx` config variables — clean break; users must update their config
- Python helper (`python/vm.py`) — replaced by Lua + nvim_buf_get_offset

## Context

**v1.0 (2026-03-01):** Shipped 5 phases (1–4.1), 11 plans, 102 tests. Core infrastructure complete: 12 Lua modules, session model, extmark rendering, feedkeys executor with undojoin grouping.

**Tech stack:** Lua (Neovim 0.10+), extmarks API, mini.test for headless unit testing.

**Next milestone (v2.0):** Insert mode, search/entry points (C-n, VM-/), full configuration surface, interactive E2E validation. Phases 5-8.

**Open research items:**
- PITFALL-06 (operator-pending getchar blocking) — prevention strategy unspecified; spike needed before Phase 4/5
- Interactive behavioral validation requires manual test plan for insert mode, operator-pending, mouse cursors
- Surround integration compatibility boundary unclear — clarify during Phase 6

## Constraints

- **Runtime**: Neovim only — use Neovim-specific APIs freely
- **Language**: Lua only — no VimScript autoload files in the ported plugin
- **Config API**: `setup(opts)` is the only supported config mechanism
- **Compatibility**: No migration path from `g:VM_xxx` — users must update their config

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Start fresh from master (VimL) | Previous Lua branch carries legacy structure; cleaner to port from source of truth | ✓ Good — reference branch helped avoid pitfalls without inheriting structure |
| No backward compat with g:VM_xxx | Cleaner API; avoids supporting two config systems indefinitely | ✓ Good — setup() API works cleanly |
| Drop Python dependency | Python optional in Neovim, adds complexity; Lua can handle byte operations | ✓ Good — nvim_buf_get_offset works cleanly |
| Neovim-only | Enables extmarks, lua API, modern autocmd system; Vim 8 is legacy | ✓ Good — extmarks essential for correct rendering |
| dofile() for mini.test loading | Dot in 'mini.test' dir name prevents require() path resolution | ✓ Good — stable workaround |
| highlight.lua is Tier-0 (no region.lua dependency) | Prevents circular require at load time | ✓ Good — clean layer separation |
| Read-then-clear-then-draw in redraw() | Positions must be cached before nvim_buf_clear_namespace | ✓ Good — prevents stale extmark reads |
| undojoin between cursor iterations | Feedkeys-based edits need explicit join for single-undo-entry grouping | ✓ Good — all-cursor ops undo as one |
| nvim_create_buf(false, false) for test buffers | Scratch buffers (true) have undolevels=-1; undo tests need real undo | ✓ Good — BUG-02 definitively prevented |
| GAP-01: define_groups() called from setup() | Ensures VM_ groups defined at plugin load, not lazily | ✓ Good — lazy.nvim works correctly |
| GAP-02: g_increment uses first/undojoin pattern | N-cursor g_increment must produce 1 undo entry, not N | ✓ Good — consistent with exec() contract |

---
*Last updated: 2026-03-01 after v1.0 milestone*
