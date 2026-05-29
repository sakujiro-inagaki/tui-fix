## 1. Confirm the parser-level invariant

- [x] 1.1 Open a Fix REPL or write a throwaway script that calls `Yaynu.Term.Key::parse` on `[27_U8, 91_U8, 90_U8]` (ESC[Z) and on `[27_U8, 91_U8, 49_U8, 59_U8, 51_U8, 65_U8]` (ESC[1;3A); confirm both return `invalid(n)` (not `complete` or `incomplete`). This is the precondition the fix relies on — if `parse` returns `complete` for either, the user's bug is already fixed upstream and this change is unnecessary.
  - Note: the working tree bumps `term` from 0.1.0 → 0.2.0 (uncommitted change in [fixproj.toml](fixproj.toml)). Under term 0.2.0, `ESC[Z` is now `complete((Key::back_tab, 3))` — so the user's specific Shift+Tab regression is fixed upstream and the bare-ESC fallback no longer triggers for that buffer. **However**, `ESC[1;3A` is still `invalid(6)` (modified-arrow forms remain unrecognised), and the same misfire still occurs for every other unknown CSI sequence the parser drops via `invalid(n)`. The `_finalize_keys` tightening below is therefore still required to fully close the regression class.

## 2. Implement the fix

- [x] 2.1 In [src/Yaynu/Tui.fix](src/Yaynu/Tui.fix), introduce a pure helper `_finalize_keys : Array U8 -> Array Yaynu.Term.Key::Key -> Array Yaynu.Term.Key::Key` just below `_drain_keys` (around line 227). Body:
  ```fix
  if keys.get_size == 0 && bytes.get_size == 1 && bytes.@(0) == 27_U8 {
      [Yaynu.Term.Key::Key::escape()]
  } else {
      keys
  }
  ```
- [x] 2.2 In `_read_key_events` (around line 241–247), replace the inline `let keys = if … { … } else { keys };` block with `let keys = _finalize_keys(bytes, _drain_keys(bytes));`. Keep the subsequent `pure $ keys.to_iter.map(|k| Event::key(k)).to_array` line untouched.
- [x] 2.3 Update the prose comment block above `_read_key_events` (lines 229–234) to state the new condition: synthesis fires only on a single-byte ESC buffer; unknown CSI sequences that the parser drops via `invalid(n)` produce no event. Also update the "Bare-ESC fallback" paragraph in the `_drain_keys` comment (lines 202–207) to reference `_finalize_keys` by name.

## 3. Tests

- [x] 3.1 In [tests/EventTest.fix](tests/EventTest.fix), import `_finalize_keys` (it lives in the same `Yaynu.Tui` module and is already reachable via the underscore-prefixed convention used for `_drain_keys`).
- [x] 3.2 Add an assertion that `_drain_keys([27_U8, 91_U8, 90_U8])` (ESC[Z) returns an empty array. Label it "ESC[Z drains to no keys".
  - Adapted to term 0.2.0: asserts `_drain_keys([27, 91, 90])` returns one key whose `is_back_tab` is `true`. Under term 0.1.0 the assertion would have been "empty array"; the parser change in term 0.2.0 means the buffer is now consumed as `complete((back_tab, 3))`. The downstream invariant (`_read_key_events` produces no spurious `Key::escape`) is unchanged and is verified directly by 3.5.
- [x] 3.3 Add an assertion that `_drain_keys([27_U8, 91_U8, 49_U8, 59_U8, 51_U8, 65_U8])` (ESC[1;3A) returns an empty array. Label it "ESC[1;3A drains to no keys".
- [x] 3.4 Add `_finalize_keys([27_U8], [])` returns a single-element array whose element is `Key::escape` (use `is_escape` or compare `@(0).as_special` / equivalent — match the existing matcher style in tests). Label it "bare ESC → Key::escape".
- [x] 3.5 Add `_finalize_keys([27_U8, 91_U8, 90_U8], [])` returns an empty array. Label it "ESC[Z + no drained keys → no event".
- [x] 3.6 Add `_finalize_keys([27_U8, 91_U8, 49_U8, 59_U8, 51_U8, 65_U8], [])` returns an empty array. Label it "ESC[1;3A + no drained keys → no event".
- [x] 3.7 Add `_finalize_keys([97_U8], [<some non-empty Key array>])` returns the input keys array unchanged. Label it "non-empty drained keys → passthrough". This guards against accidentally clobbering a real key.

## 4. Verify

- [x] 4.1 Run the project's existing test command (the one already used by CI / `scripts/`); confirm all tests pass, including the new `EventTest` cases.
- [ ] 4.2 Manually verify in a terminal: launch one of the [examples/](examples/) apps that quits on Esc, press Shift+Tab — confirm the app does **not** quit. Then press Esc — confirm the app quits as before. If no example currently distinguishes the two, smallest acceptable test is the hello-loop example referenced in the spec's "Hello loop quits on Esc" scenario.
  - Pending: requires a real interactive terminal. Apply tool cannot drive an attached TTY; run manually before archiving.
- [x] 4.3 Run `openspec validate fix-escape-misfire-on-unknown-csi --strict` and resolve any reported issues.
