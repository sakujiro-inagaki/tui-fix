# tui-event-loop Specification

## Purpose

Defines the event-driven application contract for the TUI library: the `Event` type that enumerates inputs (keys, resize, tick, custom), the `TuiApp` trait that user applications implement, and the `Yaynu.Tui::run` driver that owns raw mode, the render/wait/read/update cycle, and terminal restoration on exit.

## Requirements

### Requirement: Event type enumerates inputs to the application

The system SHALL provide `Event` as a box union with constructors `key : Key` (where `Key` is the type exported by `term`), `resize : (I64, I64)` carrying the new `(rows, cols)`, `tick : ()` for timed wake-ups, and `custom : String` for application-defined notifications.

#### Scenario: Event values are constructible and pattern-matchable

- **WHEN** a caller constructs `Event::key(Key::escape)`, `Event::resize((24, 80))`, `Event::tick(())`, `Event::custom("done")`
- **THEN** all values type-check and pattern-match against the corresponding constructor

### Requirement: TuiApp trait defines the application contract

The system SHALL provide a trait `TuiApp` with the following methods that an application state type SHALL implement: `initial : s` (the starting state), `view : s -> Frame -> Frame` (render the state into the supplied frame), `update : Event -> s -> UpdateResult s` (consume an event and return either a continuation or a quit), and `tick_rate : s -> Option I64` (the tick interval in milliseconds, or `Option::none` to disable ticks for the current state). `UpdateResult s` SHALL be a box union with constructors `continue : s` and `quit : ()`.

#### Scenario: An app with no tick rate never receives Event::tick

- **WHEN** an app's `tick_rate` returns `Option::none` for all states and the user does not press a key
- **THEN** `update` is never invoked with `Event::tick`

#### Scenario: Quit terminates the loop

- **WHEN** `update` returns `UpdateResult::quit(())` for any event
- **THEN** `Yaynu.Tui::run` exits raw mode and returns success

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

### Requirement: Bare ESC is synthesised only for a single-byte ESC buffer

When the run loop drains stdin and `_drain_keys` produces zero `Key` values, the loop SHALL synthesise a single `Event::key(Key::escape)` **only if** the drained byte buffer has length exactly 1 and that byte equals `0x1B`. For any other drained buffer that produced zero keys — including a buffer that starts with `0x1B` but contains additional bytes (e.g. unknown CSI sequences such as `ESC[Z`, `ESC[1;3A`, vendor-specific extensions) — the loop SHALL emit no event for that drain.

This requirement complements the existing Read step (in "run drives the application end-to-end"): `invalid(n)` and `incomplete` continue to drop bytes as previously specified; this requirement nails down the bare-ESC fallback that previously synthesised `Key::escape` for any non-empty ESC-prefixed buffer.

#### Scenario: Lone ESC keypress still produces Key::escape

- **GIVEN** the run loop wakes up on a key-byte arrival and the only available byte is `0x1B` (the user pressed Esc and nothing followed within the drain window)
- **WHEN** `_read_key_events` drains stdin and runs the parser
- **THEN** exactly one `Event::key(Key::escape)` is emitted

#### Scenario: Unknown CSI sequence consumed by invalid produces no event

- **GIVEN** the run loop wakes up on a key-byte arrival and stdin yields the byte sequence `0x1B 0x5B 0x5A` (the `ESC[Z` Shift+Tab encoding) which `Yaynu.Term.Key::parse` reports as `invalid(3)`
- **WHEN** `_read_key_events` drains stdin and runs the parser
- **THEN** no events are emitted for that drain; in particular no `Event::key(Key::escape)` is produced

#### Scenario: Unknown multi-byte CSI starting with ESC produces no event

- **GIVEN** the run loop wakes up on a key-byte arrival and stdin yields the byte sequence `0x1B 0x5B 0x31 0x3B 0x33 0x41` (an `ESC[1;3A` Alt+Shift+Up encoding the parser does not recognise and ends up dropping)
- **WHEN** `_read_key_events` drains stdin and runs the parser
- **THEN** no events are emitted for that drain; in particular no `Event::key(Key::escape)` is produced

#### Scenario: ESC followed by an unrelated complete key emits only the complete key

- **GIVEN** the run loop wakes up on a key-byte arrival and stdin yields a buffer whose first byte is `0x1B` but whose remainder parses as one complete key `K` (and the leading `0x1B` is consumed by an `invalid` step or by the recognised key itself)
- **WHEN** `_read_key_events` drains stdin and runs the parser
- **THEN** exactly one `Event::key(K)` is emitted; no spurious `Event::key(Key::escape)` is prepended or appended

### Requirement: Custom events can be injected from the update function

The system SHALL allow an application to schedule a `custom` event for delivery on the next loop iteration by returning a state from `update` that the application itself recognises as "fire custom on next tick", then producing the custom payload during the next `Event::tick` handler. v0.1 SHALL NOT expose a cross-thread injection handle; external injection from a separate execution context is explicitly out of scope.

#### Scenario: Application can simulate a custom event via its own state machine

- **GIVEN** an app whose `update` on `Event::tick` checks a state flag and, if set, recursively dispatches a `Event::custom("ready")` to itself before returning
- **WHEN** the flag is raised during a key handler and the next tick fires
- **THEN** the app observes the custom event and behaves accordingly

#### Scenario: No public cross-thread injection API exists in v0.1

- **WHEN** an integrator looks for a `run_with_handle` style API
- **THEN** none is exposed; the integrator must use the tick-based polling pattern
