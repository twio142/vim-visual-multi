# Roadmap: vim-visual-multi Lua Rewrite

## Overview

This roadmap ports the VimScript/Python multi-cursor plugin to pure Lua, targeting Neovim 0.10+. The build order follows the 5-tier module dependency graph: foundations first, then session lifecycle, then the rendering layer, then operations, then the full config surface and validation. Each phase delivers a complete, unit-testable capability before the next phase is written. The prior `001-lua-nvim-rewrite` branch established the architecture and confirmed behavioral parity — this rewrite starts clean from master using that branch as a reference.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation** - Tier 0-1 module scaffolding: config, util, highlight, region, undo with pitfall guards baked in
- [ ] **Phase 2: Session Lifecycle** - Session start/stop, option save/restore, keymap management, reentrancy guard
- [ ] **Phase 3: Region and Highlight** - Extmark-based region tracking, cursor/extend-mode rendering, eco-mode batch updates
- [ ] **Phase 4: Normal-Mode Operations** - d/c/y/p/case/numbers at all cursors with correct undo grouping
- [ ] **Phase 5: Insert Mode** - Simultaneous keystroke replication, InsertLeave sync, per-cursor registers
- [ ] **Phase 6: Search, Entry Points, and Advanced Commands** - C-n, select-all, skip/remove/filter regions, align, transpose, run-normal/macro
- [ ] **Phase 7: Configuration Surface and Plugin API** - Full setup(opts) with all 34 g:VM_xxx options, Plug layer, statusline, theming, compat hooks
- [ ] **Phase 8: Interactive E2E Validation** - Behavioral parity confirmation, bootstrap shim removal, autoload deletion

## Phase Details

### Phase 1: Foundation
**Goal**: Tier 0-1 modules (config, util, highlight, region, undo) are written, tested, and hardened against the 5 confirmed bugs and key pitfalls — providing a correct base for all higher-tier code
**Depends on**: Nothing (first phase)
**Requirements**: LUA-01, LUA-02, LUA-03
**Success Criteria** (what must be TRUE):
  1. Plugin loads without errors on Neovim 0.10+ with no VimScript autoload files in the runtime path
  2. The mini.test suite runs headless and all Tier 0-1 module tests pass (0 failures)
  3. `_is_session()` dispatch convention is in place — no duplicate function definitions exist in any module
  4. `nvim_buf_get_offset` is the sole byte-offset API — no Python dependency, no `line2byte()` calls
  5. Test buffers use `nvim_create_buf(false, false)` — undo tests actually exercise undo (BUG-02 prevented)
**Plans**: 4 plans

Plans:
- [ ] 01-01-PLAN.md — Branch setup, mini.test vendor, plugin shim rewrite, init.lua skeleton, test runner
- [ ] 01-02-PLAN.md — config.lua and util.lua (Tier-0 modules) with specs
- [ ] 01-03-PLAN.md — highlight.lua and region.lua (Tier-1 rendering modules) with specs
- [ ] 01-04-PLAN.md — undo.lua (Tier-1 undo grouping) with BUG-02/03/04 regression spec

### Phase 2: Session Lifecycle
**Goal**: A multi-cursor session can be started and cleanly stopped, with all options, keymaps, and autocmds correctly saved and restored — no state leaks between sessions
**Depends on**: Phase 1
**Requirements**: CFG-01, FEAT-03
**Success Criteria** (what must be TRUE):
  1. `require('visual-multi').setup(opts)` is the sole entry point — no g:VM_xxx global is read or written
  2. Starting a session in buffer A and stopping it leaves the buffer in exactly the state it was before (options, keymaps, cursor position)
  3. Pre-existing user keymaps on buffer-local bindings are preserved after session exit (PITFALL-09 prevented)
  4. Starting a session while one is already active in the same buffer does not double-initialize (PITFALL-11 prevented)
  5. Cursor mode and extend mode toggle correctly via `v`; mode is reflected in session state
**Plans**: TBD

### Phase 3: Region and Highlight
**Goal**: Regions (cursor and extend-mode selections) are tracked with extmarks and rendered correctly, with atomic teardown on session exit and no ghost highlights
**Depends on**: Phase 2
**Requirements**: FEAT-07
**Success Criteria** (what must be TRUE):
  1. Adding a cursor creates a visible extmark highlight at the correct buffer position
  2. Moving a cursor updates the extmark in place — no stale highlights remain
  3. Ending a session clears all extmarks atomically via `nvim_buf_clear_namespace` — no ghost highlights persist
  4. Extend-mode regions display as visual selections; cursor-mode regions display as single-character highlights
  5. Eco-mode batch updates complete without intermediate flicker during multi-cursor loops
**Plans**: TBD

### Phase 4: Normal-Mode Operations
**Goal**: Standard normal-mode commands (d, c, y, p, case conversion, number increment/decrement, dot-repeat) execute simultaneously at all cursors and undo as a single operation
**Depends on**: Phase 3
**Requirements**: FEAT-05, FEAT-06, FEAT-10
**Success Criteria** (what must be TRUE):
  1. Pressing `d` with 3 cursors active deletes the word at each cursor position simultaneously
  2. A single `u` undoes all cursor edits from the previous normal-mode command — not one cursor at a time
  3. Case conversion (`~`, `gu`, `gU`) applies at all cursor positions in one undo step
  4. `<C-a>` and `<C-x>` increment/decrement numbers at all cursors; `g<C-a>` applies sequential values
  5. Dot-repeat (`.`) replays the last normal-mode operation across all cursors
**Plans**: TBD

### Phase 5: Insert Mode
**Goal**: Entering insert mode with multiple cursors replicates keystrokes at all cursor positions simultaneously, with clean exit and per-cursor register isolation
**Depends on**: Phase 4
**Requirements**: FEAT-04, FEAT-12
**Success Criteria** (what must be TRUE):
  1. Pressing `i` with 3 cursors enters insert mode and each subsequent keystroke appears at all cursor positions
  2. Pressing `<Esc>` exits insert mode at all cursors and consolidates changes into a single undo entry
  3. Pressing `<C-c>` or `:stopinsert` exits insert mode without leaving orphaned InsertLeave autocmds (PITFALL-08 prevented)
  4. Yanking with multiple cursors stores per-cursor text in the VM unnamed register, not the shared Vim register
  5. `i`, `a`, `I`, `A`, `o`, `O` all work correctly as distinct insert-entry points
**Plans**: TBD

### Phase 6: Search, Entry Points, and Advanced Commands
**Goal**: All user-facing entry points for creating and manipulating cursor sets are functional: find-under, pattern search, visual entry, region lifecycle, and power-user operations
**Depends on**: Phase 5
**Requirements**: FEAT-01, FEAT-02, FEAT-08, FEAT-09, FEAT-11, FEAT-15
**Success Criteria** (what must be TRUE):
  1. `<C-n>` on a word selects it; subsequent `<C-n>` presses add the next match as a new cursor
  2. VM-/ opens a regex prompt; all matches become cursors in a single operation
  3. `q` skips the current region (moves to next without removing); `Q` removes the current region
  4. Run-normal (`/<command>`) executes the given normal command at every cursor; run-macro plays a recorded macro at every cursor
  5. Mouse `<C-LeftMouse>` adds a cursor at the clicked position; file size guard prevents VM from activating on files above the configured limit
**Plans**: TBD

### Phase 7: Configuration Surface and Plugin API
**Goal**: All 34 g:VM_xxx configuration variables are exposed as structured keys in setup(opts); the full plugin API surface (Plug mappings, user commands, theming, statusline, compat hooks) is complete
**Depends on**: Phase 6
**Requirements**: CFG-02, CFG-03, CFG-04, CFG-05, CFG-06, CFG-07, CFG-08, CFG-09, CFG-10, FEAT-13, FEAT-14
**Success Criteria** (what must be TRUE):
  1. Every option from `doc/vm-settings.txt` is settable via `setup(opts)` with a snake_case key — no g:VM_xxx variable is needed
  2. `VMInfos()` returns a string with current cursor count and mode, usable in a statusline expression
  3. `VMTheme <name>` command changes the active highlight theme; all 15 built-in themes apply without errors
  4. Conflicting plugins listed in `plugins_compat` are automatically disabled on session start and re-enabled on exit
  5. `<Plug>VM-*` mappings are available for all actions, allowing users to remap any key without modifying plugin source
**Plans**: TBD

### Phase 8: Interactive E2E Validation
**Goal**: Behavioral parity with the VimScript plugin is confirmed through interactive testing; the bootstrap shim and VimScript autoload files are removed from the runtime
**Depends on**: Phase 7
**Requirements**: TEST-01, TEST-02
**Success Criteria** (what must be TRUE):
  1. The mini.test headless suite covers all 14 Lua modules and reports 0 failures
  2. The pynvim regression harness smoke tests pass for all non-interactive scenarios
  3. Manual walkthrough of the interactive test plan (insert mode, operator-pending, mouse cursors) completes with no behavioral regressions vs the VimScript plugin on master
  4. No VimScript autoload file exists in the plugin's runtime path after bootstrap shim removal
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 2/4 | In Progress|  |
| 2. Session Lifecycle | 0/TBD | Not started | - |
| 3. Region and Highlight | 0/TBD | Not started | - |
| 4. Normal-Mode Operations | 0/TBD | Not started | - |
| 5. Insert Mode | 0/TBD | Not started | - |
| 6. Search, Entry Points, and Advanced Commands | 0/TBD | Not started | - |
| 7. Configuration Surface and Plugin API | 0/TBD | Not started | - |
| 8. Interactive E2E Validation | 0/TBD | Not started | - |
