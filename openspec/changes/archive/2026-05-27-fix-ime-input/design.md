## Context

Two defects in the v0.1 input pipeline make `Input` unusable with any IME-driven script (Japanese, Chinese, Korean):

1. **Lost commit bytes.** [src/Yaynu/Tui.fix:151-172](src/Yaynu/Tui.fix#L151-L172) drains all available stdin bytes into one buffer, calls `Yaynu.Term.Key::parse` exactly once, and discards everything past the first parsed key. An IME committing `こんにちは` delivers a single ~15-byte burst; the loop emits `Event::key(char("こ"))` and throws the rest away.
2. **Mispositioned IME pre-edit.** The run loop hides the hardware cursor on startup ([src/Yaynu/Tui.fix:63](src/Yaynu/Tui.fix#L63)) and never moves it. Terminals draw the IME's pre-edit string at the current cursor cell, which — after diff-rendering — sits wherever the last `set_cell` ANSI write left it. With `_render_single` painting the cursor block *last* at column `cx`, the hardware cursor ends up at `cx + width(cursor_cell)` — one or two cells to the right of the logical cursor. The pre-edit text appears there and over-paints the existing body characters because the IME does not move surrounding text aside in a hidden-cursor / no-OSC scenario; it simply writes into the row from where the cursor currently is.

The grapheme-cluster width logic is already correct: `_insert_string` accepts an arbitrary-length string and computes the new cursor offset from `s_bs.get_size`. `Width::string_width` and `_cluster_at_col` already handle wide characters. The bugs are entirely upstream of the widget.

Constraints:
- Must not regress existing examples (`hello_tui`, `input_demo`, `list_demo`, etc.).
- The `term` library is a separate package; this change should avoid touching it. All needed primitives (`Ansi::move_to row col`, `Ansi::show_cursor`, `Ansi::hide_cursor`) already exist in [term_0.1.0/src/Yaynu/Term/Ansi.fix](.fixlang/deps/term_0.1.0/src/Yaynu/Term/Ansi.fix).
- `Frame` is exposed in the public API (apps construct `view` against it), so additions must be backward-compatible.

## Goals / Non-Goals

**Goals:**
- Deliver every key parsed from a single stdin read to `update`, in order, before the next render.
- Place the terminal's hardware cursor at the active input's logical cell so IME pre-edit appears at the right column and behaves like a normal terminal: the pre-edit text is drawn by the terminal, not by us, and the diff renderer's redraw of the next frame naturally overwrites whatever the terminal painted during composition.
- Keep `Input::handle_key` semantics unchanged at the widget API level — multi-character `char(s)` already works.

**Non-Goals:**
- Implement an in-process IME, kana/romaji conversion, or candidate UI. The OS IME (macOS, ibus, fcitx, Windows IME) remains responsible for composition.
- Add bracketed-paste mode toggling. The "drain into N events" change makes the loop tolerate paste bursts as a side effect; an explicit `Event::paste` variant is deferred.
- Add cursor-shape control (block / bar / underline). The cursor is shown with the terminal's default shape.
- Multi-focus / multi-input cursor arbitration. Apps with several inputs decide which one publishes the cursor by ordering their `render_input` calls; the last writer wins. This matches how widgets already compose on `Frame`.

## Decisions

### Decision 1: Drain by repeated `parse`, not single-shot

After the run loop reads a byte and drains the rest non-blocking, it loops over the resulting buffer calling `Yaynu.Term.Key::parse` and advances by the consumed prefix length on each `complete`, until the buffer is empty, `incomplete`, or `invalid`.

- `complete((k, n))`: append `Event::key(k)` to a list, drop `n` bytes from the front, continue.
- `incomplete()`: the tail is a partial UTF-8 / partial CSI sequence. Stop and **discard** the tail. (Rationale: the next read will not concatenate with this tail — the bytes already left the OS buffer. v0.1 keeps it simple; a future change can introduce a parser-state carry between reads.)
- `invalid(n)`: drop `n` bytes and continue. Matches existing single-key behavior where `invalid` surfaces as `Key::unknown` and is then ignored by widgets.

A new helper `_drain_keys : Array U8 -> Array Key` performs the loop and is unit-testable without touching `IO`.

**Alternatives considered:**
- *Concatenate consecutive `char` keys into one `char(s)` and emit one event.* Rejected: it conflates IME commits with rapid ASCII typing, which other event handlers (e.g., a key-by-key vim-mode parser) may want to see distinctly. Sending multiple events is the more general primitive.
- *Carry parser state (the `incomplete` tail) into the next read.* Rejected for v0.1 because incomplete reads are pathological (single keystroke split across two `read` syscalls) and would require restructuring `_loop` to thread parser state. Worth revisiting if anyone reports a real-world incident.

### Decision 2: Multiple events per frame — process before re-render

`_loop` currently does `render → wait → read 1 event → update → loop`. After draining, we now have a list of events. The render cycle becomes:

```
render → wait → read+drain → for ev in events: update(ev) → loop
```

If any event yields `quit`, the loop exits immediately; remaining events are dropped (matches existing semantics for Ctrl+C). Resize detection still runs once per iteration (after the batch is processed), because rendering happens before the wait, not between individual events.

**Alternatives considered:**
- *Render between every event.* Rejected: an IME commit of 5 chars would cause 5 renders, all to a frame that is identical except for one extra character — the diff would still show them all to the user as a single "paint" because we don't `usleep`, but it triples the CPU cost for no benefit.

### Decision 3: `Frame::cursor : Option (I64, I64)` set by widgets, applied by run loop

`Frame` gains:

```fix
type Frame = box struct {
    size   : Rect,
    buffer : Buffer,
    cursor : Option (I64, I64)   // (col, row) in screen coordinates
};
```

A new helper `Frame::set_cursor : I64 -> I64 -> Frame -> Frame` sets the field. Default `Option::none` (matches today: no explicit cursor).

`_render_single` and `_render_multi` in `Input.fix` call `set_cursor(rect.@x + cx, rect.@y + cy)` *in addition to* the existing reverse-video block. Both stay: the block gives the cursor block its visible "I am here" feedback even on terminals that draw a thin caret; the real cursor positions IME and provides accessibility/screen-reader feedback.

After diff-writing, the run loop:

```
if frame.@cursor is some (c, r):
    write(move_to(r + 1, c + 1))   # term uses 1-based row/col
    write(show_cursor)
else:
    write(hide_cursor)
```

The startup `hide_cursor` write is removed (the loop now decides per-frame). The teardown `show_cursor` remains.

**Alternatives considered:**
- *Track cursor on `Input` and have the app explicitly call `frame.set_cursor(input.cursor_pos)`.* Rejected: error-prone (every app would need to opt in), and the widget already knows its own column. Putting the responsibility on the widget keeps the API one call.
- *Make `Input` a hidden-cursor widget and draw all IME pre-edit ourselves.* Rejected: requires implementing IME communication protocols (OSC 17x?, MacOS-specific control bytes, ibus-specific signals…) that terminals do not expose to applications. Letting the terminal handle composition is the only practical path.

### Decision 4: Update `_read_key_event` signature → `_read_key_events`

The function returns `IOFail (Array Event)` (or `Array Key` lifted). `_loop`'s `byte_opt` branch then iterates the returned events through `update`. The old single-event signature is internal so this is not a breaking API change.

## Risks / Trade-offs

- **Risk:** Some terminals do not place IME pre-edit at the hardware cursor (e.g., they pop a candidate window detached from the cell grid). → Mitigation: Even in those terminals, positioning the cursor correctly is still right for accessibility and for terminals that *do* inline pre-edit (most modern xterm-likes on macOS, Linux, Windows Terminal). Visual regression is bounded to "blinking cursor now visible where it previously was hidden" — acceptable and arguably an improvement.
- **Risk:** A pathological app calls `render_input` multiple times per frame for different inputs (focus-following composer) and expects only the focused one to publish the cursor. → Mitigation: documented as "last writer wins"; the `input_demo` already nulls the unfocused input's `cursor_style`, and the same code path can now skip `set_cursor` when unfocused (a small follow-up tweak to the example; the library API doesn't change).
- **Risk:** The `incomplete` tail discard loses one rare keystroke when stdin returns mid-UTF-8. → Mitigation: extremely rare in practice (raw terminal reads are line-buffered at the kernel layer for keypresses); documented in the spec as a known v0.1 limitation; carry-state fix is a localized future change.
- **Risk:** Showing the cursor where it was hidden before may break visual snapshot tests. → Mitigation: existing tests render into `Buffer` and compare cells; the hardware cursor is an ANSI-stream side effect not visible to `Buffer` tests. No test regression expected. Manual verification via `examples/input_demo` is part of the task list.
- **Trade-off:** Rendering once before processing N events means the user sees a single combined paint after IME commit instead of character-by-character animation. This is the standard TUI behavior (`ratatui`, `bubbletea`) and matches user expectation.

## Migration Plan

1. Land `Frame.cursor` field + `Frame::set_cursor` helper.
2. Land `_drain_keys` helper + flip `_read_key_event` to `_read_key_events`; loop iterates events.
3. Land run-loop cursor placement after diff write; remove startup `hide_cursor` (keep teardown).
4. Wire `Input::_render_single` and `_render_multi` to call `set_cursor`.
5. Add tests for: (a) commit-style multi-char drain → multiple `Event::key`; (b) `Frame::set_cursor` field round-trips; (c) Input widget publishes correct `(col, row)` for ASCII and wide characters.
6. Run all examples manually, verify Japanese IME on `input_demo`.

No rollback hazard — purely additive to public API; if a downstream relies on the old single-event-per-tick behavior, they can read multiple keys from a single physical key press (e.g., paste); that downstream was already incorrect on paste.

## Open Questions

- Should the `Event` type gain a `paste : String` variant in a follow-up so apps can distinguish "user pasted 50 chars" from "user typed 50 chars"? Out of scope for this change, but worth flagging.
- Should the hardware cursor be hidden when no widget publishes one, or shown at `(0, 0)` for accessibility? Current decision: hidden, matching v0.1 behavior. Open to revision.
