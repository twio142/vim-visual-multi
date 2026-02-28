# External Integrations

**Analysis Date:** 2025-02-28

## APIs & External Services

**Plugin Compatibility Layer:**
- Noice.nvim (compatibility fix in commit a03b78a) - UI notification plugin
  - Integration: `autoload/vm/comp.vim` handles compatibility mappings
  - Type: Plugin API compatibility (not data integration)

**Editor Integration:**
- Vim/Neovim RPC interface (pynvim client)
  - SDK/Client: `pynvim` (0.3.1)
  - Used for: Headless test execution and programmatic editor control

## Data Storage

**Databases:**
- None - No external database integration

**File Storage:**
- Local filesystem only
  - Test inputs: `test/tests/*/input_file.txt`
  - Test outputs: `test/tests/*/generated_output_file.txt`
  - Expected outputs: `test/tests/*/expected_output_file.txt`

**Caching:**
- None - Plugin state managed in-memory via buffer variables (`b:VM_Selection`, `b:VM_Debug`, `b:VM_Backup`)

## Authentication & Identity

**Auth Provider:**
- None - No authentication required

**Implementation:**
- N/A - Local editor plugin, no auth needed

## Monitoring & Observability

**Error Tracking:**
- None configured

**Logs:**
- Local file logging in tests: `log()` function writes to log files during test execution
- Debug mode: `VMDebug` command and `g:VM_debug` flag enable debugging output
- Test output: Captured to `generated_output_file.txt` for comparison with expected results

## CI/CD & Deployment

**Hosting:**
- GitHub repository: https://github.com/mg979/vim-visual-multi

**CI Pipeline:**
- GitHub Actions workflow (`.github/workflows/luarocks.yml`)
  - Runs on: ubuntu-22.04
  - Triggers: git tags, releases, manual dispatch
  - Task: Publishes releases to luarocks registry
  - Environment variable: `LUAROCKS_API_KEY` (stored in GitHub secrets)

**Legacy CI:**
- Travis CI (`.travis.yml`) - Deprecated but shows historical test setup
  - Used: vim-version-manager (vvm) to install multiple Vim versions
  - Used: xvfb for headless X11 display

## Environment Configuration

**Required env vars:**
- `LUAROCKS_API_KEY` - For publishing to luarocks (GitHub Actions only)
- `DISPLAY` - For headless test rendering (set to `:99.0` in Travis CI)

**Test-specific env vars:**
- `VM_TEST_TARGET` - Options: `vim`, `lua` (selects plugin variant)

**Secrets location:**
- GitHub Secrets for `LUAROCKS_API_KEY`
- No local `.env` file required

## Webhooks & Callbacks

**Incoming:**
- GitHub webhook triggers on tag/release events

**Outgoing:**
- Luarocks API calls (publish releases)

## Plugin System & Integrations

**Vim/Neovim Features Used:**
- Autoload system: `autoload/vm/*.vim` modules
- Plugin architecture: `plugin/visual-multi.vim` entry point
- Highlight groups: `VM_Mono`, `VM_Cursor`, `VM_Extend`, `VM_Insert`
- User commands: `VMTheme`, `VMDebug`, `VMClear`, `VMLive`, `VMRegisters`, `VMSearch`

**Compatible Plugins (Compatibility Layer):**
- Noice.nvim - Special handling for noice.nvim UI plugin
- Auto-pairs - Known interaction tracking in `autoload/vm/comp.vim`
- LunarWatcher - Compatibility maintained (commit e67f7fa)
- Other plugins: Generic compatibility framework via `g:VM_plugins_compatibilty` config

---

*Integration audit: 2025-02-28*
