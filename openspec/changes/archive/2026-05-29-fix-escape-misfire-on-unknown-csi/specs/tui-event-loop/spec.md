## ADDED Requirements

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
