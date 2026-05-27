## MODIFIED Requirements

### Requirement: run drives the application end-to-end

The system SHALL provide `Yaynu.Tui::run : [s : TuiApp] s -> IOFail ()` that performs the following protocol:

1. Enter `term` raw mode and switch to the alternate screen buffer. If this fails, return the failure without attempting any further setup.
2. Initialize the previous-frame buffer to a fully-cleared buffer of the current terminal size.
3. Loop with the current state `s` (starting from the argument):
   a. Render: build a fresh `Frame` of the current terminal size, run `view(s, frame)`, diff the resulting buffer against the previous-frame buffer, write the diff ANSI to the terminal in one write, and store the new buffer as previous. After the diff write, if the frame published a cursor position (see the `tui-rendering` spec) the loop SHALL write a single `move_to` plus `show_cursor` escape that places the terminal's hardware cursor at that `(col, row)`; otherwise the loop SHALL write `hide_cursor`. The previous behavior of writing an unconditional `hide_cursor` once at startup SHALL be removed.
   b. Wait: compute `timeout = tick_rate(s) - elapsed_since_last_tick` (clamped to `>= 0`); if `tick_rate` is `Option::none`, wait without timeout.
   c. Read: call `term`'s timed event read. On a key-byte arrival, the loop SHALL drain all currently available bytes (non-blocking) into a single buffer and parse it into a *sequence* of `Key` values by repeatedly applying `Yaynu.Term.Key::parse` and advancing past the consumed prefix; a trailing `incomplete` tail SHALL be discarded for v0.1 (documented limitation); `invalid(n)` SHALL drop those bytes and continue. The drained sequence is delivered as one `Event::key` per parsed key, in arrival order. A timeout-only result still produces a single `Event::tick`; a resize is still a single `Event::resize`.
   d. Update: for each event in arrival order, call `update(event, s)`; if any returns `quit`, break the loop immediately (later events in the batch are dropped); otherwise replace `s` with the new state and continue with the next event in the batch. After the batch is exhausted, return to step 3a.
4. On loop exit (whether normal or due to an exception escaping `view` / `update`), restore the main screen buffer, leave raw mode, write `show_cursor` to restore the user's terminal, and return success.

The run loop MUST NOT block on any I/O other than the timed event read; in particular, `view` and `update` MUST be allowed to assume they are the only writers of the terminal during their execution.

#### Scenario: Hello loop quits on Esc

- **GIVEN** a `TuiApp` whose `view` writes "hi" and whose `update` returns `quit` on `Event::key(Key::escape)` and `continue` otherwise
- **WHEN** `Yaynu.Tui::run` is invoked and the user presses Esc
- **THEN** the terminal returns to the main screen buffer with raw mode disabled and `run` returns `Result::ok(())`

#### Scenario: Tick fires at the requested cadence

- **GIVEN** an app whose `tick_rate` returns `Option::some(100)` and whose `update` increments a counter on `Event::tick`
- **WHEN** `run` executes for approximately one second without any key input
- **THEN** the counter has been incremented roughly 10 times (within timing tolerance)

#### Scenario: Resize event delivers the new dimensions

- **GIVEN** an app whose `update` records the most recent `Event::resize` payload
- **WHEN** the terminal is resized to 30 rows × 100 columns during the loop
- **THEN** the next render uses a frame of that size and `update` has observed `Event::resize((30, 100))`

#### Scenario: Raw mode is restored even when view raises

- **GIVEN** an app whose `view` raises an exception after the first render
- **WHEN** `run` is invoked
- **THEN** the terminal is restored to the main screen buffer with raw mode disabled before the failure is propagated to the caller

#### Scenario: IME commit of multiple characters delivers one event per character

- **GIVEN** a single-line `Input` widget at cursor position 0 and an OS IME that commits the string `こんにちは` (5 Japanese characters, 15 UTF-8 bytes) as one stdin burst
- **WHEN** the run loop drains stdin after the first byte arrival
- **THEN** the loop emits exactly five `Event::key(Key::char("こ"))`, `Event::key(Key::char("ん"))`, `Event::key(Key::char("に"))`, `Event::key(Key::char("ち"))`, `Event::key(Key::char("は"))` in order, each is fed to `update` before the next render, and the input's `text` becomes `"こんにちは"` with `cursor = 15`

#### Scenario: Quit mid-batch drops the remaining events in the same batch

- **GIVEN** an app whose `update` returns `quit` on the first `Event::key` it receives
- **WHEN** an IME burst delivers three keys in one read
- **THEN** only the first key is dispatched to `update`; the loop exits without processing the other two; the terminal is restored cleanly

#### Scenario: Incomplete trailing UTF-8 in a drain is discarded

- **GIVEN** a stdin read whose bytes parse as one complete `Key::char("あ")` followed by a leading UTF-8 byte with no continuation bytes available
- **WHEN** the run loop drains and parses
- **THEN** exactly one `Event::key(Key::char("あ"))` is emitted; the trailing leader byte is dropped; the loop continues without raising

#### Scenario: Hardware cursor follows the focused input

- **GIVEN** a frame whose `view` calls `frame.render_input(inp, rect)` for an input at cursor column 4 inside a rect at `(x, y) = (2, 1)`
- **WHEN** the run loop renders that frame
- **THEN** after the diff write the loop writes `move_to(2, 7)` (1-based row 2, 1-based col 7 = x + cx + 1) followed by `show_cursor`, so subsequent IME pre-edit text appears at that cell

#### Scenario: Hardware cursor hidden when no widget publishes a cursor

- **GIVEN** a frame whose `view` only calls `frame.render_text` and `frame.render_paragraph`
- **WHEN** the run loop renders that frame
- **THEN** after the diff write the loop writes `hide_cursor` and no `move_to`
