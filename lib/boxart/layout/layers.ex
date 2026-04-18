defmodule Boxart.Layout.Layers do
  @moduledoc """
  Layer assignment and ordering for the layout engine.

  Assigns each node to a layer (depth from root) and orders nodes within
  each layer to minimize edge crossings using a barycenter heuristic.
  """

  alias Boxart.Graph

  @doc """
  Assign each node to a layer based on longest path from a root.

  Back-edges (edges that would create cycles) are excluded from
  layer computation to prevent infinite loops and excessive layers.
  """
  @spec assign_layers(Graph.t()) :: %{String.t() => non_neg_integer()}
  def assign_layers(%Graph{} = graph) do
    roots = Graph.get_roots(graph)
    initial_layers = Map.new(roots, &{&1, 0})

    tree_edges = discover_tree_edges(graph, roots)
    edge_min_lengths = build_edge_min_lengths(graph)

    layers =
      initial_layers
      |> propagate_layers(tree_edges, edge_min_lengths, length(graph.node_order) * 2)
      |> assign_unplaced(graph.node_order)

    ortho_sets = get_orthogonal_sg_nodes(graph)

    if ortho_sets == [] do
      layers
    else
      collapse_orthogonal_layers(layers, graph, tree_edges, edge_min_lengths, ortho_sets)
    end
  end

  @doc """
  Fix overlapping subgraph layer ranges.

  When cross-boundary edges cause nodes from different subgraphs to land
  on the same layer, the subgraph boxes overlap visually. Reassigns layers
  so each subgraph occupies a contiguous, non-overlapping range.
  """
  @spec separate_subgraph_layers(Graph.t(), %{String.t() => non_neg_integer()}) ::
          %{String.t() => non_neg_integer()}
  def separate_subgraph_layers(%Graph{subgraphs: []}, layers), do: layers

  def separate_subgraph_layers(%Graph{} = graph, layers) do
    node_sg = build_node_sg_map(graph)
    sg_ranges = compute_sg_ranges(layers, node_sg)

    if map_size(sg_ranges) < 2 or not has_overlap?(sg_ranges) do
      layers
    else
      do_separate_subgraph_layers(graph, layers, node_sg, sg_ranges)
    end
  end

  @doc """
  Order nodes within each layer using barycenter heuristic for crossing minimization.
  """
  @spec order_layers(Graph.t(), %{String.t() => non_neg_integer()}) :: [[String.t()]]
  def order_layers(%Graph{} = graph, layers) do
    max_layer = layers |> Map.values() |> Enum.max(fn -> 0 end)

    layer_lists =
      Enum.map(0..max_layer, fn layer_idx ->
        graph.node_order |> Enum.filter(&(Map.get(layers, &1, 0) == layer_idx))
      end)

    best = barycenter_ordering(graph, layer_lists, 8)

    ortho_sets = get_orthogonal_sg_nodes(graph)

    if ortho_sets == [] do
      best
    else
      enforce_topo_order_in_layers(graph, best, ortho_sets)
    end
  end

  @doc """
  Compute extra grid cells needed between adjacent layers for crossing edges.

  Returns a map of gap index (between layer `i` and `i+1`) to the number of
  extra grid cells to insert.
  """
  @spec compute_gap_expansions(Graph.t(), [[String.t()]]) :: %{
          non_neg_integer() => non_neg_integer()
        }
  def compute_gap_expansions(%Graph{} = graph, layer_order) do
    {node_layer, node_pos} = build_layer_pos_lookup(layer_order)

    graph.edges
    |> Enum.reject(&Boxart.Graph.Edge.self_reference?(&1))
    |> Enum.reduce(%{}, fn edge, acc ->
      with src_layer when is_integer(src_layer) <- Map.get(node_layer, edge.source),
           tgt_layer when is_integer(tgt_layer) <- Map.get(node_layer, edge.target),
           src_p when is_integer(src_p) <- Map.get(node_pos, edge.source),
           tgt_p when is_integer(tgt_p) <- Map.get(node_pos, edge.target),
           true <- src_p != tgt_p do
        lo = min(src_layer, tgt_layer)
        hi = max(src_layer, tgt_layer)

        Enum.reduce(lo..(hi - 1)//1, acc, fn gap_idx, acc2 ->
          Map.update(acc2, gap_idx, 1, &(&1 + 1))
        end)
      else
        _ -> acc
      end
    end)
    |> Map.new(fn {gap, n} -> {gap, max(0, n - 1)} end)
    |> Enum.reject(fn {_gap, extra} -> extra == 0 end)
    |> Map.new()
  end

  # --- Private helpers ---

  defp discover_tree_edges(%Graph{} = graph, roots) do
    {_visited, tree_edges} =
      roots
      |> Enum.reduce({MapSet.new(), MapSet.new()}, fn root, {visited, edges} ->
        if MapSet.member?(visited, root) do
          {visited, edges}
        else
          bfs_tree_edges(graph, root, visited, edges)
        end
      end)

    graph.node_order
    |> Enum.reduce({MapSet.new(roots), tree_edges}, fn nid, {visited, edges} ->
      if MapSet.member?(visited, nid) do
        {visited, edges}
      else
        bfs_tree_edges(graph, nid, visited, edges)
      end
    end)
    |> elem(1)
  end

  defp bfs_tree_edges(graph, start, visited, edges) do
    visited = MapSet.put(visited, start)
    queue = :queue.from_list([start])
    do_bfs_tree(graph, queue, visited, edges)
  end

  defp do_bfs_tree(graph, queue, visited, edges) do
    case :queue.out(queue) do
      {:empty, _} ->
        {visited, edges}

      {{:value, node}, queue} ->
        children = Graph.get_children(graph, node)

        {visited, edges, queue} =
          Enum.reduce(children, {visited, edges, queue}, fn child, {v, e, q} ->
            if MapSet.member?(v, child) do
              {v, e, q}
            else
              v = MapSet.put(v, child)
              e = MapSet.put(e, {node, child})
              q = :queue.in(child, q)
              {v, e, q}
            end
          end)

        do_bfs_tree(graph, queue, visited, edges)
    end
  end

  defp build_edge_min_lengths(%Graph{edges: edges}) do
    Enum.reduce(edges, %{}, fn e, acc ->
      key = {e.source, e.target}
      Map.update(acc, key, e.min_length, &max(&1, e.min_length))
    end)
  end

  defp propagate_layers(layers, tree_edges, edge_min_lengths, max_iter) do
    do_propagate(layers, tree_edges, edge_min_lengths, max_iter, true)
  end

  defp do_propagate(layers, _tree_edges, _edge_min_lengths, 0, _changed), do: layers
  defp do_propagate(layers, _tree_edges, _edge_min_lengths, _remaining, false), do: layers

  defp do_propagate(layers, tree_edges, edge_min_lengths, remaining, true) do
    {layers, changed} =
      Enum.reduce(tree_edges, {layers, false}, fn {src, tgt}, {l, changed} ->
        case Map.get(l, src) do
          nil ->
            {l, changed}

          src_layer ->
            ml = Map.get(edge_min_lengths, {src, tgt}, 1)
            new_layer = src_layer + ml

            if not Map.has_key?(l, tgt) or l[tgt] < new_layer do
              {Map.put(l, tgt, new_layer), true}
            else
              {l, changed}
            end
        end
      end)

    do_propagate(layers, tree_edges, edge_min_lengths, remaining - 1, changed)
  end

  defp assign_unplaced(layers, node_order) do
    Enum.reduce(node_order, layers, fn nid, acc ->
      Map.put_new(acc, nid, 0)
    end)
  end

  defp collapse_orthogonal_layers(layers, graph, tree_edges, edge_min_lengths, ortho_sets) do
    all_ortho =
      ortho_sets
      |> Enum.reduce(MapSet.new(), fn set, acc -> MapSet.union(acc, set) end)

    layers =
      Enum.reduce(ortho_sets, layers, fn sg_nodes, acc ->
        present = Enum.filter(sg_nodes, &Map.has_key?(acc, &1))

        if present == [] do
          acc
        else
          min_layer = present |> Enum.map(&Map.fetch!(acc, &1)) |> Enum.min()
          Enum.reduce(present, acc, &Map.put(&2, &1, min_layer))
        end
      end)

    layers =
      graph.node_order
      |> Enum.reject(&MapSet.member?(all_ortho, &1))
      |> Enum.reduce(layers, fn nid, acc -> Map.delete(acc, nid) end)

    roots = Graph.get_roots(graph)

    layers =
      Enum.reduce(roots, layers, fn root, acc ->
        Map.put_new(acc, root, 0)
      end)

    non_ortho_tree_edges =
      MapSet.reject(tree_edges, fn {_src, tgt} -> MapSet.member?(all_ortho, tgt) end)

    layers
    |> propagate_layers(non_ortho_tree_edges, edge_min_lengths, length(graph.node_order) * 2)
    |> assign_unplaced(graph.node_order)
  end

  defp build_node_sg_map(%Graph{subgraphs: subgraphs}) do
    map_subgraphs(subgraphs, %{})
  end

  defp map_subgraphs([], acc), do: acc

  defp map_subgraphs([sg | rest], acc) do
    acc = map_subgraphs(sg.children, acc)
    acc = Enum.reduce(sg.node_ids, acc, &Map.put(&2, &1, sg.id))
    map_subgraphs(rest, acc)
  end

  defp compute_sg_ranges(layers, node_sg) do
    Enum.reduce(layers, %{}, fn {nid, layer}, acc ->
      case Map.get(node_sg, nid) do
        nil ->
          acc

        sg_id ->
          Map.update(acc, sg_id, {layer, layer}, fn {lo, hi} ->
            {min(lo, layer), max(hi, layer)}
          end)
      end
    end)
  end

  defp has_overlap?(sg_ranges) do
    ranges = Map.values(sg_ranges)

    ranges
    |> Enum.with_index()
    |> Enum.any?(fn {{lo1, hi1}, i} ->
      ranges
      |> Enum.with_index()
      |> Enum.any?(fn {{lo2, hi2}, j} ->
        j > i and lo1 <= hi2 and lo2 <= hi1
      end)
    end)
  end

  defp do_separate_subgraph_layers(graph, layers, node_sg, _sg_ranges) do
    sg_ids = node_sg |> Map.values() |> Enum.uniq()
    {sg_succs, sg_in_deg} = build_sg_dag(graph, node_sg, sg_ids)
    topo = topological_sort(sg_ids, sg_succs, sg_in_deg)

    if length(topo) != length(sg_ids) do
      layers
    else
      do_reassign_layers(graph, layers, node_sg, topo)
    end
  end

  defp build_sg_dag(graph, node_sg, sg_ids) do
    initial_succs = Map.new(sg_ids, &{&1, MapSet.new()})
    initial_deg = Map.new(sg_ids, &{&1, 0})

    Enum.reduce(graph.edges, {initial_succs, initial_deg}, fn edge, {succs, deg} ->
      s_sg = Map.get(node_sg, edge.source)
      t_sg = Map.get(node_sg, edge.target)

      if s_sg && t_sg && s_sg != t_sg && Map.has_key?(succs, s_sg) do
        if MapSet.member?(succs[s_sg], t_sg) do
          {succs, deg}
        else
          {Map.update!(succs, s_sg, &MapSet.put(&1, t_sg)), Map.update!(deg, t_sg, &(&1 + 1))}
        end
      else
        {succs, deg}
      end
    end)
  end

  defp topological_sort(sg_ids, succs, in_deg) do
    queue = Enum.filter(sg_ids, &(in_deg[&1] == 0))
    do_topo_sort(queue, succs, in_deg, [])
  end

  defp do_topo_sort([], _succs, _in_deg, result), do: Enum.reverse(result)

  defp do_topo_sort([node | rest], succs, in_deg, result) do
    {new_queue, in_deg} =
      Enum.reduce(succs[node], {rest, in_deg}, fn succ, {q, d} ->
        d = Map.update!(d, succ, &(&1 - 1))

        if d[succ] == 0 do
          {q ++ [succ], d}
        else
          {q, d}
        end
      end)

    do_topo_sort(new_queue, succs, in_deg, [node | result])
  end

  defp do_reassign_layers(graph, layers, node_sg, topo) do
    {sg_internal, sg_sizes} = compute_internal_layers(graph, node_sg, topo)

    non_sg_layers =
      layers
      |> Enum.reject(fn {nid, _l} -> Map.has_key?(node_sg, nid) end)
      |> Enum.map(&elem(&1, 1))

    first_sg_min =
      case Map.get(compute_sg_ranges(layers, node_sg), hd(topo)) do
        {lo, _hi} -> lo
        nil -> 0
      end

    non_sg_above = Enum.filter(non_sg_layers, &(&1 < first_sg_min))
    initial_offset = if non_sg_above == [], do: 0, else: Enum.max(non_sg_above) + 1

    {sg_offsets, _offset} =
      Enum.reduce(topo, {%{}, initial_offset}, fn sg_id, {offsets, offset} ->
        {Map.put(offsets, sg_id, offset), offset + Map.get(sg_sizes, sg_id, 0)}
      end)

    new_layers =
      Enum.reduce(sg_internal, layers, fn {sg_id, int_layers}, acc ->
        Enum.reduce(int_layers, acc, fn {nid, rel}, acc2 ->
          Map.put(acc2, nid, sg_offsets[sg_id] + rel)
        end)
      end)

    non_sg_nodes = Enum.reject(graph.node_order, &Map.has_key?(node_sg, &1))

    Enum.reduce(non_sg_nodes, new_layers, fn nid, acc ->
      best =
        graph.edges
        |> Enum.filter(&(&1.target == nid and Map.has_key?(acc, &1.source)))
        |> Enum.map(&acc[&1.source])
        |> Enum.max(fn -> -1 end)

      if best >= 0, do: Map.put(acc, nid, best + 1), else: acc
    end)
  end

  defp compute_internal_layers(graph, node_sg, topo) do
    Enum.reduce(topo, {%{}, %{}}, fn sg_id, {internals, sizes} ->
      sg_nodes = for {nid, sid} <- node_sg, sid == sg_id, do: nid, into: MapSet.new()

      int_edges =
        graph.edges
        |> Enum.filter(
          &(MapSet.member?(sg_nodes, &1.source) and MapSet.member?(sg_nodes, &1.target))
        )
        |> Enum.reject(&Boxart.Graph.Edge.self_reference?(&1))

      int_targets = MapSet.new(int_edges, & &1.target)

      int_roots =
        case Enum.reject(sg_nodes, &MapSet.member?(int_targets, &1)) do
          [] -> [sg_nodes |> Enum.to_list() |> hd()]
          roots -> roots
        end

      int_layers = Map.new(int_roots, &{&1, 0})

      int_layers =
        do_internal_propagate(int_layers, int_edges, MapSet.size(sg_nodes) * 2 + 1, true)

      int_layers = Enum.reduce(sg_nodes, int_layers, fn nid, acc -> Map.put_new(acc, nid, 0) end)

      size =
        if map_size(int_layers) > 0 do
          (int_layers |> Map.values() |> Enum.max()) + 1
        else
          0
        end

      {Map.put(internals, sg_id, int_layers), Map.put(sizes, sg_id, size)}
    end)
  end

  defp do_internal_propagate(layers, _edges, 0, _changed), do: layers
  defp do_internal_propagate(layers, _edges, _remaining, false), do: layers

  defp do_internal_propagate(layers, edges, remaining, true) do
    {layers, changed} =
      Enum.reduce(edges, {layers, false}, fn edge, {l, changed} ->
        case Map.get(l, edge.source) do
          nil ->
            {l, changed}

          src_layer ->
            new_layer = src_layer + 1

            if not Map.has_key?(l, edge.target) or l[edge.target] < new_layer do
              {Map.put(l, edge.target, new_layer), true}
            else
              {l, changed}
            end
        end
      end)

    do_internal_propagate(layers, edges, remaining - 1, changed)
  end

  defp count_crossings(graph, layer_lists) do
    layer_lists
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn [prev_layer, cur_layer], total ->
      prev_pos = prev_layer |> Enum.with_index() |> Map.new()
      cur_pos = cur_layer |> Enum.with_index() |> Map.new()

      edges_between =
        graph.edges
        |> Enum.flat_map(fn edge ->
          with u when is_integer(u) <- Map.get(prev_pos, edge.source),
               v when is_integer(v) <- Map.get(cur_pos, edge.target) do
            [{u, v}]
          else
            _ -> []
          end
        end)

      crossings =
        for {pair1, i} <- Enum.with_index(edges_between),
            {pair2, j} <- Enum.with_index(edges_between),
            j > i,
            {u1, v1} = pair1,
            {u2, v2} = pair2,
            (u1 - u2) * (v1 - v2) < 0,
            reduce: 0 do
          acc -> acc + 1
        end

      total + crossings
    end)
  end

  defp barycenter_ordering(graph, layer_lists, max_passes) do
    best_crossings = count_crossings(graph, layer_lists)
    do_barycenter(graph, layer_lists, layer_lists, best_crossings, max_passes, 0)
  end

  defp do_barycenter(_graph, _current, best, _best_crossings, _max, no_imp) when no_imp >= 4,
    do: best

  defp do_barycenter(_graph, _current, best, 0, _max, _no_imp), do: best
  defp do_barycenter(_graph, _current, best, _best_crossings, 0, _no_imp), do: best

  defp do_barycenter(graph, current, best, best_crossings, passes_left, no_imp) do
    current =
      Enum.reduce(1..(length(current) - 1)//1, current, fn layer_idx, lists ->
        prev_positions = lists |> Enum.at(layer_idx - 1) |> Enum.with_index() |> Map.new()
        layer = Enum.at(lists, layer_idx)

        barycenters =
          layer
          |> Enum.with_index()
          |> Map.new(fn {nid, original_pos} ->
            pred_positions =
              graph.edges
              |> Enum.flat_map(fn edge ->
                if edge.target == nid do
                  case Map.get(prev_positions, edge.source) do
                    nil -> []
                    pos -> [pos]
                  end
                else
                  []
                end
              end)

            bc =
              if pred_positions != [] do
                Enum.sum(pred_positions) / length(pred_positions)
              else
                original_pos * 1.0
              end

            {nid, bc}
          end)

        sorted = Enum.sort_by(layer, &Map.get(barycenters, &1, 0))
        List.replace_at(lists, layer_idx, sorted)
      end)

    crossings = count_crossings(graph, current)

    if crossings < best_crossings do
      do_barycenter(graph, current, current, crossings, passes_left - 1, 0)
    else
      do_barycenter(graph, current, best, best_crossings, passes_left - 1, no_imp + 1)
    end
  end

  defp enforce_topo_order_in_layers(graph, layer_lists, ortho_sets) do
    Enum.map(layer_lists, fn layer ->
      Enum.reduce(ortho_sets, layer, fn sg_nodes, layer_acc ->
        in_layer = Enum.filter(layer_acc, &MapSet.member?(sg_nodes, &1))

        if length(in_layer) <= 1 do
          layer_acc
        else
          topo = topo_sort_within(graph, MapSet.new(in_layer), in_layer)

          positions =
            layer_acc
            |> Enum.with_index()
            |> Enum.flat_map(fn {n, i} ->
              if MapSet.member?(sg_nodes, n), do: [i], else: []
            end)

          Enum.zip(positions, topo)
          |> Enum.reduce(layer_acc, fn {pos, nid}, acc -> List.replace_at(acc, pos, nid) end)
        end
      end)
    end)
  end

  defp topo_sort_within(graph, internal, ordered) do
    successors =
      Map.new(internal, fn n ->
        succs =
          graph.edges
          |> Enum.filter(&(&1.source == n and MapSet.member?(internal, &1.target)))
          |> Enum.map(& &1.target)

        {n, succs}
      end)

    in_degree =
      Map.new(internal, fn n ->
        deg =
          graph.edges
          |> Enum.count(&(&1.target == n and MapSet.member?(internal, &1.source)))

        {n, deg}
      end)

    queue = Enum.filter(ordered, &(in_degree[&1] == 0))
    do_kahn(queue, successors, in_degree, [])
  end

  defp do_kahn([], _succs, _deg, result), do: Enum.reverse(result)

  defp do_kahn([node | rest], succs, deg, result) do
    {new_queue, deg} =
      Enum.reduce(succs[node], {rest, deg}, fn s, {q, d} ->
        d = Map.update!(d, s, &(&1 - 1))
        if d[s] == 0, do: {q ++ [s], d}, else: {q, d}
      end)

    do_kahn(new_queue, succs, deg, [node | result])
  end

  defp build_layer_pos_lookup(layer_order) do
    layer_order
    |> Enum.with_index()
    |> Enum.reduce({%{}, %{}}, fn {nodes, layer_idx}, {layer_map, pos_map} ->
      {layer_map, pos_map} =
        nodes
        |> Enum.with_index()
        |> Enum.reduce({layer_map, pos_map}, fn {nid, pos_idx}, {lm, pm} ->
          {Map.put(lm, nid, layer_idx), Map.put(pm, nid, pos_idx)}
        end)

      {layer_map, pos_map}
    end)
  end

  @doc false
  def get_orthogonal_sg_nodes(%Graph{} = graph) do
    graph_vertical = Graph.vertical?(Graph.normalized(graph.direction))
    walk_orthogonal(graph.subgraphs, graph_vertical, [])
  end

  defp walk_orthogonal([], _graph_vertical, acc), do: acc

  defp walk_orthogonal([sg | rest], graph_vertical, acc) do
    acc = walk_orthogonal(sg.children, graph_vertical, acc)

    acc =
      if sg.direction != nil do
        sg_vertical = Graph.vertical?(Graph.normalized(sg.direction))

        if sg_vertical != graph_vertical do
          [MapSet.new(sg.node_ids) | acc]
        else
          acc
        end
      else
        acc
      end

    walk_orthogonal(rest, graph_vertical, acc)
  end
end
