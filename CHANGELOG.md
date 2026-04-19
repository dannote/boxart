# Changelog

## v0.3.2

### Bug fixes

- **Pie chart FP noise** — `show_data: true` displayed raw IEEE 754 artifacts
  like `[5.8999999999999995]`. Now uses `~g` formatting (6 significant digits,
  trailing zeros stripped) matching the Python original.

## v0.3.1

### Bug fixes

- **Stacked layout gap inflation** — when `max_width` triggered vertical stacking,
  gap expansions computed for the wide layout were incorrectly reused, adding
  excessive vertical space between every node pair
- **Mindmap multi-line labels** — labels containing `\n` were inserted raw into
  connector strings, breaking line alignment. Now joined with ` · ` for inline
  display
- Gap expansion limited to source/target layers only — intermediate gaps that
  just carry straight vertical lines no longer get inflated

## v0.3.0

### New features

- **Progressive compaction** — when `max_width` is set and the graph is too wide,
  Boxart tries progressively compact settings (smaller gap, then padding) before
  falling back to canvas clamping. Ported from termaid's auto-fit behavior.

- **Layout stacking** — when compaction isn't enough, sibling nodes in the same
  layer are stacked vertically (single column) instead of side-by-side, keeping
  all nodes fully rendered with intact borders.

- **Syntax highlighting in themed output** — code nodes with `:language` now
  render with Makeup syntax colors (keywords, functions, strings, operators)
  alongside the theme's structural colors.

### Improvements

- `max_width` now operates at the canvas cell level instead of string truncation —
  no more broken box-drawing characters or split ANSI escapes
- Labels are pre-wrapped by the layout engine and stored in `Layout.wrapped_labels` —
  the shapes renderer no longer re-wraps at a hardcoded width
- `max_label_width` option correctly flows through the entire pipeline
- Mindmap renderer handles tuple vertices without crashing (`inspect` instead of `to_string`)
- `Boxart.Graph.with_direction/2` helper for direction changes

### Bug fixes

- Shapes module no longer re-wraps labels at hardcoded 20-char width, respecting
  the `max_label_width` option
- `stamp_node_style` preserves Makeup ANSI styles instead of overwriting them
  with the node theme color
- `render_ansi_chunk` passes through raw ANSI escapes from syntax highlighting
- Dialyzer spec fixed: `render_graph_canvas` uses `BGraph.t()` not `Graph.t()`

## v0.2.0

### New features

- **`max_width` option** — clamp output to terminal width by truncating lines
- **`max_label_width` option** — configurable word wrapping threshold (default: 20)

## v0.1.0

Initial release.

- Directed graph rendering from `Graph.t()` (libgraph)
- 17 node shapes (rectangle, diamond, rounded, hexagon, stadium, circle, cylinder, etc.)
- Code nodes with line numbers and optional Makeup syntax highlighting
- Edge styles via keyword labels (`:solid`, `:dotted`, `:thick`, `:bidirectional`, `:arrow_type`)
- Edge labels
- Subgraphs
- All 4 directions (TD, LR, BT, RL)
- Unicode and ASCII charsets
- Rounded and sharp edge corners
- ANSI color themes (default, mono, neon, dracula, nord, amber, phosphor)
- `Boxart.Diagram` behaviour for specialized renderers
- Specialized renderers: state diagrams, sequence diagrams, git graphs, Gantt charts, mindmaps, pie charts
- Mindmap renderer accepts `Graph.t()`
- Sugiyama layout with barycenter crossing minimization
- A* edge routing with soft obstacles and endpoint spreading
- Direction-aware canvas with bitfield junction merging
