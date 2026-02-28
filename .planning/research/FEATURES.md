# Features Research — vim-visual-multi Lua Rewrite

**Date:** 2026-02-28
**Question:** What are all the g:VM_xxx configuration variables in vim-visual-multi, and
how should they map to a setup() opts table? What features do multiple cursor Neovim
plugins typically expose?

---

## 1. Feature Landscape

### 1.1 Table Stakes (must have or plugin is unusable)

These are the baseline capabilities every multiple cursors plugin must provide. Without any
of these, the plugin is not functional for its core use case.

| Feature | Description |
|---------|-------------|
| Add cursor at word under cursor | `<C-n>` style: select word, add next match |
| Add cursor at arbitrary position | Click or keypress to place a cursor |
| Add cursors up/down by line | `<C-Up>/<C-Down>`: column cursors |
| Exit multi-cursor mode | Escape back to normal editing |
| Simultaneous insert mode | All cursors enter insert mode; keystrokes replicate |
| Simultaneous normal commands | `d`, `c`, `y`, `p`, etc. executed at all cursors |
| Undo grouping | All-cursors edits undo as a single operation |
| Cursor highlighting | Visual distinction between cursors and normal text |
| Keymap configuration | Users must be able to remap at minimum the trigger key |

### 1.2 Differentiators (what makes vim-visual-multi special)

These features go beyond the baseline and are what distinguish vim-visual-multi from
simpler alternatives (e.g., `vim-multiple-cursors`):

| Feature | Description | Mechanism |
|---------|-------------|-----------|
| Cursor mode vs. extend mode | Two distinct modes: cursors (point) and selections (range) | `v` to switch; `VM_Extend` highlight group for selections |
| Pattern-based multi-select | `<leader>/` to start regex, `<C-n>` to find-under, `<leader>A` for select-all | Full Vim regex engine; separate search register per session |
| Skip / remove region | `q` skip and find next, `Q` remove current | Regions are indexed and can be individually removed |
| Filter regions | Keep/remove regions by pattern | `<leader>f` filter, `<leader>L` one-per-line |
| Align regions | Align all cursors/selections to a column | `<leader>a` align, `<leader><` align-char |
| Number insertion | Insert sequential numbers at all cursors | `<leader>N`, `<leader>n` append |
| Transpose / Rotate | Swap content between regions | `<leader>t`, `Rotate` |
| Run normal/visual/ex/macro | Execute arbitrary vim commands at all cursors | `<leader>z`, `<leader>v`, `<leader>x`, `<leader>@` |
| Case conversion | Upper / lower / title case; case cycling | `<leader>C` menu; `~` per char |
| Per-cursor registers | Each cursor has its own unnamed register; VM unnamed register separate from vim's | `VMRegisters` command, persistent option |
| Single-region mode | Tab through cursors one at a time in insert mode | `<leader><CR>` toggle |
| Multiline extend mode | Selections that span multiple lines | `M` toggle |
| Surround integration | Surround each selection | `S` (vim-surround compatible) |
| Replace / replace-chars | `R` replace mode, `r` replace single char at all cursors | Built-in, no plugin needed |
| Theming system | Named themes with `VMTheme` command | 15 built-in themes; ColorScheme autocommand |
| Statusline integration | Live ratio / mode display in statusline | `VMInfos()`, `vm#themes#statusline()` |
| Plugin compatibility hooks | Disable/re-enable conflicting plugins automatically | `g:VM_plugins_compatibilty` + built-in for auto-pairs, tagalong, etc. |
| File size guard | Abort if buffer is too large | `filesize_limit` option |
| Mouse support | `<C-LeftMouse>` to add cursor, `<C-RightMouse>` for word | Off by default |
| Dot-repeat integration | `.` works at all cursors | Via `run_normal('.')` |
| Increase / decrease numbers | `<C-a>/<C-x>` and sequential `g<C-a>/g<C-x>` | Numeric and alphabetic variants |
| Visual-mode entry points | Start from a visual selection: add, regex, select-all, cursors | `VM-Visual-*` plugs |
| Reselect last | Re-enter VM with the previous session's regions | `<leader>gS` |
| Shrink / enlarge selections | Expand or contract extend-mode selections | `<leader>-`, `<leader>+` |
| Split regions | Split a selection by pattern | `<leader>s` |
| Duplicate regions | Duplicate content of each region | `<leader>d` |
| Custom user operators | Register arbitrary operators to work at all cursors | `g:VM_user_operators` |
| Reindent on exit | Auto-reindent edited lines for specified filetypes | `g:VM_reindent_filetypes` |

---

## 2. g:VM_xxx Variable Catalogue

All variables are sourced from:
- `plugin/visual-multi.vim`
- `autoload/vm.vim`
- `autoload/vm/maps.vim`
- `autoload/vm/variables.vim`
- `autoload/vm/commands.vim`
- `autoload/vm/insert.vim`
- `autoload/vm/cursors.vim`
- `autoload/vm/special/case.vim`
- `doc/vm-settings.txt`

### 2.1 Appearance & Highlighting

| g:VM_xxx variable | Type | Default | Purpose |
|-------------------|------|---------|---------|
| `g:VM_highlight_matches` | `string` | `'underline'` | Highlight style for matched-but-unselected patterns. Values: `'underline'`, `'red'`, `''` (plain Search), or a full `:hi` command string. |
| `g:VM_theme` | `string` | `''` | Named theme to load on startup. Available: `iceblue`, `ocean`, `neon`, `purplegray`, `nord`, `codedark`, `spacegray`, `olive`, `sand` (dark); `lightblue1`, `lightblue2`, `lightpurple1`, `lightpurple2`, `paper` (light). `'default'` re-links to colorscheme. |

### 2.2 Statusline & UI

| g:VM_xxx variable | Type | Default | Purpose |
|-------------------|------|---------|---------|
| `g:VM_set_statusline` | `number` | `2` | `0` = off, `1` = set once on start, `2` = refresh on CursorHold, `3` = refresh on CursorMoved too. |
| `g:VM_silent_exit` | `bool` | `0` | Suppress "Exited Visual-Multi." message on exit. |
| `g:VM_show_warnings` | `bool` | `1` | Warn once per buffer if mapping conflicts were detected. Disable if using `:VMDebug` manually. |
| `g:VM_verbose_commands` | `bool` | `0` | More informative prompts for commands like case conversion. |
| `g:VM_cmdheight` | `number` | `1` | If > 1, set `cmdheight` to this value while VM is active. |

### 2.3 Behaviour & Search

| g:VM_xxx variable | Type | Default | Purpose |
|-------------------|------|---------|---------|
| `g:VM_case_setting` | `string` | `''` | Initial case mode: `'smart'`, `'sensitive'`, `'ignore'`, or `''` (inherit from editor). Can be toggled inside VM with `<leader>c`. |
| `g:VM_live_editing` | `bool` | `1` | Controls how often text syncs in insert mode. `0` = update only on InsertLeave. |
| `g:VM_reselect_first` | `bool` | `0` | After most commands, jump back to the first region rather than leaving cursor at last. |
| `g:VM_skip_shorter_lines` | `bool` | `1` | When adding cursors up/down, skip lines shorter than the current column. |
| `g:VM_skip_empty_lines` | `bool` | `0` | When adding cursors up/down, skip empty lines. |
| `g:VM_notify_previously_selected` | `number` | `0` | `0` = silent, `1` = notify when a region was already selected, `2` = notify and do not re-add. |
| `g:VM_recursive_operations_at_cursors` | `bool` | `1` | Use recursive mappings for normal commands at cursors (allows user text objects). Set `0` for always non-recursive. |
| `g:VM_filesize_limit` | `number` | `0` | Max buffer size in bytes; VM refuses to start above this. `0` = disabled. |

### 2.4 Insert Mode Behaviour

| g:VM_xxx variable | Type | Default | Purpose |
|-------------------|------|---------|---------|
| `g:VM_use_first_cursor_in_line` | `bool` | `0` | In insert mode, make the first cursor in the line the active one (needed for some autocomplete plugins). |
| `g:VM_disable_syntax_in_imode` | `bool` | `0` | Disable syntax highlighting while in VM insert mode (performance). |
| `g:VM_insert_special_keys` | `list<string>` | `['c-v']` | Special insert-mode key behaviours to activate. Options: `'c-a'` (go to indent), `'c-e'` (go to EOL), `'c-v'` (paste from VM register). |
| `g:VM_reindent_filetypes` | `list<string>` | `[]` | Filetypes for which edited lines are auto-reindented on insert mode exit. |
| `g:VM_quit_after_leaving_insert_mode` | `bool` | `0` | Automatically exit VM when leaving insert mode. |
| `g:VM_single_mode_maps` | `bool` | `1` | Enable Tab/S-Tab insert-mode maps to cycle cursors in single-region mode. |
| `g:VM_single_mode_auto_reset` | `bool` | `1` | Automatically reset single-region mode when exiting insert mode. |
| `g:VM_add_cursor_at_pos_no_mappings` | `bool` | `0` | When placing a single cursor via `<leader>\`, do not activate buffer mappings immediately (allows free movement to place more cursors). |

### 2.5 Registers

| g:VM_xxx variable | Type | Default | Purpose |
|-------------------|------|---------|---------|
| `g:VM_persistent_registers` | `bool` | `0` | Persist VM registers across Neovim sessions via `viminfo`/`shada`. Requires `!` in `'viminfo'`. |

### 2.6 Keymaps

| g:VM_xxx variable | Type | Default | Purpose |
|-------------------|------|---------|---------|
| `g:VM_maps` | `dict<string,string>` | `{}` | Override individual named keybindings. Key is the action name (e.g., `'Find Under'`), value is the lhs key string or `''` to disable. See Section 3 for the full list of bindable action names. |
| `g:VM_leader` | `string` or `dict` | `'\\'` | Prefix for most buffer-local bindings. Can be a plain string or a dict with keys `'default'`, `'visual'`, `'buffer'` for per-context leaders. |
| `g:VM_default_mappings` | `bool` | `1` | Enable the default global/permanent mappings (leader-based). Set `0` to define everything yourself. |
| `g:VM_mouse_mappings` | `bool` | `0` | Enable mouse mappings (`<C-LeftMouse>`, `<C-RightMouse>`, etc.). |
| `g:VM_check_mappings` | `bool` | `1` | Check for mapping conflicts before applying buffer maps; log conflicts to `:VMDebug`. |
| `g:VM_force_maps` | `list<string>` | `[]` | List of lhs keys to apply even if a buffer mapping conflict exists. |
| `g:VM_custom_remaps` | `dict<string,string>` | `{}` | Remap a key to another VM key inside VM. E.g. `{'<c-p>': 'N'}`. |
| `g:VM_custom_noremaps` | `dict<string,string>` | `{}` | Remap a key to a `normal!` command at all cursors. E.g. `{'==': '=='}`. |
| `g:VM_custom_motions` | `dict<string,string>` | `{}` | Remap motion keys. E.g. `{'h': 'l', 'l': 'h'}` for alternate keyboard layouts. |
| `g:VM_user_operators` | `list` | `[]` | Register custom operators to work at all cursors. Elements are strings or `{op: nchars}` dicts. |
| `g:VM_custom_commands` | `dict<string,string>` | `{}` | Map a key to an arbitrary ex command inside VM. |
| `g:VM_commands_aliases` | `dict<string,string>` | `{}` | Alias VM ex-command names. |

### 2.7 Compatibility

| g:VM_xxx variable | Type | Default | Purpose |
|-------------------|------|---------|---------|
| `g:VM_plugins_compatibilty` | `dict` | `{}` | Declare plugins to disable/re-enable around VM sessions. Structure: `{name: {test: lambda, enable: cmd, disable: cmd}}`. |

### 2.8 Debug / Internal (not user-facing in normal use)

| g:VM_xxx variable | Type | Default | Purpose |
|-------------------|------|---------|---------|
| `g:VM_debug` | `bool` | `0` | Enable debug output in region display functions. |
| `g:VM_use_python` | `bool` | `0` (nvim) | Use Python3 backend for byte operations. Always `0` in Neovim (dropped in Lua rewrite). |

---

## 3. Named Keybindings (g:VM_maps keys)

These are all action names accepted as keys in `g:VM_maps`. They map to `<Plug>(VM-*)` internally.

### Permanent (global) mappings
```
"Reselect Last"          "Add Cursor At Pos"       "Add Cursor At Word"
"Start Regex Search"     "Select All"              "Add Cursor Down"
"Add Cursor Up"          "Visual Regex"            "Visual All"
"Visual Add"             "Visual Find"             "Visual Cursors"
"Find Under"             "Find Subword Under"      "Select Cursor Down"
"Select Cursor Up"       "Select j"  "Select k"    "Select l"  "Select h"
"Select w"  "Select b"   "Select E"  "Select BBW"
"Mouse Cursor"           "Mouse Word"              "Mouse Column"
```

### Buffer-local mappings
```
"Switch Mode"            "Toggle Single Region"    "Find Next"   "Find Prev"
"Goto Next"              "Goto Prev"               "Seek Up"     "Seek Down"
"Skip Region"            "Remove Region"           "Remove Last Region"
"Remove Every n Regions" "Select Operator"         "Find Operator"
"Tools Menu"             "Show Registers"          "Case Setting"
"Toggle Whole Word"      "Case Conversion Menu"    "Search Menu"
"Rewrite Last Search"    "Show Infoline"           "One Per Line"
"Filter Regions"         "Toggle Multiline"        "Undo"        "Redo"
"Surround"               "Merge Regions"           "Transpose"   "Rotate"
"Duplicate"              "Align"                   "Split Regions"
"Visual Subtract"        "Visual Reduce"           "Run Normal"  "Run Last Normal"
"Run Visual"             "Run Last Visual"          "Run Ex"      "Run Last Ex"
"Run Macro"              "Run Dot"                 "Align Char"  "Align Regex"
"Numbers"                "Numbers Append"          "Zero Numbers" "Zero Numbers Append"
"Shrink"                 "Enlarge"                 "Goto Regex"  "Goto Regex!"
"Slash Search"           "Toggle Mappings"         "Exit"
"D"  "Y"  "x"  "X"  "J"  "~"  "&"  "Del"  "Dot"
"Increase"  "Decrease"   "gIncrease"  "gDecrease"
"Alpha Increase"         "Alpha Decrease"
"a"  "A"  "i"  "I"  "o"  "O"  "c"  "gc"  "gu"  "gU"  "C"
"Delete"                 "Replace Characters"      "Replace"
"Transform Regions"      "p Paste"                 "P Paste"     "Yank"
"I Next"                 "I Prev"
(plus all "I Arrow *" insert-mode navigation keys)
```

---

## 4. Proposed setup() Options Table

The following is the idiomatic Lua `setup(opts)` mapping for every `g:VM_xxx` variable.
Naming follows snake_case throughout; related options are grouped into nested tables.

```lua
require('visual-multi').setup({
  -- Appearance
  highlight_matches = 'underline', -- string: 'underline'|'red'|''|full hi cmd
  theme             = '',          -- string: named theme, '' = use colorscheme

  -- Statusline
  statusline = {
    enabled        = true,   -- bool: set statusline at all
    refresh_mode   = 2,      -- number: 1=once, 2=CursorHold, 3=CursorMoved
    silent_exit    = false,  -- bool: suppress "Exited Visual-Multi" msg
  },

  -- UI / Warnings
  show_warnings    = true,   -- bool: warn on mapping conflicts
  verbose_commands = false,  -- bool: more informative command prompts
  cmdheight        = 1,      -- number: cmdheight override while active (1 = no change)

  -- Search / Navigation behaviour
  case_setting            = '',     -- string: 'smart'|'sensitive'|'ignore'|''
  skip_shorter_lines      = true,   -- bool: skip shorter lines when adding cursors up/down
  skip_empty_lines        = false,  -- bool: skip empty lines when adding cursors up/down
  notify_previously_selected = 0,  -- number: 0=silent, 1=notify, 2=notify+no-re-add
  filesize_limit          = 0,     -- number: bytes; 0 = disabled

  -- Edit behaviour
  live_editing     = true,   -- bool: sync text continuously in insert mode
  reselect_first   = false,  -- bool: jump to first region after commands
  recursive_operations_at_cursors = true, -- bool: use recursive maps at cursors

  -- Insert mode
  insert = {
    use_first_cursor_in_line   = false,  -- bool: active cursor = first in line
    disable_syntax             = false,  -- bool: disable syntax in insert mode
    special_keys               = { 'c-v' }, -- list: 'c-a'|'c-e'|'c-v'
    reindent_filetypes         = {},     -- list<string>: filetypes to auto-reindent
    quit_on_leave              = false,  -- bool: exit VM when leaving insert mode
    single_mode_maps           = true,   -- bool: Tab/S-Tab cycle in single-region mode
    single_mode_auto_reset     = true,   -- bool: reset single-region mode on InsertLeave
    add_cursor_no_mappings     = false,  -- bool: no buffer maps on single-cursor-at-pos
  },

  -- Registers
  persistent_registers = false,  -- bool: persist VM registers in shada

  -- Keymaps
  leader           = '\\',  -- string or {default, visual, buffer} table
  default_mappings = true,  -- bool: enable default global mappings
  mouse_mappings   = false, -- bool: enable mouse mappings
  check_mappings   = true,  -- bool: check for conflicts before mapping
  force_maps       = {},    -- list<string>: keys to force-map despite conflicts
  maps             = {},    -- dict<string,string>: override named action bindings
                            --   key = action name, value = lhs or '' to disable
  custom_remaps    = {},    -- dict<string,string>: remap key to another VM key
  custom_noremaps  = {},    -- dict<string,string>: remap key to normal! command
  custom_motions   = {},    -- dict<string,string>: remap motion keys
  user_operators   = {},    -- list: strings or {op=nchars} dicts for custom operators
  custom_commands  = {},    -- dict<string,string>: key -> ex command
  commands_aliases = {},    -- dict<string,string>: ex command name aliases

  -- Plugin compatibility
  plugins_compat   = {},    -- dict<name, {test, enable, disable}>
})
```

### Notes on naming decisions

- `g:VM_set_statusline` is split into `statusline.enabled` + `statusline.refresh_mode`
  because the original overloads presence and refresh frequency into a single number.
- `g:VM_quit_after_leaving_insert_mode` becomes `insert.quit_on_leave` (shorter, clearer).
- `g:VM_plugins_compatibilty` (original has a typo) becomes `plugins_compat` (corrected spelling, shorter).
- `g:VM_recursive_operations_at_cursors` becomes `recursive_operations_at_cursors`
  (the original `doc/vm-settings.txt` omits the `g:` prefix for this one — it is confirmed
  present in `autoload/vm/cursors.vim` line 254).
- `g:VM_cmdheight` is a niche override; kept flat as `cmdheight`.
- `g:VM_debug` is internal/developer use; not surfaced in `setup()` — remains as a raw
  global or a separate `debug = false` top-level key if needed.
- `g:VM_use_python` is dropped entirely — Python backend is removed in the Lua rewrite.
- `g:VM_leader` supporting both string and dict is preserved via accepting either
  `string` or `{default=, visual=, buffer=}` table.

---

## 5. Quality Gate Verification

- [x] Every g:VM_xxx variable catalogued with its purpose
  - 34 distinct variables identified across all source files and docs.
- [x] setup() key naming is idiomatic Lua (snake_case, nested tables)
  - All keys use snake_case; insert-mode options grouped under `insert = {}`;
    statusline options grouped under `statusline = {}`.
- [x] Categories are clear (table stakes vs differentiators)
  - Section 1.1 lists 9 table-stakes features.
  - Section 1.2 lists 26 differentiators specific to vim-visual-multi.

---

## 6. Sources

All findings derived from direct source reading of the master branch:

- `plugin/visual-multi.vim` — plugin entry point, highlight groups, `g:VM_highlight_matches`, `g:VM_persistent_registers`
- `autoload/vm.vim` — primary variable declarations, `g:VM_live_editing`, `g:VM_case_setting`, `g:VM_debug`, `g:VM_reselect_first`, `g:VM_use_first_cursor_in_line`, `g:VM_disable_syntax_in_imode`, `g:VM_reindent_filetypes`, `g:VM_custom_commands`, `g:VM_commands_aliases`
- `autoload/vm/maps.vim` — `g:VM_custom_noremaps`, `g:VM_custom_remaps`, `g:VM_custom_motions`, `g:VM_check_mappings`, `g:VM_default_mappings`, `g:VM_mouse_mappings`, `g:VM_maps`, `g:VM_force_maps`
- `autoload/vm/maps/all.vim` — default key assignments, permanent vs buffer map structure
- `autoload/vm/variables.vim` — `g:VM_case_setting` application, `g:VM_cmdheight`, `g:VM_set_statusline` restore
- `autoload/vm/commands.vim` — `g:VM_skip_shorter_lines`, `g:VM_skip_empty_lines`, `g:VM_add_cursor_at_pos_no_mappings`, `g:VM_notify_previously_selected`
- `autoload/vm/insert.vim` — `g:VM_quit_after_leaving_insert_mode`, `g:VM_single_mode_maps`, `g:VM_single_mode_auto_reset`, insert navigation
- `autoload/vm/cursors.vim` — `g:VM_recursive_operations_at_cursors`
- `autoload/vm/special/case.vim` — `g:VM_verbose_commands`
- `autoload/vm/funcs.vim` — `g:VM_set_statusline`, `g:VM_debug`
- `autoload/vm/themes.vim` — `g:VM_highlight_matches`, `g:VM_theme`, theme catalogue
- `autoload/vm/comp.vim` — `g:VM_plugins_compatibilty` integration
- `autoload/vm/plugs.vim` — `g:VM_user_operators`, `g:VM_custom_remaps`, `g:VM_custom_noremaps`, `g:VM_custom_commands`
- `doc/vm-settings.txt` — canonical documentation with defaults
- `doc/vm-mappings.txt` — mapping system documentation
- `doc/vm-troubleshooting.txt` — `g:VM_plugins_compatibilty` structure
