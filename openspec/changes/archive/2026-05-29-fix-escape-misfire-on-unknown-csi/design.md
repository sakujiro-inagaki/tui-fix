## Context

`Yaynu.Tui::run` reads stdin in non-blocking drains: on a key-byte wake-up it calls `_read_key_events`, which concatenates the first byte with everything else currently available and feeds the resulting buffer to `_drain_keys`. `_drain_keys` is a pure loop over `Yaynu.Term.Key::parse` that may emit `complete`, `invalid(n)` (drop n bytes), or `incomplete` (stop draining and discard the tail for v0.1).

A bare Esc press is special: stdin delivers a single `0x1B` byte, the CSI sub-parser inside `parse` cannot tell whether more bytes will follow, so it returns `incomplete`. Without a fallback, that lone Esc would be silently dropped — which is why `_read_key_events` synthesises a `Key::escape` when the drain produces no keys. The current guard is:

```fix
if keys.get_size == 0 && bytes.get_size > 0 && bytes.@(0) == 27_U8 { … }
```

`bytes.get_size > 0` is too permissive. Any `ESC`-prefixed sequence that the CSI parser rejects via `invalid(n)` (e.g. `ESC[Z` for Shift+Tab, `ESC[1;3A` for Alt+Shift+Up, vendor-specific extensions, …) ends with `keys.get_size == 0` and `bytes.@(0) == 27_U8`, and is therefore reported as Esc. Users who press Shift+Tab expecting no-op (or a tab-cycle they'll wire later) instead trigger their app's Esc-handler — often "quit".

## Goals / Non-Goals

**Goals:**
- Stop synthesising `Key::escape` for unknown ESC-prefixed CSI sequences that the parser fully drops.
- Preserve the existing bare-Esc behaviour: a single `0x1B` byte still maps to one `Event::key(Key::escape)`.
- Keep the change local to `_read_key_events`; no changes to `Yaynu.Term.Key::parse` or `_drain_keys`.

**Non-Goals:**
- Improving CSI coverage so that Shift+Tab et al. parse to real `Key` values (separate change).
- Carrying an `incomplete` tail across reads (still a documented v0.1 limitation).
- Changing the `Event`, `Key`, or `TuiApp` public surface.

## Decisions

### Decision 1: Tighten the guard to `bytes.get_size == 1`

Replace `bytes.get_size > 0` with `bytes.get_size == 1`. A buffer of exactly one byte equal to `0x1B` is the only case where `Yaynu.Term.Key::parse` cannot produce a `complete` and the byte is unambiguously a bare Esc keypress — there is no possible follow-up sequence in the buffer.

**Why this over alternatives:**
- *Alternative A — check `_drain_keys` actually returned `incomplete` and only then synthesise:* would require threading the terminating reason out of `_drain_keys`, which is currently a pure `Array Key` returner. Adds API surface for a one-call-site distinction.
- *Alternative B — also check that the buffer ends in `incomplete` for any length:* still wrong, because `ESC` followed by an `invalid(n)` chunk that consumes the rest also ends with `keys.get_size == 0`, and a multi-byte buffer is not a bare Esc.
- *Alternative C — strip leading `ESC` and re-parse:* over-engineered for v0.1; we just need the regression gone.

The `== 1` check is the smallest correct discriminator and the user's proposed fix.

### Decision 2: Keep `_drain_keys` unchanged

`_drain_keys` already handles `invalid(n)` by dropping `n` bytes and continuing — that's the desired "no event" behaviour for unknown CSI. The bug is purely in the fallback condition, not in the drainer.

### Decision 3: Extract the guard into a small pure helper so the spec scenarios are unit-testable

The bare-ESC fallback currently lives inline inside `_read_key_events`, which returns `IOFail (Array Event)` and reads stdin. That makes the new spec scenarios ("unknown CSI emits no event") awkward to test directly. Lift the synthesise-or-not decision into a tiny pure helper:

```fix
_finalize_keys : Array U8 -> Array Yaynu.Term.Key::Key -> Array Yaynu.Term.Key::Key;
_finalize_keys = |bytes, keys| (
    if keys.get_size == 0 && bytes.get_size == 1 && bytes.@(0) == 27_U8 {
        [Yaynu.Term.Key::Key::escape()]
    } else {
        keys
    }
);
```

Then `_read_key_events` becomes:

```fix
let keys = _finalize_keys(bytes, _drain_keys(bytes));
```

`EventTest.fix` already exercises `_drain_keys` directly through the underscore-prefixed convention; the same pattern applies to `_finalize_keys`. Each new spec scenario maps 1:1 to a `_finalize_keys` call against a hand-built byte buffer plus the corresponding `_drain_keys` output.

**Why this small refactor over a literal one-line edit:** the literal `> 0` → `== 1` change is the user's proposed patch and is correct. Extracting the helper adds ~6 lines of code and gives us automated coverage of all four spec scenarios; without it, only the underlying `_drain_keys` invariant ("unknown CSI parses to no keys") would be unit-testable and the fallback guard itself would be untested. The refactor is the smallest change that lets the new scenarios become tests.

## Risks / Trade-offs

- **[Risk]** An app currently relying on Shift+Tab → Esc to quit will stop quitting. **Mitigation:** this is the entire point of the fix; document it in the changelog / release notes for the next version bump.
- **[Risk]** A future change that buffers an `incomplete` tail across reads could make the `== 1` check fire on a buffer that *started* as a multi-byte ESC sequence but was trimmed down to one byte by an earlier partial parse. **Mitigation:** when that cross-read state lands, revisit this guard — the incomplete-tail handling will subsume bare-Esc detection anyway.
- **Trade-off:** a real user pressing Esc *during* an unrelated burst of bytes (e.g. paste of `ESC[Z` immediately after pressing Esc) loses the Esc event. This was already broken in the opposite direction (false Esc for every unknown CSI) and the new behaviour is strictly safer for app authors.
