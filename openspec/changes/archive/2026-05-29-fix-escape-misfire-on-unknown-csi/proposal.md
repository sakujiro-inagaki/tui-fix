## Why

A user reported that pressing keys such as Shift+Tab (`ESC[Z`) or Alt+Shift+Up (`ESC[1;3A`) — sequences the CSI sub-parser currently treats as `invalid(n)` and drops — causes `Yaynu.Tui::run` to emit a spurious `Event::key(Key::escape)`. The bare-ESC fallback in `_read_key_events` only checks that the drained byte buffer is non-empty and starts with `0x1B`, which is true of every unknown ESC-prefixed sequence as well as a genuine lone Esc press. As a result, apps that quit on Esc spuriously quit when the user hits Shift+Tab, and apps that treat Esc as "cancel" see false cancellations.

## What Changes

- Tighten the bare-ESC fallback in [src/Yaynu/Tui.fix](src/Yaynu/Tui.fix) so that a synthetic `Key::escape` is produced only when the drained buffer is **exactly one byte** equal to `0x1B`. Unknown CSI sequences continue to be dropped silently, as `invalid(n)` already specifies.
- Update the `tui-event-loop` spec's "Read" requirement to state the bare-ESC rule explicitly and add scenarios covering (a) lone Esc still produces `Key::escape` and (b) an unknown CSI sequence consumed entirely by `invalid(n)` produces no event.

## Capabilities

### Modified Capabilities
- `tui-event-loop`: the Read step's handling of dropped/invalid ESC-prefixed sequences is tightened so that only a truly bare ESC (single-byte buffer) synthesises `Key::escape`.

## Impact

- Code: [src/Yaynu/Tui.fix](src/Yaynu/Tui.fix), `_read_key_events` (around line 242).
- Behavioural: previously, any unknown ESC-prefixed sequence that the CSI parser fully dropped via `invalid(n)` would fire a `Key::escape`; after this change, no event is emitted in that case. Apps that relied on the buggy behaviour (treating Shift+Tab as Esc) will break — this is the intended correction.
- No API, type, or trait changes. No dependency changes.
- Tests: add a test under [tests/](tests/) that feeds an unknown CSI byte sequence into `_read_key_events` (or `_drain_keys` + the fallback logic) and asserts no `Key::escape` is produced, plus a regression test that a single `0x1B` byte still yields `Key::escape`.
