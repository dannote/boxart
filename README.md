# Boxart

Terminal graph rendering with Unicode box-drawing characters.

Takes a `Graph.t()` from [libgraph](https://hex.pm/packages/libgraph)
and renders it as ASCII/Unicode art in the terminal, with multiline labels
inside nodes, edge labels, and automatic layout.

## Usage

```elixir
graph =
  Graph.new()
  |> Graph.add_vertex("A", label: "Start")
  |> Graph.add_vertex("B", label: "Decision", shape: :diamond)
  |> Graph.add_vertex("C", label: "Process")
  |> Graph.add_vertex("D", label: "End")
  |> Graph.add_edge("A", "B")
  |> Graph.add_edge("B", "C", label: "yes")
  |> Graph.add_edge("B", "D", label: "no")

IO.puts(Boxart.render(graph, direction: :td))
```

```
┌───────────┐
│           │
│   Start   │
│           │
└─────┬─────┘
      │
      ▼
┌─────◇─────┐
│           │
│ Decision  │
│           │
└─────◇─────┘
      │
      ├────────────╮no
   yes│            │
      ▼            ▼
┌───────────┐ ┌───────────┐
│           │ │           │
│  Process  │ │    End    │
│           │ │           │
└───────────┘ └───────────┘
```

Multiline labels work naturally — useful for code fragments:

```elixir
Graph.add_vertex(g, "block", label: "x = fetch(url)\ncase decode(x)")
```

## Vertex labels

Vertex labels are keyword lists (libgraph convention). Boxart recognizes:

- `:label` — display text inside the node (defaults to `inspect(vertex)`)
- `:shape` — node shape atom (`:rectangle`, `:diamond`, `:rounded`, `:hexagon`,
  `:stadium`, `:circle`, `:cylinder`, etc.)

## Edge labels

Edge labels become the display text on the connecting edge:

```elixir
Graph.add_edge(g, "A", "B", label: "yes")
```

## Options

```elixir
Boxart.render(graph,
  direction: :td,     # :td, :lr, :bt, :rl
  charset: :unicode,  # :unicode (default) or :ascii
  padding_x: 4,       # horizontal padding inside nodes
  padding_y: 2,       # vertical padding inside nodes
  gap: 4              # gap between nodes
)
```

## Installation

```elixir
def deps do
  [
    {:boxart, "~> 0.1.0"}
  ]
end
```

## Prior art

Boxart's layout engine is an Elixir port of [termaid](https://github.com/fasouto/termaid) by Fabio Souto,
which itself was inspired by [mermaid-ascii](https://github.com/AlexanderGrooff/mermaid-ascii) by Alexander Grooff.
We also evaluated [beautiful-mermaid](https://github.com/lukilabs/beautiful-mermaid) by Craft
and chose termaid for its cleaner layout pipeline (Sugiyama-style with barycenter crossing
minimization, A* routing with soft obstacles, and direction-aware canvas junction merging).

## License

MIT
