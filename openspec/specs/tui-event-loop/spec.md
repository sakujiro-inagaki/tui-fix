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
   a. Render: build a fresh `Frame` of the current terminal size, run `view(s, frame)`, diff the resulting buffer against the previous-frame buffer, write the diff ANSI to the terminal in one write, and store the new buffer as previous.
   b. Wait: compute `timeout = tick_rate(s) - elapsed_since_last_tick` (clamped to `>= 0`); if `tick_rate` is `Option::none`, wait without timeout.
   c. Read: call `term`'s timed event read; map a key to `Event::key`, a resize to `Event::resize`, and a timeout to `Event::tick(())`.
   d. Update: call `update(event, s)`; if `quit`, break the loop; otherwise replace `s` with the new state.
4. On loop exit (whether normal or due to an exception escaping `view` / `update`), restore the main screen buffer, leave raw mode, and return success.

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

### Requirement: Custom events can be injected from the update function

The system SHALL allow an application to schedule a `custom` event for delivery on the next loop iteration by returning a state from `update` that the application itself recognises as "fire custom on next tick", then producing the custom payload during the next `Event::tick` handler. v0.1 SHALL NOT expose a cross-thread injection handle; external injection from a separate execution context is explicitly out of scope.

#### Scenario: Application can simulate a custom event via its own state machine

- **GIVEN** an app whose `update` on `Event::tick` checks a state flag and, if set, recursively dispatches a `Event::custom("ready")` to itself before returning
- **WHEN** the flag is raised during a key handler and the next tick fires
- **THEN** the app observes the custom event and behaves accordingly

#### Scenario: No public cross-thread injection API exists in v0.1

- **WHEN** an integrator looks for a `run_with_handle` style API
- **THEN** none is exposed; the integrator must use the tick-based polling pattern
