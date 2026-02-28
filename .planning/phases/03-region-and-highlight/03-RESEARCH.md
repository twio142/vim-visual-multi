# Phase 3: Region and Highlight - Research

**Researched:** 2026-02-28
**Domain:** Neovim extmark-based multi-cursor rendering — highlight groups, region data model, eco-mode batch redraw, teardown
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Cursor appearance model**
- Four highlight groups: `VM_Cursor` (primary cursor-mode), `VM_CursorSecondary` (others, cursor-mode), `VM_Extend` (primary extend-mode selection), `VM_ExtendSecondary` (others, extend-mode)
- `primary_idx` tracks which cursor is primary; defaults to last-added (i.e., `#session.cursors`); Phase 3 must add this field to the session table
- In extend mode the character at the cursor tip (anchor end) gets an additional `VM_Cursor` / `VM_CursorSecondary` overlay on top of the selection highlight
- Zero-width extend regions (anchor == cursor byte position) render as a single-character cursor-mode highlight — not invisible, not a bar

**Eco-mode update strategy**
- Clear-all then redraw-all: `nvim_buf_clear_namespace` followed by a loop setting all extmarks. One screen refresh shows final state.
- Explicitly driven: `highlight.redraw(session)` is called explicitly by operations that change cursor state. No CursorMoved autocmd — the highlight module is a passive renderer.
- Teardown: `session.stop()` calls `highlight.clear(session)` which runs `nvim_buf_clear_namespace` atomically. The `cursors` list is NOT cleared — only visual extmarks are removed.

**Extend-mode selection style**
- Use `VM_Extend` / `VM_ExtendSecondary` (not Neovim's built-in `Visual`) to distinguish VM regions from real visual selection
- Cursor-within-selection: In extend mode, the cursor-tip character gets an additional highlight on top of the selection hl_group. Two extmarks per extend-mode region: one for the full selection span, one for the cursor tip character.
- Original plugin used `matchaddpos`; Lua rewrite uses `nvim_buf_set_extmark` exclusively — no `matchadd`

### Claude's Discretion

- Exact default colors for the four highlight groups (should work on both dark and light themes; `default = true` so colorschemes can override)
- Whether `primary_idx` lives as a field on the session or is derived as `#session.cursors` (last index)
- Whether highlight groups are defined with `nvim_set_hl` (preferred) or `vim.cmd('highlight ...')`
- Exact extmark options: `hl_mode`, `priority`, `strict` values

### Deferred Ideas (OUT OF SCOPE)

- None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FEAT-07 | Extmark-based cursor/selection highlighting with full theming system | Phase 1 stubs cover single-group cursor; Phase 3 expands to 4-group primary/secondary model, extend-mode selections with cursor-tip overlay, eco-mode redraw, and `highlight.redraw(session)` entry point |
</phase_requirements>

---

## Summary

Phase 3 expands the Phase 1 `highlight.lua` and `region.lua` stubs into full implementations. The Phase 1 stubs provide: the `ns` namespace, `draw_cursor`, `draw_selection`, `clear`, and the basic `Region` object with `mark_id` / `pos()` / `move()` / `remove()`. Phase 3 adds the primary/secondary distinction, extend-mode dual-extmark rendering, the `redraw(session)` eco-mode batch function, and the `primary_idx` session field.

The VimScript reference (`global.vim` `update_highlight()` and `update_cursor_highlight()`) shows a clear two-pass pattern: first `remove_highlight()` for all regions (via `matchdelete`), then `r.highlight()` for each region (via `matchaddpos`). The Lua rewrite maps this directly to `nvim_buf_clear_namespace` (one atomic call) followed by a loop that calls `nvim_buf_set_extmark` for each region. This is architecturally cleaner and eliminates ghost highlight risk entirely — the namespace clear is an O(n) operation in Neovim's rbtree, not n individual deletes.

The core data model expansion is: `Region` objects need to store two extmark IDs (one for the selection span, one for the cursor-tip overlay in extend mode), plus a `mode` field (`'cursor'` or `'extend'`) and an `anchor` position for extend-mode selections. The `session` table needs `primary_idx` so `redraw` knows which cursor gets the primary highlight group.

**Primary recommendation:** Implement `highlight.redraw(session)` as the single redraw entry point. It does one clear then one draw pass. Region objects store `sel_mark_id` (selection span) and `tip_mark_id` (cursor-tip overlay, nil in cursor mode). All four highlight groups are defined with `default = true` and linked to semantically appropriate built-in groups.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `nvim_buf_set_extmark` | Neovim 0.10+ stable | Place/update cursor and selection highlights | Single API handles both create and in-place update via `id=` param; auto-adjusts positions on text change |
| `nvim_buf_clear_namespace` | Neovim 0.10+ stable | Atomic teardown of all VM extmarks in a buffer | O(1) from caller's perspective; no ghost highlights; namespace-scoped so it never touches other plugins |
| `nvim_set_hl` | Neovim 0.10+ stable | Define VM highlight groups with `default = true` | Type-safe; `default = true` means colorschemes win; no string parsing |
| `highlight.ns` (Phase 1) | Phase 1 built | Shared namespace for all VM extmarks | Already created at module level in Phase 1; idempotent by name |
| mini.test | vendored | Spec file for Phase 3 new behaviors | Already vendored; 63 tests passing; same test runner |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `nvim_buf_get_extmark_by_id` | built-in | Read back current mark position after text edits | `Region:pos()` — already implemented in Phase 1; unchanged |
| `nvim_buf_del_extmark` | built-in | Delete a single extmark by ID (pcall-wrapped) | `Region:remove()` — already implemented; also for tip_mark_id cleanup |
| `vim.api.nvim_buf_get_extmarks` | built-in | List all marks in namespace (useful for test assertions) | In specs to confirm clear() removed all marks |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `nvim_buf_clear_namespace` + redraw-all | Per-region `nvim_buf_del_extmark` + targeted redraw | Per-region teardown is O(n) individual API calls; clear-namespace is one call; no intermediate visible state; chose clear-all |
| Two extmarks per extend region (sel_mark + tip_mark) | One extmark with `virt_text` for cursor tip | virt_text is not the same as a background highlight on the actual character; `hl_mode = 'combine'` with second extmark at higher priority is the correct approach |
| `nvim_set_hl` with explicit fg/bg colors | `link = 'SomeGroup'` | Links require no color negotiation with theme; `default = true` means user can override; hard-coded colors break many themes; use links |

**No installation needed.** All APIs are built-in. mini.test already vendored.

---

## Architecture Patterns

### Recommended Project Structure (Phase 3 changes only)

```
lua/
  visual-multi/
    highlight.lua     -- EXPAND: add define_groups() with 4 groups, redraw(session)
    region.lua        -- EXPAND: add sel_mark_id, tip_mark_id, anchor, mode fields
    session.lua       -- PATCH: add primary_idx field to _new_session()
test/
  spec/
    highlight_spec.lua  -- EXPAND: add primary/secondary, redraw, extend-mode tests
    region_spec.lua     -- EXPAND: add extend-mode region tests
```

All Phase 1 specs must continue to pass — Phase 3 adds new tests; does not modify existing ones.

---

### Pattern 1: Session `primary_idx` Field

**What:** `primary_idx` is an integer index into `session.cursors`. It identifies which cursor gets the primary highlight groups (`VM_Cursor`, `VM_Extend`). All others get secondary groups.

**When to use:** Set in `_new_session()` to a default; updated by Phase 6 Goto Next/Prev commands.

**Default value:** The last-added cursor is primary. Since cursors are appended to `session.cursors`, default = `#session.cursors` (1-indexed length) — or equivalently, the session initializes with `primary_idx = 0` (no cursors yet), and `redraw` treats `primary_idx == 0` as "no primary" (edge case when session has no cursors).

```lua
-- Source: CONTEXT.md locked decisions + session.lua Phase 1 _new_session()
-- Add to _new_session() in session.lua:
primary_idx = 0,  -- 0 = no cursors yet; updated to #session.cursors when cursor added

-- Convention: Phase 4+ cursor-add operations set primary_idx = #session.cursors
-- Phase 6 Goto Next/Prev updates primary_idx = (primary_idx % #cursors) + 1
```

**Whether it is a stored field or derived:** Store it as a field (`session.primary_idx`). Derivation as `#session.cursors` only holds if primary is always the last-added — Goto commands (Phase 6) will change it independently. Storing it as a field is forward-compatible.

---

### Pattern 2: Region Data Model Expansion

**What:** Each `Region` object gains three new fields to support Phase 3 rendering:
- `sel_mark_id`: extmark ID for the full selection span (cursor mode: single char; extend mode: anchor→tip)
- `tip_mark_id`: extmark ID for the cursor-tip char overlay in extend mode (`nil` in cursor mode)
- `anchor`: `{row, col}` (0-indexed) byte position of the anchor (extend mode only; `nil` in cursor mode)
- `mode`: `'cursor'` or `'extend'` — mirrors `session.extend_mode` at creation time

**Note:** In Phase 1, `Region` stored only `mark_id`. Phase 3 renames `mark_id` to `sel_mark_id` for clarity and adds `tip_mark_id`. The Phase 1 API (`Region:pos()`, `Region:move()`, `Region:remove()`) must be updated to use `sel_mark_id` internally.

**Backward compatibility:** Rename `mark_id` → `sel_mark_id` in `region.lua` and update all internal uses. Phase 1 specs reference `r.mark_id` — those tests must be updated in the same plan that changes the field name. All Phase 1 spec assertions on mark positioning still hold; only the field name changes.

```lua
-- Source: CONTEXT.md decisions + Phase 1 region.lua
-- Phase 3 Region table shape:
{
  buf        = buf,
  _stopped   = false,
  mode       = 'cursor',   -- or 'extend'
  anchor     = nil,        -- {row, col} in extend mode
  sel_mark_id = <integer>, -- extmark for full selection span (was mark_id)
  tip_mark_id = nil,       -- extmark for cursor-tip overlay (extend mode only)
}
```

---

### Pattern 3: `highlight.define_groups()` — Four Primary Groups

**What:** Phase 3 expands `define_groups()` from 4 generic groups to the 4 Phase-3-specific groups. The Phase 1 groups (`VMCursor`, `VMExtend`, `VMInsert`, `VMSearch`) are restructured: the Phase 3 groups are `VM_Cursor`, `VM_CursorSecondary`, `VM_Extend`, `VM_ExtendSecondary`. The naming switches to underscore convention to match the VimScript originals (`VM_Cursor`, `VM_Extend`, etc.).

**Note on naming:** Phase 1 used camelCase (`VMCursor`, `VMExtend`). The CONTEXT.md uses underscore convention (`VM_Cursor`, `VM_Extend`). Phase 3 must rename the groups. All Phase 1 code that references `VMCursor` / `VMExtend` must be updated.

**Default color strategy:** Use `default = true` + `link =` to semantically similar built-in groups. This ensures the plugin works on all colorschemes without hard-coded colors.

```lua
-- Source: CONTEXT.md decisions + themes.vim default theme reference
-- themes.vim "default" theme: VM_Cursor → Visual, VM_Extend → PmenuSel
function M.define_groups()
  -- Primary cursor-mode: bright block-style, visually distinct from normal cursor
  vim.api.nvim_set_hl(0, 'VM_Cursor',          { default = true, link = 'Visual'   })
  -- Secondary cursors: same family, less prominent
  vim.api.nvim_set_hl(0, 'VM_CursorSecondary', { default = true, link = 'Cursor'   })
  -- Primary extend-mode selection
  vim.api.nvim_set_hl(0, 'VM_Extend',          { default = true, link = 'PmenuSel' })
  -- Secondary extend-mode selections
  vim.api.nvim_set_hl(0, 'VM_ExtendSecondary', { default = true, link = 'PmenuSbar'})
  -- Keep VMInsert and VMSearch for later phases (Phase 5, Phase 6)
  vim.api.nvim_set_hl(0, 'VM_Insert',          { default = true, link = 'DiffChange'})
  vim.api.nvim_set_hl(0, 'VM_Search',          { default = true, link = 'Search'   })
end
```

**Note on `default = true`:** When `default = true`, `nvim_set_hl` only sets the group if it has no existing definition. This means: first call sets defaults; colorscheme or user `hi VM_Cursor ...` commands override without conflict. This is the correct pattern for plugin highlight groups.

---

### Pattern 4: `highlight.redraw(session)` — Eco-Mode Batch Redraw

**What:** `redraw(session)` is the single entry point for updating all VM highlights in a buffer. It clears all extmarks for the session's buffer, then re-draws each cursor/region from scratch. This is the "eco-mode" pattern from the VimScript source (global.vim `update_highlight()` → `remove_highlight()` + per-region `r.highlight()`).

**When to use:** Called explicitly by operations after they mutate cursor positions. NOT called on CursorMoved (no autocmd). Called by `session.stop()` indirectly via `highlight.clear(session)` (which already exists in Phase 1).

**Critical detail:** The clear-then-redraw approach means there is exactly one screen refresh cycle between the clear and the final state. Neovim batches extmark mutations and only redraws when control returns to the event loop. So the intermediate state (all marks cleared, none yet redrawn) is never visible to the user.

```lua
-- Source: global.vim update_highlight() pattern + CONTEXT.md eco-mode decision
---@param session table
function M.redraw(session)
  -- Step 1: Atomic clear of all VM extmarks in this buffer
  vim.api.nvim_buf_clear_namespace(session.buf, M.ns, 0, -1)

  -- Step 2: Redraw each cursor/region
  local primary_idx = session.primary_idx
  for i, region in ipairs(session.cursors) do
    local is_primary = (i == primary_idx)
    if session.extend_mode then
      M._draw_extend_region(region, is_primary)
    else
      M._draw_cursor_region(region, is_primary)
    end
  end
end
```

---

### Pattern 5: Drawing Cursor-Mode Regions (4-group model)

**What:** In cursor mode, each region is a single-character highlight using either `VM_Cursor` (primary) or `VM_CursorSecondary` (others). Uses `hl_mode = 'combine'` so the highlight blends with existing syntax. Priority 200 puts VM highlights above normal syntax (100) but below search highlights (300+).

**Zero-width extend fallback:** If a region in extend mode has anchor == cursor position (zero width), it renders identically to a cursor-mode region. The function `_draw_cursor_region` handles both.

```lua
-- Source: Phase 1 highlight.lua draw_cursor + CONTEXT.md primary/secondary model
---@param region table  Region object with sel_mark_id, buf
---@param is_primary boolean
local function _draw_cursor_region(region, is_primary)
  local hl = is_primary and 'VM_Cursor' or 'VM_CursorSecondary'
  local row, col = _region_cursor_pos(region)   -- reads extmark for current position
  region.sel_mark_id = vim.api.nvim_buf_set_extmark(region.buf, M.ns, row, col, {
    id       = region.sel_mark_id,   -- update in place if exists
    end_row  = row,
    end_col  = col + 1,
    hl_group = hl,
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })
end
```

---

### Pattern 6: Drawing Extend-Mode Regions (two extmarks per region)

**What:** In extend mode, each region has:
1. A full-span extmark from `anchor` to `cursor_pos` (or vice versa depending on direction) with `VM_Extend` or `VM_ExtendSecondary`
2. A cursor-tip extmark at the cursor position (the moving end) with `VM_Cursor` or `VM_CursorSecondary` at higher priority (201) so it visually appears on top of the selection

**Direction convention:** The cursor tip is the movable end of the selection. In the VimScript source, `r.b` is the cursor end and `r.a` is the anchor end when `r.dir == 1`. For Phase 3, the `Region` object stores `anchor = {row, col}` (the fixed end) and the movable end is read back from the `sel_mark_id` extmark position.

**Column byte offsets:** `end_col` for the selection extmark must be `cursor_col + char_width` where `char_width` is the byte width of the character at the cursor position (1 for ASCII, 2 for many accented chars, 3 for CJK). Use `vim.fn.strcharlen(char_str)` is wrong here — need byte width. Use `#char_str` where `char_str = vim.api.nvim_buf_get_text(buf, row, col, row, col+1, {})[1]` then `#char_str`.

```lua
-- Source: CONTEXT.md extend-mode selection decisions
---@param region table
---@param is_primary boolean
local function _draw_extend_region(region, is_primary)
  local sel_hl = is_primary and 'VM_Extend'          or 'VM_ExtendSecondary'
  local tip_hl = is_primary and 'VM_Cursor'          or 'VM_CursorSecondary'

  -- Read current cursor tip position from extmark (auto-tracked by Neovim)
  local tip_row, tip_col = _region_cursor_pos(region)
  local anc_row, anc_col = region.anchor[1], region.anchor[2]

  -- Selection span: from min to max of anchor and tip
  local start_row, start_col, end_row, end_col
  if anc_row < tip_row or (anc_row == tip_row and anc_col <= tip_col) then
    start_row, start_col, end_row, end_col = anc_row, anc_col, tip_row, _col_end(region.buf, tip_row, tip_col)
  else
    start_row, start_col, end_row, end_col = tip_row, tip_col, anc_row, _col_end(region.buf, anc_row, anc_col)
  end

  region.sel_mark_id = vim.api.nvim_buf_set_extmark(region.buf, M.ns, start_row, start_col, {
    id       = region.sel_mark_id,
    end_row  = end_row,
    end_col  = end_col,
    hl_group = sel_hl,
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
  })

  -- Cursor-tip overlay at higher priority (visible on top of selection)
  region.tip_mark_id = vim.api.nvim_buf_set_extmark(region.buf, M.ns, tip_row, tip_col, {
    id       = region.tip_mark_id,
    end_row  = tip_row,
    end_col  = _col_end(region.buf, tip_row, tip_col),
    hl_group = tip_hl,
    priority = 201,     -- one above selection: tip visible on top
    hl_mode  = 'combine',
    strict   = false,
  })
end
```

---

### Pattern 7: `_col_end(buf, row, col)` — Safe Byte-Width Helper

**What:** Returns `col + byte_width_of_char_at(buf, row, col)`. This is the `end_col` for a single-character extmark. Must handle: end-of-line (col == line_len), multibyte chars, empty lines.

**Why needed:** `nvim_buf_set_extmark` `end_col` is a byte offset. For a single-character highlight, `end_col = col + 1` is WRONG for multibyte characters. A CJK character at col 0 is 3 bytes wide, so `end_col` should be 3, not 1. This is PITFALL-14 from Phase 1 research.

```lua
-- Source: PITFALLS.md PITFALL-14 + Neovim API byte convention
---@param buf integer
---@param row integer 0-indexed
---@param col integer 0-indexed byte column
---@return integer end_col  col + byte_width_of_char (min 1, safe at EOL)
local function _col_end(buf, row, col)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line or #line == 0 or col >= #line then
    return col + 1  -- EOL or empty line: use col+1 (strict=false handles it)
  end
  -- Get the byte representation of the character at col
  local char = vim.fn.matchstr(line, '.', col)   -- matchstr at byte offset col
  local char_bytes = #char
  return col + (char_bytes > 0 and char_bytes or 1)
end
```

**Critical:** `vim.fn.matchstr(str, '.', byte_offset)` returns the character (potentially multibyte) starting at the given byte offset. `#char` is then the byte width of that character.

---

### Pattern 8: `Region:remove()` — Cleanup Both Extmarks

**What:** Phase 3 `Region:remove()` must delete both `sel_mark_id` AND `tip_mark_id` (if present). The Phase 1 implementation only deletes one mark.

```lua
-- Source: Phase 1 region.lua Region:remove() + CONTEXT.md teardown rule
function Region:remove()
  local hl = require('visual-multi.highlight')
  pcall(vim.api.nvim_buf_del_extmark, self.buf, hl.ns, self.sel_mark_id)
  if self.tip_mark_id then
    pcall(vim.api.nvim_buf_del_extmark, self.buf, hl.ns, self.tip_mark_id)
    self.tip_mark_id = nil
  end
  self._stopped = true
end
```

---

### Pattern 9: Mode Transition — Cursor ↔ Extend

**What:** When `session.toggle_mode()` flips `extend_mode`, the rendering must change for all cursors. In Phase 2, `toggle_mode()` was a stub (just flipped the boolean). Phase 3 fills in the rendering side: after flipping the boolean, call `highlight.redraw(session)`.

**Cursor → Extend mode:** Each cursor needs an `anchor` assigned. The anchor is the cursor's current position (where the cursor was when extend mode was entered). `region.anchor = {row, col}` is set from the current extmark position.

**Extend → Cursor mode:** The VimScript `collapse_regions()` sets each cursor to `r.b` if `r.dir == 1` else `r.a` — i.e., the movable end of the selection. In the Lua model, the movable end is always the extmark position (the anchor is fixed). So collapsing means: keep the `sel_mark_id` extmark at its current position (the cursor tip), delete `tip_mark_id`, clear `anchor`, set `region.mode = 'cursor'`. Then call `highlight.redraw(session)`.

```lua
-- Source: global.vim change_mode() / collapse_regions() + CONTEXT.md mode decision
-- Add to session.lua toggle_mode() in Phase 3:
function M.toggle_mode(session)
  local hl = require('visual-multi.highlight')
  if session.extend_mode then
    -- Extend → Cursor: collapse each selection to its cursor tip
    for _, r in ipairs(session.cursors) do
      local row, col = r:pos()  -- current cursor-tip extmark position
      r.anchor = nil
      r.tip_mark_id = nil  -- will be cleaned up by redraw clear-all
      r.mode = 'cursor'
    end
    session.extend_mode = false
  else
    -- Cursor → Extend: set anchor to current position
    for _, r in ipairs(session.cursors) do
      local row, col = r:pos()
      r.anchor = { row, col }
      r.mode = 'extend'
    end
    session.extend_mode = true
  end
  -- Redraw reflects new mode
  hl.redraw(session)
end
```

---

### Anti-Patterns to Avoid

- **`end_col = col + 1` for multibyte chars:** Silent wrong-width highlight. CJK characters are 2–3 bytes; `col + 1` leaves a gap or wrong boundary. Always use `_col_end(buf, row, col)` (Pattern 7).
- **Per-region `nvim_buf_del_extmark` instead of `nvim_buf_clear_namespace`:** O(n) individual API calls vs O(1) namespace clear. Also leaves ghost marks if any `pcall` fails mid-loop.
- **Triggering `redraw` on CursorMoved autocmd:** The spec says "explicitly driven". An autocmd would fire on every cursor movement including Neovim's own cursor, not just VM cursor changes. Causes performance and infinite-loop bugs.
- **Storing anchor as a byte offset:** Extmarks auto-adjust on text edits but a raw `{row, col}` stored on the table does not. The anchor must itself be tracked as an extmark (or be read and refreshed from a stable source). Simplest approach for Phase 3: also store the anchor as an extmark (`anchor_mark_id`) in the `sel_mark_id` position at the time extend mode was entered, with `right_gravity = false` so insertions before it don't shift it.
- **`VMCursor` / `VMExtend` names from Phase 1:** Phase 3 renames to `VM_Cursor`, `VM_ExtendSecondary`, etc. Any reference to old names in `region.lua` or `highlight.lua` must be updated in the same wave.
- **`priority = 200` for both selection and cursor-tip:** The cursor tip must have a higher priority than the selection so it renders on top. Use 200 for selection, 201 for cursor-tip overlay.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tracking cursor position after text edits | Manual byte-delta math | `nvim_buf_get_extmark_by_id(buf, ns, id, {})` | Neovim updates extmark positions automatically when text is inserted/deleted nearby |
| Atomic highlight teardown | Loop over `session.cursors` and delete each extmark | `nvim_buf_clear_namespace(buf, ns, 0, -1)` | One API call; O(1) from caller; no ghost marks if a region was already removed |
| Anchor position tracking after edits | Store `anchor = {row, col}` as a plain table field | Store anchor as a second extmark (`anchor_mark_id`) with `right_gravity = false` | Plain table field drifts when text is inserted before the anchor; extmarks auto-adjust |
| Byte width of char at position | `1` (ASCII assumption) | `_col_end(buf, row, col)` using `vim.fn.matchstr` | Silent truncation on any multibyte content (é, 字, 🤔) |
| Primary/secondary determination in redraw | Recount cursors each time | Read `session.primary_idx` once at top of `redraw` | O(1) vs O(n); avoids recalculation |

**Key insight:** The three hardest problems in the VimScript highlight system — ghost marks on cursor removal, position drift after edits, and O(n) teardown loops — are all solved for free by the Neovim extmark API. The entire Phase 3 implementation is expressing what to render, not managing where marks live.

---

## Common Pitfalls

### Pitfall 1: Anchor Drift After Text Edits (PITFALL-04 variant)

**What goes wrong:** Region anchor stored as plain `{row, col}` table field. User inserts text before the anchor. The extmark for the cursor tip updates automatically (Neovim tracks it), but `region.anchor` stays at the old coordinate. The selection span is now drawn incorrectly — stretched or inverted.

**Why it happens:** `nvim_buf_set_extmark` returns an ID that Neovim updates on edits. A plain Lua table field `{row, col}` is not an extmark and does not update.

**How to avoid:** Store the anchor as a second extmark with `right_gravity = false` (insertions before it don't shift it to the right). Add `anchor_mark_id` to the Region table. Read `anchor_mark_id` via `nvim_buf_get_extmark_by_id` in `_draw_extend_region` just like the cursor tip.

**Warning signs:** Selection span flips direction or jumps after an insert; tests with buffer edits between cursor creation and redraw show wrong highlight positions.

### Pitfall 2: `end_col` Byte Width for Multibyte Characters (PITFALL-14)

**What goes wrong:** `end_col = col + 1` for a CJK character. The extmark highlight covers only 1 byte but the character is 3 bytes wide. The highlight appears on only the first byte (partial character highlight or invisible on many terminals). Worse, with `strict = false`, this produces no error and the bug is silent.

**Why it happens:** Lua `col + 1` is byte arithmetic. The API expects byte offsets. A 3-byte character at `col` needs `end_col = col + 3`.

**How to avoid:** Use `_col_end(buf, row, col)` everywhere. Never use `col + 1` for single-character extmarks.

**Warning signs:** All tests pass on ASCII content; CJK or emoji test strings show off-by-one highlight boundaries.

### Pitfall 3: Cursor-Tip Highlight Invisible Under Selection (Wrong Priority)

**What goes wrong:** Cursor-tip overlay at priority 200, selection at priority 200. In extend mode, the selection hl_group visually wins (last-set at same priority wins, or the result is colorscheme-dependent). The cursor tip is not visible inside the selection.

**Why it happens:** Same priority = undefined render order between two extmarks at the same position.

**How to avoid:** Always set cursor-tip overlay priority = 201 (one above selection at 200). This is deterministic regardless of colorscheme.

**Warning signs:** In extend mode, can't see which character is the "active" cursor end; the cursor tip looks identical to rest of selection.

### Pitfall 4: Phase 1 `mark_id` References After Field Rename

**What goes wrong:** Phase 3 renames `mark_id` to `sel_mark_id` in `region.lua`. Any code (including Phase 1 specs) that references `r.mark_id` breaks with a nil field dereference — not a Lua error, just a nil extmark ID passed to `nvim_buf_set_extmark` creating a new mark instead of updating in place.

**Why it happens:** Lua tables: accessing an undefined field returns `nil`; no compile-time error.

**How to avoid:** When renaming `mark_id` → `sel_mark_id`, grep for all references and update them. The Phase 1 spec assertions on `r.mark_id` must be updated to `r.sel_mark_id` in the same wave.

**Warning signs:** Extmark count in tests grows unexpectedly (new mark created on each "update"); `r.mark_id` is always nil.

### Pitfall 5: `redraw` Called Before `primary_idx` Is Set

**What goes wrong:** `primary_idx = 0` but `session.cursors` has one entry. `redraw` checks `i == primary_idx` → `1 == 0` → false for all cursors. All cursors render as secondary even though one should be primary.

**Why it happens:** Cursor was added (Phase 4+) but `primary_idx` was not updated.

**How to avoid:** The cursor-add operation (Phase 4) must set `session.primary_idx = #session.cursors` after appending to `session.cursors`. Document this contract in session.lua and in the `primary_idx` field comment. For Phase 3 testing, set `primary_idx` manually in test fixtures.

**Warning signs:** All cursors render with secondary highlight groups even when `#session.cursors == 1`.

### Pitfall 6: `nvim_buf_clear_namespace` + Redraw During Existing Redraw

**What goes wrong:** An operation calls `highlight.redraw(session)`. Inside the redraw loop, another operation (e.g., triggered by an autocmd) also calls `redraw`. The second call clears the namespace mid-loop, causing the first pass to write extmarks to a cleared buffer. Result: double-draw or interleaved extmarks.

**Why it happens:** `redraw` is not re-entrant. If any autocmd triggers another `redraw` during the first one's extmark-setting loop, state is corrupted.

**How to avoid:** Set `session._in_redraw = true` at the top of `redraw`, clear it at the end. Any autocmd handler that might call `redraw` checks this flag and skips. In Phase 3 this is low risk (no CursorMoved autocmd), but document the guard for Phase 4+.

**Warning signs:** Extmark count doubles after certain operations; ghost highlights appear after rapid consecutive operations.

---

## Code Examples

Verified patterns from official Neovim API and project documentation:

### `highlight.lua` — `define_groups()` with 4 Phase-3 groups

```lua
-- Source: CONTEXT.md locked decisions + themes.vim default theme + nvim_set_hl docs
function M.define_groups()
  -- Cursor mode: primary cursor (distinct from real Neovim cursor)
  vim.api.nvim_set_hl(0, 'VM_Cursor',          { default = true, link = 'Visual'    })
  -- Cursor mode: secondary cursors (all non-primary cursors)
  vim.api.nvim_set_hl(0, 'VM_CursorSecondary', { default = true, link = 'Cursor'    })
  -- Extend mode: primary selection span
  vim.api.nvim_set_hl(0, 'VM_Extend',          { default = true, link = 'PmenuSel'  })
  -- Extend mode: secondary selection spans
  vim.api.nvim_set_hl(0, 'VM_ExtendSecondary', { default = true, link = 'PmenuSbar' })
  -- For Phase 5 (insert) and Phase 6 (search) — defined now so colorscheme links work
  vim.api.nvim_set_hl(0, 'VM_Insert',          { default = true, link = 'DiffChange'})
  vim.api.nvim_set_hl(0, 'VM_Search',          { default = true, link = 'Search'    })
end
```

### `highlight.lua` — `redraw(session)` full implementation

```lua
-- Source: CONTEXT.md eco-mode decisions + global.vim update_highlight() pattern
function M.redraw(session)
  if session._stopped then return end

  -- Atomic clear: one call removes all VM extmarks, no ghosts possible
  vim.api.nvim_buf_clear_namespace(session.buf, M.ns, 0, -1)

  local primary_idx = session.primary_idx
  for i, region in ipairs(session.cursors) do
    if not region._stopped then
      local is_primary = (i == primary_idx)
      if session.extend_mode and region.mode == 'extend' then
        _draw_extend_region(region, is_primary)
      else
        _draw_cursor_region(region, is_primary)
      end
    end
  end
end
```

### `region.lua` — Phase 3 `Region.new()` with anchor and mode fields

```lua
-- Source: CONTEXT.md region model + Phase 1 region.lua
---@param buf integer buffer handle
---@param row integer 0-indexed row (cursor tip position)
---@param col integer 0-indexed byte column (cursor tip position)
---@param mode string 'cursor' or 'extend'
---@param anchor table|nil {row, col} anchor position (nil in cursor mode)
function Region.new(buf, row, col, mode, anchor)
  local hl = require('visual-multi.highlight')
  mode = mode or 'cursor'

  local r = setmetatable({
    buf         = buf,
    _stopped    = false,
    mode        = mode,
    tip_mark_id = nil,       -- nil in cursor mode; set by redraw in extend mode
  }, Region)

  -- The main extmark tracks the cursor-tip (movable end) position.
  -- In cursor mode this IS the cursor; in extend mode this is the movable end.
  r.sel_mark_id = vim.api.nvim_buf_set_extmark(buf, hl.ns, row, col, {
    end_row  = row,
    end_col  = _col_end(buf, row, col),
    hl_group = mode == 'cursor' and 'VM_CursorSecondary' or 'VM_ExtendSecondary',
    priority = 200,
    hl_mode  = 'combine',
    strict   = false,
    right_gravity = true,  -- cursor tip: moves right on insert-before
  })

  -- Anchor: store as a second extmark with left_gravity so it doesn't drift right
  if mode == 'extend' and anchor then
    r.anchor_mark_id = vim.api.nvim_buf_set_extmark(buf, hl.ns,
      anchor[1], anchor[2], {
        right_gravity = false,   -- anchor: does NOT move right on insert-before
        strict = false,
      }
    )
  else
    r.anchor_mark_id = nil
  end

  return r
end
```

### `region.lua` — Reading anchor and tip positions in `redraw`

```lua
-- Source: nvim_buf_get_extmark_by_id docs + CONTEXT.md anchor decision
-- Called inside _draw_extend_region to get current positions after text edits:
local function _region_cursor_pos(region)
  local hl = require('visual-multi.highlight')
  local info = vim.api.nvim_buf_get_extmark_by_id(region.buf, hl.ns, region.sel_mark_id, {})
  return info[1], info[2]  -- row (0-indexed), col (0-indexed byte)
end

local function _region_anchor_pos(region)
  local hl = require('visual-multi.highlight')
  if not region.anchor_mark_id then return nil, nil end
  local info = vim.api.nvim_buf_get_extmark_by_id(region.buf, hl.ns, region.anchor_mark_id, {})
  return info[1], info[2]
end
```

### `test/spec/highlight_spec.lua` — Phase 3 new test skeleton

```lua
-- Source: Phase 1 highlight_spec.lua pattern (MiniTest conventions preserved)
-- All Phase 1 tests continue to pass; Phase 3 adds these new test groups:

-- Test: redraw with 2 cursors, primary_idx = 2 → first gets secondary group
T_hl['redraw draws primary cursor with VM_Cursor group'] = function()
  -- Setup: fake session with 2 cursors
  local hl = require('visual-multi.highlight')
  local r1 = require('visual-multi.region').new(buf, 0, 0)
  local r2 = require('visual-multi.region').new(buf, 0, 5)
  local session = {
    buf         = buf,
    _stopped    = false,
    extend_mode = false,
    primary_idx = 2,      -- r2 is primary
    cursors     = { r1, r2 },
  }
  hl.redraw(session)
  -- Verify r2's sel_mark_id uses VM_Cursor (primary):
  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, { details = true })
  -- At least one mark at (0,5) should have hl_group = 'VM_Cursor'
  local found_primary = false
  for _, m in ipairs(marks) do
    if m[2] == 0 and m[3] == 5 and m[4].hl_group == 'VM_Cursor' then
      found_primary = true
    end
  end
  assert(found_primary, 'Expected VM_Cursor highlight at primary cursor position')
end

-- Test: clear(session) after redraw leaves zero extmarks
T_hl['clear after redraw leaves no extmarks'] = function()
  local hl = require('visual-multi.highlight')
  local r1 = require('visual-multi.region').new(buf, 0, 0)
  local session = { buf = buf, _stopped = false, extend_mode = false, primary_idx = 1, cursors = {r1} }
  hl.redraw(session)
  hl.clear(session)
  local marks = vim.api.nvim_buf_get_extmarks(buf, hl.ns, 0, -1, {})
  MiniTest.expect.equality(marks, {})
end
```

### `session.lua` — `_new_session` patch: add `primary_idx`

```lua
-- Source: CONTEXT.md primary_idx decision + Phase 2 session.lua
-- Add to the existing _new_session() return table:
primary_idx = 0,   -- 0 = no cursors; set to #session.cursors when cursor added
```

---

## State of the Art

| Old Approach (VimScript) | Lua Approach (Phase 3) | Impact |
|--------------------------|------------------------|--------|
| `matchaddpos` per-region highlight | `nvim_buf_set_extmark` with `hl_group` | Positions auto-track text edits; no ghost marks; atomic teardown |
| `remove_highlight()` loop + `matchdelete` per-region | `nvim_buf_clear_namespace(buf, ns, 0, -1)` | One call vs n calls; atomic; never fails on already-deleted marks |
| `VM_Cursor` / `VM_Extend` (two groups only, single tier) | 4 groups: `VM_Cursor`, `VM_CursorSecondary`, `VM_Extend`, `VM_ExtendSecondary` | Primary/secondary visual distinction without changing the core clear-and-redraw architecture |
| `highlight clear MultiCursor` + `link MultiCursor VM_Cursor` | `nvim_set_hl(0, 'VM_Cursor', { default=true, link='...' })` | No string parsing; `default = true` means colorscheme overrides work without explicit user config |
| Region `r.a`/`r.b` byte offsets + manual shift on edits | Extmark IDs; `nvim_buf_get_extmark_by_id` reads current position | Eliminates the entire VimScript `r.shift()` method and all byte-delta arithmetic |

**Deprecated/outdated in this phase:**
- `VMCursor` / `VMExtend` (camelCase, Phase 1 stubs): Rename to `VM_Cursor`, `VM_Extend` etc. in Phase 3
- `mark_id` field on Region: Rename to `sel_mark_id` in Phase 3
- `highlight.draw_cursor(buf, row, col, mark_id)` style API: Still kept for compatibility but `redraw(session)` is the primary entry point going forward

---

## Phase 3 Plan Structure Recommendation

Phase 3 has a natural two-wave structure:

**Wave 1 — Data model and teardown (no rendering visible)**
- Add `primary_idx` to `session.lua`
- Rename `mark_id` → `sel_mark_id` in `region.lua`; add `anchor_mark_id`, `tip_mark_id`, `mode` fields
- Expand `highlight.define_groups()` to 4 groups (rename `VMCursor`→`VM_Cursor` etc.)
- Update all Phase 1 specs for renamed field and groups
- Expand `Region:remove()` to clean up both extmarks

**Wave 2 — `highlight.redraw(session)` + mode transition**
- Implement `_col_end` helper
- Implement `_draw_cursor_region` and `_draw_extend_region` in `highlight.lua`
- Implement `highlight.redraw(session)`
- Integrate `redraw` call into `session.toggle_mode()`
- Write new specs for primary/secondary, extend-mode, mode toggle, teardown

---

## Open Questions

1. **Whether `anchor_mark_id` needs to be a namespace extmark or can be a zero-priority invisible extmark**
   - What we know: Phase 3 uses `nvim_buf_clear_namespace` to clear ALL marks in the namespace, including `anchor_mark_id`. After a clear-all, the next redraw would try to update `anchor_mark_id` via `id=` but the mark is gone.
   - What's unclear: Whether the redraw pattern (clear-all, then recreate all marks) means we should NOT use `id=` for any mark (just always create new marks), or whether we need to track that after a clear-all, all stored IDs are stale.
   - Recommendation: The simplest resolution — after `nvim_buf_clear_namespace`, all stored mark IDs are stale. The redraw loop creates new marks (without `id=`) and stores the new IDs back on the region objects. This avoids the `id=` update-in-place pattern during eco-mode redraw, which is fine because the clear-all already atomically removed all marks. **Use: always create new marks in `redraw`, store returned IDs back on region objects.**

2. **Right-gravity vs left-gravity for cursor-tip extmark**
   - What we know: When text is inserted AT the cursor position, `right_gravity = true` means the mark moves to the right of the inserted text (stays at the insertion point after insert). `right_gravity = false` means the mark stays at the original position (before the inserted text).
   - For a VM cursor in cursor mode: inserting `i` (insert mode) should move the extmark forward (right_gravity = true is correct for a cursor that advances as you type).
   - What's unclear: Whether Phase 3 needs to address this at all since insert mode is Phase 5.
   - Recommendation: Default `right_gravity = true` for `sel_mark_id` (cursor tip moves right on insert). Document this as a known consideration for Phase 5 insert mode integration.

3. **Whether `foldenable` save/restore belongs in Phase 3**
   - What we know: The Phase 2 RESEARCH.md option inventory lists `foldenable` as "Phase 3 — implicit". The VimScript source disables folding during VM sessions via `vm#variables#set`.
   - What's unclear: Whether the Phase 3 plan should add `foldenable` save/restore to `session.lua`, or whether it is a Phase 7 config concern.
   - Recommendation: Add `foldenable = false` during session start to Phase 3. It is a rendering concern (folds interfere with multi-cursor highlight visibility) and fits naturally with the highlight/region phase. Save with `nvim_win_get_option(win, 'foldenable')`, restore on stop.

---

## Sources

### Primary (HIGH confidence)

- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/highlight.lua` — Phase 1 stub; actual API surface confirmed
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/region.lua` — Phase 1 stub; actual field names confirmed (`mark_id`, `_stopped`, `pos()`, `move()`, `remove()`)
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/lua/visual-multi/session.lua` — Phase 2 implementation; actual `_new_session()` shape confirmed; `primary_idx` not yet present
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/test/spec/highlight_spec.lua` — Phase 1 specs; all must pass after Phase 3 changes
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/test/spec/region_spec.lua` — Phase 1 specs; `r.mark_id` references need updating to `r.sel_mark_id`
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/global.vim` — `update_highlight()` (lines 148–158) and `collapse_regions()` (lines 337–345): authoritative clear-and-redraw pattern
- `/Users/h.s.zhou/.local/share/nvim/lazy/vim-visual-multi/autoload/vm/themes.vim` — Default theme color links (lines 34–39): `VM_Cursor → Visual`, `VM_Extend → PmenuSel`
- `.planning/phases/03-region-and-highlight/03-CONTEXT.md` — All locked decisions: 4 groups, primary_idx, cursor-tip overlay, zero-width fallback, eco-mode explicit-drive, teardown preserves cursors list
- `.planning/research/PITFALLS.md` — PITFALL-04 (byte vs char), PITFALL-05 (matchaddpos → extmarks), PITFALL-14 (col + 1 for multibyte)

### Secondary (MEDIUM confidence)

- `.planning/phases/01-foundation/01-RESEARCH.md` — Pattern 5 (extmark ID stored for in-place update), Pattern 4 (namespace sharing), Anti-Patterns list
- `.planning/phases/02-session-lifecycle/02-RESEARCH.md` — Session table shape, option save/restore inventory, Phase 2 deferred items (foldenable, guicursor) now relevant to Phase 3

### Tertiary (LOW confidence)

- No web search used. All findings are based on project documentation, actual Phase 1/2 code, and VimScript source. All claims are verifiable in the repository.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are Phase 1 confirmed working; `nvim_buf_clear_namespace`, `nvim_buf_set_extmark` with `hl_group` are well-exercised in Phase 1 specs
- Architecture (4-group model, redraw pattern): HIGH — directly derived from locked CONTEXT.md decisions and VimScript `update_highlight()` / `collapse_regions()` source
- Anchor-as-extmark decision: MEDIUM — solves the drift problem definitively but adds complexity (anchor_mark_id cleared by clear-all then recreated in redraw); the Open Question 1 resolution (always create new marks in redraw) needs one test to confirm
- Code examples: HIGH — all examples follow Phase 1 patterns directly; extmark API options confirmed against Neovim 0.10 docs via Phase 1 research
- Pitfalls: HIGH for col+1/multibyte (PITFALL-14 confirmed in Phase 1), HIGH for priority ordering, MEDIUM for anchor drift (architectural analysis, not a confirmed prior bug)

**Research date:** 2026-02-28
**Valid until:** 2026-05-28 (90 days — all APIs are Neovim stable; VimScript reference is frozen)
