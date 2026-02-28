# Architecture

**Analysis Date:** 2025-02-28

## Pattern Overview

**Overall:** Class-based object-oriented design using VimScript function dictionaries and a global session/buffer-level state pattern.

**Key Characteristics:**
- Multi-cursor session activated lazily per buffer via `vm#init_buffer()`
- Stateful regions management with per-region object lifecycle
- Functional class pattern: script-local dictionaries with methods defined as functions
- Global state in `g:Vm` (plugin-wide), buffer state in `b:VM_Selection`
- Python helper for expensive byte operations
- Vim autocommand-driven lifecycle

## Layers

**Plugin Layer:**
- Purpose: Entry points, top-level commands, permanent mappings
- Location: `plugin/visual-multi.vim`
- Contains: User commands (`:VMTheme`, `:VMDebug`, `:VMSearch`), plugin initialization, highlight groups
- Depends on: Autoload modules
- Used by: Vim/Neovim directly

**Session Layer:**
- Purpose: Initialize and manage per-buffer VM session state
- Location: `autoload/vm.vim` (core: `vm#init_buffer()`, `vm#reset()`)
- Contains: Buffer initialization, class factory functions, session lifecycle hooks
- Depends on: All class modules (Maps, Global, Search, Edit, Insert, Case)
- Used by: Commands layer, entry points

**Class Layer:**
- Purpose: Object-oriented abstractions for multi-cursor operations
- Location: `autoload/vm/` modules
- Contains: Six primary classes (Global, Maps, Search, Edit, Insert, Case) plus helpers
- Depends on: Core abstractions (Region, Funcs)
- Used by: Each other (composition), Entry points (commands)

**Region Layer:**
- Purpose: Manage individual cursor/selection objects with content and state
- Location: `autoload/vm/region.vim`
- Contains: Region class factory, region creation, indexing, positioning
- Depends on: Funcs (utilities), Variables (state)
- Used by: Global class (creation/access), all edit operations

**Utility Layer:**
- Purpose: Helper functions and conversion utilities
- Location: `autoload/vm/funcs.vim`, `autoload/vm/comp.vim`, `autoload/vm/themes.vim`
- Contains: Cursor/byte position conversion, register handling, compatibility
- Depends on: Vim API only
- Used by: All other modules

**Python Layer:**
- Purpose: Expensive byte-range operations for performance
- Location: `python/vm.py`
- Contains: Region reconstruction from byte maps, line-with-regions lookup
- Depends on: Vim Python API
- Used by: `autoload/vm/edit.vim` for bulk operations

## Data Flow

**Session Initialization:**
1. User triggers VM (e.g., via `:/<pattern>` → `/<Plug>(VM-/)` → plugin event handler)
2. Command handler calls `s:init()` in `autoload/vm/commands.vim`
3. `vm#init_buffer(cmd_type)` creates `b:VM_Selection` dict with Regions, Vars, Funcs
4. All class instances (Global, Maps, Search, Edit, Insert, Case) initialized as dict methods
5. Mappings enabled via `s:V.Maps.enable()`
6. Autocommands registered for cursor movement, buffer leave/enter

**Region Creation:**
1. User action (cursor add, search result) triggers `vm#region#new(cursor, [args])`
2. Region factory creates new Region dict with properties (a, b for byte offsets; l, L for lines)
3. Region stored in `s:V.Regions` array, sorted by start position
4. `s:v.index` tracks active region; `s:v.ID` increments for unique identification
5. Global class updates cursor highlighting via `s:G.update_cursor_highlight()`

**Edit Operation:**
1. User inserts/edits at multi-cursors via Insert mode or normal commands
2. `s:Edit.before_commands()` stores undo state, records initial text
3. Operation applied to all active regions (via `s:G.active_regions()`)
4. `s:Edit.after_commands()` syncs undo blocks, updates region byte offsets
5. Cursor highlighting redrawn via `s:G.update_cursor_highlight()`

**Search and Replace:**
1. User initiates search pattern via command (`:/<Plug>(VM-/)`)
2. `s:Search.add()` / `s:Search.join()` updates search state
3. `s:G.get_all_regions()` finds all pattern matches using `ygn` (yank next)
4. Each match becomes a region; regions kept in `b:VM_Selection.Bytes` for reconstruction
5. Replace workflow: search pattern → edit regions → `s:Edit.after_commands()` updates positions

**Exit Flow:**
1. User presses exit key or buffer leaves
2. `vm#reset()` called: clears regions, removes mappings, restores settings
3. Highlight groups removed via `s:V.Global.remove_highlight()`
4. Undo/registers restored via `s:V.Funcs.restore_regs()` and `s:V.Funcs.restore_visual_marks()`
5. `b:visual_multi` unlet; `b:VM_Selection` becomes empty dict

**State Management:**
- `g:Vm` dict: plugin-wide (extend_mode, buffer, mappings_enabled, registers, themes)
- `b:VM_Selection` dict: per-buffer session (Regions, Vars, Funcs, class instances)
- `s:V`, `s:v`, `s:G`, `s:F` (script-local): cached references within modules for performance

## Key Abstractions

**Region:**
- Purpose: Represents a single cursor or selection
- Examples: `autoload/vm/region.vim` (Region.new(), Region.char(), Region.cur_col())
- Pattern: Factory function `vm#region#new()` returns dict with methods; properties include byte offsets (A, B), line bounds (l, L), text (txt), pattern (pat)

**Session (b:VM_Selection):**
- Purpose: Encapsulates all state for active multi-cursor session
- Examples: Initialized in `autoload/vm.vim` `vm#init_buffer()`
- Pattern: Dict containing Regions array, Vars dict, Funcs dict, and class instances

**Search Pattern:**
- Purpose: Manage regex patterns and matching across buffer
- Examples: `autoload/vm/search.vim` (s:Search.add(), s:Search.join())
- Pattern: `s:v.search` list tracks patterns; `@/` register synced for Vim integration

**Edit Stack:**
- Purpose: Track byte offset changes during bulk edits
- Examples: `s:v.W` (word lengths), `s:v.storepos` (original positions), `s:v.new_text` (replacement)
- Pattern: Stored per-operation; used to recalculate region byte offsets post-edit

**Extend Mode vs Cursor Mode:**
- Purpose: Two operational modes for region selection
- Examples: Toggled via `g:Vm.extend_mode` flag; region operations differ per mode
- Pattern: `s:G.change_mode()` transitions; affects visual selection representation

## Entry Points

**`:/<pattern>` (Search Init):**
- Location: `plugin/visual-multi.vim` → `<Plug>(VM-/)` → `autoload/vm/plugs.vim` → `vm#commands#search_patterns()`
- Triggers: User enters `/` in normal mode
- Responsibilities: Initialize buffer, parse pattern, find all matches, create regions

**`vm#commands#add_cursor_*()`:**
- Location: `autoload/vm/commands.vim` (add_cursor_at_pos, add_cursor_down, add_cursor_up, etc.)
- Triggers: User presses mapped keys (default: `Ctrl-Down`, `Ctrl-Up`, `Ctrl-L`, etc.)
- Responsibilities: Init session if needed, create new cursor at position, handle multi-line logic

**`vm#operators#select()`:**
- Location: `autoload/vm/operators.vim`
- Triggers: User invokes text object selection (e.g., `v` in extend mode)
- Responsibilities: Prompt for motion/text object, apply to all regions, update highlighting

**Insert Mode Entry (i/a/I/A/o/O):**
- Location: `autoload/vm/insert.vim` `s:Insert.key()`
- Triggers: User presses i, a, I, A, o, or O in multi-cursor mode
- Responsibilities: Set insert type, merge regions if needed, switch to insert mode, manage undo blocks

**Normal Mode Commands:**
- Location: `autoload/vm/edit.vim` (run_normal, run_visual)
- Triggers: User types normal commands while regions active
- Responsibilities: Execute command over all active regions, sync undo, update byte offsets

**Exit Handlers:**
- Location: `autoload/vm.vim` `vm#reset()`, buffer autocommand handlers
- Triggers: User presses Esc, switches buffer, or closes buffer
- Responsibilities: Clean state, restore settings, unwind undo stack

## Error Handling

**Strategy:** Try-catch in init path; graceful degradation in operations; per-region error isolation.

**Patterns:**
- Init catches: `vm#init_buffer()` wraps in try-catch; returns error string on failure, session dict on success
- Size check: `VM_filesize_limit` option prevents startup on huge files
- Region operation: Individual operations continue even if one region fails; `s:F.should_quit()` checks if plugin should self-destruct
- Undo state: Tracked separately in `b:VM_Backup` to recover if edit sequence breaks
- Python errors: Wrapped via Vim python try-catch; fallback to VimScript path if unavailable

## Cross-Cutting Concerns

**Logging:**
- Debug output via `s:F.msg()` function; controlled by `g:VM_debug` flag
- Status line messages show current region count and index
- No persistent logging; console output only

**Validation:**
- Byte offset validation: `s:F.pos2byte()` handles marks, lists, or raw offsets
- Region bounds: `s:F.byte2pos()` ensures positions stay within buffer
- Pattern validation: `s:Search.ensure_is_set()` prevents operations without active search

**Authentication:**
- No auth mechanism; all operations assume local buffer access
- Buffer-level isolation: `b:visual_multi` flag prevents concurrent sessions

**Compatibility:**
- Vim version check (v:version >= 800) in plugin entry
- Python availability check: graceful fallback if python3 unavailable
- Neovim-specific tweaks in `autoload/vm/comp.vim` (conceallevel, option access)
- Plugin conflict detection via `g:VM_check_mappings` option

---

*Architecture analysis: 2025-02-28*
