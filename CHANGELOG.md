# Changelog

## v0.2.0

### New features

- **`max_width` option** — clamp output to terminal width by truncating lines
- **`max_label_width` option** — configurable word wrapping threshold (default: 20)

### Example

```elixir
Boxart.render(graph,
  max_width: 80,
  max_label_width: 30
)
```

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
