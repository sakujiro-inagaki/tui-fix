## Why

Typing Japanese (and any other IME-driven script — Chinese, Korean, etc.) into an `Input` widget produces two visible bugs that make the widget unusable for non-ASCII users:

1. **Pre-edit text appears in the wrong place and overwrites existing content.** With the hardware cursor hidden and never repositioned, the terminal places the IME's pre-edit (uncommitted candidate) string at whichever cell the diff renderer happened to write last — typically one or two columns to the right of the input's logical cursor — and the pre-edit characters paint *over* the body text instead of pushing it aside.
2. **Only the first character of a committed string survives.** When the IME commits a multi-character string like `こんにちは`, the OS delivers ~15 bytes in a single read. `_read_key_event` calls `Yaynu.Term.Key::parse` once, takes the first parsed `char` key (3 bytes for one Japanese character), and silently discards the remaining 12 bytes. The Input widget only sees the first character.

Both bugs were latent in v0.1 because every test and example uses ASCII keystrokes that arrive one byte at a time. The grapheme-cluster width logic is already correct; the input pipeline simply never exercises it.

## What Changes

- The run loop SHALL parse the *entire* drained byte buffer into a sequence of `Key` events and deliver each in order, instead of taking only the first parsed key. This makes IME-committed strings, fast typing, and bracketed-paste-like bursts all reach `update` intact.
- The `Frame` type SHALL gain an optional logical-cursor field (`(col, row)`) that widgets like `Input` set during render. The run loop SHALL, after writing the frame's diff, position the terminal's hardware cursor to that location and show it (when set), and hide it otherwise.
- `Input::render_input` SHALL set the frame's cursor position to its logical cursor cell instead of (only) painting a reverse-video block. The reverse-video block is retained for visual clarity in non-IME contexts but is now redundant with the real cursor; both can coexist.
- The `tui-event-loop` and `tui-widgets` specs SHALL gain requirements covering IME commits and cursor positioning. The `tui-rendering` spec SHALL gain a requirement on the `Frame` cursor field.

## Capabilities

### New Capabilities

None — this change extends existing capabilities only.

### Modified Capabilities

- `tui-event-loop`: The run loop's "read" step must drain into multiple events, not one. Adds a requirement on IME-style multi-key bursts and on positioning the terminal cursor after each render.
- `tui-widgets`: The `Input` widget render contract gains an obligation to publish its logical cursor position to the frame so the terminal cursor lands on it (required for IME pre-edit to display at the correct column).
- `tui-rendering`: `Frame` gains an optional cursor position that the run loop consumes after diffing.

## Impact

- **Code**: [src/Yaynu/Tui.fix](src/Yaynu/Tui.fix) (run loop, `_read_key_event` → multi-event drain, post-diff cursor placement), [src/Yaynu/Tui/Frame.fix](src/Yaynu/Tui/Frame.fix) (add cursor field + setter), [src/Yaynu/Tui/Widget/Input.fix](src/Yaynu/Tui/Widget/Input.fix) (publish cursor to frame).
- **Tests**: Add `tests/InputTest.fix` and `tests/EventTest.fix` (or equivalent) cases for IME-committed multi-character `char` parsing and for frame cursor placement.
- **APIs**: `Frame` gains a new field and a `set_cursor` helper — additive, non-breaking. The `Event` enum is unchanged; the loop simply may now emit several `Event::key` events between renders.
- **Behavior change**: The terminal's hardware cursor is now visible at the active input's position (previously hidden for the whole session). Applications that explicitly relied on the cursor being hidden everywhere can opt out by not calling `Frame::set_cursor`.
- **Dependencies**: No new dependencies. Uses existing `Yaynu.Term.Ansi::show_cursor` / `hide_cursor` / `move_to` (verify the latter exists in `term`; if not, this change SHALL add a thin wrapper around the `CSI <r>;<c> H` escape locally without touching `term`).
- **Non-goals**: This change does NOT add an in-process IME (the OS / terminal IME is responsible for composition). It does NOT introduce bracketed-paste mode toggling; multi-byte drains are handled uniformly whether they come from IME commits, paste, or rapid typing.
