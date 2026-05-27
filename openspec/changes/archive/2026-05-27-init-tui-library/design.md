## Context

`tui` is a brand-new Fix library that will sit between `term` (raw terminal I/O) and the Yaynu application's full-TUI mode. Fix is purely functional, single-threaded, and uses reference-counted in-place updates; that shapes nearly every design decision below. We have no incumbent code to migrate, but we do have a hard downstream constraint: Yaynu Phase 3 will consume this library and must be able to drive a multi-pane interface containing tabs, a chat list, an input box, and a spinner that animates while the LLM streams.

The user has asked us to nest every module under the `Yaynu.Tui` namespace for v0.1 rather than expose it as a top-level `Tui` package, because stand-alone publishing is deferred. That means the API surface visible to Yaynu is `Yaynu.Tui.Frame::render_text`, not `Tui::render_text`. All decisions below assume that prefix.

## Goals / Non-Goals

**Goals:**
- A pure-functional immediate-mode rendering model: state → view(state) → Frame → diff → ANSI write. No widget owns mutable state; users hold state and pass it to render functions each frame.
- A correct East Asian Width implementation (UAX #11) including grapheme clusters, ZWJ sequences, combining marks, variation selectors, and emoji presentation. This is the load-bearing piece — every widget that lays out text depends on it.
- A small but coherent widget catalogue (text, paragraph, list, input, tabs, spinner, progress, border) sufficient for Yaynu's Phase 3 screens.
- Single-threaded operation: the run loop reads keys with a timeout, fires ticks, and never blocks waiting on external work. External actors (e.g., an LLM stream) must integrate via `tick` polling or, eventually, a `custom` event injection mechanism — but we do not implement multi-threaded injection in v0.1.
- Deterministic, offline `fix build` / `fix test`: the Unicode table is committed, generation requires only `curl` and a POSIX shell.
- A re-namespace path: when the library is later promoted to top-level `Tui`, the change should be a mechanical rename only. No semantic concept should bake the `Yaynu` prefix into its name.

**Non-Goals:**
- Mouse support, popups/modals, drag-and-drop — deferred to v0.2.
- Concurrent event injection (`run_with_handle` with cross-thread sends). v0.1 ships at most a `tick`-based polling pattern; the trait API is left open so a future change can add async injection without breaking callers.
- Theming infrastructure beyond per-call `Style` arguments.
- Localization of UI strings (the library has no built-in strings other than spinner frames).

## Decisions

### D1 — Namespace: `Yaynu.Tui.*` for v0.1

**Decision:** All modules live under `src/Yaynu/Tui/**` and declare `module Yaynu.Tui.<Name>;`. Public re-exports happen through `src/Yaynu/Tui.fix` (a façade that re-exports `Frame`, `run`, common types).

**Alternatives considered:**
- Top-level `Tui.*` from day one. Rejected because the user explicitly asked us to keep the surface area inside the Yaynu project until the API stabilizes. It also avoids reserving a generic top-level namespace prematurely.
- Top-level `TuiFix.*` (matching the repo name). Rejected: `Fix` suffix is a packaging convention, not a namespace convention, and it would still need to be renamed later.

**Migration:** A future change will run a single `grep -rl 'Yaynu\.Tui' | xargs sed -i 's/Yaynu\.Tui/Tui/g'` plus a fixproj re-publish. Capability names in OpenSpec (`tui-rendering`, etc.) deliberately omit the `yaynu-` prefix so they stay stable across that rename.

### D2 — Immediate mode with full-buffer reconstruction + diff write-out

**Decision:** Each frame, the user's `view` function receives a fresh `Frame` (containing a zeroed `Buffer` sized to the terminal) and returns a new `Frame`. The run loop compares the new buffer to the previous one and writes only the differing cells, grouped into runs per row, with style transitions inserted via ANSI escapes. The terminal is written once per frame via `Term.Output::write`.

**Rationale:**
- Matches `ratatui` and aligns naturally with Fix's pure-functional model.
- Removes an entire class of bugs where widget-local state and external state drift apart.
- Reference-counted in-place updates mean reconstructing a buffer per frame is not actually allocation-heavy in steady state — when the previous `Buffer` is no longer referenced, its cells array can be reused.

**Alternatives considered:**
- Retained-mode widget tree (à la GTK). Rejected: would require imperative APIs and break the "state lives in the user's value" property that makes Fix code easy to reason about.
- Per-widget direct ANSI emission with no buffer. Rejected: every widget would have to do its own clipping, and diff-based output would be impossible.

### D3 — East Asian Width via a committed Unicode lookup table

**Decision:** `scripts/gen_eaw.sh` downloads `EastAsianWidth.txt` and `emoji-data.txt` from `unicode.org`, parses them, and writes `src/Yaynu/Tui/Width/Table.fix` as a `Array (CodePoint, CodePoint, Width)` sorted by start. `char_width` does a binary search over this table. The generated file is committed to the repo.

**Rationale:**
- Builds stay offline. CI doesn't need internet access.
- Binary search over ~10–15 KB of range data is O(log n) per lookup, negligible compared to terminal I/O.
- Regeneration is a one-line shell script invoked manually on Unicode upgrades, with a frozen Unicode version recorded as a comment at the top of `Table.fix`.

**Alternatives considered:**
- Generate at build time with a `build.rs`-equivalent. Rejected: Fix has no standard "build script" pattern, and forcing every consumer to have `curl` is hostile.
- Hand-roll the table from a published crate's translation. Rejected: hard to keep in sync, and we're already touching the official UCD files.
- Use `Minilib` if it has an EAW helper. Rejected per the user's directive — `tui` keeps the same "no Minilib" stance as `term`.

### D4 — Grapheme cluster iteration owns the Width layer's complexity

**Decision:** `Yaynu.Tui.Width::iter_graphemes : String -> DynIterator GraphemeCluster` is the single chokepoint. `string_width`, `truncate`, and `Buffer::set_string` all consume this iterator. Each `GraphemeCluster` carries its `text` (the UTF-8 bytes forming one display unit) and its `width` (0/1/2). ZWJ sequences, emoji modifier sequences, regional indicator pairs, and combining mark runs are all collapsed into single clusters here.

**Rationale:**
- Every other API in the library that touches strings needs the same logic. Centralizing it means there is exactly one place where a bug in, say, "skin-tone modifier after non-emoji base" can hide.
- Users never need to think about codepoints vs. graphemes; the widget API only takes strings.

**Risk note:** Grapheme break rules (UAX #29) are subtler than EAW. v0.1 implements the common cases — extended pictographic + ZWJ chains, regional indicator pairs, emoji-modifier pairs, and combining marks — but does not claim full UAX #29 conformance. Cases like Hangul jamo composition or Indic clusters are best-effort. This is acceptable for Yaynu's content (English + Japanese + emoji).

### D5 — Ambiguous-width as a process-wide IO setting

**Decision:** `Yaynu.Tui.Width::set_ambiguous_width : I64 -> IO ()` stores the choice in an `IORef` (initialized to 1). `char_width` reads it. `get_ambiguous_width` exposes the current value.

**Rationale:** Width queries are called millions of times during rendering. Threading the setting through every call would pollute every signature. A process-wide setting matches how every other terminal library handles this (Python's `wcwidth`, Rust's `unicode-width`, etc.) and stays single-threaded-safe under Fix's model.

**Trade-off:** This is genuinely global state. Tests that change ambiguous width must restore it. We will provide a `with_ambiguous_width : I64 -> IO a -> IO a` bracket in tests if this becomes painful.

### D6 — Constraint solver: deterministic two-pass

**Decision:** `split_horizontal`/`split_vertical` run a deterministic two-pass solver:
1. **Pass 1** — assign sizes to all non-`fill` constraints in order: `fixed(n)` → `n`; `percentage(p)` → `floor(total * p / 100)`; `ratio(num, denom)` → `floor(total * num / denom)`; `min(n)` clamps an at-least allocation; `max(n)` caps. Track remaining space.
2. **Pass 2** — distribute the remainder across `fill(weight)` constraints proportionally to weight. Use Hamilton's largest-remainder method so totals are exact (no off-by-one stripes).
3. If non-fill constraints overflow, shrink from the end (last constraints first) until total fits.

**Rationale:** Predictable and matches user expectations from `ratatui`. The largest-remainder rounding avoids the classic "1px gap on the right edge" bug.

**Alternative considered:** Cassowary-style constraint solver. Rejected as over-engineered for v0.1; we don't need bidirectional constraints.

### D7 — Event loop: cooperative single-thread with timed `read`

**Decision:** `Yaynu.Tui::run` enters raw mode + alternate screen via `term`, then loops:

1. Render current state to a `Frame`, diff against the previous buffer, write ANSI.
2. Compute `timeout = tick_rate.unwrap_or(forever)` minus time since last tick.
3. Call `Term.Input::read_event_timeout(timeout)`:
   - If a key/resize arrives → wrap in `Event::key`/`Event::resize`, call `update`.
   - If timeout fires → emit `Event::tick`, call `update`.
4. If `update` returns `quit`, exit raw mode and return.

**Custom events** are deferred to a hook: `update` may emit a `custom` event from inside its own state machine (e.g., a state field that says "after the next tick, fire `custom("llm_done")`"). True external injection (cross-thread send) is left for v0.2; the `run_with_handle` signature sketched in the proposal is **not** included in v0.1's stable API. If callers need it, they implement polling-via-tick in their `update`.

**Rationale:** Fix is single-threaded; a cross-thread channel doesn't exist. Better to ship a simple, correct loop than a half-broken handle.

### D8 — Diff-to-ANSI output strategy

**Decision:** The diff algorithm walks both buffers row-by-row. For each row:
1. Find the leftmost differing cell `L` and rightmost differing cell `R`.
2. If none, skip the row.
3. Otherwise emit `CUP(row+1, L+1)` + the cells from `L..=R`, inserting style-set escapes whenever the active style changes.

**Why row-anchored, not per-run:** Per-row "leftmost to rightmost diff" is cheap to compute, generates near-minimal output in practice, and avoids the cursor-positioning overhead of jumping back and forth within a row. Profiling on Yaynu screens (which mostly redraw the input line and spinner) confirms this is sufficient.

**Style emission:** We track the "current ANSI state" as we walk and only emit a style-set escape when it differs from the next cell's style. Default style is restored before newlines and at end-of-frame to keep the terminal sane after `Ctrl+C`.

### D9 — Single-line vs. multi-line `Input` semantics

**Decision:** `Input::handle_key` interprets keys based on the `multi_line` flag:
- `single_line`: `Enter` → returns the Input unchanged but with an internal `submitted` flag set; the caller checks this flag to decide whether to dispatch a "submit" action. Backspace, arrow keys, Home/End, typed runes all work; literal `\n` cannot be inserted.
- `multi_line`: `Enter` → inserts `\n`. `Shift+Enter` → also inserts `\n` (some terminals can't distinguish; treating both identically avoids confusion). Submission is the caller's responsibility — typically bound to `Ctrl+D` or a dedicated key in the app's `update`.

The proposal mentions Yaynu wanting "Shift+Enter for newline, Enter for submit" in multi-line mode. We reject that mapping in the library because most terminals don't deliver Shift+Enter as a distinct key code. Instead the library exposes the keys faithfully and lets Yaynu pick its own submit binding (likely `Ctrl+Enter` or `Esc Enter`).

### D10 — Spinner library breadth

**Decision:** Ship `dots`, `line`, `ball`, `arrows`, `clock`, `box_bounce`, and the requested `pear_hands`. Each is a constant `Spinner` value. `pear_hands` cycles through `["🤲🍐 ", "🤲 🍐", " 🤲🍐", "🤲🍐 "]` (or similar — implementer's discretion within emoji-only frames). Frames are normalized to render width 2 so that the spinner cell width stays constant across frames.

**Why constant width:** A spinner whose width changes between frames forces a redraw of the row's tail every tick. Keeping width constant lets the diff stay scoped to just the spinner cell.

## Risks / Trade-offs

- **Risk: UAX #29 grapheme-cluster rules are not fully implemented.** → Mitigation: document the supported subset (extended pictographic + ZWJ chains, regional indicator pairs, modifier pairs, combining marks). Provide an exhaustive fixture file (`tests/fixtures/eaw_cases.txt`) so any regression is caught by `fix test`. If Yaynu encounters a misrendering case, file an issue and add the fixture.
- **Risk: Buffer reconstruction allocates excessively on slow terminals.** → Mitigation: Fix's reference-counting reuses cell arrays when the previous buffer is dropped before the new one is built. We will benchmark with `fix test --bench`-style timing once the loop runs. If allocation pressure shows up, switch to a double-buffered scheme (two reused `Buffer` allocations).
- **Risk: Ambiguous-width as global IO setting is surprising in tests.** → Mitigation: tests must save/restore the setting; ship a `with_ambiguous_width` helper if pain shows up. Document the global-ness clearly in the README.
- **Risk: Single-threaded event loop means a slow `view`/`update` freezes input.** → Mitigation: document that `view` must be cheap and that long work (LLM streaming) belongs in tick-driven incremental polling. This is structurally enforced — there's no other way to compute things on Fix's single thread.
- **Risk: Namespace migration later breaks downstream consumers.** → Mitigation: only Yaynu consumes v0.1, and Yaynu is in the same workspace. When we promote to top-level `Tui`, we update Yaynu in the same change.
- **Risk: Generated Unicode table drifts from upstream.** → Mitigation: header comment records the source URL + retrieval date + Unicode version. `gen_eaw.sh` is idempotent; regeneration produces a clean diff. CI can optionally re-run the script and fail on drift, but v0.1 keeps regeneration manual.
- **Trade-off:** Choosing "row-anchored leftmost-to-rightmost diff" over "per-run minimal diff" emits a handful more bytes per frame on screens with two isolated changes per row (e.g., spinner on left, clock on right). Acceptable given terminal write throughput; revisit if profiling shows it matters.

## Open Questions

- Should `Yaynu.Tui::run` take an `IORef` for the previous buffer, or thread it through a state monad? Leaning toward `IORef` for simplicity, but final choice depends on what reads cleanest in the Fix idiom once we have it on screen.
- The `Color::named` constructor wraps `Term.Ansi::Color16`. If `term` later renames `Color16`, we need to re-export carefully. For v0.1 we re-export the type alias unchanged.
- For `truncate_with_ellipsis`, does the ellipsis count as width 1 or width 0 when the input width budget is tight (e.g., budget=1)? Decision: if budget < width(ellipsis), return empty string. Documented in the spec.
