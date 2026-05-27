## ADDED Requirements

### Requirement: Rect describes an axis-aligned screen region

The system SHALL provide `Rect` as a struct of `x : I64`, `y : I64`, `width : I64`, `height : I64`, all measured in terminal cells with `(x, y) = (0, 0)` at the top-left of the terminal. `Rect::make` SHALL build a rect from those four values without normalization (negative widths/heights are the caller's responsibility, but rendering operations consuming such a rect SHALL treat it as empty).

#### Scenario: make stores fields verbatim

- **WHEN** `Rect::make(2, 3, 10, 5)` is called
- **THEN** the returned rect has `@x = 2`, `@y = 3`, `@width = 10`, `@height = 5`

#### Scenario: A rect with non-positive dimensions is rendered as empty

- **WHEN** any `Frame::render_*` is invoked with a rect whose `@width <= 0` or `@height <= 0`
- **THEN** the frame's buffer is returned unchanged

### Requirement: Constraint enumerates the layout policies

The system SHALL provide `Constraint` as a box union with constructors `fixed : I64`, `percentage : I64`, `ratio : (I64, I64)`, `min : I64`, `max : I64`, and `fill : I64`. The semantics SHALL be: `fixed(n)` requests exactly `n` cells; `percentage(p)` requests `floor(total * p / 100)` cells; `ratio(num, denom)` requests `floor(total * num / denom)` cells; `min(n)` requests at least `n` cells; `max(n)` requests at most `n` cells; `fill(w)` requests a share of the leftover space proportional to its weight `w` (relative to other `fill` weights in the same split).

#### Scenario: Constraint values are constructible and pattern-matchable

- **WHEN** a caller constructs `Constraint::fixed(5)`, `Constraint::percentage(30)`, `Constraint::ratio((2, 3))`, `Constraint::min(4)`, `Constraint::max(20)`, `Constraint::fill(1)`
- **THEN** all values type-check and pattern-match against the corresponding constructor

### Requirement: split_horizontal divides a rect along the X axis

The system SHALL provide `Rect::split_horizontal : Array Constraint -> Rect -> Array Rect` that returns one sub-rect per constraint, in input order, such that all returned rects share the parent's `y` and `height`, their `x` values are non-decreasing, and their widths sum to exactly the parent's width. The sub-rects MUST be contiguous (no gaps, no overlap). The allocator SHALL resolve constraints in two passes: (1) assign sizes to non-`fill` constraints using their formulas above; (2) distribute the leftover cells to `fill` constraints using Hamilton's largest-remainder method so the total is exact. If the sum from step 1 already exceeds the parent's width, sub-rects from the end are reduced first until the total fits.

#### Scenario: All fixed sums to the parent width

- **WHEN** splitting a 30-wide rect with `[fixed(5), fixed(10), fixed(15)]`
- **THEN** the returned rects have widths `5`, `10`, `15` and `x` values `0`, `5`, `15`

#### Scenario: Fill divides remainder by weight

- **WHEN** splitting a 20-wide rect with `[fixed(4), fill(1), fill(3)]`
- **THEN** the returned rects have widths `4`, `4`, `12`

#### Scenario: Percentages round without losing total width

- **WHEN** splitting a 10-wide rect with `[percentage(33), percentage(33), percentage(34)]`
- **THEN** the returned widths sum to exactly `10`

#### Scenario: Empty constraint array returns empty array

- **WHEN** splitting a non-empty rect with `[]`
- **THEN** the returned array is empty and the parent is unchanged

#### Scenario: Overflow shrinks from the end

- **WHEN** splitting a 10-wide rect with `[fixed(6), fixed(6), fixed(6)]`
- **THEN** the returned widths sum to `10` and the trailing rects are shrunk first (e.g. `6, 4, 0` or `6, 4, 0`-equivalent)

### Requirement: split_vertical divides a rect along the Y axis

The system SHALL provide `Rect::split_vertical : Array Constraint -> Rect -> Array Rect` with the same constraint semantics as `split_horizontal`, applied to the parent's `height` (and yielding sub-rects with shared `x` and `width`).

#### Scenario: Vertical split mirrors horizontal logic

- **WHEN** splitting a 24-tall rect with `[fixed(1), fill(1), fixed(1)]`
- **THEN** the returned rects have heights `1`, `22`, `1` and `y` values `0`, `1`, `23`
