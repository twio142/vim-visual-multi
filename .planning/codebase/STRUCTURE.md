# Codebase Structure

**Analysis Date:** 2025-02-28

## Directory Layout

```
vim-visual-multi/
├── plugin/                    # Entry points and plugin initialization
│   └── visual-multi.vim       # Main plugin file, commands, highlights
├── autoload/                  # Lazy-loaded modules (Vim autoload convention)
│   └── vm/                    # Core VM modules
│       ├── vm.vim            # Init, reset, autocommand handlers
│       ├── global.vim        # Global class: region management, mode changes
│       ├── region.vim        # Region class: individual cursor/selection objects
│       ├── maps.vim          # Maps class: mapping enable/disable, setup
│       ├── search.vim        # Search class: pattern matching, search updates
│       ├── edit.vim          # Edit class: normal/visual commands at regions
│       ├── insert.vim        # Insert class: insert mode handling
│       ├── funcs.vim         # Funcs class: utility functions
│       ├── operators.vim     # Operator selection (text objects in extend mode)
│       ├── commands.vim      # Command entry points (add cursor, search, etc.)
│       ├── variables.vim     # Variable initialization and reset
│       ├── plugs.vim         # Plug definitions and mapping builders
│       ├── visual.vim        # Visual mode operations
│       ├── comp.vim          # Compatibility layer (Neovim, plugins)
│       ├── cursors.vim       # Cursor-specific operations
│       ├── themes.vim        # Highlight theme management
│       ├── special/
│       │   ├── commands.vim  # Special commands (debug, registers, live)
│       │   └── case.vim      # Case conversion class
│       ├── icmds.vim         # Insert mode commands
│       ├── ecmds1.vim        # Edit commands part 1 (yank, delete, indent)
│       ├── ecmds2.vim        # Edit commands part 2 (substitute, case change)
│       └── maps/
│           └── all.vim       # Default mapping definitions
├── doc/                       # Help documentation (Vim doc format)
├── python/                    # Python helpers (optional, Vim only)
│   └── vm.py                 # Byte range operations, region reconstruction
├── test/                      # Test suite
│   ├── run_spec.lua          # Test runner (Lua, for Neovim)
│   ├── vendor/               # Vendored mini.test framework
│   ├── default/
│   │   └── vimrc.vim         # Default test environment config
│   └── tests/                # Individual test suites by category
│       ├── example/
│       │   └── commands.py   # Test commands (Python test syntax)
│       ├── change/
│       ├── search/
│       ├── insert/
│       └── [15+ more test categories]/
├── README.md                  # Main documentation
├── LICENSE                    # MIT license
└── .gitignore                # Git ignore rules
```

## Directory Purposes

**`plugin/`:**
- Purpose: Vim plugin initialization and entry points
- Contains: User commands, permanent mappings, highlight definitions, global state init
- Key files: `plugin/visual-multi.vim`
- Loaded once at Vim startup

**`autoload/vm/`:**
- Purpose: Core plugin logic organized by class/feature
- Contains: Session management, region ops, search, edit, insert, utilities
- Lazy-loaded on first use (Vim autoload convention)
- Organized by responsibility: one main class per file (Global, Search, Edit, Insert, etc.)

**`autoload/vm/special/`:**
- Purpose: Specialized operations and compatibility
- Contains: Special commands (debug, registers), case conversion, plugin-specific tweaks
- Key files: `commands.vim` (user-facing special commands), `case.vim` (case class)

**`autoload/vm/maps/`:**
- Purpose: Mapping definition and management
- Contains: Default keybinding definitions, mapping builders
- Key files: `all.vim` (comprehensive default map definitions)

**`doc/`:**
- Purpose: Vim help documentation
- Contains: Plugin help pages in Vim doc format
- Generated from inline comments; viewable via `:help vm-*`

**`python/`:**
- Purpose: Performance-critical byte operations
- Contains: Bulk region reconstruction from byte maps, line lookups
- Loaded conditionally if Python3 available and `g:VM_use_python` enabled
- Used by: `autoload/vm/edit.vim` for expensive bulk operations

**`test/`:**
- Purpose: Test suite for feature validation
- Contains: Unit and integration tests organized by feature
- Test format: Python command sequences (legacy) and Lua unit tests (modern)
- Run via: `nvim --headless -u NORC -l test/run_spec.lua` (Lua) or `python test.py` (Python)

**`test/tests/*/`:**
- Purpose: Individual test suites by feature area
- Contains: Per-feature test subdirectories (example, change, search, curs_del, regex, etc.)
- Each has: `commands.py` (test sequence) and optional `vimrc.vim` (test config)
- Run individually: `python test.py --test example`

## Key File Locations

**Entry Points:**
- `plugin/visual-multi.vim`: User commands (`:VMTheme`, `:VMDebug`, `:VMSearch`), plugin guards
- `autoload/vm/commands.vim`: Command handler entry points (search init, add cursor, etc.)
- `autoload/vm/plugs.vim`: Plug definition and temporary mapping builders

**Configuration:**
- `autoload/vm.vim`: Buffer initialization and session setup
- `autoload/vm/variables.vim`: User option defaults and variable initialization
- `test/default/vimrc.vim`: Default test environment

**Core Logic:**
- `autoload/vm/region.vim`: Region class and factory
- `autoload/vm/global.vim`: Global class managing all regions, mode changes
- `autoload/vm/search.vim`: Search pattern management
- `autoload/vm/edit.vim`: Normal/visual command execution at regions
- `autoload/vm/insert.vim`: Insert mode lifecycle and multi-cursor insert

**Utilities:**
- `autoload/vm/funcs.vim`: Byte/position conversion, register access, messaging
- `autoload/vm/comp.vim`: Compatibility checks and tweaks
- `autoload/vm/themes.vim`: Highlight group management
- `python/vm.py`: Byte range reconstruction for bulk ops

**Testing:**
- `test/run_spec.lua`: Modern Lua test runner
- `test/tests/*/commands.py`: Legacy Python test sequences
- Individual test categories mirror feature areas

## Naming Conventions

**Files:**
- `*.vim`: VimScript files (plugin logic, config)
- `*.py`: Python test sequences and helpers
- `*.lua`: Lua unit tests (modern test suite)
- Classes typically lowercase with `.vim` extension: `global.vim`, `search.vim`, `edit.vim`

**Directories:**
- `autoload/vm/`: Core modules (one class/feature per file)
- `autoload/vm/special/`: Non-core operations
- `autoload/vm/maps/`: Mapping definitions
- `test/tests/[feature-name]/`: One test subdirectory per feature area
- Test categories use underscores: `curs_del`, `curs2`, `pasteatcur`

**Functions/Classes:**
- Class init functions: `vm#modulename#init()` (e.g., `vm#global#init()`)
- Private functions: `s:functionname()` (script-local)
- Public functions: `vm#modulename#functionname()` (autoload pattern)
- Lambdas use short names: `s:R = { -> s:V.Regions }` (refs to Regions array)

**Variables:**
- Global: `g:Vm`, `g:VM_*` (user options)
- Buffer-local: `b:VM_Selection`, `b:VM_maps`, `b:visual_multi`
- Script-local: `s:V` (session), `s:v` (vars), `s:G` (Global class), `s:F` (Funcs class)

## Where to Add New Code

**New Feature (multi-cursor operation):**
- Primary code: `autoload/vm/[feature].vim` or extend existing class
- Commands entry: Add function to `autoload/vm/commands.vim`, reference in `autoload/vm/plugs.vim`
- Mappings: Add to `autoload/vm/maps/all.vim`
- Tests: Create `test/tests/[feature]/` with `commands.py` or Lua test in `test/run_spec.lua`

**New Component/Module:**
- Implementation: `autoload/vm/[component].vim` (follow class pattern with init function)
- Integration: Call init in `vm#init_buffer()` in `autoload/vm.vim`, store in `b:VM_Selection`
- Reset logic: Add reset handler in `vm#reset()` function
- Tests: Add unit test to `test/run_spec.lua` or new test subdirectory

**Utilities:**
- Shared helpers: Add to `autoload/vm/funcs.vim` as new method on `s:Funcs` dict
- Vim/plugin compatibility: Add to `autoload/vm/comp.vim`
- Byte/position utilities: Add to `s:Funcs` in `autoload/vm/funcs.vim`

**Themes/Highlights:**
- New highlight group: Add to `autoload/vm/themes.vim`
- Defaults: `plugin/visual-multi.vim` lines 39-42 set default links

**Tests:**
- Unit tests (modern): Add to `test/run_spec.lua` using mini.test
- Integration tests (legacy): Add subdirectory to `test/tests/[feature]/` with `commands.py`
- Test data: Use fixtures in test subdirectories or inline in test files

## Special Directories

**`autoload/`:**
- Purpose: VimScript lazy-load convention directory
- Generated: No
- Committed: Yes
- Content: All plugin core logic; loaded on demand when functions called

**`python/`:**
- Purpose: Optional Python performance helpers
- Generated: No
- Committed: Yes
- Content: Bulk byte operations; only loaded if Python3 available

**`doc/`:**
- Purpose: Vim help documentation
- Generated: Partially (built from source comments)
- Committed: Yes
- Content: Help pages for plugin features and options

**`test/vendor/`:**
- Purpose: Vendored test framework (mini.test)
- Generated: No
- Committed: Yes
- Content: Mini.test test runner library (extracted from mini.nvim)

**`test/tests/*/`:**
- Purpose: Individual test suites
- Generated: No
- Committed: Yes
- Content: Test sequences and expected outputs per feature

---

*Structure analysis: 2025-02-28*
