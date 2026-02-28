# vim-visual-multi Lua Rewrite

## What This Is

vim-visual-multi is a Neovim plugin for multiple cursor editing. This project is a clean rewrite of the existing VimScript implementation into idiomatic Lua, targeting Neovim only, with a conventional `setup()` configuration API replacing all `g:VM_xxx` global variables.

## Core Value

All existing multi-cursor behaviors work identically after the rewrite — users lose no functionality, and configuration becomes ergonomic.

## Requirements

### Validated

<!-- Capabilities confirmed working in the current VimL implementation. -->

- ✓ Multiple cursors created at cursor position — existing
- ✓ Multiple cursors created by searching a pattern (VM-/) — existing
- ✓ Add cursors up/down (Ctrl-Up/Down) — existing
- ✓ Cursor mode and extend mode (visual selection per cursor) — existing
- ✓ Insert mode operations (i/a/I/A/o/O) across all cursors simultaneously — existing
- ✓ Normal mode commands executed across all cursors (d, c, y, p, etc.) — existing
- ✓ Visual operations and text objects in extend mode — existing
- ✓ Undo/redo grouping: all-cursors edits undo as a single operation — existing
- ✓ Find/replace across all regions — existing
- ✓ Case conversion operations (upper, lower, title) — existing
- ✓ Per-cursor register/clipboard management — existing
- ✓ Cursor highlighting and statusline integration — existing
- ✓ Theming system for highlight groups — existing
- ✓ Custom keymaps via g:VM_maps — existing
- ✓ File size limit guard to prevent startup on huge files — existing
- ✓ Graceful exit: restores settings, mappings, undo state on session end — existing

### Active

- [ ] Pure Lua implementation — no VimScript autoload files in the runtime path
- [ ] `setup(opts)` entry point replacing all `g:VM_xxx` global variables
- [ ] All `g:VM_xxx` options exposed as structured keys in `setup()` opts table
- [ ] Neovim-only: use extmarks, `vim.keymap.set`, `vim.api`, `nvim_create_autocmd` etc.
- [ ] No Python dependency for core operations (replace python/vm.py with Lua)
- [ ] Test suite updated to reflect new Lua module structure and setup() API

### Out of Scope

- Vim 8 compatibility — Neovim-only from now on
- Backward compatibility with `g:VM_xxx` config variables — clean break
- Python helper (`python/vm.py`) — replaced by Lua equivalent

## Context

The existing plugin (`master` branch) is a mature VimScript implementation with ~15 autoload modules, a Python helper for byte operations, and a global-variable-based config system. The architecture is well-understood (session/region model, class-layer with Global/Maps/Search/Edit/Insert/Case, undo grouping).

A previous Lua port exists on branch `001-lua-nvim-rewrite` (phases 1-8 done, 94 unit tests). However, this new rewrite starts fresh from master, using the old Lua branch as a reference when helpful but not inheriting its structure or config approach.

The primary motivation for the rewrite is to align with modern Neovim plugin conventions: `setup()` config, Lua module system, extmarks API, and dropping Vim 8 / Python dependencies.

## Constraints

- **Runtime**: Neovim only — use Neovim-specific APIs freely
- **Language**: Lua only — no VimScript autoload files in the ported plugin
- **Config API**: `setup(opts)` is the only supported config mechanism
- **Compatibility**: No migration path from `g:VM_xxx` — users must update their config

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Start fresh from master (VimL) | Previous Lua branch carries legacy structure; cleaner to port from source of truth | — Pending |
| No backward compat with g:VM_xxx | Cleaner API; avoids supporting two config systems indefinitely | — Pending |
| Drop Python dependency | Python optional in Neovim, adds complexity; Lua can handle byte operations | — Pending |
| Neovim-only | Enables extmarks, lua API, modern autocmd system; Vim 8 is legacy | — Pending |

---
*Last updated: 2026-02-28 after initialization*
