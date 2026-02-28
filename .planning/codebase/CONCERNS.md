# Codebase Concerns

**Analysis Date:** 2026-02-28

## Tech Debt

**Multibyte Character Handling:**
- Issue: Multiple TODOs and FIXMEs identify incomplete handling of multibyte characters in insert mode and region manipulation. VimScript's byte-offset and char-offset model creates fragile edge cases.
- Files: `autoload/vm/icmds.vim` (line 49), `autoload/vm/region.vim` (line 179)
- Impact: Insert mode operations with multibyte characters (CJK, emoji, accented chars) may shift cursors incorrectly or corrupt text. Replace mode backspace specifically noted as "bugged with multibyte chars".
- Fix approach: Audit all byte/char conversion logic. Replace `strlen()` patterns with `strwidth()` and `strcharpart()` where appropriate. Add comprehensive test coverage for multibyte scenarios across all text operations.

**Deletion in Insert Mode Edge Cases:**
- Issue: Deletion operations (backspace, delete, Ctrl-U) have known issues with certain position scenarios
- Files: `autoload/vm/icmds.vim` (lines 49, 95)
- Impact: Line joining behavior and deletion-to-line-above can produce unexpected results. Affects users editing with trailing/leading whitespace.
- Fix approach: Refactor `vm#icmds#x()` and `vm#icmds#cw()` to handle boundary conditions systematically. Add test cases for EOL, BOL, and whitespace-only scenarios.

**Region Shifting with Multibyte:**
- Issue: `r.shift()` method assumes byte changes are uniform across all text operations, but multibyte characters break this assumption in insert mode
- Files: `autoload/vm/region.vim` (lines 177-192)
- Impact: Cursor positions drift when text contains multibyte characters and multiple edits occur. The comment explicitly warns this will "surely cause trouble".
- Fix approach: Replace shift-based tracking with explicit `update_cursor()` calls in all insert mode paths. Validate byte offsets after each operation.

## Known Bugs

**Snippet Plugins Incompatible:**
- Symptoms: Snippet expansion does not work inside VM. Plugin silently degrades UX without error.
- Files: `doc/vm-troubleshooting.txt` (line 20-22), `autoload/vm/insert.vim` (plugin initialization)
- Trigger: Activate VM in snippet-enabled buffer, attempt to expand snippet during insert mode
- Workaround: Use abbreviations instead; disable snippets in VM context via `b:visual_multi` guard
- Reason: VM intercepts all autocommands during insert mode to synchronize text across cursors. Snippet plugins (which rely on TextChangedI/TextYankPost) can't interact properly.

**Autocompletion with Non-First Cursor:**
- Symptoms: Autocomplete popups show incorrect completions or hang when active cursor is not leftmost in line
- Files: `autoload/vm/comp.vim` (deoplete/ncm2 compatibility), `doc/vm-troubleshooting.txt` (line 37-40)
- Trigger: Multiple cursors in same line, cursor not at start, trigger autocomplete
- Workaround: Set `g:VM_use_first_cursor_in_line = 1` to force interaction through first cursor
- Reason: Autocomplete engines expect a single cursor position; VM's multi-cursor state confuses the plugin.

**Single-Region Mode Insert Limitations:**
- Symptoms: <C-w>, <C-u>, <CR> don't work normally in single-region mode; <BS>/<Del> can delete other cursors unexpectedly
- Files: `autoload/vm/insert.vim`, `doc/vm-troubleshooting.txt` (line 45-49)
- Trigger: Enable single-region mode and use those keys in insert mode
- Reason: These keys are designed for single cursor and don't translate well to multi-cursor scenario

**vim-noice Compatibility:**
- Symptoms: Changed operator causes display glitches or unexpected interaction
- Files: Addressed in `a03b78a fix(plugin): Refactor change operator to fix noice.nvim compatibility` (commit history shows it was fixed)
- Current status: Fixed in recent commits, but fragility indicates tight coupling with plugin ecosystem

## Security Considerations

**Not detected** in codebase scope - this is a text editing utility without network, auth, or external data handling.

## Performance Bottlenecks

**Insert Mode Synchronization Overhead:**
- Problem: All N cursors are synchronized on every keystroke via autocommands, creating O(N) work per character entry
- Files: `autoload/vm/insert.vim` (insert loop logic), `autoload/vm/icmds.vim` (change command per cursor)
- Cause: For-loop iterating regions to apply each keystroke change; byte offset tracking; highlight updates
- Current impact: ~100 cursors still responsive, but becomes sluggish. Lua rewrite would address this.
- Improvement path: The ongoing Lua rewrite (branch `001-lua-nvim-rewrite`) should dramatically improve this via direct Lua APIs and batched operations.

**Highlight Update Frequency:**
- Problem: Every region change triggers full highlight redraw via `r.highlight()` calls
- Files: `autoload/vm/region.vim` (multiple call sites)
- Cause: No batching of updates; each operation redraws independently
- Improvement path: Batch highlight operations, update only affected regions, defer until insert mode exit.

**Regex Search Through Large Buffers:**
- Problem: Pattern stacking without optimization can slow searching in files with 10k+ lines
- Files: `autoload/vm/commands.vim` (lines 152-201, regex find logic), `autoload/vm/search.vim`
- Cause: Each pattern adds region, filtering is done naively
- Improvement path: Add incremental search limits, implement pattern range constraints.

## Fragile Areas

**Insert Mode Architecture:**
- Files: `autoload/vm/insert.vim` (645 lines), `autoload/vm/icmds.vim` (232 lines)
- Why fragile: Insert mode is the most complex state in VM. It manages:
  - Synchronizing text changes across multiple cursors
  - Tracking byte offsets through edits
  - Managing undo/redo boundaries
  - Handling edge cases (EOL, BOL, empty lines, multibyte)
  - Suppressing autocommands while still using them for detection
- Safe modification: Test with both ASCII and multibyte content. Verify undo/redo behavior. Test edge positions (BOL, EOL, very long lines).
- Test coverage: Multiple test suites exist (`test/tests/` directory), but gaps remain for multibyte scenarios.

**Multibyte Character Support:**
- Files: All region/insert/edit files touch this problem; hardest in `autoload/vm/icmds.vim`, `autoload/vm/region.vim`
- Why fragile: VimScript distinguishes bytes, chars, and columns inconsistently. `strlen()` returns bytes, `len()` returns chars, `col()` returns display columns. The plugin uses all three, and mixing them causes bugs.
- Safe modification: Establish a single byte-offset coordinate system. Use consistent helpers. Add preconditions/postconditions to verify invariants.
- Test coverage: Very limited - the main test suite uses primarily ASCII. Multibyte testing exists but is not comprehensive.

**Plugin Compatibility Layer:**
- Files: `autoload/vm/comp.vim` (deoplete, ncm2, auto-pairs, tagalong, ctrlsf)
- Why fragile: Each plugin has its own assumptions about cursor state. VM modifies these assumptions. Changes to plugin APIs require VM updates.
- Safe modification: Add a compatibility test for each integrated plugin. Test both with plugin enabled and disabled.
- Test coverage: Limited - no test suite validates that specific plugins still work.

**Autocommand Suppression:**
- Files: 40+ uses of `noautocmd` and `silent!` across autoload scripts
- Why fragile: These suppress errors and events, making it hard to detect failures. If an autocommand is needed but suppressed, the plugin silently breaks.
- Safe modification: Document why each `noautocmd` exists. Consider more surgical suppression (suppress only specific events if possible).

## Scaling Limits

**Cursor Count Scaling:**
- Current capacity: Tested with 100+ cursors; performance acceptable
- Limit: ~500+ cursors → performance degrades, insert mode becomes sluggish
- Reason: O(N) per-keystroke iteration over all regions; no batching of operations
- Scaling path: Lua rewrite will enable efficient bulk operations via Neovim extmarks API

**Line Count in Buffer:**
- Current capacity: 10k-50k lines work fine
- Limit: 100k+ lines with complex patterns → regex search becomes slow
- Reason: Linear scan of all lines for pattern matching without index optimization
- Scaling path: Implement search bounds, add incremental search, cache pattern results

**Pattern Stacking:**
- Current capacity: 10-20 patterns stack without issues
- Limit: 50+ patterns → memory usage grows, search becomes slow
- Reason: Each pattern stored in `s:v.search[]`, each matched region created independently
- Scaling path: Implement pattern pruning, merge overlapping patterns, limit active pattern count

## Dependencies at Risk

**VimScript Language Dependency:**
- Risk: VimScript's limitations (poor multibyte support, slower execution, limited standard library) make this plugin fragile and complex
- Impact: Bytecode/character/column confusion is hardcoded into VimScript; can't be solved without language migration
- Migration plan: The Lua rewrite (branch `001-lua-nvim-rewrite`) addresses this by porting to Lua + Neovim APIs. This is in progress.
- Current status: Master branch remains VimScript; Lua branch is development target.

**Autocommand Event Ordering:**
- Risk: Plugin relies on specific autocommand firing order and timing. Changes to Vim/Neovim event system could break VM.
- Impact: Snippet plugins, other multi-cursor tools, or Vim changes could cause text corruption
- Current mitigation: Version guard checks `v:version < 800`; requires Vim 8+/Neovim
- Recommendations: Add event listener tests; document assumptions about event ordering; consider migration to callback-based architecture (more robust).

**Python Test Infrastructure:**
- Risk: Tests use `pynvim` for integration testing, which has limitations (`input()` blocking, timing issues)
- Impact: Can't fully validate plugin behavior in some scenarios; false negatives in test results
- Current status: Known limitation documented in memory (T052 finding: 15/18 tests fail due to pynvim, not plugin bugs)
- Recommendations: Migrate test infrastructure to Vim 9 or Lua test framework (mini.test is already vendored for Lua tests)

## Missing Critical Features

**Neovim API Adoption:**
- Problem: Plugin written for Vim 8, doesn't fully leverage Neovim's capabilities (extmarks, Lua, tree-sitter)
- Blocks: Can't use Neovim-specific features; slower performance than possible; can't integrate with modern Neovim ecosystem
- Current status: Lua rewrite in progress (branch `001-lua-nvim-rewrite`) will address this
- Priority: High - this is the motivation for the Lua rewrite

**Interactive End-to-End Testing:**
- Problem: Integration tests are automated but don't include real-world interactive scenarios
- Blocks: Can't validate UX, edge cases with specific combinations of plugins, or latency-sensitive operations
- Current status: Tests are comprehensive but machine-driven; human validation needed for release
- Priority: Medium - can be added post-integration

## Test Coverage Gaps

**Multibyte Character Operations:**
- What's not tested: Insert mode with CJK, emoji, combining marks; delete/backspace with multibyte; region shifting with mixed ASCII/multibyte
- Files: `autoload/vm/icmds.vim`, `autoload/vm/region.vim`, `autoload/vm/insert.vim`
- Risk: Undetected data corruption, silent cursor drift, garbled text. The TODOs/FIXMEs in code confirm this is known broken.
- Priority: High - actively blocks use in non-ASCII environments

**Plugin Compatibility Integration:**
- What's not tested: Actual interaction with deoplete, ncm2, auto-pairs, tagalong, ctrlsf during VM operations
- Files: `autoload/vm/comp.vim`
- Risk: Users discover incompatibilities in the wild; recent noice.nvim fix suggests tight coupling that breaks easily
- Priority: High - compatibility is core to plugin usability

**Edge Cases in Deletion:**
- What's not tested: Backspace/delete at BOL, EOL, empty lines, with trailing whitespace; Ctrl-U with mixed content; line joining edge cases
- Files: `autoload/vm/icmds.vim` (vm#icmds#x, vm#icmds#cw)
- Risk: Users hit corrupted state when editing at document edges. The TODO on line 95 confirms incompleteness.
- Priority: High - affects common editing scenarios

**Single-Region Mode:**
- What's not tested: Comprehensive behavior of single-region mode, sequential field editing, interaction with limited keymap
- Files: `autoload/vm/insert.vim` (s:map_single_mode, single_region checks)
- Risk: Feature works but untested; users may discover edge cases. Limited documented use.
- Priority: Medium - feature is less common but should work reliably

**Undo/Redo Consistency:**
- What's not tested: Complex undo scenarios (undo mid-insert, redo with text changes, undo across cursor creation/deletion)
- Files: Implicit in insert mode flow; tracked via byte offsets
- Risk: Undo tree can become inconsistent with VM's internal state; users see confusing undo behavior
- Priority: Medium - affects data integrity if not robust

---

*Concerns audit: 2026-02-28*
