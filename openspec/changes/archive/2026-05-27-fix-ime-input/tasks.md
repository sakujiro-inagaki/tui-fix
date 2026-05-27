## 1. Frame cursor field (foundational, no behavior change)

- [x] 1.1 Add `cursor : Option (I64, I64)` field to the `Frame` struct in [src/Yaynu/Tui/Frame.fix](src/Yaynu/Tui/Frame.fix) and initialize to `Option::none` in `Frame::new`.
- [x] 1.2 Add `Frame::set_cursor : I64 -> I64 -> Frame -> Frame` helper that sets the field via `set_cursor` (last writer wins).
- [x] 1.3 Add a unit test in `tests/FrameTest.fix` verifying `Frame::new` has `@cursor = none`, `set_cursor(5, 2)` round-trips, and chained calls keep the last value.
- [x] 1.4 Run `fix test` and confirm all existing tests still pass.

## 2. Multi-key drain in the run loop

- [x] 2.1 In [src/Yaynu/Tui.fix](src/Yaynu/Tui.fix), add a pure helper `_drain_keys : Array U8 -> Array Key` that repeatedly calls `Yaynu.Term.Key::parse`, advances by the consumed prefix on `complete`, drops `n` bytes on `invalid(n)`, and stops on `incomplete` (discarding the tail). A bare ESC tail SHALL still yield `Key::escape` if no follow-up bytes are present (mirror the current single-event behavior).
- [x] 2.2 Add unit tests in `tests/EventTest.fix` (create the file if missing and register it in `fixproj.toml` under `[build.test].files`):
  - [x] 2.2.1 ASCII bytes `"abc"` → three `Key::char` keys.
  - [x] 2.2.2 UTF-8 bytes for `"こんにちは"` → five `Key::char` keys with the correct strings.
  - [x] 2.2.3 Mixed bytes (ASCII + multi-byte UTF-8 + Ctrl + arrow CSI) parse to the right sequence in order.
  - [x] 2.2.4 Bytes that end mid-UTF-8 (e.g. `"あ"` + `0xE3`) → one `Key::char("あ")` and the tail is dropped.
- [x] 2.3 Rename `_read_key_event : U8 -> IOFail Event` to `_read_key_events : U8 -> IOFail (Array Event)`; have it build the byte buffer as today and return `_drain_keys(bytes).map(Event::key)`. Keep the bare-ESC fallback when the drain returns empty.
- [x] 2.4 Update `_loop` to iterate the returned events through `update`, exiting immediately on the first `quit`. Keep the existing Ctrl+C force-quit check applied per event.
- [ ] 2.5 Run `examples/input_demo` manually with rapid ASCII typing and confirm no regression.

## 3. Apply Frame cursor in the run loop

- [x] 3.1 Remove the unconditional startup `Yaynu.Term.Output::write(Yaynu.Term.Ansi::hide_cursor)` at [src/Yaynu/Tui.fix:63](src/Yaynu/Tui.fix#L63).
- [x] 3.2 After the diff write in `_loop`, branch on `frame.@cursor`:
  - `some((c, r))` → write `Yaynu.Term.Ansi::move_to(r + 1, c + 1) + Yaynu.Term.Ansi::show_cursor` as one `Output::write` call.
  - `none()` → write `Yaynu.Term.Ansi::hide_cursor`.
- [x] 3.3 Keep the teardown `show_cursor` write so the user's terminal cursor is restored on exit.
- [x] 3.4 Confirm no test compiles against the old startup sequence (search `hide_cursor` in `tests/`).

## 4. Input widget publishes the cursor

- [x] 4.1 In [src/Yaynu/Tui/Widget/Input.fix](src/Yaynu/Tui/Widget/Input.fix), have `_render_single` call `Frame::set_cursor(rect.@x + cx, rect.@y)` after the existing reverse-video cell write, only when `cx < rect.@width` (matches the existing guard for drawing the cursor cell).
- [x] 4.2 Have `_render_multi` do the same with `Frame::set_cursor(rect.@x + cx, rect.@y + cy)` under the existing in-bounds guard.
- [x] 4.3 Decide on focused-vs-unfocused convention: skip `set_cursor` when `inp.@cursor_style == Style::default` (the existing `input_demo` convention for the unfocused input). Add a small helper or inline equality check; document the decision in the function header comment.
- [x] 4.4 Extend `tests/InputTest.fix` with two scenarios:
  - [x] 4.4.1 After `render_input` of an ASCII input with cursor at column 2 in a rect at `(4, 1)`, the resulting `Frame::@cursor` is `Option::some((6, 1))`.
  - [x] 4.4.2 After `render_input` of `"あい"` with cursor at byte 6 in a rect at `(0, 0)`, `Frame::@cursor` is `Option::some((4, 0))`.
  - [x] 4.4.3 An input rendered with `cursor_style = Style::default` does NOT set the frame cursor.
- [x] 4.5 Add a test confirming an IME-style commit applied via `Input::handle_key(Key::char("こんにちは"), input)` produces `@text = "こんにちは"` and `@cursor = 15`.

## 5. Manual verification

- [x] 5.1 Build with `fix build`; ensure no warnings introduced by the new field. (Verified via `fix check` — the project is a library so `fix build` requires `Main::main`; check covers the same type-correctness scope.)
- [ ] 5.2 Run `examples/input_demo` in a terminal with an active Japanese IME (macOS native, ibus, or Windows Terminal with Microsoft IME). Verify:
  - Pre-edit characters appear at the input's cursor column, not 1–2 cells right.
  - Confirming the IME inserts the *entire* committed string at the cursor position.
  - The terminal's hardware cursor is visible at the focused input and disappears (or moves) when focus changes.
- [ ] 5.3 Run `examples/list_demo`, `examples/spinner_demo`, `examples/tabs_demo`, `examples/layout_demo`, `examples/hello_tui` to confirm no regression in non-Input contexts (the cursor should be hidden as before since no widget publishes a position).
- [x] 5.4 Run `fix test` and confirm all tests pass green.

## 6. Documentation

- [x] 6.1 Update [README.md](README.md) "Input widget" section (if it exists) to mention IME support; otherwise add a brief note.
- [x] 6.2 Update the doc comments at the top of [src/Yaynu/Tui/Widget/Input.fix](src/Yaynu/Tui/Widget/Input.fix) noting that `render_input` publishes a frame cursor and the run loop honours it.
- [x] 6.3 Update the doc comment in [src/Yaynu/Tui/Frame.fix](src/Yaynu/Tui/Frame.fix) describing the new `cursor` field and its consumer.
