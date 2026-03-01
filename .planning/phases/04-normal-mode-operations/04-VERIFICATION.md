---
phase: 04-normal-mode-operations
verified: 2026-03-01T00:30:00Z
status: passed
score: 10/10 must-haves verified
re_verification: false
---

# Phase 4: Normal-Mode Operations Verification Report

**Phase Goal:** Implement normal-mode operations (exec, yank, paste, dot, g_increment, case/replace wrappers) at all cursors simultaneously with single-undo-entry grouping.
**Verified:** 2026-03-01T00:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                        | Status     | Evidence                                                                         |
|----|----------------------------------------------------------------------------------------------|------------|----------------------------------------------------------------------------------|
| 1  | session.start() saves synmaxcol, textwidth, hlsearch, concealcursor alongside Phase 2 opts  | VERIFIED   | session.lua lines 67-83: all four saved in _save_and_set_options, restored in _restore_options |
| 2  | edit.lua exports exec, yank, paste, dot, g_increment as callable functions                   | VERIFIED   | edit.lua 301 lines; all 5 exported + change/case_toggle/case_upper/case_lower/replace_char |
| 3  | edit_spec.lua scaffold exists with test harness                                              | VERIFIED   | edit_spec.lua 410 lines; MiniTest.new_set with pre_case/post_case hooks          |
| 4  | dw with 2 cursors deletes one word at each cursor position                                   | VERIFIED   | Test "exec deletes word at each cursor — dw at hello and foo" passes             |
| 5  | A single u undoes all cursor edits from one M.exec call                                      | VERIFIED   | Tests "exec wraps edits in a single undo entry" and "undo after exec reverses all cursor deletions" pass |
| 6  | p with VM register pastes per-cursor text; falls back to Vim register when empty             | VERIFIED   | Tests "yank populates session._vm_register" and "paste with empty VM register" pass |
| 7  | Dot-repeat replays last exec'd keys at all active cursors                                    | VERIFIED   | Tests "dot replays last exec keys" and "dot is silent when _vm_dot is nil" pass  |
| 8  | g<C-a> with 3 cursors increments top-to-bottom by +1, +2, +3                                | VERIFIED   | Test "g_increment applies +1,+2,+3 top-to-bottom on numbers" passes (10→11, 20→22, 30→33) |
| 9  | g<C-x> decrements symmetrically: -1, -2, -3                                                 | VERIFIED   | Test "g_increment applies -1,-2,-3 top-to-bottom on numbers" passes (10→9, 20→18, 30→27) |
| 10 | Case conversion and replace-char apply at all cursors in one undo step                       | VERIFIED   | Category K (case_toggle/upper/lower) and Category R (replace_char) all pass     |

**Score:** 10/10 truths verified

---

### Required Artifacts

| Artifact                            | Expected                                              | Lines | Status     | Details                                                                |
|-------------------------------------|-------------------------------------------------------|-------|------------|------------------------------------------------------------------------|
| `lua/visual-multi/session.lua`      | Option save/restore with Phase 4 options              | 322   | VERIFIED   | synmaxcol, textwidth, hlsearch, concealcursor present with validity guards |
| `lua/visual-multi/edit.lua`         | M.exec, M.yank, M.paste, M.dot, g_increment, wrappers | 301   | VERIFIED   | All functions implemented, no stubs remaining; min_lines 160 exceeded   |
| `test/spec/edit_spec.lua`           | FEAT-05 + FEAT-06 + FEAT-10 behavioral tests          | 410   | VERIFIED   | 27 tests covering all required behaviors; min_lines 150 exceeded        |

---

### Key Link Verification

| From                              | To                            | Via                                           | Pattern Checked              | Status     | Details                                                              |
|-----------------------------------|-------------------------------|-----------------------------------------------|------------------------------|------------|----------------------------------------------------------------------|
| session.lua _save_and_set_options | synmaxcol/textwidth/hlsearch/concealcursor | saves and sets values               | "synmaxcol" literal          | WIRED      | Lines 67-83: all four options saved, set, and restored in _restore_options |
| edit.lua                          | visual-multi.undo             | `local undo = require('visual-multi.undo')`   | top-level require            | WIRED      | Line 15: top-level require; undo.begin_block called at lines 79, 175, 240 |
| edit.lua                          | visual-multi.highlight        | `local hl = require('visual-multi.highlight')` | top-level require           | WIRED      | Line 16; hl.redraw(session) called at lines 115, 155, 201, 268      |
| edit.lua M.exec                   | nvim_feedkeys                 | `pcall(vim.api.nvim_feedkeys, encoded, 'x', false)` | feedkeys.*'x'           | WIRED      | Line 97; 'x' mode (synchronous) as required                          |
| edit.lua M.exec                   | undo.begin_block / end_block  | wraps cursor loop                             | undo.begin_block(session)    | WIRED      | Lines 79+101; also uses undojoin between cursors for FEAT-06 guarantee |
| edit.lua M.g_increment            | undo.begin_block / end_block  | wraps top-to-bottom loop                      | begin_block at line 240      | WIRED      | Lines 240+260; eventignore bracket with pcall-finally restore        |
| edit.lua M.g_increment            | nvim_feedkeys                 | string.rep('<C-a>', step) encoded             | string.rep at lines 251+253  | WIRED      | Lines 251-256; string.rep('<C-a>', step) with nvim_replace_termcodes  |

---

### Requirements Coverage

| Requirement | Source Plans    | Description                                                                 | Status    | Evidence                                                               |
|-------------|-----------------|-----------------------------------------------------------------------------|-----------|------------------------------------------------------------------------|
| FEAT-05     | 04-01, 04-02    | Simultaneous normal mode commands — d, c, y, p, D, C, x, J, and all standard ops | SATISFIED | M.exec (bottom-to-top feedkeys loop), M.yank, M.paste, M.dot, M.change all implemented and tested; 27 passing tests |
| FEAT-06     | 04-01, 04-02    | Undo grouping — all-cursor edits within a session undo as a single operation | SATISFIED | undojoin between cursor iterations + undo.begin/end_block; "exec wraps edits in a single undo entry" and "undo after exec reverses all cursor deletions" pass |
| FEAT-10     | 04-03           | Case conversion (upper/lower/title/cycle), replace-chars (r), increase/decrease numbers | SATISFIED | M.g_increment (+1/+2/+3 sequential), M.case_toggle/upper/lower, M.replace_char all implemented; Categories G, K, R all pass |

**Orphaned requirements check:** REQUIREMENTS.md maps exactly FEAT-05, FEAT-06, FEAT-10 to Phase 4. All three appear in plan frontmatter. No orphaned requirements.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| edit.lua | 221-225 | Comment "Phase 5 will handle insert-mode entry" in _exec_change | Info | Intentional scope boundary documentation; not a stub — the function is implemented and exported |

No TODO/FIXME/XXX/HACK/PLACEHOLDER strings found in any phase 4 files. No empty implementations (`return null`, `return {}`, stub bodies) found. All function bodies contain real code.

---

### Human Verification Required

None. All behaviors are verifiable programmatically via the headless test suite. The test suite (100 tests, 0 failures) directly exercises every behavioral truth established in the must-haves.

---

### Gaps Summary

No gaps. All 10 observable truths verified, all 3 required artifacts pass all three levels (exists, substantive, wired), all 7 key links confirmed active, all 3 requirement IDs satisfied with passing tests, no blocker anti-patterns found.

---

## Commit Verification

All commits referenced in summaries exist and are reachable:

| Commit  | Message                                                                  |
|---------|--------------------------------------------------------------------------|
| 37f25b3 | feat(04-01): patch session.lua with Phase 4 options                      |
| c51e2e3 | feat(04-01): create edit.lua skeleton and edit_spec.lua scaffold          |
| 1e8b730 | feat(04-02): implement M.exec, M.yank, M.paste, M.dot, M.change in edit.lua |
| 970bb98 | feat(04-03): implement M.g_increment and case/replace wrappers in edit.lua |
| 6a7e222 | test(04-03): add FEAT-10 behavioral tests — g_increment, case, replace-char |

## Notable Implementation Decisions (Deviations from Plan)

The following plan deviations were auto-fixed during execution and are verified correct in the final state:

1. **undojoin vs. begin/end block alone (Plan 02):** M.exec uses undojoin between cursor iterations (lines 91-95), not solely undo.begin_block/end_block, to achieve FEAT-06 single-undo-entry guarantee. begin_block/end_block track state but do not merge feedkeys undo entries — undojoin does the actual merging. Both mechanisms are present and wired.

2. **File-backed tmpfile buffers in tests (Plan 02):** edit_spec.lua pre_case uses `vim.fn.tempname()` + `vim.cmd('edit')` instead of `nvim_create_buf(false, false)` with buftype=nofile. This is required because buftype=nofile sets undolevels=-123456, preventing feedkeys edits from registering in undotree().seq_cur.

3. **BUG-04 test adjusted to `delta <= 1` (Plan 02):** The no-op test checks `after - before <= 1` rather than strict `== 0`, because feedkeys on an empty line may create an internal undo entry even when content doesn't visibly change. The critical invariant (not N entries for N cursors) is still validated by the 3-cursor test.

4. **undolevels flush in undo-count tests (Plan 03):** Tests that call nvim_buf_set_lines to set up test content flush undo history with the undolevels=-1 trick before measuring the seq_cur baseline.

---

_Verified: 2026-03-01T00:30:00Z_
_Verifier: Claude (gsd-verifier)_
