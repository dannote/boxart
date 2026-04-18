defmodule Boxart.Layout do
  @moduledoc """
  Grid-based layout engine for flowchart diagrams.

  ## Coordinate Systems

  **Grid coordinates** `{col, row}` — logical positions on a coarse grid.
  Each node occupies a 3×3 block centered at `{col, row}`. The 8 surrounding
  cells are border/attachment cells used for edge routing.

  **Draw coordinates** `{x, y}` — character positions in the final output.
  Column widths and row heights vary (content, padding, gap, subgraph borders),
  so a single grid cell may span many characters.

  ## Layout Model

  Nodes are separated by `STRIDE` grid units (default 4 = 3 block + 1 gap).
  Gap cells between node blocks provide routing space for edges.

  `compute_layout/2` orchestrates the full pipeline: layer assignment, ordering,
  placement, sizing, and coordinate conversion.
  """

  alias Boxart.Graph
  alias Boxart.Layout.{Coordinates, Layers, Placement, Subgraphs}

  @stride 4
  @max_label_width 20
  @max_normalized_width 25
  @max_normalized_height 7
  @sg_border_pad 2
  @sg_label_height 2
  @sg_gap_per_level @sg_border_pad + @sg_label_height + 1

  @doc false
  def stride, do: @stride
  @doc false
  def max_label_width, do: @max_label_width
  @doc false
  def max_normalized_width, do: @max_normalized_width
  @doc false
  def max_normalized_height, do: @max_normalized_height
  @doc false
  def sg_border_pad, do: @sg_border_pad
  @doc false
  def sg_label_height, do: @sg_label_height
  @doc false
  def sg_gap_per_level, do: @sg_gap_per_level

  defmodule GridCoord do
    @moduledoc "Logical position on the layout grid."
    @type t :: %__MODULE__{col: integer(), row: integer()}
    defstruct col: 0, row: 0
  end

  defmodule NodePlacement do
    @moduledoc "Grid and draw-coordinate placement for a single node."

    @type t :: %__MODULE__{
            node_id: String.t(),
            grid: Boxart.Layout.GridCoord.t(),
            draw_x: integer(),
            draw_y: integer(),
            draw_width: integer(),
            draw_height: integer()
          }

    defstruct node_id: "",
              grid: %Boxart.Layout.GridCoord{},
              draw_x: 0,
              draw_y: 0,
              draw_width: 0,
              draw_height: 0
  end

  defmodule SubgraphBounds do
    @moduledoc "Bounding box for a subgraph in draw coordinates."

    @type t :: %__MODULE__{
            subgraph_id: String.t(),
            x: integer(),
            y: integer(),
            width: integer(),
            height: integer()
          }

    defstruct subgraph_id: "", x: 0, y: 0, width: 0, height: 0
  end

  @type t :: %__MODULE__{
          placements: %{String.t() => NodePlacement.t()},
          col_widths: %{integer() => integer()},
          row_heights: %{integer() => integer()},
          grid_occupied: %{{integer(), integer()} => String.t()},
          canvas_width: integer(),
          canvas_height: integer(),
          subgraph_bounds: [SubgraphBounds.t()],
          offset_x: integer(),
          offset_y: integer()
        }

  defstruct placements: %{},
            col_widths: %{},
            row_heights: %{},
            grid_occupied: %{},
            canvas_width: 0,
            canvas_height: 0,
            subgraph_bounds: [],
            offset_x: 0,
            offset_y: 0

  @doc "Check if a grid cell is not occupied, optionally excluding certain node IDs."
  @spec free?(t(), integer(), integer(), MapSet.t() | nil) :: boolean()
  def free?(layout, col, row, exclude \\ nil)
  def free?(_layout, col, row, _exclude) when col < 0 or row < 0, do: false

  def free?(%__MODULE__{grid_occupied: occupied}, col, row, exclude) do
    case Map.get(occupied, {col, row}) do
      nil -> true
      id -> exclude != nil and MapSet.member?(exclude, id)
    end
  end

  @doc "Convert grid coordinates to draw coordinates (top-left of the cell)."
  @spec grid_to_draw(t(), integer(), integer()) :: {integer(), integer()}
  def grid_to_draw(
        %__MODULE__{col_widths: cw, row_heights: rh, offset_x: ox, offset_y: oy},
        col,
        row
      ) do
    x = Enum.reduce(0..(col - 1)//1, 0, fn c, acc -> acc + Map.get(cw, c, 1) end) + ox
    y = Enum.reduce(0..(row - 1)//1, 0, fn r, acc -> acc + Map.get(rh, r, 1) end) + oy
    {x, y}
  end

  @doc "Convert grid coordinates to the center of the cell in draw coordinates."
  @spec grid_to_draw_center(t(), integer(), integer()) :: {integer(), integer()}
  def grid_to_draw_center(%__MODULE__{col_widths: cw, row_heights: rh} = layout, col, row) do
    {x, y} = grid_to_draw(layout, col, row)
    w = Map.get(cw, col, 1)
    h = Map.get(rh, row, 1)
    {x + div(w, 2), y + div(h, 2)}
  end

  @doc """
  Compute the grid layout for a graph.

  ## Options

    * `:padding_x` — horizontal padding inside nodes (default: `4`)
    * `:padding_y` — vertical padding inside nodes (default: `2`)
    * `:gap` — gap size between nodes in characters (default: `4`, minimum `1`)
  """
  @spec compute_layout(Graph.t(), keyword()) :: t()
  def compute_layout(graph, opts \\ [])
  def compute_layout(%Graph{node_order: []}, _opts), do: %__MODULE__{}

  def compute_layout(%Graph{} = graph, opts) do
    padding_x = Keyword.get(opts, :padding_x, 4)
    padding_y = Keyword.get(opts, :padding_y, 2)
    gap = max(Keyword.get(opts, :gap, 4), 1)

    direction = Graph.normalized(graph.direction)

    layers = Layers.assign_layers(graph)
    layers = Layers.separate_subgraph_layers(graph, layers)
    layer_order = Layers.order_layers(graph, layers)
    gap_expansions = Layers.compute_gap_expansions(graph, layer_order)

    layout = %__MODULE__{}

    layout =
      layout
      |> Placement.place_nodes(graph, layer_order, direction, gap_expansions)
      |> Placement.compute_sizes(graph, padding_x, padding_y, gap)
      |> Placement.normalize_sizes(graph)
      |> Subgraphs.expand_gaps_for_subgraphs(graph, direction)
      |> Coordinates.compute_draw_coords()
      |> Subgraphs.compute_subgraph_bounds(graph)
      |> Coordinates.adjust_for_negative_bounds()
      |> compute_canvas_size()

    layout
  end

  defp compute_canvas_size(%__MODULE__{placements: placements, subgraph_bounds: bounds} = layout) do
    {max_x, max_y} =
      placements
      |> Map.values()
      |> Enum.reduce({0, 0}, fn p, {mx, my} ->
        {max(mx, p.draw_x + p.draw_width), max(my, p.draw_y + p.draw_height)}
      end)

    {max_x, max_y} =
      Enum.reduce(bounds, {max_x, max_y}, fn sb, {mx, my} ->
        {max(mx, sb.x + sb.width), max(my, sb.y + sb.height)}
      end)

    %{layout | canvas_width: max_x, canvas_height: max_y}
  end
end
