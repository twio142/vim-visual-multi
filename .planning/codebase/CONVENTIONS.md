# Coding Conventions

**Analysis Date:** 2025-02-28

## Naming Patterns

**Files:**
- VimL: `snake_case.vim` for autoload modules
  - Example: `region.vim`, `commands.vim`, `search.vim` in `autoload/vm/`
- Python: `snake_case.py` for test runners
  - Example: `test.py`
- Documentation: lowercase with dashes
  - Example: `commands.py`, `input_file.txt`, `expected_output_file.txt`

**Functions:**
- VimL: `module#function_name()` for public autoload functions
  - Example: `vm#region#new()`, `vm#commands#add_cursor_down()`
- VimL: `s:function_name()` for script-local (private) functions
  - Example: `s:init()`, `s:skip_shorter_lines()`, `s:went_too_far()`
- VimL: `s:ClassName.method()` for class-like objects with methods
  - Example: `s:Funcs.pos2byte()`, `s:Search.add()`, `s:Maps.enable()`
- Python: `snake_case_function()` with docstrings
  - Example: `run_core()`, `run_one_test()`, `get_test_description()`

**Variables:**
- VimL script-local: `s:var_name` (single letter shortcuts like `s:V`, `s:v`, `s:F`, `s:G`)
  - `s:V` = current buffer's VM_Selection (main session object)
  - `s:v` = s:V.Vars (plugin variables)
  - `s:F` = s:V.Funcs (function registry)
  - `s:G` = s:V.Global (global operations)
  - `s:R` = lambda returning s:V.Regions
  - `s:X` = lambda returning extend mode state
- VimL buffer-local: `b:var_name`
  - Example: `b:VM_Selection`, `b:visual_multi`, `b:VM_Debug`, `b:VM_Backup`
- VimL global: `g:var_name`
  - Configuration: `g:VM_live_editing`, `g:VM_custom_commands`, `g:VM_debug`
  - Runtime: `g:Vm` (main plugin state dict), `g:loaded_visual_multi`
- Python: `lowercase_with_underscore`
  - Global constants: `UPPERCASE_SNAKE` (e.g., `KEY_PRESS_INTERVAL`, `LIVE_EDITING`)

**Types:**
- VimL uses implicit typing but follows conventions:
  - Dicts: `VarName` (PascalCase) when representing object-like structures
    - Example: `b:VM_Selection`, `s:Region`, `s:Search`, `s:Maps`, `s:Funcs`
  - Lists: plural or suffixed with `s`
  - Lambdas: minimal, often assigned to single letters
    - Example: `let s:X = { -> g:Vm.extend_mode }`

## Code Style

**Formatting:**
- VimL: 4-space indentation (observed in all modules)
- VimL: Line continuations use `\` with leading space (standard VimL style)
- Python: 4-space indentation (standard PEP 8)
- Comments: Full-width decoration lines using `"` and `=`/`-`
  ```vim
  """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
  " Section Name
  """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
  ```

**Linting:**
- No `.eslintrc`, `.luacheck`, or `stylua` config found
- No enforced linting (code relies on manual review)
- Error handling uses VimL's `abort` keyword for safe function termination
  - All functions: `fun! function_name(...) abort`

## Import Organization

**VimL Pattern:**
- Each module calls `vm#module#init()` to set up script-local variables
- Script-local shorthand assignments at module init:
  ```vim
  fun! vm#search#init() abort
      let s:V        = b:VM_Selection
      let s:v        = s:V.Vars
      let s:F        = s:V.Funcs
      let s:G        = s:V.Global
      return s:Search
  endfun
  ```
- Initialize lambdas and module-level dicts after init section
  ```vim
  let s:Search = {}
  let s:R = { -> s:V.Regions }
  ```

**Python Pattern:**
- Standard imports at top: `import`, `from pathlib`, `os`, `sys`, `json`, `subprocess`
- Module globals declared with type hints in comments (implicit)
- No explicit import organization rules observed beyond standard Python convention

## Error Handling

**VimL Patterns:**
- All functions use `abort` keyword: `fun! name(...) abort`
- Try-catch blocks for critical initialization:
  ```vim
  try
      if exists('b:visual_multi') | return s:V | endif
      " ... initialization code ...
  catch
      let v:errmsg = 'VM cannot start, unhandled exception.'
      call vm#variables#reset_globals()
      return v:errmsg
  endtry
  ```
- Error messages via `v:errmsg` for propagation
- Function returns empty dict `{}` on error or failure case
- Conditional execution via `if exists()` checks before accessing variables
- Silent mode for operations that may fail: `silent! call s:V.Insert.auto_end()`

**Python Patterns:**
- File-based error reporting: log to file handle `f`
- Exit with code 1 on test failure: `sys.exit(1)`
- No try-catch observed in test runner; relies on exceptions propagating

## Logging

**Framework:** No external logger; uses print and VimL's built-in messages

**VimL Patterns:**
- Message function (likely `s:F.msg()`): `call s:F.msg('Message here')`
- Silent operations for non-critical actions
- Debug dict for test scenarios: `b:VM_Debug = {'lines': []}`

**Python Patterns:**
- Simple `print()` for console output
- File logging: `log(string, f=None)` writes to both stdout and file
- Colored output with ANSI escape codes for pass/fail indicators

## Comments

**When to Comment:**
- Section headers use full-width decoration (required for major code blocks)
- Inline comments explain non-obvious logic, especially parameter details
  ```vim
  " @param whole: use word boundaries
  " @param type: 0 if a pattern will be added, 1 if not, 2 if using regex
  " @param extend_mode: 1 if forcing extend mode
  " Returns: 1 if VM was already active when called
  ```
- Logic notes for complex calculations or hacks
  ```vim
  "TODO: this will surely cause trouble in insert mode with multibyte chars
  "FIXME this part is bugged with multibyte chars
  ```

**JSDoc/TSDoc:**
- Not applicable (VimL and Python do not use JSDoc)
- Parameter documentation in VimL uses `" @param name: description` format (informal)

## Function Design

**Size:**
- Functions range from minimal (10 lines) to large (100+ lines)
- Class-like objects organize related functions: `s:Funcs`, `s:Search`, `s:Region`, `s:Maps`
- No explicit size limit; complexity managed via modular script separation

**Parameters:**
- VimL: Functions accept variadic arguments with `...` for optional parameters
  ```vim
  fun! s:Funcs.pos2byte(...) abort
      if type(a:1) == 0
          return a:1
      elseif type(a:1) == v:t_list
          return (line2byte(a:1[0]) + a:1[1] - 1)
      else
          let pos = getpos(a:1)[1:2]
          return (line2byte(pos[0]) + min([pos[1], col([pos[0], '$'])]) - 1)
      endif
  endfun
  ```
- Python: Standard parameter lists with keyword args for options

**Return Values:**
- VimL: Return values vary by function purpose
  - Utility functions return computed values: positions, text, byte offsets
  - Status functions return 0/1 (success/failure)
  - Initialization functions return object dict (often `s:Search`, `s:Maps`, etc.)
  - Error cases return empty dict `{}` or string error message
- Python: Test functions return `True` (pass) or `False` (fail)

## Module Design

**Exports:**
- VimL: Public API via `vm#module#function()` pattern
- VimL: Classes returned from `vm#module#init()`: `s:Search`, `s:Maps`, `s:Funcs`, `s:Region`
- Python: Entry point is `main()`, with helper functions

**Barrel Files:**
- Not applicable (VimL doesn't have barrel exports)
- Main entry: `plugin/visual-multi.vim` loads autoload modules on demand
- Autoload modules: `autoload/vm.vim` is parent; `autoload/vm/*.vim` are submodules

## Special Patterns

**Dictionary Methods in VimL:**
- Methods defined as `fun! s:DictName.method()` are registered as object methods
- Example:
  ```vim
  let s:Funcs = {}
  fun! s:Funcs.pos2byte(...) abort
      " ...
  endfun
  ```
- Called as `s:Funcs.pos2byte()` or passed to other code via object reference

**Lambda Usage:**
- Short lambdas for closures over frequently-accessed variables:
  ```vim
  let s:R = { -> s:V.Regions }
  let s:X = { -> g:Vm.extend_mode }
  ```
- Used to avoid repeating long property chains

---

*Convention analysis: 2025-02-28*
