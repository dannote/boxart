# Boxart

Terminal graph rendering with Unicode box-drawing characters.

Boxart takes a directed graph and renders it as ASCII/Unicode art in the terminal,
with multiline labels inside nodes, edge labels, and automatic layout.

## Features

- Sugiyama-style layered graph layout with crossing minimization
- A\* edge routing with soft obstacle avoidance
- Direction-aware junction merging (Canvas with bitfield tracking)
- Unicode and ASCII rendering modes
- Multiline node labels (code fragments, etc.)
- Edge labels
- Multiple node shapes (rectangle, rounded, diamond, hexagon, stadium, circle, cylinder, and more)
- Subgraph support
- Configurable padding and gap spacing

## Usage

```elixir
alias Boxart.Graph
alias Boxart.Graph.{Node, Edge}

graph = %Graph{
  direction: :td,
  nodes: %{
    "A" => Node.new("A", label: "Start"),
    "B" => Node.new("B", label: "Decision", shape: :diamond),
    "C" => Node.new("C", label: "Process"),
    "D" => Node.new("D", label: "End")
  },
  edges: [
    %Edge{source: "A", target: "B"},
    %Edge{source: "B", target: "C", label: "yes"},
    %Edge{source: "B", target: "D", label: "no"}
  ],
  node_order: ~w(A B C D)
}

IO.puts(Boxart.render(graph))
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
Node.new("block", label: "x = fetch(url)\ncase decode(x)")
```

## Options

```elixir
Boxart.render(graph,
  charset: :unicode,  # :unicode (default) or :ascii
  padding_x: 4,       # horizontal padding inside nodes
  padding_y: 2,        # vertical padding inside nodes
  gap: 4               # gap between nodes
)
```

## Directions

- `:td` / `:tb` — top to bottom (default)
- `:lr` — left to right
- `:bt` — bottom to top
- `:rl` — right to left

## Installation

```elixir
def deps do
  [
    {:boxart, "~> 0.1.0"}
  ]
end
```

## Acknowledgements

Layout engine ported from [termaid](https://github.com/fasouto/termaid) by Fabio Souto (MIT).

## License

MIT
