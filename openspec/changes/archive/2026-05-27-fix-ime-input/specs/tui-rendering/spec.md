## MODIFIED Requirements

### Requirement: Frame composes a buffer and its size

The system SHALL provide `Frame` as a box struct containing the terminal `size : Rect`, the working `buffer : Buffer`, and an optional `cursor : Option (I64, I64)` field carrying the screen-coordinate `(col, row)` at which the terminal's hardware cursor should be placed after the frame is rendered. The cursor field defaults to `Option::none` for newly constructed frames; widgets that own a focused caret SHALL publish their position via `Frame::set_cursor : I64 -> I64 -> Frame -> Frame`. `Frame::render_*` functions SHALL be the public surface for drawing a widget into the frame's buffer at a given `Rect`. The run loop (see `tui-event-loop`) consumes `@cursor` after diffing.

#### Scenario: render_text writes a styled string at a Rect's origin

- **WHEN** a caller invokes `frame.render_text("hi", style, Rect::make(0, 0, 10, 1))`
- **THEN** the returned frame's buffer has cells (0,0)="h" and (1,0)="i" with `@style = style`

#### Scenario: render_text clips to its Rect

- **WHEN** a caller invokes `frame.render_text("Hello, World!", style, Rect::make(0, 0, 5, 1))`
- **THEN** only "Hello" is written to the buffer and remaining text is dropped

#### Scenario: A new Frame has no cursor published

- **WHEN** a caller invokes `Frame::new(Rect::make(0, 0, 80, 24))`
- **THEN** the returned frame has `@cursor = Option::none`

#### Scenario: set_cursor records the (col, row) on the frame

- **WHEN** a caller invokes `frame.set_cursor(5, 2)`
- **THEN** the returned frame has `@cursor = Option::some((5, 2))` and the buffer and size are unchanged

#### Scenario: Multiple set_cursor calls keep the last one (last writer wins)

- **WHEN** a caller chains `frame.set_cursor(3, 1).set_cursor(7, 4)`
- **THEN** the returned frame has `@cursor = Option::some((7, 4))`
