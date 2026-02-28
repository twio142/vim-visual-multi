# Testing Patterns

**Analysis Date:** 2025-02-28

## Test Framework

**Runner:**
- Python test harness: `test/test.py`
- Framework: Custom VimL + Python integration via `vimrunner` (Vim) and `pynvim` (Neovim)
- Vim execution: Two modes - classic Vim via `vimrunner.Server` or Neovim via `pynvim.attach()` with socket communication
- Config: No dedicated test config file; test discovery is automatic from `test/tests/` subdirectories

**Assertion Library:**
- File comparison: `filecmp.cmp()` (Python standard library)
- Tests assert that generated output matches expected output exactly (byte-for-byte)

**Run Commands:**
```bash
./test/test.py                # Run all tests
./test/test.py [test_name]    # Run single test
./test/test.py -l             # List all tests
./test/test.py -t 0.3         # Set key delay in seconds (default 0.1)
./test/test.py -n             # Run with Neovim instead of Vim
./test/test.py -L             # Disable live editing mode
./test/test.py -d             # Show diff of failed tests
```

## Test File Organization

**Location:**
- Test directories: `test/tests/[test_name]/`
- Each test is a subdirectory containing test case files

**Naming:**
- Test directories: `lowercase_descriptive_name`
  - Examples: `abbrev`, `alignment`, `backspace`, `change`, `example`, `regex`, `repl`, `trans`, `vmsearch`
- Required files in each test directory:
  - `input_file.txt` - Starting buffer content
  - `commands.py` - VimL commands to execute (Python script that calls `keys()`)
  - `expected_output_file.txt` - Expected final buffer state
  - (Optional) `vimrc.vim` - Test-specific Vim configuration (falls back to `test/default/vimrc.vim`)
  - (Optional) `config.json` - Test constraints (e.g., max CPU time)

**Structure:**
```
test/
├── test.py                          # Main test runner
├── README.md                        # Test documentation
├── requirements.txt                 # Python dependencies (vimrunner, pynvim)
├── default/
│   └── vimrc.vim                   # Default Vim config for all tests
├── tests/
│   ├── abbrev/
│   │   ├── input_file.txt
│   │   ├── commands.py
│   │   ├── expected_output_file.txt
│   │   └── [vimrc.vim]             # Optional: override default
│   ├── alignment/
│   │   ├── ...
│   └── [other_tests]/
│       ├── ...
└── vendor/
    └── [test dependencies]
```

## Test Structure

**Command Organization:**
Tests are written as Python scripts that execute VimL key sequences. Example from `test/tests/abbrev/commands.py`:

```python
# abbreviations in insert mode

keys(r':inoreabbrev rr return\<CR>')

keys(r':VMLive\<CR>')
keys(r'4\<C-N>')
keys('c')
keys('rr')
keys(r'\<Esc>')
keys(r'\<Esc>')
```

**Patterns:**

1. **Test Discovery:**
   - Automatic: reads all directories under `test/tests/`
   - Sorted alphabetically: `sorted([PurePath(str(p)).name for p in Path('tests').glob('*')])`

2. **Test Description:**
   - First line of `commands.py` starting with `#` is used as test description
   - Example: `# abbreviations in insert mode`
   - Parsed via `get_test_description(test)`

3. **Test Execution:**
   ```python
   def run_one_test(test, f=None, nvim=False):
       paths = get_paths(test, f)        # Locate all test files
       config = {}
       if os.path.exists(paths["config"]):
           config = json.load(open(paths["config"]))

       commands_cpu_time = run_core(paths, nvim)  # Execute test

       # Verify output matches expected
       if filecmp.cmp(paths["exp_out_file"], paths["gen_out_file"]):
           # Check CPU time constraint if present
           if "max_cpu_time" in config and config["max_cpu_time"] < commands_cpu_time:
               return False  # FAIL: too slow
           return True       # PASS
       else:
           return False      # FAIL: output mismatch
   ```

4. **Setup Pattern:**
   - No explicit setup; each test is independent
   - Vim/Neovim launches with test-specific or default vimrc
   - Input file loaded via `CLIENT.command('e %s' % paths["in_file"])`

5. **Teardown Pattern:**
   - Output written: `CLIENT.command(':w! %s' % paths["gen_out_file"])`
   - Client quit: `CLIENT.quit()`
   - Server process terminated via multiprocessing

## Key Input and Automation

**Framework:**
- Two implementations of `keys()` function depending on client type

**Patterns:**

1. **Neovim via pynvim:**
   ```python
   def keys_nvim(key_str):
       """nvim implementation of keys()"""
       key_str = key_str.replace(r'\<', '<')
       key_str = key_str.replace(r'\"', r'"')
       key_str = key_str.replace('\\\\', '\\')
       CLIENT.input(key_str)
       time.sleep(KEY_PRESS_INTERVAL)
   ```

2. **Vim via vimrunner:**
   ```python
   def keys_vim(key_str):
       """vim implementation of keys()"""
       CLIENT.feedkeys(key_str)
       time.sleep(KEY_PRESS_INTERVAL)
   ```

3. **Key Notation Conventions in commands.py:**
   - Raw strings: `r'...'` to avoid Python escaping
   - Literal backslash: `r'\\'`
   - Literal double quote: `r'\"'`
   - Vim key notation: `r'\<CR>'`, `r'\<Esc>'`, `r'\<C-N>'`, `r'\<C-Down>'`
   - Key delay: `KEY_PRESS_INTERVAL` (default 0.1s, configurable via `-t` flag)

## Test Configuration

**config.json (Optional):**
Constraints per test:
```json
{
  "max_cpu_time": 2.7
}
```
- Only current constraint: `max_cpu_time` - test fails if execution exceeds threshold
- Used to detect performance regressions

## Test Types

**Functional/Integration Tests:**
- All tests are functional integration tests
- Scope: Full buffer operations from insert/normal mode through output
- Approach: Command replay with byte-for-byte output comparison
- No unit tests or isolated component testing

**Scope Examples:**
- `abbrev/` - abbreviation expansion in insert mode with VM_live_editing
- `alignment/` - cursor alignment operations
- `change/` - change operator behavior
- `regex/` - regex-based pattern matching and replacement
- `trans/` - text transposition
- `vmsearch/` - search functionality

## Coverage

**Requirements:** Not enforced

**Test Count:**
- 19 separate test directories across different VM features
- `python test.py -l` to list all available tests
- No coverage metrics or reports

**View Test Results:**
```bash
# Run tests and see output
./test/test.py

# Run with diff of failed tests
./test/test.py -d

# Check test log
cat test/test.log
```

**Output:**
- Colored terminal output (ANSI codes): green for PASS, red for FAIL
- Summary: pass/fail count, list of failed tests
- Log file: `test/test.log` (always created)
- Per-test timing: Each test reports CPU time taken

## What Gets Tested

**Tested Areas:**
- Abbreviation handling in insert mode
- Cursor alignment
- Backspace behavior with multiple cursors
- Change operator behavior
- Character deletion and cursor movement
- Cursor positioning operations
- Dot command (repeat)
- Character code retrieval
- Line operations (O/o)
- Paste at cursor
- Regex search and pattern matching
- Text replacement (repl)
- Transposition operations
- VM search functionality

**What NOT Tested:**
- Unit tests for individual functions
- Lua implementation (separate from VimL implementation)
- GUI-specific behavior
- External plugin integration (except VimL core operations)

## Important Test Notes

**Live Editing Mode:**
- Default: `g:VM_live_editing = 1` (enabled)
- Can be disabled globally via `-L` flag
- Tests verify behavior under both modes (some tests run twice)

**Output File Generation:**
- Input file: copied to buffer, modified by test commands
- Output file: generated by `:w!` command in test runner
- Comparison: binary-exact match required

**Platform Compatibility:**
- Tests run on Vim or Neovim (selectable via `-n` flag)
- Default: uses first found `vim` executable
- Supports custom key intervals for slow systems (`-t` flag)

**Error Handling in Tests:**
- File not found: raises FileNotFoundError during path resolution
- Command execution failure: test fails on output mismatch
- Performance threshold exceeded: reports as slow, marked FAIL
- No partial credit: tests are pass/fail binary

## Test Maintenance

**Creating New Tests:**
```bash
# From within Vim:
:call vm#special#commands#new_test()
```

Creates template with:
1. Empty `input_file.txt`
2. Template `commands.py` with comment field
3. Empty `expected_output_file.txt`

Then populate the files:
- Write test steps to `commands.py` using `keys(r'...')` calls
- Record expected output in `expected_output_file.txt`
- Optionally add `vimrc.vim` and `config.json` for customization

---

*Testing analysis: 2025-02-28*
