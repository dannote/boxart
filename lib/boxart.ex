defmodule Boxart do
  @moduledoc """
  Terminal graph rendering with Unicode box-drawing characters.

  Accepts a `Graph.t()` from [libgraph](https://hex.pm/packages/libgraph)
  and renders it as a text diagram.

  ## Quick start

      graph =
        Graph.new()
        |> Graph.add_vertex("A", label: "Start")
        |> Graph.add_vertex("B", label: "Decision", shape: :diamond)
        |> Graph.add_vertex("C", label: "End")
        |> Graph.add_edge("A", "B")
        |> Graph.add_edge("B", "C", label: "yes")

      IO.puts(Boxart.render(graph))

  ## Vertex labels

  Vertex labels are keyword lists (libgraph convention). Boxart recognizes:

    * `:label` — display text inside the node (defaults to `inspect(vertex)`)
    * `:shape` — node shape atom (`:rectangle`, `:diamond`, `:rounded`, `:hexagon`,
      `:stadium`, `:circle`, `:cylinder`, etc.)
    * `:source` — raw source code string (renders as a code block with line numbers)
    * `:start_line` — first line number for code display (default: `1`)
    * `:language` — language atom for syntax highlighting (e.g. `:elixir`)

  ## Code nodes

  When a vertex has a `:source` label, it renders as a code block with line
  numbers and optional syntax highlighting:

      Graph.add_vertex(g, "block",
        source: "x = fetch(url)\ncase decode(x)",
        start_line: 5,
        language: :elixir
      )

  ## Edge labels

  Edge labels are used as the display text on the edge.

  ## Directions

    * `:td` / `:tb` — top-down (default)
    * `:lr` — left-to-right
    * `:bt` — bottom-to-top
    * `:rl` — right-to-left
  """

  @type option ::
          {:charset, :unicode | :ascii}
          | {:direction, Boxart.Graph.direction()}
          | {:padding_x, non_neg_integer()}
          | {:padding_y, non_neg_integer()}
          | {:gap, non_neg_integer()}
          | {:theme, atom() | Boxart.Theme.t()}
          | {:rounded_edges, boolean()}

  @doc """
  Renders a libgraph `Graph.t()` as a Unicode/ASCII text diagram.

  ## Options

    * `:direction` — layout direction (default: `:td`)
    * `:charset` — `:unicode` (default) or `:ascii`
    * `:padding_x` — horizontal padding inside node boxes (default: `4`)
    * `:padding_y` — vertical padding inside node boxes (default: `2`)
    * `:gap` — space between nodes (default: `4`)
    * `:theme` — color theme: `:default`, `:mono`, `:neon`, `:dracula`, `:nord`,
      `:amber`, `:phosphor`, or a `%Boxart.Theme{}` struct
    * `:rounded_edges` — use rounded corners on edge turns (default: `true`)

  Returns `""` for empty graphs.
  """
  @spec render(Graph.t(), [option()]) :: String.t()
  def render(%Graph{} = graph, opts \\ []) do
    graph
    |> Boxart.Graph.from_libgraph(opts)
    |> Boxart.Render.render_graph(opts)
  end
end
