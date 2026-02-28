# Technology Stack

**Analysis Date:** 2025-02-28

## Languages

**Primary:**
- VimScript - Main plugin implementation
- Python 3 (3.6+) - Test infrastructure and integration

**Secondary:**
- Lua - Emerging support (luarocks integration noted in commit history)

## Runtime

**Environment:**
- Vim 8.0+ (minimum required) or Neovim
- VimScript engine for plugin execution

**Package Manager:**
- pip (for Python test dependencies)
- luarocks (for Lua package distribution - see commit e2ff111)

## Frameworks

**Core:**
- vim-visual-multi (VimScript plugin framework) - Multiple cursor selection and manipulation

**Testing:**
- vimrunner (1.0.3) - VimScript test execution framework for headless Vim/Neovim
- pynvim (0.3.1) - Python Neovim client for programmatic editor control

**Build/Dev:**
- GitHub Actions workflows for CI/CD
- luarocks-tag-release (v5) - Automated Luarocks package publishing

## Key Dependencies

**Critical:**
- `vimrunner` (1.0.3) - Enables headless test execution with Vim/Neovim instances
- `pynvim` (0.3.1) - Provides RPC client interface for Neovim testing via socket communication

**Infrastructure:**
- Python 3.x test runner - `test/test.py` uses subprocess and multiprocessing for parallel test execution
- GitHub Actions `nvim-neorocks/luarocks-tag-release@v5` - Handles automated release publishing

## Configuration

**Environment:**
- Test environment variables:
  - `VM_TEST_TARGET` (vim or lua) - Selects which plugin variant to test
  - `DISPLAY` - X11 display server for headless test rendering (xvfb-run)
- Plugin configuration via global variables (e.g., `g:VM_live_editing`, `g:VM_custom_commands`)

**Build:**
- `.travis.yml` - Legacy CI configuration (Python 3.6, Vim 8.0.1529+)
- `.github/workflows/luarocks.yml` - GitHub Actions workflow for luarocks publishing
  - Triggered on: git tags, releases, manual dispatch
  - Environment: ubuntu-22.04

## Platform Requirements

**Development:**
- Vim 8.0+ with huge features or Neovim (see `vvm use vimorg--v8.0.1529 --install --with-features=huge`)
- Python 3.6+
- X11 display server (for headless GUI testing via xvfb)

**Production:**
- Vim 8.0+ or Neovim
- No external service dependencies
- Works with any standard Vim plugin manager (vim-plug, native packer, etc.)

---

*Stack analysis: 2025-02-28*
