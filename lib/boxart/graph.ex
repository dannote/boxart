defmodule Boxart.Graph do
  @moduledoc """
  Core graph data model for diagram rendering.

  Defines the primary data structures — `Graph`, `Node`, `Edge`, and `Subgraph` —
  along with direction, edge style, and node shape enumerations.
  """

  alias __MODULE__

  @directions [:tb, :td, :lr, :bt, :rl]
  @edge_styles [:solid, :dotted, :thick, :invisible]
  @arrow_types [:arrow, :circle, :cross]
  @node_shapes [
    :rectangle,
    :rounded,
    :stadium,
    :subroutine,
    :diamond,
    :hexagon,
    :circle,
    :double_circle,
    :asymmetric,
    :cylinder,
    :parallelogram,
    :parallelogram_alt,
    :trapezoid,
    :trapezoid_alt,
    :start_state,
    :end_state,
    :fork_join,
    :junction
  ]

  @type direction :: :tb | :td | :lr | :bt | :rl
  @type edge_style :: :solid | :dotted | :thick | :invisible
  @type arrow_type :: :arrow | :circle | :cross
  @type node_shape ::
          :rectangle
          | :rounded
          | :stadium
          | :subroutine
          | :diamond
          | :hexagon
          | :circle
          | :double_circle
          | :asymmetric
          | :cylinder
          | :parallelogram
          | :parallelogram_alt
          | :trapezoid
          | :trapezoid_alt
          | :start_state
          | :end_state
          | :fork_join
          | :junction

  defguard is_direction(d) when d in @directions
  defguard is_edge_style(s) when s in @edge_styles
  defguard is_arrow_type(t) when t in @arrow_types
  defguard is_node_shape(s) when s in @node_shapes

  # ── Direction helpers ─────────────────────────────────────────────

  @doc "Returns `true` if the direction flows vertically."
  @spec vertical?(direction()) :: boolean()
  def vertical?(dir) when dir in [:tb, :td, :bt], do: true
  def vertical?(_), do: false

  @doc "Returns `true` if the direction flows horizontally."
  @spec horizontal?(direction()) :: boolean()
  def horizontal?(dir) when dir in [:lr, :rl], do: true
  def horizontal?(_), do: false

  @doc "Returns `true` if the direction is reversed (bottom-to-top or right-to-left)."
  @spec reversed?(direction()) :: boolean()
  def reversed?(dir) when dir in [:bt, :rl], do: true
  def reversed?(_), do: false

  @doc "Normalizes a direction to its canonical form (`:bt` → `:tb`, `:rl` → `:lr`, `:td` → `:tb`)."
  @spec normalized(direction()) :: :tb | :lr
  def normalized(:bt), do: :tb
  def normalized(:rl), do: :lr
  def normalized(:td), do: :tb
  def normalized(dir) when dir in [:tb, :lr], do: dir

  # ── Node ──────────────────────────────────────────────────────────

  defmodule Node do
    @moduledoc "A node in the graph with an id, display label, and shape."

    @type t :: %__MODULE__{
            id: String.t(),
            label: String.t(),
            shape: Graph.node_shape()
          }

    @enforce_keys [:id]
    defstruct [:id, label: nil, shape: :rectangle]

    @doc "Creates a new node. Label defaults to the id when omitted."
    @spec new(String.t(), keyword()) :: t()
    def new(id, opts \\ []) do
      %__MODULE__{
        id: id,
        label: Keyword.get(opts, :label, id),
        shape: Keyword.get(opts, :shape, :rectangle)
      }
    end
  end

  # ── Edge ──────────────────────────────────────────────────────────

  defmodule Edge do
    @moduledoc "A directed edge connecting two nodes."

    @type t :: %__MODULE__{
            source: String.t(),
            target: String.t(),
            label: String.t(),
            style: Graph.edge_style(),
            has_arrow_start: boolean(),
            has_arrow_end: boolean(),
            arrow_type_start: Graph.arrow_type(),
            arrow_type_end: Graph.arrow_type(),
            min_length: pos_integer()
          }

    @enforce_keys [:source, :target]
    defstruct [
      :source,
      :target,
      label: "",
      style: :solid,
      has_arrow_start: false,
      has_arrow_end: true,
      arrow_type_start: :arrow,
      arrow_type_end: :arrow,
      min_length: 1
    ]

    @doc "Returns `true` when both ends have arrows."
    @spec bidirectional?(t()) :: boolean()
    def bidirectional?(%__MODULE__{has_arrow_start: true, has_arrow_end: true}), do: true
    def bidirectional?(_), do: false

    @doc "Returns `true` when source and target are the same node."
    @spec self_reference?(t()) :: boolean()
    def self_reference?(%__MODULE__{source: id, target: id}), do: true
    def self_reference?(_), do: false
  end

  # ── Subgraph ──────────────────────────────────────────────────────

  defmodule Subgraph do
    @moduledoc "A named group of nodes, optionally nested."

    @type t :: %__MODULE__{
            id: String.t(),
            label: String.t(),
            node_ids: [String.t()],
            children: [t()],
            direction: Graph.direction() | nil,
            parent: t() | nil
          }

    @enforce_keys [:id]
    defstruct [:id, :direction, :parent, label: "", node_ids: [], children: []]
  end

  # ── Graph ─────────────────────────────────────────────────────────

  @type t :: %__MODULE__{
          direction: direction(),
          nodes: %{String.t() => Node.t()},
          edges: [Edge.t()],
          node_order: [String.t()],
          subgraphs: [Subgraph.t()]
        }

  defstruct direction: :tb, nodes: %{}, edges: [], node_order: [], subgraphs: []

  @doc """
  Adds a node to the graph.

  If a node with the same id already exists, merges non-default fields
  from the new node into the existing one.
  """
  @spec add_node(t(), Node.t()) :: t()
  def add_node(%Graph{nodes: nodes, node_order: order} = graph, %Node{id: id} = node) do
    case Map.fetch(nodes, id) do
      :error ->
        %{graph | nodes: Map.put(nodes, id, node), node_order: order ++ [id]}

      {:ok, existing} ->
        merged = merge_node(existing, node)
        %{graph | nodes: Map.put(nodes, id, merged)}
    end
  end

  defp merge_node(existing, new) do
    label =
      if new.label != new.id and existing.label == existing.id,
        do: new.label,
        else: existing.label

    shape = if new.shape != :rectangle, do: new.shape, else: existing.shape
    %{existing | label: label, shape: shape}
  end

  @doc "Appends an edge to the graph."
  @spec add_edge(t(), Edge.t()) :: t()
  def add_edge(%Graph{edges: edges} = graph, %Edge{} = edge) do
    %{graph | edges: edges ++ [edge]}
  end

  @doc """
  Returns root node ids — nodes with no incoming edges, in definition order.

  Falls back to the first defined node when every node has incoming edges.
  """
  @spec get_roots(t()) :: [String.t()]
  def get_roots(%Graph{edges: edges, node_order: order}) do
    targets = MapSet.new(edges, & &1.target)
    roots = Enum.filter(order, &(&1 not in targets))

    case roots do
      [] -> Enum.take(order, 1)
      _ -> roots
    end
  end

  @doc "Returns ids of nodes reachable via outgoing edges from `node_id`, in edge order."
  @spec get_children(t(), String.t()) :: [String.t()]
  def get_children(%Graph{edges: edges}, node_id) do
    edges
    |> Enum.reduce({[], MapSet.new()}, fn
      %Edge{source: ^node_id, target: target}, {children, seen} when target != node_id ->
        if MapSet.member?(seen, target),
          do: {children, seen},
          else: {[target | children], MapSet.put(seen, target)}

      _edge, acc ->
        acc
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc "Finds a subgraph by its id, searching recursively through nested children."
  @spec find_subgraph_by_id(t(), String.t()) :: Subgraph.t() | nil
  def find_subgraph_by_id(%Graph{subgraphs: subgraphs}, sg_id) do
    search_subgraphs(subgraphs, &(&1.id == sg_id))
  end

  @doc "Finds the innermost subgraph containing `node_id`."
  @spec find_subgraph_for_node(t(), String.t()) :: Subgraph.t() | nil
  def find_subgraph_for_node(%Graph{subgraphs: subgraphs}, node_id) do
    search_subgraphs_deepest(subgraphs, node_id)
  end

  defp search_subgraphs([], _match_fn), do: nil

  defp search_subgraphs([sg | rest], match_fn) do
    if match_fn.(sg) do
      sg
    else
      search_subgraphs(sg.children, match_fn) || search_subgraphs(rest, match_fn)
    end
  end

  defp search_subgraphs_deepest([], _node_id), do: nil

  defp search_subgraphs_deepest([sg | rest], node_id) do
    case search_subgraphs_deepest(sg.children, node_id) do
      nil ->
        if node_id in sg.node_ids,
          do: sg,
          else: search_subgraphs_deepest(rest, node_id)

      found ->
        found
    end
  end
end
