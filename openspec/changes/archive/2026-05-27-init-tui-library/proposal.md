## Why

Yaynu's full-TUI mode needs a structured widget toolkit that the raw `term` terminal layer cannot provide on its own: layout primitives, reusable widgets (text, list, input, tabs, spinner, progress, border), an event loop, and diff-based rendering. Without these, every Yaynu screen would re-implement framing, focus, scrolling, and East Asian Width handling — duplicating subtle logic and risking display corruption with Japanese text and emoji. This change establishes `tui` as the immediate-mode (Elm/`ratatui`-style) layer on top of `term` that Yaynu Phase 3 will build against.

The initial release keeps all code under the `Yaynu.Tui` namespace so that the library can ship alongside Yaynu without forcing a stand-alone publishing process up front. A future change can rename to a top-level `Tui` namespace and extract the package once the API stabilizes.

## What Changes

- Initialize the `tui` Fix project (`fixproj.toml`) depending on `Std` and `term` only (no Minilib).
- Place all modules under the `Yaynu.Tui` namespace (e.g., `src/Yaynu/Tui/Style.fix`, `src/Yaynu/Tui/Buffer.fix`) so they coexist cleanly with the Yaynu application code. Top-level `Tui` namespace is deferred to a future stand-alone release.
- Add an immediate-mode rendering pipeline: `Style`, `Color`, `Cell`, `Buffer`, `Frame`, plus diff-to-ANSI output.
- Add East Asian Width-compliant text width measurement, including grapheme-cluster iteration, ZWJ sequences, combining characters, and emoji.
- Add layout primitives: `Rect` and `Constraint` (`fixed`, `percentage`, `ratio`, `min`, `max`, `fill`) with `split_horizontal` / `split_vertical`.
- Add the widget set: `text`, `paragraph` (with wrap modes), `list` (with selection + scrolling), `input` (single/multi-line, UTF-8 cursor), `tabs`, `spinner` (multiple presets including a playful `pear_hands`), `progress` (determinate + indeterminate), `border`.
- Add the event loop: `Event` (key / resize / tick / custom), `TuiApp` trait, and `Yaynu.Tui::run`.
- Generate `src/Yaynu/Tui/Width/Table.fix` from Unicode UCD data via `scripts/gen_eaw.sh`, committed so builds need no network.
- Ship `examples/` programs and a fixture-based width test suite (`tests/fixtures/eaw_cases.txt`).

## Capabilities

### New Capabilities

- `tui-rendering`: Immediate-mode buffer/frame/cell/style model and diff-to-ANSI output that turns a re-built frame into the minimal ANSI sequence written to the terminal.
- `tui-text-width`: UAX #11-compliant character and string width measurement, grapheme-cluster iteration, truncation, and runtime ambiguous-width switching.
- `tui-layout`: `Rect` plus `Constraint`-based horizontal/vertical splits used to carve the screen into widget regions.
- `tui-widgets`: The v0.1 widget catalogue — text, paragraph, list, input, tabs, spinner, progress, border — including their state types and key-input handlers where applicable.
- `tui-event-loop`: The `Event` type, `TuiApp` trait, and `run` driver that owns raw mode, ticks, key reading, and the view→update cycle.

### Modified Capabilities

None — this is a greenfield repository; no existing specs to modify.

## Impact

- **Code**: Adds `src/Yaynu/Tui/**`, `tests/**`, `examples/**`, `scripts/gen_eaw.sh`, `fixproj.toml`, `README.md`. No existing code to migrate.
- **Dependencies**: New runtime dependency on `term` (`https://github.com/sakujiro-inagaki/term-fix`); no Minilib usage.
- **Build**: `scripts/gen_eaw.sh` requires `curl` and a POSIX shell, but only at table-regeneration time; the generated `Table.fix` is committed so normal `fix build` / `fix test` are offline.
- **Downstream**: Yaynu Phase 3 will depend on this library. Because everything lives under `Yaynu.Tui`, no namespace clash is possible inside the Yaynu workspace; a later promotion to top-level `Tui` will be a single namespace-rename change.
- **Non-goals (deferred)**: Full mouse support, popups/modals, and drag-and-drop are explicitly out of scope for v0.1.
