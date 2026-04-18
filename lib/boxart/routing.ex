defmodule Boxart.Routing do
  @moduledoc """
  Edge routing orchestrator.

  Determines start/end attachment points on nodes, runs A* pathfinding,
  and handles direction selection (preferred vs alternative paths).
  Previously-routed edges' cells become soft obstacles for later edges.
  """

  alias Boxart.Routing.Pathfinder

  @type attach_dir :: :top | :bottom | :left | :right

  defmodule RoutedEdge do
    @moduledoc """
    An edge with its computed path in grid and drawing coordinates.
    """

    @type t :: %__MODULE__{
            edge: struct(),
            grid_path: [{integer(), integer()}],
            draw_path: [{integer(), integer()}],
            start_dir: Boxart.Routing.attach_dir(),
            end_dir: Boxart.Routing.attach_dir(),
            label: String.t(),
            index: non_neg_integer(),
            occupied_cells: MapSet.t({integer(), integer()})
          }

    defstruct edge: nil,
              grid_path: [],
              draw_path: [],
              start_dir: :right,
              end_dir: :left,
              label: "",
              index: 0,
              occupied_cells: MapSet.new()
  end

  @prefer_bias 3

  @doc """
  Route all edges in the graph, returning a list of `RoutedEdge` structs.

  Each edge is routed via A* pathfinding between attachment points on its
  source and target nodes. Previously-routed edges contribute soft obstacles
  so later edges prefer avoiding overlap.
  """
  @spec route_edges(struct(), struct()) :: [RoutedEdge.t()]
  def route_edges(graph, layout) do
    direction = normalized_direction(graph.direction)
    sg_bounds = build_subgraph_bounds(layout)

    {routed, _soft} =
      graph.edges
      |> Enum.with_index()
      |> Enum.reduce({[], MapSet.new()}, fn {edge, idx}, {acc, soft} ->
        src =
          resolve_placement(
            edge.source,
            Map.get(edge, :source_is_subgraph, false),
            layout,
            sg_bounds
          )

        tgt =
          resolve_placement(
            edge.target,
            Map.get(edge, :target_is_subgraph, false),
            layout,
            sg_bounds
          )

        cond do
          is_nil(src) or is_nil(tgt) ->
            {acc, soft}

          edge.source == edge.target and not Map.get(edge, :source_is_subgraph, false) ->
            re = route_self_edge(edge, src, layout) |> Map.put(:index, idx)
            {[re | acc], soft}

          true ->
            re = route_edge(edge, src, tgt, layout, direction, soft) |> Map.put(:index, idx)
            {[re | acc], MapSet.union(soft, re.occupied_cells)}
        end
      end)

    routed = Enum.reverse(routed)
    spread_shared_endpoints(routed, layout)
  end

  # --- Direction helpers ---

  defp normalized_direction(:tb), do: :tb
  defp normalized_direction(:td), do: :tb
  defp normalized_direction(:bt), do: :tb
  defp normalized_direction(:lr), do: :lr
  defp normalized_direction(:rl), do: :lr
  defp normalized_direction(other), do: other

  defp horizontal_direction?(:lr), do: true
  defp horizontal_direction?(_), do: false

  # --- Subgraph bounds ---

  defp build_subgraph_bounds(layout) do
    (Map.get(layout, :subgraph_bounds, []) || [])
    |> Enum.reduce(%{}, fn sb, acc ->
      Map.put(acc, sb.subgraph.id, sb)
    end)
  end

  # --- Placement resolution ---

  defp resolve_placement(node_id, false, layout, _sg_bounds) do
    Map.get(layout.placements, node_id)
  end

  defp resolve_placement(sg_id, true, layout, sg_bounds) do
    case Map.get(sg_bounds, sg_id) do
      nil -> nil
      sb -> build_subgraph_placement(sg_id, sb, layout)
    end
  end

  defp build_subgraph_placement(sg_id, sb, layout) do
    cx = sb.x + div(sb.width, 2)
    cy = sb.y + div(sb.height, 2)

    {best_col, best_row} = find_nearest_grid_cell(layout.placements, cx, cy)

    %{
      node_id: sg_id,
      grid: %{col: best_col, row: best_row},
      draw_x: sb.x,
      draw_y: sb.y,
      draw_width: sb.width,
      draw_height: sb.height
    }
  end

  defp find_nearest_grid_cell(placements, cx, cy) do
    placements
    |> Map.values()
    |> Enum.reduce({0, 0, :infinity}, fn p, {bc, br, bd} ->
      dx = p.draw_x + div(p.draw_width, 2) - cx
      dy = p.draw_y + div(p.draw_height, 2) - cy
      dist = abs(dx) + abs(dy)
      if dist < bd, do: {p.grid.col, p.grid.row, dist}, else: {bc, br, bd}
    end)
    |> then(fn {c, r, _} -> {c, r} end)
  end

  # --- Attachment points ---

  defp get_attach_point(placement, :top), do: {placement.grid.col, placement.grid.row - 1}
  defp get_attach_point(placement, :bottom), do: {placement.grid.col, placement.grid.row + 1}
  defp get_attach_point(placement, :left), do: {placement.grid.col - 1, placement.grid.row}
  defp get_attach_point(placement, :right), do: {placement.grid.col + 1, placement.grid.row}

  # --- Direction selection ---

  @doc false
  @spec determine_directions(struct(), struct(), atom()) ::
          {{attach_dir(), attach_dir()}, {attach_dir(), attach_dir()}}
  def determine_directions(src, tgt, direction) do
    {sc, sr} = {src.grid.col, src.grid.row}
    {tc, tr} = {tgt.grid.col, tgt.grid.row}

    if horizontal_direction?(direction) do
      determine_horizontal_directions(sc, sr, tc, tr)
    else
      determine_vertical_directions(sc, sr, tc, tr)
    end
  end

  defp determine_horizontal_directions(sc, sr, tc, tr) do
    preferred =
      cond do
        tc > sc -> {:right, :left}
        tc < sc -> {:bottom, :bottom}
        tr > sr -> {:bottom, :top}
        true -> {:top, :bottom}
      end

    if tc < sc do
      # Back-edge
      {preferred, {:bottom, :top}}
    else
      alt =
        cond do
          tr > sr -> {:bottom, :top}
          tr < sr -> {:top, :bottom}
          true -> preferred
        end

      {preferred, alt}
    end
  end

  defp determine_vertical_directions(sc, sr, tc, tr) do
    preferred =
      cond do
        tr > sr -> {:bottom, :top}
        tr < sr -> {:right, :right}
        tc > sc -> {:right, :left}
        true -> {:left, :right}
      end

    if tr < sr do
      # Back-edge
      {preferred, {:right, :left}}
    else
      alt =
        cond do
          tc > sc -> {:right, :left}
          tc < sc -> {:left, :right}
          true -> preferred
        end

      {preferred, alt}
    end
  end

  # --- Edge routing ---

  defp route_edge(edge, src, tgt, layout, direction, soft_obstacles) do
    {preferred, alt} = determine_directions(src, tgt, direction)
    free? = fn c, r -> layout_free?(layout, c, r) end

    {start_pref_col, start_pref_row} = get_attach_point(src, elem(preferred, 0))
    {end_pref_col, end_pref_row} = get_attach_point(tgt, elem(preferred, 1))

    path_pref =
      Pathfinder.find_path(
        start_pref_col,
        start_pref_row,
        end_pref_col,
        end_pref_row,
        free?,
        soft_obstacles: soft_obstacles
      )

    {start_alt_col, start_alt_row} = get_attach_point(src, elem(alt, 0))
    {end_alt_col, end_alt_row} = get_attach_point(tgt, elem(alt, 1))

    path_alt =
      Pathfinder.find_path(
        start_alt_col,
        start_alt_row,
        end_alt_col,
        end_alt_row,
        free?,
        soft_obstacles: soft_obstacles
      )

    {path, start_dir, end_dir} = pick_path(path_pref, path_alt, preferred, alt)

    simplified = Pathfinder.simplify_path(path)
    draw_path = Enum.map(simplified, fn {c, r} -> grid_to_draw_center(layout, c, r) end)
    occupied = MapSet.new(path)

    %RoutedEdge{
      edge: edge,
      grid_path: simplified,
      draw_path: draw_path,
      start_dir: start_dir,
      end_dir: end_dir,
      label: Map.get(edge, :label, ""),
      occupied_cells: occupied
    }
  end

  defp pick_path(path_pref, path_alt, preferred, alt) do
    case {path_pref, path_alt} do
      {nil, nil} ->
        # Fallback: direct line from preferred endpoints
        {[{0, 0}, {0, 0}], elem(preferred, 0), elem(preferred, 1)}

      {nil, path_alt} ->
        {path_alt, elem(alt, 0), elem(alt, 1)}

      {path_pref, nil} ->
        {path_pref, elem(preferred, 0), elem(preferred, 1)}

      {path_pref, path_alt} ->
        if length(path_pref) <= length(path_alt) + @prefer_bias do
          {path_pref, elem(preferred, 0), elem(preferred, 1)}
        else
          {path_alt, elem(alt, 0), elem(alt, 1)}
        end
    end
  end

  # --- Self-edge routing ---

  defp route_self_edge(edge, src, layout) do
    gc = src.grid

    path = [
      {gc.col, gc.row - 1},
      {gc.col, gc.row - 2},
      {gc.col + 2, gc.row - 2},
      {gc.col + 2, gc.row},
      {gc.col + 1, gc.row}
    ]

    draw_path = Enum.map(path, fn {c, r} -> grid_to_draw_center(layout, c, r) end)

    %RoutedEdge{
      edge: edge,
      grid_path: path,
      draw_path: draw_path,
      start_dir: :top,
      end_dir: :right,
      label: Map.get(edge, :label, ""),
      occupied_cells: MapSet.new(path)
    }
  end

  # --- Endpoint spreading ---

  defp spread_shared_endpoints(routed, layout) do
    end_groups =
      routed
      |> Enum.filter(&(length(&1.draw_path) >= 2))
      |> Enum.group_by(&List.last(&1.draw_path))

    Enum.reduce(end_groups, routed, fn {_point, edges}, acc ->
      spread_group(acc, edges, layout)
    end)
  end

  defp spread_group(routed, edges, _layout) when length(edges) <= 1, do: routed

  defp spread_group(routed, edges, layout) do
    tgt_id = edges |> hd() |> Map.get(:edge) |> Map.get(:target)

    case Map.get(layout.placements, tgt_id) do
      nil -> routed
      placement -> apply_spread(routed, edges, List.last(hd(edges).draw_path), placement)
    end
  end

  defp apply_spread(all_routed, edges, endpoint, placement) do
    n = length(edges)
    attach = hd(edges).end_dir

    case compute_offsets(attach, n, endpoint, placement, edges) do
      nil -> all_routed
      offset_map -> apply_offset_map(all_routed, offset_map)
    end
  end

  defp apply_offset_map(routed, offset_map) do
    Enum.map(routed, fn re ->
      case Map.get(offset_map, re.index) do
        nil -> re
        updater -> updater.(re)
      end
    end)
  end

  defp compute_offsets(attach, n, {px, py}, placement, edges) when attach in [:top, :bottom] do
    min_x = placement.draw_x + 1
    max_x = placement.draw_x + placement.draw_width - 2
    spread_range = max_x - min_x

    if spread_range < n - 1 do
      nil
    else
      step = min(2, div(spread_range, max(n - 1, 1)))
      build_horizontal_offsets(edges, n, step, px, py, min_x, max_x)
    end
  end

  defp compute_offsets(attach, n, {px, py}, placement, edges) when attach in [:left, :right] do
    min_y = placement.draw_y + 1
    max_y = placement.draw_y + placement.draw_height - 2
    spread_range = max_y - min_y

    min_gap =
      edges |> Enum.map(fn re -> abs(px - elem(Enum.at(re.draw_path, -2), 0)) end) |> Enum.min()

    if spread_range < n - 1 or min_gap < 4 do
      nil
    else
      step = min(2, div(spread_range, max(n - 1, 1)))
      build_vertical_offsets(edges, n, step, px, py, min_y, max_y)
    end
  end

  defp build_horizontal_offsets(edges, n, step, px, py, min_x, max_x) do
    edges
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {re, i}, acc ->
      offset = trunc((i - (n - 1) / 2) * step)
      if offset == 0, do: acc, else: put_h_offset(acc, re.index, px + offset, py, min_x, max_x)
    end)
  end

  defp put_h_offset(acc, index, target_x, py, min_x, max_x) do
    new_x = max(min_x, min(max_x, target_x))

    Map.put(acc, index, fn re ->
      {_adj_x, adj_y} = Enum.at(re.draw_path, -2)
      draw_path = List.replace_at(re.draw_path, -1, {new_x, py})
      draw_path = List.replace_at(draw_path, -2, {new_x, adj_y})
      %{re | draw_path: draw_path}
    end)
  end

  defp build_vertical_offsets(edges, n, step, px, py, min_y, max_y) do
    edges
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {re, i}, acc ->
      offset = trunc((i - (n - 1) / 2) * step)
      if offset == 0, do: acc, else: put_v_offset(acc, re.index, px, py + offset, min_y, max_y)
    end)
  end

  defp put_v_offset(acc, index, px, target_y, min_y, max_y) do
    new_y = max(min_y, min(max_y, target_y))

    Map.put(acc, index, fn re ->
      {adj_x, _adj_y} = Enum.at(re.draw_path, -2)
      draw_path = List.replace_at(re.draw_path, -1, {px, new_y})
      draw_path = List.insert_at(draw_path, -1, {adj_x, new_y})
      %{re | draw_path: draw_path}
    end)
  end

  # --- Layout delegation ---

  defp layout_free?(%{grid_occupied: occupied}, col, row) do
    col >= 0 and row >= 0 and not Map.has_key?(occupied, {col, row})
  end

  defp grid_to_draw_center(layout, col, row) do
    if function_exported?(layout.__struct__, :grid_to_draw_center, 3) do
      layout.__struct__.grid_to_draw_center(layout, col, row)
    else
      {col, row}
    end
  end
end
