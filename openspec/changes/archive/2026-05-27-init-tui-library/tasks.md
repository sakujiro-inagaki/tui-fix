## 1. Project Scaffolding

- [x] 1.1 Create `fixproj.toml` declaring the project (library), depending on `Std` and `term` (`https://github.com/sakujiro-inagaki/term-fix`), with no Minilib dependency
- [x] 1.2 Create directory layout: `src/Yaynu/Tui/`, `src/Yaynu/Tui/Width/`, `src/Yaynu/Tui/Widget/`, `tests/`, `tests/fixtures/`, `examples/`, `scripts/`
- [x] 1.3 Add `.gitignore` entries for Fix build artefacts (`.fix/`, `target/`, etc. as applicable)
- [x] 1.4 Add `src/Yaynu/Tui.fix` skeleton (façade module that will re-export `Frame`, `run`, common types once they exist) with a placeholder `module Yaynu.Tui;` declaration

## 2. Core Types (Pure, No Dependencies on Width)

- [x] 2.1 Implement `src/Yaynu/Tui/Style.fix`: `Style` struct with `default`, `set_fg`, `set_bg`, `set_bold`, `set_underline`, `set_italic`, `set_reverse`, `set_dim`; `Color` union with `indexed`, `rgb`, `named` (re-exporting `Term.Ansi::Color16`)
- [x] 2.2 Implement `src/Yaynu/Tui/Rect.fix`: `Rect` struct and `make`; `Constraint` union; leave `split_horizontal` / `split_vertical` as `todo` stubs to be filled in section 11
- [x] 2.3 Implement `src/Yaynu/Tui/Cell.fix`: `Cell` struct
- [x] 2.4 Add unit tests for `Style` setters (`tests/StyleTest.fix`)

## 3. Unicode Width Table Generation

- [x] 3.1 Write `scripts/gen_eaw.sh` that fetches `EastAsianWidth.txt` from `https://www.unicode.org/Public/UCD/latest/ucd/` and `emoji-data.txt` from `.../ucd/emoji/`
- [x] 3.2 Have the script parse both files and emit `src/Yaynu/Tui/Width/Table.fix` containing:
  - A leading comment with the Unicode version and retrieval date
  - `eaw_ranges : Array (U32, U32, EawClass)` sorted by start
  - `emoji_ranges : Array (U32, U32, EmojiProp)` sorted by start
  - `combining_ranges : Array (U32, U32)` (general categories Mn/Me)
  - `variation_selector_ranges` and ZWJ as singleton ranges
- [x] 3.3 Run the script once to generate `Table.fix`; commit the generated file
- [x] 3.4 Verify the table compiles by running `fix build`

## 4. Width API (depends on Section 3)

- [x] 4.1 Implement `src/Yaynu/Tui/Width.fix` with the public API: `char_width`, `string_width`, `truncate`, `truncate_with_ellipsis`, `set_ambiguous_width`, `get_ambiguous_width`, `iter_graphemes`, plus `GraphemeCluster` struct
- [x] 4.2 Implement `src/Yaynu/Tui/Width/Grapheme.fix` with the cluster-boundary state machine: base+combining marks, extended-pictographic + ZWJ chains, regional indicator pairs, emoji modifier sequences, `\r\n` as one cluster
- [x] 4.3 Implement binary search over `Table.fix`'s range arrays for codepoint lookup
- [x] 4.4 Wire `ambiguous_width` to an `IORef I64` (initialized to 1) read from `char_width`
- [x] 4.5 Author `tests/fixtures/eaw_cases.txt` covering at minimum: ASCII, Japanese, mixed JA/EN, fullwidth digits, halfwidth katakana, single emoji, ZWJ family, skin-tone modifier, regional indicator pair, combining mark on Latin base, control char, lone ZWJ
- [x] 4.6 Implement `tests/WidthTest.fix` that parses the fixture file and asserts `string_width` matches every expected value
- [x] 4.7 Add unit tests for `char_width` on representative codepoints (one per EAW class plus emoji exceptions for `#`, `*`, `0`–`9`)
- [x] 4.8 Add unit tests for `iter_graphemes` covering ASCII, ZWJ family, combining-mark cluster, CRLF
- [x] 4.9 Add unit tests for `truncate` (exact fit, wide-char overflow, budget 0, ZWJ-emoji atomicity) and `truncate_with_ellipsis` (passthrough, shortening, budget < ellipsis width)
- [x] 4.10 Add a test that round-trips `set_ambiguous_width(2)` / `set_ambiguous_width(1)` and observes both behaviours

## 5. Buffer (depends on Width)

- [x] 5.1 Implement `src/Yaynu/Tui/Buffer.fix`: `Buffer` struct, `empty`, `set_cell` (with bounds checking → no-op out of bounds), `fill`
- [x] 5.2 Implement `Buffer::set_string` iterating with `iter_graphemes`: each cluster writes its bytes to its cell; wide clusters write a continuation marker (`Cell { ch = "", style }`) to the cell to the right; clipping at the right edge drops the cluster entirely rather than splitting
- [x] 5.3 Implement `Buffer::set_string_clipped` taking a `Rect` plus an `(x, y)` offset within it
- [x] 5.4 Add unit tests for: empty buffer state; set_cell in-bounds + out-of-bounds; set_string with ASCII; set_string with wide chars (continuation cell present); set_string clipping (right edge with wide char excluded); set_string_clipped honouring a sub-rect; fill painting a sub-rect

## 6. Frame and render_text (depends on Buffer)

- [x] 6.1 Implement `src/Yaynu/Tui/Frame.fix` with `Frame` struct and constructor `Frame::new : Rect -> Frame` (zero-fills the buffer)
- [x] 6.2 Implement `Frame::render_text` (call site for `Buffer::set_string_clipped`)
- [x] 6.3 Add unit tests for `render_text` covering: in-rect, truncation, rect-height-greater-than-1 only using row 0

## 7. Diff-to-ANSI (depends on Frame/Buffer)

- [x] 7.1 Implement `src/Yaynu/Tui/Diff.fix`: `diff_to_ansi : Buffer -> Buffer -> String` doing per-row leftmost-to-rightmost diff, emitting at most one `CUP` per row, tracking the active SGR style and emitting an SGR change only on style transition, ending with an SGR reset whenever anything was emitted
- [x] 7.2 Add unit tests: identical buffers → empty; one changed cell → one CUP + one char + reset; run of 5 changed cells → one CUP + 5 chars + reset; style change mid-row inserts an SGR; wide-cell change includes both the cell and its continuation marker

## 8. Event Loop (depends on Diff)

- [x] 8.1 Implement `src/Yaynu/Tui/Event.fix`: `Event` union (`key`, `resize`, `tick`, `custom`), `UpdateResult` union (`continue`, `quit`), `TuiApp` trait declaration
- [x] 8.2 Implement `Yaynu.Tui::run` in `src/Yaynu/Tui.fix`: enter raw mode + alternate screen via `term`; initialize previous buffer to all-blanks at terminal size; loop render→read-with-timeout→update; handle resize by reallocating the previous buffer to the new size; ensure raw mode and alternate screen are restored even on exception via a `bracket`-style finalizer
- [x] 8.3 Verify the façade `src/Yaynu/Tui.fix` re-exports `Frame`, `run`, `Event`, `UpdateResult`, `TuiApp`, common widget render fns
- [x] 8.4 Build `examples/hello_tui.fix`: a state with no fields that renders "Hello, TUI! (press Esc to quit)" and quits on Esc; verify by manual run
- [x] 8.5 Build `examples/width_demo.fix`: render Japanese, emoji, ZWJ family, skin-tone, regional indicator, combining-mark text on separate lines and visually confirm no display corruption

## 9. Border Widget

- [x] 9.1 Implement `src/Yaynu/Tui/Widget/Border.fix`: `Border`, `BorderSides`, `BorderType`, `Alignment` types; `Border::all`, `Border::none`, `Border::with_title`; `Border::inner`
- [x] 9.2 Implement `Frame::render_border` drawing corner + horizontal/vertical glyphs per `BorderType`; render title on top edge per alignment when `@sides.top`
- [x] 9.3 Add unit tests for `Border::inner` (all sides, no sides, mixed), and a render test for `rounded` corners and title placement (left / center / right)

## 10. Paragraph Widget

- [x] 10.1 Implement `src/Yaynu/Tui/Widget/Paragraph.fix`: `Paragraph` struct, `WrapMode` union
- [x] 10.2 Implement `Frame::render_paragraph`: layout algorithm (split on `\n`, then per line apply the wrap mode; honour `@scroll`); use `iter_graphemes` throughout
- [x] 10.3 Add unit tests for each `WrapMode` (no_wrap truncation, word wrap with space, word wrap with no space falling back to char wrap, char wrap), explicit-newline behaviour, and scroll offset

## 11. Layout split functions (replace section 2.2 stubs)

- [x] 11.1 Implement `Rect::split_horizontal` with the two-pass solver (assign non-fill, then distribute fill via largest-remainder), and overflow-shrink-from-end
- [x] 11.2 Implement `Rect::split_vertical` (mirror of split_horizontal on the Y axis)
- [x] 11.3 Add unit tests: all-fixed; fill weights; percentage rounding without total drift; empty constraint array; overflow; ratio constraint; min/max clamping

## 12. List Widget

- [x] 12.1 Implement `src/Yaynu/Tui/Widget/List.fix`: `List a` struct, `ListItem a` struct, `List::new`, `List::with_selected`, `List::with_highlight_symbol`, `List::selected_value`
- [x] 12.2 Implement `Frame::render_list` honouring scroll, selected style, highlight symbol, and per-item truncation
- [x] 12.3 Implement `List::handle_key` for down/up/page_down/page_up/home/end with bounds clamping
- [x] 12.4 Add unit tests for selection movement, page movement, selected_value with/without selection, render with highlight symbol on selected row

## 13. Input Widget

- [x] 13.1 Implement `src/Yaynu/Tui/Widget/Input.fix`: `Input` struct, `Input::new`, `with_placeholder`, `with_multi_line`, `text`, `clear`
- [x] 13.2 Implement `Input::handle_key`: printable insert (grapheme-aware), backspace/delete (grapheme-aware), left/right by grapheme, home/end, up/down (multi-line, column-intent preserved), enter behaviour by mode, max_length enforcement
- [x] 13.3 Implement `Frame::render_input`: placeholder rendering when empty; cursor cell override with `@cursor_style`; horizontal scroll (single-line) keeping cursor visible; vertical scroll (multi-line) keeping cursor line visible
- [x] 13.4 Add unit tests for: empty new input, single-rune insert, backspace removing combining-mark cluster (`café`), left/right across wide chars, enter single-line passthrough, enter multi-line inserts newline, max_length blocking insert
- [x] 13.5 Build `examples/input_demo.fix`: single-line + multi-line variants accepting Japanese and emoji input; on Enter (single) or Ctrl+D (multi) print the accumulated text on quit

## 14. Tabs Widget

- [x] 14.1 Implement `src/Yaynu/Tui/Widget/Tabs.fix`: `Tabs` struct, `Tabs::new`, `with_selected`, `next` (wrapping), `prev` (wrapping)
- [x] 14.2 Implement `Frame::render_tabs` joining titles with `@divider` and styling the selected title
- [x] 14.3 Add unit tests for next/prev wrap-around and a render test confirming selected style is applied only to the selected title's cells
- [x] 14.4 Build `examples/tabs_demo.fix`: three tabs, Tab key cycles, Shift+Tab cycles back

## 15. Spinner Widget

- [x] 15.1 Implement `src/Yaynu/Tui/Widget/Spinner.fix`: `Spinner` struct, `tick`, `with_label`
- [x] 15.2 Implement presets `dots`, `line`, `ball`, `arrows`, `clock`, `box_bounce`, and `pear_hands`; verify all frames of each preset have equal display width
- [x] 15.3 Implement `Frame::render_spinner` rendering current frame + space + optional label, truncated to rect width
- [x] 15.4 Add unit tests for `tick` advancement/wrap and a width-equality test asserting all preset frames have constant width
- [x] 15.5 Build `examples/spinner_demo.fix`: display every preset side-by-side animating at 100ms ticks, with labels

## 16. Progress Widget

- [x] 16.1 Implement `src/Yaynu/Tui/Widget/Progress.fix`: `Progress` struct with determinate + indeterminate modes; `new`, `with_value`, `with_width`, `indeterminate`, `tick`
- [x] 16.2 Implement `Frame::render_progress`: determinate fills with `@fill_char` and `@empty_char` and appends auto-percentage label when `@label = none`; indeterminate renders an animated stripe
- [x] 16.3 Add unit tests: 0% / 50% / 100% / clamping above 1.0 / auto-label / indeterminate tick advancement

## 17. Layout + Examples (integration)

- [x] 17.1 Build `examples/layout_demo.fix`: top row tabs, status-bar bottom row, middle split into left side panel (List) and main pane (Paragraph), demonstrating `split_vertical` + nested `split_horizontal`
- [x] 17.2 Build `examples/list_demo.fix`: a list with 20 items, arrow keys move selection, Enter prints selection
- [x] 17.3 Manually verify every example: launches cleanly, responds to keys as documented, restores terminal on quit, and survives terminal resize without corruption

## 18. README and Final Wrap-Up

- [x] 18.1 Write `README.md` covering: scope, immediate-mode + Elm-style architecture, dependency on `term`, minimal "Hello, TUI" example (under the `Yaynu.Tui` namespace), per-widget usage snippets, layout examples, East Asian Width section with `set_ambiguous_width` note, emoji/ZWJ/combining-mark coverage statement, examples directory pointer
- [x] 18.2 Add a note in README about the future namespace promotion (`Yaynu.Tui` → top-level `Tui`) so Yaynu maintainers know the rename is planned
- [x] 18.3 Run `fix test` and confirm green; capture the test count in the README's status section
- [x] 18.4 Run every `examples/*.fix` manually and tick the corresponding 17.3 checkbox after observing correct behaviour
- [x] 18.5 Sanity-check that `scripts/gen_eaw.sh` runs to completion on a fresh checkout and produces a clean diff (idempotency check)
