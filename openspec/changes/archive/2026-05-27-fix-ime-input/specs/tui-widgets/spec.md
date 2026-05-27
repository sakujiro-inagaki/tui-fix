## MODIFIED Requirements

### Requirement: Input widget edits a UTF-8 string with a cursor

The system SHALL provide an `Input` struct with fields `text : String`, `cursor : I64` (byte offset constrained to UTF-8 grapheme-cluster boundaries), `placeholder : String`, `style : Style`, `cursor_style : Style`, `multi_line : Bool`, `max_length : Option I64`. `Input::new` SHALL return an empty single-line input. Builders `with_placeholder` and `with_multi_line` SHALL set the corresponding fields. `Input::text` SHALL return the current text, `Input::clear` SHALL reset the input to empty.

`Frame::render_input : Input -> Rect -> Frame -> Frame` SHALL render the input's text (or `@placeholder` in `@style.dim` if the text is empty), positioning the visual cursor by overriding the cell at `@cursor` with `@cursor_style`. In single-line mode the visible window SHALL scroll horizontally so the cursor is always visible; in multi-line mode lines SHALL wrap at the rect's width (char wrap) and the visible window SHALL scroll vertically so the cursor line is in view. In addition to painting the reverse-video cursor cell, `render_input` SHALL publish the input's logical cursor cell to the frame via `Frame::set_cursor(rect.@x + cx, rect.@y + cy)` where `(cx, cy)` is the cursor's display-column / row inside the rect; this enables the run loop to place the terminal's hardware cursor at the same cell so IME pre-edit text appears at the correct column. When the input is not focused (the application convention being `@cursor_style = Style::default`, i.e. an invisible cursor block) `render_input` MAY skip publishing the cursor so a different focused widget can claim it; for v0.1 the convention is documented but not enforced — last writer on the frame wins.

`Input::handle_key : Key -> Input -> Input` SHALL update the input according to: printable runes (including multi-character `Key::char(s)` values such as those produced by IME commits or paste) insert at the cursor and advance it by the inserted string's UTF-8 byte length; `backspace` removes the grapheme cluster left of the cursor; `delete` removes the grapheme cluster at the cursor; `left`/`right` move the cursor by one grapheme cluster (clamped); `home`/`end` move to the start/end of the current line; `up`/`down` (multi-line only) move between lines preserving column intent; `enter` in multi-line inserts `\n`; `enter` in single-line is preserved unchanged (the application observes the keypress via its own update). Inserts that would exceed `@max_length` (in bytes) SHALL be silently dropped.

#### Scenario: New input is empty with cursor at 0

- **WHEN** `Input::new` is invoked
- **THEN** the result has `@text = ""`, `@cursor = 0`, `@multi_line = false`, `@placeholder = ""`

#### Scenario: Typing inserts at cursor

- **WHEN** `Input::handle_key(Key::char("a"), input)` is called on an empty input
- **THEN** the returned input has `@text = "a"` and `@cursor = 1`

#### Scenario: Backspace removes the preceding grapheme

- **WHEN** `Input::handle_key(Key::backspace, input)` is called on an input with `@text = "café"` (e+combining-acute) and cursor at the end
- **THEN** the returned input has `@text = "caf"` and the cursor sits at byte offset 3

#### Scenario: Wide character cursor moves by one grapheme

- **WHEN** `Input::handle_key(Key::left, input)` is called on an input with `@text = "あい"` and cursor after "い"
- **THEN** the cursor moves to between "あ" and "い" (one grapheme back, three UTF-8 bytes)

#### Scenario: Enter in single-line is passed through unchanged

- **WHEN** `Input::handle_key(Key::enter, input)` is called on a single-line input
- **THEN** the input's text and cursor are unchanged

#### Scenario: Enter in multi-line inserts a newline

- **WHEN** `Input::handle_key(Key::enter, input)` is called on a multi-line input with text "abc" and cursor at end
- **THEN** the returned input has `@text = "abc\n"` and cursor at byte 4

#### Scenario: max_length blocks oversized insert

- **WHEN** `Input::handle_key(Key::char("x"), input)` is called on an input with `@text = "ab"`, cursor at 2, and `@max_length = Option::some(2)`
- **THEN** the returned input has `@text = "ab"` (unchanged)

#### Scenario: Multi-character char insert is applied atomically

- **WHEN** `Input::handle_key(Key::char("こんにちは"), input)` is called on an empty input (this `Key` value is produced when an IME commits or a future event source folds a burst)
- **THEN** the returned input has `@text = "こんにちは"` and `@cursor = 15` (the byte length of the inserted string)

#### Scenario: render_input publishes the cursor cell for ASCII text

- **GIVEN** an input with `@text = "abc"`, `@cursor = 2`, drawn into `Rect::make(4, 1, 20, 1)` on a new frame
- **WHEN** `frame.render_input(input, rect)` is invoked
- **THEN** the returned frame has `@cursor = Option::some((6, 1))` (rect.x + display column 2)

#### Scenario: render_input publishes the cursor cell for wide characters

- **GIVEN** an input with `@text = "あい"`, `@cursor = 6` (after both wide characters), drawn into `Rect::make(0, 0, 20, 1)` on a new frame
- **WHEN** `frame.render_input(input, rect)` is invoked
- **THEN** the returned frame has `@cursor = Option::some((4, 0))` (each wide character contributes display width 2)
