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
  |> Graph.add_vertex("B", label: "Process")
  |> Graph.add_vertex("C", label: "End")
  |> Graph.add_edge("A", "B")
  |> Graph.add_edge("B", "C")

IO.puts(Boxart.render(graph, direction: :lr))
```

```
┌─────────┐    ┌───────────┐    ┌───────┐
│         │    │           │    │       │
│  Start  ├───►│  Process  ├───►│  End  │
│         │    │           │    │       │
└─────────┘    └───────────┘    └───────┘
```

Branching with edge labels and node shapes:

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
┌────────────┐
│            │
│   Start    │
│            │
└──────┬─────┘
       │
       ▼
┌──────◇─────┐
│            │
│  Decision  │
│            │
└──────◇─────┘
       │
       ├─────────────────╮yes
     no│                 │
       ▼                 ▼
┌────────────┐    ┌────────────┐
│            │    │            │
│    End     │    │  Process   │
│            │    │            │
└────────────┘    └────────────┘
```

## Code nodes

Render source code with line numbers inside nodes — useful for control flow
graphs, program dependence graphs, and code analysis tools:

```elixir
graph =
  Graph.new()
  |> Graph.add_vertex("entry",
    source: "def fetch(url) do\n  case HTTP.get(url) do",
    start_line: 1,
    language: :elixir
  )
  |> Graph.add_vertex("ok",
    source: "{:ok, body} ->\n  body",
    start_line: 3
  )
  |> Graph.add_vertex("err",
    source: "{:error, reason} ->\n  raise reason",
    start_line: 5
  )
  |> Graph.add_edge("entry", "ok", label: ":ok")
  |> Graph.add_edge("entry", "err", label: ":error")

IO.puts(Boxart.render(graph, direction: :td))
```

```
┌─┬─────────────────────────────┐
│1│ def fetch(url) do           │
│2│   case HTTP.get(url) do     │
└─┴─────────────┬───────────────┘
                │
                │
                ├─────────────────────────────────────╮:error
             :ok│                                     │
                ▼                                     ▼
┌─┬─────────────────────────────┐       ┌─┬─────────────────────────┐
│3│ {:ok, body} ->              │       │5│ {:error, reason} ->     │
│4│   body                      │       │6│   raise reason          │
└─┴─────────────────────────────┘       └─┴─────────────────────────┘
```

When `makeup` and `makeup_elixir` are installed, code is syntax-highlighted
with ANSI colors in the terminal.

## Vertex labels

Vertex labels are keyword lists (libgraph convention). Boxart recognizes:

- `:label` — display text inside the node (defaults to `inspect(vertex)`)
- `:shape` — node shape atom (`:rectangle`, `:diamond`, `:rounded`, `:hexagon`,
  `:stadium`, `:circle`, `:cylinder`, etc.)
- `:source` — source code string (renders as code node with line numbers)
- `:start_line` — first line number for code display (default: `1`)
- `:language` — language atom for syntax highlighting (e.g. `:elixir`)

## Edge labels

Edge labels become the display text on the connecting edge:

```elixir
Graph.add_edge(g, "A", "B", label: "yes")
```

## Specialized renderers

Beyond directed graphs, Boxart includes standalone renderers for:

- `Boxart.Render.Sequence` — sequence diagrams with lifelines, messages,
  activation boxes, notes, and interaction blocks
- `Boxart.Render.Mindmap` — tree layout with left/right branching
- `Boxart.Render.PieChart` — horizontal bar charts

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
    {:boxart, "~> 0.1.0"},

    # optional, for syntax highlighting in code nodes
    {:makeup, "~> 1.0"},
    {:makeup_elixir, "~> 1.0"}
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
