# tui-widgets Specification

## Purpose

Defines the v0.1 set of stock widgets the TUI ships: text, paragraph (with wrap modes and scroll), selectable list, editable input, tab bar, animated spinner, progress bar, and decorative border. Each widget is exposed through a builder/constructor surface, a `Frame::render_*` rendering entry point, and (where relevant) a `handle_key` for state updates.

## Requirements

### Requirement: Text widget renders a single styled line

The system SHALL provide `Frame::render_text : String -> Style -> Rect -> Frame -> Frame` that writes the given string into the frame's buffer starting at the rect's top-left, applying the given style, truncating to the rect's width using the grapheme-aware truncation, and writing only into the rect's first row.

#### Scenario: Text inside the rect appears verbatim

- **WHEN** `frame.render_text("hi", style, Rect::make(2, 1, 10, 1))` is invoked on a 20×3 frame
- **THEN** cells (2,1)="h" and (3,1)="i" carry the style and all other cells are unchanged

#### Scenario: Text wider than the rect is truncated

- **WHEN** `frame.render_text("Hello, World", style, Rect::make(0, 0, 5, 1))` is invoked
- **THEN** only "Hello" is written; the trailing characters are dropped

#### Scenario: Rect height >1 only uses the first row

- **WHEN** `frame.render_text("abc", style, Rect::make(0, 0, 10, 3))` is invoked
- **THEN** row 0 contains "abc" and rows 1 and 2 are unchanged

### Requirement: Paragraph widget wraps text within a rect

The system SHALL provide a `Paragraph` struct with fields `text : String`, `style : Style`, `wrap : WrapMode`, and `scroll : I64` (a vertical offset in wrapped rows), where `WrapMode` is a box union with constructors `no_wrap : ()`, `word : ()`, and `char : ()`. `Frame::render_paragraph : Paragraph -> Rect -> Frame -> Frame` SHALL lay out the paragraph row-by-row within the rect: existing `\n` in the source text always break lines; in `word` mode soft wraps occur at the last ASCII space before the width limit (falling back to character wrap if no space exists in the line); in `char` mode soft wraps occur at the next grapheme boundary that would exceed the width; in `no_wrap` mode lines that overflow are truncated at the right edge. The first `@scroll` wrapped rows SHALL be skipped before drawing.

#### Scenario: no_wrap truncates long lines

- **WHEN** rendering `Paragraph { text = "Hello, World", wrap = no_wrap, scroll = 0, ... }` into a `Rect::make(0, 0, 5, 3)`
- **THEN** row 0 contains "Hello" and rows 1 and 2 are blank

#### Scenario: word wrap breaks at the last space within the width

- **WHEN** rendering `Paragraph { text = "the quick brown fox", wrap = word, scroll = 0, ... }` into a `Rect::make(0, 0, 10, 3)`
- **THEN** row 0 is "the quick", row 1 is "brown fox", and row 2 is blank

#### Scenario: char wrap breaks at the next grapheme boundary

- **WHEN** rendering `Paragraph { text = "abcdefghij", wrap = char, scroll = 0, ... }` into a `Rect::make(0, 0, 4, 3)`
- **THEN** row 0 is "abcd", row 1 is "efgh", row 2 is "ij"

#### Scenario: Explicit newline always breaks regardless of wrap mode

- **WHEN** rendering `Paragraph { text = "a\nb", wrap = no_wrap, scroll = 0, ... }` into a wide rect
- **THEN** row 0 is "a" and row 1 is "b"

#### Scenario: Scroll skips the first N wrapped rows

- **WHEN** rendering a paragraph that wraps to 5 rows with `@scroll = 2` into a 3-row rect
- **THEN** the visible content is the paragraph's rows 2, 3, 4

### Requirement: List widget displays selectable items

The system SHALL provide a parametric `List a` struct with fields `items : Array (ListItem a)`, `selected : Option I64`, `scroll : I64`, `style : Style`, `selected_style : Style`, and `highlight_symbol : Option String`, plus a `ListItem a` struct with `text : String`, `value : a`, `style : Style`. `List::new`, `List::with_selected`, and `List::with_highlight_symbol` SHALL be the constructors and builders. `List::selected_value : List a -> Option a` SHALL return the value of the currently selected item or `Option::none` if none is selected.

`Frame::render_list : List a -> Rect -> Frame -> Frame` SHALL render visible items starting at row `@scroll` of the list, one item per row, truncating each item's text to the rect's width (minus the highlight symbol's width when applicable), applying `@style` to non-selected rows and `@selected_style` to the selected row, and prefixing the selected row with the highlight symbol when present.

`List::handle_key : Key -> List a -> List a` SHALL update selection and scroll in response to: `down` / `up` / `page_down` / `page_up` / `home` / `end`. Down/Up SHALL move the selection by one within `[0, len-1]` bounds; PageDown/PageUp SHALL move by 10 (clamped). Scroll position SHALL be adjusted so the selected item remains visible given a hint of the most-recently-rendered viewport height (in v0.1, the implementation MAY conservatively scroll to keep `selected` on the first visible row when it would otherwise leave the viewport; this trade-off is documented).

#### Scenario: render_list shows visible items with highlight on the selected row

- **WHEN** rendering a list of items `["alpha", "beta", "gamma"]` with `@selected = Some(1)`, `@highlight_symbol = Some("> ")` into a 10×3 rect
- **THEN** row 0 contains "  alpha", row 1 contains "> beta" in `selected_style`, row 2 contains "  gamma"

#### Scenario: handle_key with down advances selection

- **WHEN** `List::handle_key(Key::down, list)` is called on a list with `@selected = Some(0)` and 3 items
- **THEN** the returned list has `@selected = Some(1)`

#### Scenario: handle_key with down at the end stays at the last item

- **WHEN** `List::handle_key(Key::down, list)` is called with `@selected = Some(2)` on a 3-item list
- **THEN** the returned list has `@selected = Some(2)`

#### Scenario: selected_value returns the chosen item's value

- **WHEN** `List::selected_value(list)` is called on a list with `@selected = Some(1)` whose item at index 1 has `@value = "x"`
- **THEN** the result is `Option::some("x")`

#### Scenario: selected_value returns none when nothing selected

- **WHEN** `List::selected_value(list)` is called on a list with `@selected = Option::none`
- **THEN** the result is `Option::none`

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

### Requirement: Tabs widget renders a horizontal title bar with a selected tab

The system SHALL provide a `Tabs` struct with fields `titles : Array String`, `selected : I64`, `style : Style`, `selected_style : Style`, `divider : String`. `Tabs::new`, `Tabs::with_selected`, `Tabs::next`, `Tabs::prev` SHALL be the helpers. `Frame::render_tabs : Tabs -> Rect -> Frame -> Frame` SHALL render each title joined by `@divider` along the rect's first row, applying `@selected_style` to the selected title's cells and `@style` to all others, truncating at the right edge if the joined string exceeds the rect width.

#### Scenario: tabs render with divider between titles

- **WHEN** `frame.render_tabs(Tabs::new(["a", "b", "c"]).with_selected(1), Rect::make(0, 0, 20, 1))` is called with divider " | "
- **THEN** row 0 reads "a | b | c" with "b" carrying `selected_style` and the rest carrying `style`

#### Scenario: next wraps around at the end

- **WHEN** `Tabs::next(tabs)` is called on a 3-tab Tabs with `@selected = 2`
- **THEN** the returned tabs has `@selected = 0`

#### Scenario: prev wraps around at the start

- **WHEN** `Tabs::prev(tabs)` is called on a 3-tab Tabs with `@selected = 0`
- **THEN** the returned tabs has `@selected = 2`

### Requirement: Spinner widget animates through a frame sequence

The system SHALL provide a `Spinner` struct with fields `frames : Array String`, `frame_index : I64`, `style : Style`, `label : Option String`. Presets `Spinner::dots`, `Spinner::line`, `Spinner::ball`, `Spinner::arrows`, `Spinner::clock`, `Spinner::box_bounce`, and `Spinner::pear_hands` SHALL be exposed as constants. `Spinner::with_label` SHALL set the label. `Spinner::tick : Spinner -> Spinner` SHALL advance `@frame_index` by one modulo the frame count. `Frame::render_spinner : Spinner -> Rect -> Frame -> Frame` SHALL render the current frame followed by a single space and the label (if present), all with `@style`, truncating to the rect's width. All frames of a given preset SHALL have the same display width so the row tail does not flicker.

#### Scenario: tick advances and wraps

- **WHEN** `Spinner::tick(spinner)` is called repeatedly on a spinner whose frames have length 4
- **THEN** `@frame_index` follows the sequence `0 → 1 → 2 → 3 → 0 → 1 → ...`

#### Scenario: pear_hands preset exists and all frames have width 2

- **WHEN** `Spinner::pear_hands` is constructed and each frame's `string_width` is computed
- **THEN** every frame has display width `2`

#### Scenario: render_spinner draws the current frame followed by an optional label

- **WHEN** rendering a dots spinner with `@frame_index = 0` and `@label = Option::some("Thinking…")` into a wide rect
- **THEN** the rendered row starts with the dots frame, then a space, then "Thinking…"

### Requirement: Progress widget renders a fill bar

The system SHALL provide a `Progress` struct with fields `value : F64` (clamped to `[0.0, 1.0]` when rendered), `width : I64`, `style : Style`, `fill_char : String`, `empty_char : String`, `label : Option String`. `Progress::new` SHALL return defaults `value = 0.0, width = 20, style = Style::default, fill_char = "█", empty_char = "░", label = Option::none`. Builders `with_value` and `with_width` SHALL set the respective fields. `Progress::indeterminate : I64 -> Progress` SHALL return a Progress whose `value = -1.0` (a sentinel meaning "indeterminate") and whose `frame_index` (carried internally via `@width` rotation) drives an animated stripe. `Progress::tick : Progress -> Progress` SHALL advance the animation by one step when in indeterminate mode and SHALL return the input unchanged otherwise. `Frame::render_progress : Progress -> Rect -> Frame -> Frame` SHALL draw `@fill_char` for the filled prefix and `@empty_char` for the remainder, or an animated stripe pattern in indeterminate mode, and append the label (auto-generated as e.g. "42%" if `@label = Option::none` in determinate mode).

#### Scenario: 50% draws half full, half empty

- **WHEN** rendering `Progress::new.with_value(0.5).with_width(10)` into a wide rect
- **THEN** the rendered row starts with five fill chars followed by five empty chars

#### Scenario: Value above 1.0 clamps to 1.0

- **WHEN** rendering with `@value = 2.0` and `@width = 5`
- **THEN** the rendered row contains 5 fill chars

#### Scenario: Determinate progress with no label shows a percentage

- **WHEN** rendering `Progress::new.with_value(0.42)` with `@label = Option::none` into a wide rect
- **THEN** the rendered row ends with " 42%"

#### Scenario: Indeterminate tick advances the animation frame

- **WHEN** `Progress::tick(p)` is called on an indeterminate progress at frame N
- **THEN** the returned progress is at frame N+1 modulo its animation length

### Requirement: Border widget frames a rect

The system SHALL provide a `Border` struct with fields `style : Style`, `sides : BorderSides`, `border_type : BorderType`, `title : Option String`, `title_alignment : Alignment`, where `BorderSides` is a struct of `top : Bool, right : Bool, bottom : Bool, left : Bool`, `BorderType` is a box union `plain | rounded | double | thick`, and `Alignment` is a box union `left | center | right`. `Border::all`, `Border::none`, and `Border::with_title` SHALL be the helpers. `Border::inner : Rect -> Border -> Rect` SHALL return the rect inside the border, reduced by 1 cell on each enabled side. `Frame::render_border : Border -> Rect -> Frame -> Frame` SHALL draw the border's corners and sides using the per-`border_type` Unicode box-drawing glyphs and, if a title is set and `@sides.top` is true, draw the title (truncated as needed) on the top edge at the position dictated by `@title_alignment`.

#### Scenario: inner reduces the rect by enabled sides

- **WHEN** `Border::all.inner(Rect::make(2, 1, 10, 5))` is called (all four sides on)
- **THEN** the returned rect is `Rect::make(3, 2, 8, 3)`

#### Scenario: A border with no sides leaves inner equal to outer

- **WHEN** `Border::none.inner(Rect::make(2, 1, 10, 5))` is called
- **THEN** the returned rect is `Rect::make(2, 1, 10, 5)`

#### Scenario: rounded border type uses rounded corner glyphs

- **WHEN** `frame.render_border(Border::all with @border_type = rounded, Rect::make(0, 0, 4, 3))` is invoked
- **THEN** cells (0,0)="╭", (3,0)="╮", (0,2)="╰", (3,2)="╯"

#### Scenario: Title is drawn on the top edge when sides.top is enabled

- **WHEN** rendering a Border with `@title = Option::some("Hello")` and `@title_alignment = center` into a 10×3 rect
- **THEN** the title "Hello" appears on row 0 centered between the top corners, overwriting the horizontal-line glyphs where it lands
