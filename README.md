# tui

An immediate-mode TUI widget toolkit for [Fix](https://github.com/tttmmmyyyy/fixlang), layered on top of [`term`](https://github.com/sakujiro-inagaki/term-fix). Inspired by [`ratatui`](https://github.com/ratatui/ratatui) and Elm.

All modules live under the `Yaynu.Tui.*` namespace for v0.1. The promotion to a top-level `Tui.*` namespace is planned for a later release (see the **Namespace migration** note below).

## Scope

`tui` ships:

- An immediate-mode rendering pipeline: `Style` / `Color` / `Cell` / `Buffer` / `Frame`, plus diff-to-ANSI output that turns a re-built frame into the minimal escape sequence written to the terminal.
- UAX #11-compliant text width measurement, with grapheme-cluster iteration, ZWJ sequences, combining marks, regional indicators, and emoji.
- Layout primitives: `Rect` plus `Constraint` (`fixed`, `percentage`, `ratio`, `min`, `max`, `fill`) with `split_horizontal` / `split_vertical`.
- A widget catalogue sufficient for Yaynu's Phase 3 screens: `text`, `paragraph` (with wrap modes), `list`, `input` (single & multi-line, UTF-8 cursor), `tabs`, `spinner` (multiple presets including a playful `pear_hands`), `progress` (determinate + indeterminate), `border`.
- An event loop: `Event` (`key` / `resize` / `tick` / `custom`), the `TuiApp` trait, and `Yaynu.Tui::run`.

Out of scope for v0.1: mouse support, popups/modals, drag-and-drop, cross-thread event injection.

## Architecture

`tui` is immediate-mode: the user holds the entire application state and re-renders a fresh `Frame` every tick. The `run` loop compares the new buffer to the previous one and writes only the differing cells to the terminal.

```
state ──► view(state) ──► Frame ──► diff(prev, next) ──► ANSI
  ▲                                                       │
  └─────────── update(event, state) ◄────── read_event ◄──┘
```

Widgets are pure: they consume the current state and a `Rect` and return a modified `Frame`. There is no widget-local mutable state.

## Hello, TUI

```fix
module Main;

import Yaynu.Tui;
import Yaynu.Tui.Event;
import Yaynu.Tui.Frame;
import Yaynu.Tui.Style;
import Yaynu.Term.Key;

type AppState = box struct { _placeholder : () };

impl AppState : TuiApp {
    initial = AppState { _placeholder : () };
    view = |_, frame|
        frame.render_text("Hello, TUI! (Esc to quit)", Style::default, frame.@size);
    update = |ev, s| (
        match ev {
            key(k) => (
                match k {
                    escape() => UpdateResult::quit(),
                    _        => UpdateResult::continue(s)
                }
            ),
            _ => UpdateResult::continue(s)
        }
    );
    tick_rate = |_| Option::none();
}

main : IO ();
main = (
    let initial_state : AppState = TuiApp::initial;
    let r = *Yaynu.Tui::run(initial_state).to_result;
    match r { ok(_) => pure(), err(e) => println("error: " + e) }
);
```

Run with `fix run -f examples/hello_tui.fix`.

## Widget catalogue

Each widget lives under `Yaynu.Tui.Widget.<Name>` and exposes its `Frame::render_*` function via the façade.

```fix
// Borders.
let border = Border::all.with_title("Stats").set_border_type(BorderType::rounded());
let inner  = border.inner(rect);
frame.render_border(border, rect).render_text("count: 3", Style::default, inner)
```

```fix
// Paragraph with word wrap.
let p = Paragraph::new("the quick brown fox").with_wrap(WrapMode::word());
frame.render_paragraph(p, rect)
```

```fix
// List with selection + highlight symbol.
let items = ["alpha", "beta", "gamma"].to_iter.map(|s| ListItem::new(s, s)).to_array;
let l = List::new(items).with_selected(1).with_highlight_symbol("> ");
frame.render_list(l, rect)
```

```fix
// Input with placeholder.
let i = Input::new.with_placeholder("type something...");
frame.render_input(i, rect)
```

```fix
// Tabs.
let t = Tabs::new(["overview", "details", "logs"]).with_selected(0);
frame.render_tabs(t, top_bar)
```

```fix
// Spinner — playful default.
frame.render_spinner(Spinner::pear_hands.with_label("loading..."), spinner_rect)
```

```fix
// Progress.
let p = Progress::new.with_value(0.42).with_width(20);
frame.render_progress(p, rect)
```

## Layout

```fix
let rows = Rect::split_vertical(
    [Constraint::fixed(1), Constraint::fill(1), Constraint::fixed(1)],
    frame.@size
);
let cols = Rect::split_horizontal(
    [Constraint::fixed(20), Constraint::fill(1)],
    rows.@(1)
);
let top = rows.@(0); let bot = rows.@(2);
let side = cols.@(0); let main_pane = cols.@(1);
```

Percentages and ratios round via Hamilton largest-remainder so totals stay exact (no off-by-one stripes).

## East Asian Width

The width API lives at `Yaynu.Tui.Width`:

- `char_width : String -> I64` — display width of a single grapheme cluster (0/1/2)
- `string_width : String -> I64` — display width of a string
- `iter_graphemes : String -> DynIterator GraphemeCluster` — grapheme-cluster iteration
- `truncate : I64 -> String -> String` — grapheme-aware cap at a width budget
- `truncate_with_ellipsis : I64 -> String -> String` — same, appending `…` if shortened
- `set_ambiguous_width : I64 -> IO ()` / `get_ambiguous_width : IO I64` — process-wide override

Coverage includes ZWJ-joined emoji families, regional indicator pairs, skin-tone modifier sequences, combining marks, variation selectors. Hangul jamo composition and Indic clusters are best-effort.

### Ambiguous-width override

UAX #11 declares some codepoints "Ambiguous" — their display width depends on the rendering context (CJK vs. Western). `tui` defaults to width 1; if your terminal renders A-class characters at width 2 (typical for CJK locales), call `set_ambiguous_width(2)` once at startup:

```fix
main : IO ();
main = (
    Width::set_ambiguous_width(2);;
    let r = *Yaynu.Tui::run(initial_state).to_result;
    ...
);
```

The setting is process-wide and read by every subsequent width query.

## Examples

| File | What it shows |
|------|---------------|
| `examples/hello_tui.fix` | Minimal `TuiApp` skeleton, Esc to quit |
| `examples/width_demo.fix` | Japanese / emoji / ZWJ / RI / combining-mark rendering |
| `examples/tabs_demo.fix` | Tabs, Tab key cycles |
| `examples/list_demo.fix` | 20-item list with arrow-key selection |
| `examples/input_demo.fix` | Single-line input, accepts Japanese + emoji |
| `examples/spinner_demo.fix` | Every spinner preset, 100 ms ticks |
| `examples/layout_demo.fix` | Tabs + status bar + side panel + main pane |

Run any example with `fix run -f examples/<name>.fix`.

## Namespace migration

All modules currently sit under `Yaynu.Tui.*`. A future release will promote them to top-level `Tui.*` — that change is a mechanical `Yaynu.Tui → Tui` rename and a `fixproj.toml` re-publish. No semantic concept bakes the `Yaynu` prefix into its name, so callers will only need to fix imports.

## Regenerating the Unicode width table

`src/Yaynu/Tui/Width/Table.fix` is generated from the Unicode UCD. To refresh:

```sh
sh scripts/gen_eaw.sh
```

The script needs only `curl` and a POSIX shell, runs once on Unicode upgrades, and is idempotent on repeated invocations.

## Status

`fix test` runs 13 module suites (including a width-fixture file) — all green. Examples have been compiled; manual launch/quit verification per example is left to the integrator per `tasks.md` §17.3.

## Non-goals

- Mouse, popups, drag-and-drop (deferred to v0.2)
- Cross-thread event injection (`run_with_handle`) — applications can simulate custom events via their own state machine in `update`
- Theming infrastructure beyond per-call `Style` arguments
- Localization of UI strings
