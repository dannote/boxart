defmodule Boxart.Layout.Subgraphs do
  @moduledoc """
  Subgraph layout handling for the layout engine.

  Manages gap expansion for subgraph borders and labels,
  and computes subgraph bounding boxes after node placement.
  """

  alias Boxart.Graph
  alias Boxart.Layout
  alias Boxart.Layout.SubgraphBounds

  @sg_border_pad Layout.sg_border_pad()
  @sg_label_height Layout.sg_label_height()
  @sg_gap_per_level Layout.sg_gap_per_level()

  @doc """
  Expand gap cells to accommodate subgraph borders, labels, and nesting.

  Analyzes nesting depth changes between adjacent layers and sibling subgraph
  transitions in both flow and cross directions, inserting extra space as needed.
  """
  @spec expand_gaps_for_subgraphs(Layout.t(), Graph.t(), atom()) :: Layout.t()
  def expand_gaps_for_subgraphs(%Layout{} = layout, %Graph{subgraphs: []} = _graph, _direction),
    do: layout

  def expand_gaps_for_subgraphs(%Layout{} = layout, %Graph{} = graph, direction) do
    vertical = Graph.vertical?(direction)
    node_depths = compute_node_depths(graph)

    {flow_groups, cross_groups} = group_by_axes(layout, vertical)

    layout
    |> expand_flow_gaps(graph, flow_groups, node_depths, vertical)
    |> expand_cross_gaps(graph, cross_groups, vertical)
  end

  @doc """
  Compute bounding boxes for all subgraphs after node placement.

  Recursively processes nested subgraphs from innermost to outermost,
  computing bounds that encompass all contained nodes and child subgraph bounds.
  """
  @spec compute_subgraph_bounds(Layout.t(), Graph.t()) :: Layout.t()
  def compute_subgraph_bounds(%Layout{} = layout, %Graph{subgraphs: []} = _graph), do: layout

  def compute_subgraph_bounds(%Layout{} = layout, %Graph{} = graph) do
    {bounds, _} =
      Enum.reduce(graph.subgraphs, {[], layout}, fn sg, {acc_bounds, l} ->
        {new_bounds, l} = compute_sg_bounds(sg, graph, l)
        {acc_bounds ++ new_bounds, l}
      end)

    %{layout | subgraph_bounds: bounds}
  end

  # --- Private helpers ---

  defp compute_node_depths(graph) do
    Map.new(graph.node_order, fn nid ->
      {nid, node_depth(graph, nid)}
    end)
  end

  defp node_depth(graph, nid) do
    case Graph.find_subgraph_for_node(graph, nid) do
      nil -> 0
      sg -> count_ancestors(sg, 1)
    end
  end

  defp count_ancestors(%{parent: nil}, depth), do: depth
  defp count_ancestors(%{parent: parent}, depth), do: count_ancestors(parent, depth + 1)

  defp group_by_axes(layout, vertical) do
    Enum.reduce(layout.placements, {%{}, %{}}, fn {nid, p}, {flow, cross} ->
      flow_pos = if vertical, do: p.grid.row, else: p.grid.col
      cross_pos = if vertical, do: p.grid.col, else: p.grid.row

      flow = Map.update(flow, flow_pos, [nid], &[nid | &1])
      cross = Map.update(cross, cross_pos, [nid], &[nid | &1])
      {flow, cross}
    end)
  end

  defp expand_flow_gaps(layout, graph, flow_groups, node_depths, vertical) do
    sorted_flow = flow_groups |> Map.keys() |> Enum.sort()

    sorted_flow
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(
      layout,
      &expand_flow_gap_pair(&1, &2, graph, flow_groups, node_depths, vertical)
    )
  end

  defp expand_flow_gap_pair([pos1, pos2], layout, graph, flow_groups, node_depths, vertical) do
    nodes1 = Map.get(flow_groups, pos1, [])
    nodes2 = Map.get(flow_groups, pos2, [])

    depth_change = compute_depth_change(graph, nodes1, nodes2, node_depths)

    if depth_change > 0 do
      extra = depth_change * @sg_gap_per_level
      expand_gap_cells(layout, pos1 + 2, pos2 - 2, extra, vertical)
    else
      layout
    end
  end

  defp compute_depth_change(graph, nodes1, nodes2, node_depths) do
    min_depth1 = nodes1 |> Enum.map(&Map.get(node_depths, &1, 0)) |> Enum.min(fn -> 0 end)
    max_depth2 = nodes2 |> Enum.map(&Map.get(node_depths, &1, 0)) |> Enum.max(fn -> 0 end)
    entering = max(0, max_depth2 - min_depth1)

    min_depth2 = nodes2 |> Enum.map(&Map.get(node_depths, &1, 0)) |> Enum.min(fn -> 0 end)
    max_depth1 = nodes1 |> Enum.map(&Map.get(node_depths, &1, 0)) |> Enum.max(fn -> 0 end)
    exiting = max(0, max_depth1 - min_depth2)

    depth_change = max(entering, exiting)

    if depth_change == 0 do
      check_sibling_transition(graph, nodes1, nodes2)
    else
      depth_change
    end
  end

  defp check_sibling_transition(graph, nodes1, nodes2) do
    sg_ids1 = nodes_to_sg_ids(graph, nodes1)
    sg_ids2 = nodes_to_sg_ids(graph, nodes2)

    if MapSet.size(sg_ids1) > 0 and MapSet.size(sg_ids2) > 0 and
         not MapSet.equal?(sg_ids1, sg_ids2) do
      2
    else
      0
    end
  end

  defp nodes_to_sg_ids(graph, nodes) do
    nodes
    |> Enum.map(&Graph.find_subgraph_for_node(graph, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp expand_cross_gaps(layout, graph, cross_groups, vertical) do
    sorted_cross = cross_groups |> Map.keys() |> Enum.sort()

    sorted_cross
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(layout, &expand_cross_gap_pair(&1, &2, graph, cross_groups, vertical))
  end

  defp expand_cross_gap_pair([pos1, pos2], layout, graph, cross_groups, vertical) do
    nodes1 = Map.get(cross_groups, pos1, [])
    nodes2 = Map.get(cross_groups, pos2, [])

    inner1 = nodes_to_sg_ids(graph, nodes1)
    inner2 = nodes_to_sg_ids(graph, nodes2)

    if (MapSet.size(inner1) > 0 or MapSet.size(inner2) > 0) and
         not MapSet.equal?(inner1, inner2) do
      expand_gap_cells(layout, pos1 + 2, pos2 - 2, 8, not vertical)
    else
      layout
    end
  end

  defp expand_gap_cells(layout, gap_start, gap_end, extra, vertical) do
    Enum.reduce(gap_start..gap_end//1, layout, fn gap, acc ->
      if vertical do
        cur = Map.get(acc.row_heights, gap, 1)
        %{acc | row_heights: Map.put(acc.row_heights, gap, max(cur, extra))}
      else
        cur = Map.get(acc.col_widths, gap, 2)
        %{acc | col_widths: Map.put(acc.col_widths, gap, max(cur, extra))}
      end
    end)
  end

  defp compute_sg_bounds(sg, graph, layout) do
    {child_bounds, layout} =
      Enum.reduce(sg.children, {[], layout}, fn child, {acc, l} ->
        {new_bounds, l} = compute_sg_bounds(child, graph, l)
        {acc ++ new_bounds, l}
      end)

    all_node_ids = gather_all_nodes(sg)
    node_extents = collect_node_extents(layout, all_node_ids)

    child_extents =
      Enum.map(child_bounds, fn cb ->
        {cb.x, cb.y, cb.x + cb.width, cb.y + cb.height}
      end)

    all_extents = node_extents ++ child_extents

    if all_extents == [] do
      {child_bounds, layout}
    else
      bounds = build_bounds_from_extents(sg, all_extents)
      {child_bounds ++ [bounds], layout}
    end
  end

  defp collect_node_extents(layout, node_ids) do
    Enum.flat_map(node_ids, fn nid ->
      case Map.get(layout.placements, nid) do
        nil -> []
        p -> [{p.draw_x, p.draw_y, p.draw_x + p.draw_width, p.draw_y + p.draw_height}]
      end
    end)
  end

  defp build_bounds_from_extents(sg, extents) do
    {min_x, min_y, max_x, max_y} =
      Enum.reduce(extents, {nil, nil, 0, 0}, fn {x1, y1, x2, y2}, {mx1, my1, mx2, my2} ->
        {
          if(mx1 == nil, do: x1, else: min(mx1, x1)),
          if(my1 == nil, do: y1, else: min(my1, y1)),
          max(mx2, x2),
          max(my2, y2)
        }
      end)

    content_width = max_x - min_x + @sg_border_pad * 2
    label_width = String.length(sg.label) + 4
    final_width = max(content_width, label_width)

    %SubgraphBounds{
      subgraph_id: sg.id,
      x: min_x - @sg_border_pad,
      y: min_y - @sg_border_pad - @sg_label_height,
      width: final_width,
      height: max_y - min_y + @sg_border_pad * 2 + @sg_label_height
    }
  end

  defp gather_all_nodes(sg) do
    child_nodes =
      Enum.flat_map(sg.children, fn child ->
        MapSet.to_list(gather_all_nodes(child))
      end)

    MapSet.new(sg.node_ids ++ child_nodes)
  end
end
