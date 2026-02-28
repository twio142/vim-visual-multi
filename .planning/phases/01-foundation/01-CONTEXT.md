# Phase 1: Foundation - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Build and test the 5 Tier-0/1 Lua modules: `config`, `util`, `highlight`, `region`, `undo`. These modules have no inter-plugin dependencies (only Neovim API), must be hardened against the 5 confirmed bugs from the prior Lua port, and must pass the mini.test unit suite headless. This phase does NOT include session lifecycle, keymaps, or any user-facing features — those are Phase 2+.

</domain>

<decisions>
## Implementation Decisions

### Coexistence with VimScript

- Development happens on a new branch (e.g. `002-lua-rewrite`); the VimScript plugin on `master` stays untouched and fully functional throughout
- No feature flag — on the Lua branch, the Lua side is simply the active entry point
- `plugin/visual-multi.vim` shim: minimal bootstrap only — version guard (Neovim 0.10+) + `require('visual-multi')`. No VimScript logic duplicated there.
- VimScript `autoload/` tree remains on the Lua branch as reference material until Phase 8, when it is deleted after E2E parity is confirmed

### Config Validation

- **Unknown keys** → `vim.notify` warning (plugin still loads): e.g. `"visual-multi: unknown option 'hightlight_matches' — did you mean 'highlight_matches'?"`
- **Wrong type** → hard error with descriptive message: e.g. `"visual-multi: setup() maps must be a table, got string"`
- **Called twice** → merge/overwrite — second call's opts are deep-merged over the existing config. No warning. Supports incremental config patterns (lazy.nvim, modular init files).
- **Lazy init** → `setup(opts)` stores config immediately but defers heavy initialization (autocommands, keymaps, highlight group registration) until the first buffer is opened. Standard Neovim plugin pattern.

### Public API & Namespace

- Require path: `require('visual-multi')` — matches the plugin's directory and repo name
- Public surface on `init.lua`:
  - `setup(opts)` — sole config entry point
  - `get_state(bufnr?)` — returns current session state table (or nil if no active session); `bufnr` defaults to current buffer
  - All `<Plug>(VM-xxx)` mappings — exposed for every action so users can remap any key without modifying plugin source
- `vim.b.VM_Selection` — maintained on the buffer variable for backward compatibility with existing statusline configs and external integrations that read it today; `get_state()` is the new idiomatic accessor
- Internal modules (`require('visual-multi.session')`, etc.) are **private** — no public contract, free to refactor

### Claude's Discretion

- Exact structure of the `M` (module) table pattern in each Lua file
- How config defaults are stored (module-level frozen table vs function returning fresh table)
- test helper design (fake session factory, buffer setup/teardown utilities)
- highlight namespace initialization timing (module-level `nvim_create_namespace` vs lazy)

</decisions>

<specifics>
## Specific Ideas

- The `<Plug>(VM-xxx)` naming convention from the VimScript version should be preserved exactly — users who have remapped keys in their dotfiles will expect the same plug names
- `vim.b.VM_Selection` key name should match exactly to avoid breaking any existing integrations (lualine components, custom statusline functions, etc.)

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within Phase 1 scope

</deferred>

---

*Phase: 01-foundation*
*Context gathered: 2026-02-28*
