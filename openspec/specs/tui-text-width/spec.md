# tui-text-width Specification

## Purpose

Defines the Unicode-aware text-width and grapheme-segmentation utilities the rest of the TUI depends on for correct layout: per-grapheme display width derived from UAX #11 East Asian Width plus emoji presentation rules, a process-wide ambiguous-width override, string-level width, grapheme iteration, and budget-aware truncation. Also covers the build-time generator that produces the Unicode width table.

## Requirements

### Requirement: char_width returns the display width of a single grapheme

The system SHALL provide `Yaynu.Tui.Width::char_width : String -> I64` returning the display column count for a string treated as a single grapheme cluster. The result MUST be 0, 1, or 2 and SHALL be derived from the Unicode East Asian Width property (UAX #11) with the following normative rules: `W` and `F` are width 2; `Na`, `H`, and `N` are width 1; `A` is width 1 unless the ambiguous-width override has been set to 2 (see "Ambiguous width override"). Control characters U+0000–U+001F and U+007F SHALL be width 0. Combining marks (general categories Mn/Me), zero-width joiner (U+200D), and variation selectors (U+FE00–U+FE0F, U+E0100–U+E01EF) SHALL be width 0. Characters with the Unicode `Emoji_Presentation` property SHALL be width 2, except that U+0023, U+002A, and U+0030–U+0039 SHALL be width 1 (these lack default emoji presentation).

#### Scenario: ASCII letter is width 1

- **WHEN** `char_width("A")` is called
- **THEN** the result is `1`

#### Scenario: CJK ideograph is width 2

- **WHEN** `char_width("漢")` is called
- **THEN** the result is `2`

#### Scenario: Fullwidth digit is width 2

- **WHEN** `char_width("１")` is called (U+FF11)
- **THEN** the result is `2`

#### Scenario: Halfwidth katakana is width 1

- **WHEN** `char_width("ｱ")` is called (U+FF71)
- **THEN** the result is `1`

#### Scenario: BEL is width 0

- **WHEN** `char_width("\x07")` is called
- **THEN** the result is `0`

#### Scenario: Combining acute accent is width 0

- **WHEN** `char_width("\u{0301}")` is called
- **THEN** the result is `0`

#### Scenario: Bare emoji presentation character is width 2

- **WHEN** `char_width("😀")` is called
- **THEN** the result is `2`

#### Scenario: Digit zero is width 1 despite being keycap-eligible

- **WHEN** `char_width("0")` is called
- **THEN** the result is `1`

### Requirement: Ambiguous-width override

The system SHALL provide `set_ambiguous_width : I64 -> IO ()` and `get_ambiguous_width : IO I64` to switch the display width applied to characters with the East Asian Width `A` (Ambiguous) property. Valid values are `1` (default) and `2`. The setting SHALL be process-wide and SHALL be read by every subsequent `char_width`, `string_width`, `truncate`, `iter_graphemes`, and widget rendering call.

#### Scenario: Default ambiguous width is 1

- **WHEN** the process starts and `get_ambiguous_width` is called before any `set_ambiguous_width`
- **THEN** the result is `1`

#### Scenario: Switching to 2 changes Greek capital alpha to width 2

- **WHEN** `set_ambiguous_width(2)` is executed and then `char_width("Α")` (U+0391, EAW=A) is called
- **THEN** the result is `2`

#### Scenario: Switching back to 1 is observable

- **WHEN** after setting to 2, `set_ambiguous_width(1)` is executed and `char_width("Α")` is called again
- **THEN** the result is `1`

### Requirement: string_width handles grapheme clusters

The system SHALL provide `string_width : String -> I64` returning the total display width of a string, computed by summing `char_width` over the result of `iter_graphemes`. ZWJ-joined emoji sequences and grapheme clusters formed by combining marks, variation selectors, or modifier sequences SHALL be counted as a single grapheme (typically width 2 for emoji clusters, width 1 for combining-mark clusters on a narrow base). Regional Indicator pairs SHALL be counted as a single width-2 grapheme.

#### Scenario: Pure ASCII length equals byte count

- **WHEN** `string_width("Hello")` is called
- **THEN** the result is `5`

#### Scenario: Mixed Japanese and ASCII sums per-character widths

- **WHEN** `string_width("Hello, 世界!")` is called
- **THEN** the result is `12`

#### Scenario: Family emoji ZWJ sequence is width 2

- **WHEN** `string_width("👨‍👩‍👧‍👦")` is called (4 person codepoints joined by 3 ZWJs)
- **THEN** the result is `2`

#### Scenario: Skin-tone modifier sequence is width 2

- **WHEN** `string_width("👋🏽")` is called
- **THEN** the result is `2`

#### Scenario: Regional indicator pair is width 2

- **WHEN** `string_width("🇯🇵")` is called
- **THEN** the result is `2`

#### Scenario: Combining mark merges with its base

- **WHEN** `string_width("café")` is called where the é is `e` + U+0301
- **THEN** the result is `4`

#### Scenario: Lone ZWJ in the middle of ASCII does not add width

- **WHEN** `string_width("ABC\u{200D}DEF")` is called
- **THEN** the result is `6`

#### Scenario: Control character is skipped

- **WHEN** `string_width("\x07Hello")` is called
- **THEN** the result is `5`

### Requirement: iter_graphemes splits at extended-grapheme boundaries

The system SHALL provide `iter_graphemes : String -> DynIterator GraphemeCluster` that yields `GraphemeCluster { text, width }` values. The break rules SHALL recognise at minimum: (a) base + combining mark sequences, (b) Extended_Pictographic followed by zero or more `Emoji_Modifier`/ZWJ/Extended_Pictographic continuations, (c) Regional Indicator pairs, (d) `\r\n` as a single cluster. Each cluster's `width` SHALL equal `char_width` applied to that cluster's bytes, which under these rules collapses ZWJ-joined emoji to a single width-2 cluster.

#### Scenario: Plain ASCII produces one cluster per byte

- **WHEN** `iter_graphemes("abc")` is collected
- **THEN** the iterator yields three clusters with `@text = "a"`, `"b"`, `"c"` and `@width = 1` each

#### Scenario: ZWJ-joined family is one cluster

- **WHEN** `iter_graphemes("👨‍👩‍👧‍👦")` is collected
- **THEN** the iterator yields exactly one cluster with `@width = 2` whose `@text` is the entire 25-byte UTF-8 sequence

#### Scenario: e + combining acute is one cluster

- **WHEN** `iter_graphemes("e\u{0301}")` is collected
- **THEN** the iterator yields one cluster with `@width = 1`

#### Scenario: CRLF is one cluster

- **WHEN** `iter_graphemes("\r\n")` is collected
- **THEN** the iterator yields exactly one cluster with `@text = "\r\n"`

### Requirement: truncate respects grapheme boundaries

The system SHALL provide `truncate : I64 -> String -> String` that returns the longest prefix whose `string_width` does not exceed the given width budget, with cuts only at grapheme-cluster boundaries. When a wide grapheme would partially fit (budget remaining is 1, next cluster has width 2), it SHALL be excluded entirely. Negative budgets SHALL return the empty string.

#### Scenario: Truncate ASCII at exact budget

- **WHEN** `truncate(3, "Hello")` is called
- **THEN** the result is `"Hel"`

#### Scenario: Wide character that would overflow is excluded

- **WHEN** `truncate(3, "あい")` is called (each character is width 2)
- **THEN** the result is `"あ"` (width 2 — the second character would push width to 4)

#### Scenario: Budget of 0 returns empty

- **WHEN** `truncate(0, "Hello")` is called
- **THEN** the result is `""`

#### Scenario: ZWJ emoji sequence is treated atomically

- **WHEN** `truncate(1, "👨‍👩‍👧‍👦")` is called
- **THEN** the result is `""` (the family emoji has width 2, will not fit)

### Requirement: truncate_with_ellipsis appends a sentinel when shortened

The system SHALL provide `truncate_with_ellipsis : I64 -> String -> String` that behaves as follows: if `string_width(input) <= budget`, the input is returned unchanged. Otherwise the result is `truncate(budget - 1, input) ++ "…"` provided `budget >= 1`. If `budget < 1`, the result is the empty string.

#### Scenario: Short string passes through unchanged

- **WHEN** `truncate_with_ellipsis(10, "abc")` is called
- **THEN** the result is `"abc"`

#### Scenario: Long string is shortened and ellipsis appended

- **WHEN** `truncate_with_ellipsis(5, "Hello, World")` is called
- **THEN** the result is `"Hell…"` with display width 5

#### Scenario: Budget of 0 returns empty

- **WHEN** `truncate_with_ellipsis(0, "Hello")` is called
- **THEN** the result is `""`

### Requirement: Width table is generated from Unicode UCD

The system SHALL include `scripts/gen_eaw.sh` that fetches `EastAsianWidth.txt` and `emoji-data.txt` from `https://www.unicode.org/Public/UCD/latest/ucd/` (and the emoji subdirectory), parses them, and writes `src/Yaynu/Tui/Width/Table.fix`. The generated file MUST include, as a leading comment, the Unicode version and the retrieval date so that drift is detectable. The generated `Table.fix` SHALL be committed to the repository so that `fix build` and `fix test` require no network access.

#### Scenario: Generated table compiles

- **WHEN** `scripts/gen_eaw.sh` is run and `fix build` is invoked
- **THEN** the build succeeds without network access

#### Scenario: Regeneration is idempotent

- **WHEN** `scripts/gen_eaw.sh` is run twice in succession with no upstream change
- **THEN** the second run produces a `Table.fix` identical to the first (no spurious diff)
