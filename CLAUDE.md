# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Plugin Does

vim-visual-multi is a Vim 8+ / Neovim plugin implementing multiple cursors. It has two modes:
- **Cursor mode** – normal-mode semantics at each cursor
- **Extend mode** – visual-mode semantics (range selections)

Default activation: `<C-n>` to select word under cursor, `<C-Down>`/`<C-Up>` to add cursors.

## Running Tests

```sh
# Run all tests
./run_tests

# Run a specific test
python3 test/test.py <test_name>

# List available tests
python3 test/test.py -l

# Show diffs on failure
python3 test/test.py -d <test_name>
```

Tests require Python 3.6+ and an X virtual framebuffer (xvfb) for headless Vim. Each test in `test/tests/` has an input file, a `commands.py` that sends key sequences, and an expected output file.

Manual interactive testing:
```
vim -Nu tutorialrc      # tutorial mode
:VMLive                 # live editing test mode inside Vim
```

## Architecture

### Module Organization

All core logic lives in `autoload/vm/`. Vim's autoload system (`#` path separator) lazy-loads modules on first use.

| File | Purpose |
|------|---------|
| `autoload/vm.vim` | Entry point: `vm#init_buffer()` bootstraps all state |
| `autoload/vm/commands.vim` | User-facing command implementations (Ctrl-N, find, skip, motion, etc.) |
| `autoload/vm/plugs.vim` | Defines all `<Plug>` mappings; permanent + buffer-local layers |
| `autoload/vm/maps.vim` | `Maps` class: enables/disables buffer mappings when VM activates/exits |
| `autoload/vm/global.vim` | `Global` class: region management, mode switching, highlight updates |
| `autoload/vm/region.vim` | `Region` class: single cursor/selection data structure |
| `autoload/vm/edit.vim` | `Edit` class: executes normal/visual/ex commands at all cursors |
| `autoload/vm/insert.vim` | `Insert` class: syncs keystrokes across cursors in insert mode |
| `autoload/vm/search.vim` | `Search` class: pattern management and multi-cursor search |
| `autoload/vm/funcs.vim` | Utility: byte/line conversion, register management |
| `autoload/vm/variables.vim` | Saves/restores Vim settings on VM enter/exit |
| `plugin/visual-multi.vim` | Plugin entry: guards, global commands (`:VMTheme`, `:VMClear`, etc.), highlight groups |

### Central State

All per-buffer state is in `b:VM_Selection`:

```
b:VM_Selection
├── Regions[]     ← array of Region instances, sorted by byte offset
├── Vars{}        ← plugin flags and mode state
├── Bytes{}       ← byte offset tracking
├── Funcs         ← utility function class
├── Maps          ← mapping management class
├── Global        ← region management class
├── Search        ← pattern/search class
├── Edit          ← edit operations class
├── Insert        ← insert mode class
└── Case          ← case conversion class
```

Plugin-wide state is in `g:Vm` (current buffer, extend_mode flag, registers, etc.).

### Region Model

Each `Region` tracks a cursor or selection with byte offsets:
- `A` / `B` – start/end byte offsets
- `K` – anchor byte offset (for extend mode)
- `a` / `b` – corresponding line/column positions
- `dir` – selection direction

All position arithmetic uses byte offsets (not line/col) to handle multi-byte characters correctly.

### Mapping Layers

1. **Permanent plugs** – defined at Vim startup in `plugs.vim`, always active (e.g., `<C-n>` to enter VM)
2. **Buffer plugs** – activated by `Maps.enable()` when VM starts, deactivated on exit
3. **Custom maps** – user overrides via `g:VM_custom_commands` or `g:VM_commands_aliases`

### Key Configuration Variables

All user settings are prefixed `g:VM_`:

```vim
g:VM_default_mappings        " Use default bindings (default: 1)
g:VM_leader                  " Leader prefix (default: '\\')
g:VM_custom_commands         " Override specific command mappings
g:VM_case_setting            " Search case: '' | 'sensitive' | 'ignore' | 'smart'
g:VM_live_editing            " Enable live editing (default: 1)
g:VM_persistent_registers    " Save registers across sessions (default: 0)
g:VM_filesize_limit          " Skip activation on large files (default: 0=unlimited)
```

Highlight groups: `VM_Mono` (matches), `VM_Cursor` (cursors), `VM_Extend` (selections), `VM_Insert` (insert mode).
