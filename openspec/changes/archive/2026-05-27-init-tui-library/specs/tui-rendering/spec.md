## ADDED Requirements

### Requirement: Style and Color types

The system SHALL provide a `Style` struct holding optional foreground colour, optional background colour, and boolean flags for `bold`, `underline`, `italic`, `reverse`, and `dim`, together with a `Color` union supporting `indexed : U8` (256-colour), `rgb : (U8, U8, U8)` (24-bit truecolor), and `named : Term.Ansi::Color16` (16-colour, re-exported from `term`).

#### Scenario: Default Style has no foreground, no background, and no attributes set

- **WHEN** a caller constructs `Style::default`
- **THEN** `@fg` is `Option::none`, `@bg` is `Option::none`, and `@bold`, `@underline`, `@italic`, `@reverse`, `@dim` are all `false`

#### Scenario: Style fields can be set fluently

- **WHEN** a caller chains `Style::default.set_fg(Color::indexed(9)).set_bold(true)`
- **THEN** the resulting Style has `@fg = Option::some(Color::indexed(9))` and `@bold = true` and other fields remain at their defaults

#### Scenario: Color::named re-exports term's Color16

- **WHEN** a caller constructs `Color::named(Term.Ansi::Color16::red)`
- **THEN** the value type-checks and renders to the same SGR code as `term` produces for `red`

### Requirement: Cell represents one screen position

The system SHALL define `Cell` as a struct of `ch : String` (the UTF-8 bytes of a single grapheme cluster, possibly width 1 or width 2) and `style : Style`. A "wide" cell occupies its leftmost position; the position immediately to its right in the same row SHALL be marked as a continuation cell containing an empty `ch` and the wide cell's `style`.

#### Scenario: Wide grapheme writes a continuation cell to its right

- **WHEN** a caller writes the string "あ" (width 2) at position (0, 0) in a buffer of width 4
- **THEN** cell (0, 0) has `@ch = "あ"` and cell (1, 0) has `@ch = ""` (continuation marker) and the buffer's logical layout reports the next writable column as 2

#### Scenario: Narrow grapheme writes a single cell

- **WHEN** a caller writes the string "A" at position (0, 0)
- **THEN** cell (0, 0) has `@ch = "A"` and cell (1, 0) is unaffected

### Requirement: Buffer is the in-memory frame canvas

The system SHALL provide `Buffer` as a row-major array of `Cell` with explicit `width` and `height`, accessed only through the public API. `Buffer::empty(width, height)` SHALL return a buffer filled with `Cell { ch = " ", style = Style::default }`. All write operations SHALL clip writes that fall outside the buffer's bounds rather than panic.

#### Scenario: empty Buffer is all blanks

- **WHEN** `Buffer::empty(10, 3)` is called
- **THEN** the returned buffer has `@width = 10`, `@height = 3`, and every cell has `@ch = " "` and `@style = Style::default`

#### Scenario: set_cell at an out-of-bounds position is a no-op

- **WHEN** a caller invokes `Buffer::set_cell(20, 5, cell, buf)` against a 10x3 buffer
- **THEN** the buffer is returned unchanged

#### Scenario: set_string clips at the right edge

- **WHEN** a caller invokes `Buffer::set_string(8, 0, "ABCDEF", style, buf)` against a 10-column buffer
- **THEN** cells (8,0) and (9,0) contain "A" and "B" respectively and remaining characters are dropped silently

#### Scenario: set_string preserves grapheme boundaries when clipping

- **WHEN** a caller writes "Aあ" starting at column 9 of a 10-column buffer
- **THEN** cell (9,0) contains "A" and the wide grapheme "あ" is dropped entirely (not split into half)

#### Scenario: set_string_clipped honours a sub-rectangle

- **WHEN** a caller invokes `Buffer::set_string_clipped(Rect::make(2, 1, 5, 1), 0, 0, "Hello, World!", style, buf)`
- **THEN** only the cells inside the rect — (2,1) through (6,1) — are written with "H", "e", "l", "l", "o"

#### Scenario: fill paints a rectangle with one cell value

- **WHEN** a caller invokes `Buffer::fill(Rect::make(1, 1, 3, 2), Cell { ch = "#", style = s }, buf)`
- **THEN** the six cells inside that rect have `@ch = "#"` and `@style = s` and all other cells are unchanged

### Requirement: Frame composes a buffer and its size

The system SHALL provide `Frame` as a box struct containing the terminal `size : Rect` and the working `buffer : Buffer`. `Frame::render_*` functions SHALL be the public surface for drawing a widget into the frame's buffer at a given `Rect`.

#### Scenario: render_text writes a styled string at a Rect's origin

- **WHEN** a caller invokes `frame.render_text("hi", style, Rect::make(0, 0, 10, 1))`
- **THEN** the returned frame's buffer has cells (0,0)="h" and (1,0)="i" with `@style = style`

#### Scenario: render_text clips to its Rect

- **WHEN** a caller invokes `frame.render_text("Hello, World!", style, Rect::make(0, 0, 5, 1))`
- **THEN** only "Hello" is written to the buffer and remaining text is dropped

### Requirement: Diff-to-ANSI output produces minimal terminal writes

The system SHALL provide `Yaynu.Tui.Diff::diff_to_ansi : Buffer -> Buffer -> String` that compares the previous and next buffers and returns an ANSI escape sequence string that, when written to a terminal that already shows the previous buffer's content, transitions the display to match the next buffer. The output SHALL contain at most one cursor positioning escape per row that changed, MUST insert SGR style-change escapes whenever the per-cell style differs from the cursor's currently active style, and MUST reset the SGR style at the end of the returned string.

#### Scenario: Identical buffers produce empty output

- **WHEN** `diff_to_ansi(buf, buf)` is called for any buffer
- **THEN** the result is the empty string (modulo a trailing reset, which is also empty when nothing else was emitted)

#### Scenario: A single changed cell produces one cursor move plus that cell

- **WHEN** the previous buffer has cell (3, 1) = "A" and the next buffer has cell (3, 1) = "B" with all other cells identical
- **THEN** `diff_to_ansi` emits exactly one `CUP(2, 4)` escape, the character "B", and a final reset escape — no other cursor moves

#### Scenario: A run of changed cells on one row uses one cursor move

- **WHEN** the previous and next buffers differ only in cells (2..=6, 0) on row 0
- **THEN** the output positions the cursor once at column 3, row 1 and writes the five updated cells in sequence

#### Scenario: Style changes mid-row emit an SGR escape between cells

- **WHEN** updating two adjacent cells on the same row where the first cell has `@style = Style::default` and the second has `@style.bold = true`
- **THEN** an SGR escape changing the active style is inserted between the two characters
