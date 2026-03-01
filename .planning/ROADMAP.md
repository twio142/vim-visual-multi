# Roadmap: vim-visual-multi Lua Rewrite

## Milestones

- ✅ **v1.0 Lua Rewrite Foundation** — Phases 1–4.1 (shipped 2026-03-01)
- 🚧 **v2.0 Full Feature Parity** — Phases 5–8 (planned)

## Phases

<details>
<summary>✅ v1.0 Lua Rewrite Foundation (Phases 1–4.1) — SHIPPED 2026-03-01</summary>

- [x] Phase 1: Foundation (4/4 plans) — completed 2026-02-28
- [x] Phase 2: Session Lifecycle (1/1 plans) — completed 2026-02-28
- [x] Phase 3: Region and Highlight (2/2 plans) — completed 2026-02-28
- [x] Phase 4: Normal-Mode Operations (3/3 plans) — completed 2026-03-01
- [x] Phase 4.1: Gap Closure — Highlight Init and g_increment Undo Wiring (1/1 plans) — completed 2026-03-01

See `.planning/milestones/v1.0-ROADMAP.md` for full phase details.

</details>

### 🚧 v2.0 Full Feature Parity (Planned)

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (4.1): Urgent insertions (marked with INSERTED)

- [ ] **Phase 5: Insert Mode** - Simultaneous keystroke replication, InsertLeave sync, per-cursor registers
- [ ] **Phase 6: Search, Entry Points, and Advanced Commands** - C-n, select-all, skip/remove/filter regions, align, transpose, run-normal/macro
- [ ] **Phase 7: Configuration Surface and Plugin API** - Full setup(opts) with all 34 g:VM_xxx options, Plug layer, statusline, theming, compat hooks
- [ ] **Phase 8: Interactive E2E Validation** - Behavioral parity confirmation, bootstrap shim removal, autoload deletion

## Phase Details

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

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v1.0 | 4/4 | Complete | 2026-02-28 |
| 2. Session Lifecycle | v1.0 | 1/1 | Complete | 2026-02-28 |
| 3. Region and Highlight | v1.0 | 2/2 | Complete | 2026-02-28 |
| 4. Normal-Mode Operations | v1.0 | 3/3 | Complete | 2026-03-01 |
| 4.1. Gap Closure | v1.0 | 1/1 | Complete | 2026-03-01 |
| 5. Insert Mode | v2.0 | 0/TBD | Not started | - |
| 6. Search, Entry Points, Advanced Commands | v2.0 | 0/TBD | Not started | - |
| 7. Configuration Surface and Plugin API | v2.0 | 0/TBD | Not started | - |
| 8. Interactive E2E Validation | v2.0 | 0/TBD | Not started | - |
