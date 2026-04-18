defmodule Boxart.Graph do
  @moduledoc """
  Internal graph representation for the rendering pipeline.

  Users should build graphs with `Graph` from libgraph and pass them to
  `Boxart.render/2`. This module handles the conversion via `from_libgraph/2`.
  """

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
            label: String.t() | nil,
            shape: Boxart.Graph.node_shape(),
            source: String.t() | nil,
            start_line: integer(),
            language: atom() | nil
          }

    @enforce_keys [:id]
    defstruct [:id, :source, :language, label: nil, shape: :rectangle, start_line: 1]

    @doc "Creates a new node. Label defaults to the id when omitted."
    @spec new(String.t(), keyword()) :: t()
    def new(id, opts \\ []) do
      %__MODULE__{
        id: id,
        label: Keyword.get(opts, :label, id),
        shape: Keyword.get(opts, :shape, :rectangle),
        source: Keyword.get(opts, :source),
        start_line: Keyword.get(opts, :start_line, 1),
        language: Keyword.get(opts, :language)
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
            style: Boxart.Graph.edge_style(),
            has_arrow_start: boolean(),
            has_arrow_end: boolean(),
            arrow_type_start: Boxart.Graph.arrow_type(),
            arrow_type_end: Boxart.Graph.arrow_type(),
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
            direction: Boxart.Graph.direction() | nil,
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
  Converts a libgraph `Graph.t()` into the internal representation.

  Vertex labels are keyword lists. Recognized keys:

    * `:label` — display text (defaults to `inspect(vertex)`)
    * `:shape` — node shape atom (default: `:rectangle`)
    * `:source` — raw source code string (renders as a code block instead of label)
    * `:start_line` — starting line number for code display (default: `1`)
    * `:language` — language atom for syntax highlighting (e.g. `:elixir`)

  Edge labels become the display text on the edge.

  ## Options

    * `:direction` — layout direction (default: `:td`)
  """
  @spec from_libgraph(Graph.t(), keyword()) :: t()
  def from_libgraph(%Graph{} = libgraph, opts \\ []) do
    direction = Keyword.get(opts, :direction, :td)
    vertices = Graph.vertices(libgraph)

    nodes =
      Map.new(vertices, fn v ->
        id = to_id(v)
        labels = Graph.vertex_labels(libgraph, v)
        label = label_from_vertex(v, labels)
        shape = shape_from_labels(labels)
        source = find_label_value(labels, :source)
        start_line = find_label_value(labels, :start_line) || 1
        language = find_label_value(labels, :language)

        {id,
         %Node{
           id: id,
           label: label,
           shape: shape,
           source: source,
           start_line: start_line,
           language: language
         }}
      end)

    node_order =
      case Graph.topsort(libgraph) do
        false -> source_biased_order(libgraph, vertices)
        sorted -> Enum.map(sorted, &to_id/1)
      end

    order_index = node_order |> Enum.with_index() |> Map.new()

    edges =
      Graph.edges(libgraph)
      |> Enum.map(fn %Graph.Edge{v1: v1, v2: v2, label: edge_lbl} ->
        build_edge(v1, v2, edge_lbl)
      end)
      |> Enum.sort_by(fn e ->
        si = Map.get(order_index, e.source, :infinity)
        ti = Map.get(order_index, e.target, :infinity)
        {si, ti}
      end)

    %__MODULE__{
      direction: direction,
      nodes: nodes,
      edges: edges,
      node_order: node_order
    }
  end

  defp source_biased_order(libgraph, vertices) do
    edges = Graph.edges(libgraph)

    {in_deg, out_deg} =
      Enum.reduce(edges, {%{}, %{}}, fn e, {ind, outd} ->
        {Map.update(ind, e.v2, 1, &(&1 + 1)), Map.update(outd, e.v1, 1, &(&1 + 1))}
      end)

    vertices
    |> Enum.sort_by(fn v ->
      {Map.get(in_deg, v, 0) - Map.get(out_deg, v, 0), to_id(v)}
    end)
    |> Enum.map(&to_id/1)
  end

  defp build_edge(v1, v2, label) when is_list(label) do
    bidirectional = Keyword.get(label, :bidirectional, false)
    has_arrow = Keyword.get(label, :arrow, true)

    %Edge{
      source: to_id(v1),
      target: to_id(v2),
      label: edge_label(Keyword.get(label, :label) || Keyword.get(label, :text, "")),
      style: Keyword.get(label, :style, :solid),
      has_arrow_start: bidirectional,
      has_arrow_end: has_arrow == true,
      arrow_type_start: arrow_type_from(Keyword.get(label, :arrow_type, :arrow)),
      arrow_type_end: arrow_type_from(Keyword.get(label, :arrow_type, :arrow)),
      min_length: Keyword.get(label, :min_length, 1)
    }
  end

  defp build_edge(v1, v2, label) do
    %Edge{
      source: to_id(v1),
      target: to_id(v2),
      label: edge_label(label)
    }
  end

  defp arrow_type_from(t) when t in [:arrow, :circle, :cross], do: t
  defp arrow_type_from(nil), do: :arrow

  defp arrow_type_from(t),
    do:
      raise(
        ArgumentError,
        "invalid arrow_type: #{inspect(t)}, expected :arrow, :circle, or :cross"
      )

  defp to_id(v) when is_binary(v), do: v
  defp to_id(v) when is_atom(v), do: Atom.to_string(v)
  defp to_id(v), do: inspect(v)

  defp label_from_vertex(vertex, labels) do
    case find_label_value(labels, :label) do
      nil -> to_id(vertex)
      val -> to_string(val)
    end
  end

  defp shape_from_labels(labels) do
    case find_label_value(labels, :shape) do
      nil -> :rectangle
      shape when is_atom(shape) -> shape
      _ -> :rectangle
    end
  end

  defp find_label_value(labels, key) do
    Enum.find_value(labels, fn
      {^key, val} -> val
      kw when is_list(kw) -> Keyword.get(kw, key)
      _ -> nil
    end)
  end

  defp edge_label(nil), do: ""
  defp edge_label(label) when is_binary(label), do: label
  defp edge_label(label), do: inspect(label)

  @doc """
  Adds a node to the graph.

  If a node with the same id already exists, merges non-default fields
  from the new node into the existing one.
  """
  @spec add_node(t(), Node.t()) :: t()
  def add_node(%__MODULE__{nodes: nodes, node_order: order} = graph, %Node{id: id} = node) do
    case Map.fetch(nodes, id) do
      :error ->
        # O(n) append is fine — from_libgraph builds the whole graph at once via Map.new/Enum.map,
        # so add_node is rarely called in hot loops.
        %{graph | nodes: Map.put(nodes, id, node), node_order: order ++ [id]}

      {:ok, existing} ->
        merged = merge_node(existing, node)
        %{graph | nodes: Map.put(nodes, id, merged)}
    end
  end

  # Label detection heuristic: if new.label == new.id, it's the default
  # (user didn't specify a label). This can't distinguish a user-provided
  # label that happens to equal the id — a known libgraph limitation.
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
  def add_edge(%__MODULE__{edges: edges} = graph, %Edge{} = edge) do
    # O(n) append is fine — from_libgraph builds the whole graph at once via Enum.map,
    # so add_edge is rarely called in hot loops.
    %{graph | edges: edges ++ [edge]}
  end

  @doc "Returns a copy of the graph with the given direction."
  @spec with_direction(t(), direction()) :: t()
  def with_direction(%__MODULE__{} = graph, direction), do: %{graph | direction: direction}

  @doc """
  Returns root node ids — nodes with no incoming edges, in definition order.

  Falls back to the first defined node when every node has incoming edges.
  """
  @spec get_roots(t()) :: [String.t()]
  def get_roots(%__MODULE__{edges: edges, node_order: order}) do
    targets = MapSet.new(edges, & &1.target)
    roots = Enum.filter(order, &(&1 not in targets))

    case roots do
      [] -> [best_root_candidate(edges, order)]
      _ -> roots
    end
  end

  defp best_root_candidate(edges, order) do
    out_degree =
      Enum.reduce(edges, %{}, fn e, acc ->
        Map.update(acc, e.source, 1, &(&1 + 1))
      end)

    Enum.max_by(order, &Map.get(out_degree, &1, 0))
  end

  @doc "Returns ids of nodes reachable via outgoing edges from `node_id`, in edge order."
  @spec get_children(t(), String.t()) :: [String.t()]
  def get_children(%__MODULE__{edges: edges}, node_id) do
    edges
    |> Enum.filter(&(&1.source == node_id and &1.target != node_id))
    |> Enum.map(& &1.target)
    |> Enum.uniq()
  end

  @doc "Finds a subgraph by its id, searching recursively through nested children."
  @spec find_subgraph_by_id(t(), String.t()) :: Subgraph.t() | nil
  def find_subgraph_by_id(%__MODULE__{subgraphs: subgraphs}, sg_id) do
    search_subgraphs(subgraphs, &(&1.id == sg_id))
  end

  @doc "Finds the innermost subgraph containing `node_id`."
  @spec find_subgraph_for_node(t(), String.t()) :: Subgraph.t() | nil
  def find_subgraph_for_node(%__MODULE__{subgraphs: subgraphs}, node_id) do
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
