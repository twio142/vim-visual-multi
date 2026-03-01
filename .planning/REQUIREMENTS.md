# Requirements: vim-visual-multi Lua Rewrite

**Defined:** 2026-02-28
**Core Value:** All existing multi-cursor behaviors work identically after the rewrite — users lose no functionality, and configuration becomes ergonomic via setup()

## v1 Requirements

### Implementation

- [x] **LUA-01**: Plugin runs entirely in Lua — no VimScript autoload files in runtime path
- [x] **LUA-02**: Targets Neovim 0.10+ only — uses vim.api, vim.keymap.set, extmarks, nvim_create_autocmd
- [x] **LUA-03**: No Python dependency — byte operations replaced with nvim_buf_get_offset

### Configuration API

- [x] **CFG-01**: setup(opts) is the sole config entry point (no g:VM_xxx support)
- [ ] **CFG-02**: Appearance opts — highlight_matches, theme
- [ ] **CFG-03**: Statusline opts — statusline.enabled, statusline.refresh_mode, statusline.silent_exit
- [ ] **CFG-04**: UI opts — show_warnings, verbose_commands, cmdheight
- [ ] **CFG-05**: Search/navigation opts — case_setting, skip_shorter_lines, skip_empty_lines, notify_previously_selected, filesize_limit
- [ ] **CFG-06**: Edit behavior opts — live_editing, reselect_first, recursive_operations_at_cursors
- [ ] **CFG-07**: Insert mode opts — insert.use_first_cursor_in_line, insert.disable_syntax, insert.special_keys, insert.reindent_filetypes, insert.quit_on_leave, insert.single_mode_maps, insert.single_mode_auto_reset, insert.add_cursor_no_mappings
- [ ] **CFG-08**: Register opts — persistent_registers
- [ ] **CFG-09**: Keymap opts — leader, default_mappings, mouse_mappings, check_mappings, force_maps, maps, custom_remaps, custom_noremaps, custom_motions, user_operators, custom_commands, commands_aliases
- [ ] **CFG-10**: Plugin compatibility opts — plugins_compat

### Core Multi-cursor Features

- [ ] **FEAT-01**: Add cursor at word under cursor, at arbitrary position, up/down by line
- [ ] **FEAT-02**: Pattern-based multi-select: VM-/ regex, find-under (C-n), select-all, visual entry points
- [x] **FEAT-03**: Cursor mode and extend mode with switching between them (v key)
- [ ] **FEAT-04**: Simultaneous insert mode — i/a/I/A/o/O replicated across all cursors
- [x] **FEAT-05**: Simultaneous normal mode commands — d, c, y, p, D, C, x, J, and all standard ops
- [x] **FEAT-06**: Undo grouping — all-cursor edits within a session undo as a single operation
- [x] **FEAT-07**: Extmark-based cursor/selection highlighting with full theming system (15 built-in themes + VMTheme command)

### Advanced Features

- [ ] **FEAT-08**: Region lifecycle — skip region (q), remove region (Q), filter regions, one-per-line
- [ ] **FEAT-09**: Alignment (align, align-char), number insertion (sequential/zero), transpose, rotate, split regions, duplicate regions
- [x] **FEAT-10**: Case conversion (upper/lower/title/cycle), replace-chars (r), replace mode (R), increase/decrease numbers (C-a/C-x/g-variants)
- [ ] **FEAT-11**: Run-normal, run-visual, run-ex, run-macro, dot-repeat — execute arbitrary commands at all cursors
- [ ] **FEAT-12**: Per-cursor register management — VM unnamed register separate from Vim register
- [ ] **FEAT-13**: Statusline integration — VMInfos() function, live cursor count and mode display
- [ ] **FEAT-14**: Plugin compatibility hooks — auto-disable/re-enable conflicting plugins (auto-pairs etc.)
- [ ] **FEAT-15**: Mouse support (C-LeftMouse/C-RightMouse), file size guard, reindent-on-exit by filetype

### Tests

- [ ] **TEST-01**: mini.test unit suite covers all Lua modules (config, session, region, highlight, undo, edit, insert, search, case, operators, maps)
- [ ] **TEST-02**: Behavioral parity confirmed vs VimScript version via pynvim regression harness

## v2 Requirements

*(None identified — this is a complete rewrite targeting full parity)*

## Out of Scope

| Feature | Reason |
|---------|--------|
| Vim 8 compatibility | Neovim-only rewrite; Vim 8 is legacy |
| g:VM_xxx config variables | Clean break — setup() only, no migration path |
| Python backend (python/vm.py) | Replaced by Lua + nvim_buf_get_offset |
| g:VM_use_python option | Python backend dropped entirely |
| g:VM_debug as setup() opt | Internal dev tool; remains as separate raw global if needed |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| LUA-01 | Phase 1 | Complete |
| LUA-02 | Phase 1 | Complete |
| LUA-03 | Phase 1 | Complete |
| CFG-01 | Phase 2 | Complete |
| CFG-02 | Phase 7 | Pending |
| CFG-03 | Phase 7 | Pending |
| CFG-04 | Phase 7 | Pending |
| CFG-05 | Phase 7 | Pending |
| CFG-06 | Phase 7 | Pending |
| CFG-07 | Phase 7 | Pending |
| CFG-08 | Phase 7 | Pending |
| CFG-09 | Phase 7 | Pending |
| CFG-10 | Phase 7 | Pending |
| FEAT-01 | Phase 6 | Pending |
| FEAT-02 | Phase 6 | Pending |
| FEAT-03 | Phase 2 | Complete |
| FEAT-04 | Phase 5 | Pending |
| FEAT-05 | Phase 4 | Complete |
| FEAT-06 | Phase 4 | Complete |
| FEAT-07 | Phase 3 | Complete |
| FEAT-08 | Phase 6 | Pending |
| FEAT-09 | Phase 6 | Pending |
| FEAT-10 | Phase 4 | Complete |
| FEAT-11 | Phase 6 | Pending |
| FEAT-12 | Phase 5 | Pending |
| FEAT-13 | Phase 7 | Pending |
| FEAT-14 | Phase 7 | Pending |
| FEAT-15 | Phase 6 | Pending |
| TEST-01 | Phase 8 | Pending |
| TEST-02 | Phase 8 | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0

---
*Requirements defined: 2026-02-28*
*Last updated: 2026-02-28 after roadmap creation*
