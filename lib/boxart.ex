defmodule Boxart do
  @moduledoc """
  Terminal graph rendering with Unicode box-drawing characters.

  Renders directed graphs as text diagrams using box-drawing characters
  for nodes and edges.

  ## Example

      graph =
        Boxart.Graph.new()
        |> Boxart.Graph.add_node("A", "Start")
        |> Boxart.Graph.add_node("B", "End")
        |> Boxart.Graph.add_edge("A", "B")

      Boxart.render(graph)
  """

  alias Boxart.Graph
  alias Boxart.Render

  @type option ::
          {:charset, :unicode | :ascii}
          | {:padding_x, non_neg_integer()}
          | {:padding_y, non_neg_integer()}
          | {:gap, non_neg_integer()}

  @doc """
  Renders a graph as a Unicode/ASCII text diagram.

  ## Options

    * `:charset` - `:unicode` (default) or `:ascii`
    * `:padding_x` - horizontal padding inside node boxes (default: `4`)
    * `:padding_y` - vertical padding inside node boxes (default: `2`)
    * `:gap` - space between nodes (default: `4`)

  Returns `""` for empty graphs.
  """
  @spec render(Graph.t(), [option()]) :: String.t()
  def render(%Graph{} = graph, opts \\ []) do
    Render.render_graph(graph, opts)
  end
end
