defmodule Boxart.Layout.Placement do
  @moduledoc """
  Node placement and sizing for the layout engine.

  Handles placing nodes on the grid, computing column widths and row
  heights based on label content, and normalizing sizes within layers.
  """

  alias Boxart.Graph
  alias Boxart.Layout
  alias Boxart.Layout.{GridCoord, NodePlacement}

  @stride Layout.stride()
  @max_label_width Layout.max_label_width()
  @max_normalized_width Layout.max_normalized_width()
  @max_normalized_height Layout.max_normalized_height()

  @doc """
  Place nodes on the grid based on layer assignments.

  `gap_expansions` maps gap index to the number of extra grid cells to
  insert between that gap's adjacent layers, giving the pathfinder more
  room to route crossing edges without overlap.
  """
  @spec place_nodes(Layout.t(), Graph.t(), [[String.t()]], atom(), %{
          non_neg_integer() => non_neg_integer()
        }) ::
          Layout.t()
  def place_nodes(
        %Layout{} = layout,
        %Graph{} = _graph,
        layer_order,
        direction,
        gap_expansions \\ %{}
      ) do
    horizontal = Graph.horizontal?(direction)

    {layout, _} =
      layer_order
      |> Enum.with_index()
      |> Enum.reduce({layout, 0}, fn {nodes, layer_idx}, {layout_acc, cumulative_extra} ->
        cumulative_extra =
          if layer_idx > 0 do
            cumulative_extra + Map.get(gap_expansions, layer_idx - 1, 0)
          else
            cumulative_extra
          end

        layout_acc =
          nodes
          |> Enum.with_index()
          |> Enum.reduce(layout_acc, fn {nid, pos_idx}, l ->
            {col, row} =
              if horizontal do
                {layer_idx * @stride + 1 + cumulative_extra, pos_idx * @stride + 1}
              else
                {pos_idx * @stride + 1, layer_idx * @stride + 1 + cumulative_extra}
              end

            gc = resolve_placement(l, %GridCoord{col: col, row: row}, horizontal)
            placement = %NodePlacement{node_id: nid, grid: gc}

            l = put_in(l.placements[nid], placement)
            reserve_block(l, gc, nid)
          end)

        {layout_acc, cumulative_extra}
      end)

    layout
  end

  @doc """
  Compute column widths and row heights based on node content.
  """
  @spec compute_sizes(Layout.t(), Graph.t(), integer(), integer(), integer()) :: Layout.t()
  def compute_sizes(%Layout{} = layout, %Graph{} = graph, padding_x, padding_y, gap) do
    layout =
      Enum.reduce(layout.placements, layout, fn {nid, placement}, l ->
        node = Map.fetch!(graph.nodes, nid)

        if node.shape == :junction do
          l
          |> ensure_col_width(placement.grid.col, 1)
          |> ensure_row_height(placement.grid.row, 1)
        else
          compute_node_size(l, node, placement, padding_x, padding_y)
        end
      end)

    layout
    |> set_border_cell_defaults()
    |> set_gap_cell_defaults(gap)
    |> expand_gaps_for_edge_labels(graph)
  end

  @doc """
  Normalize node dimensions within the same layer, capped at a maximum.

  Nodes at the same flow level are normalized to the same perpendicular
  dimension so side-by-side nodes look consistent.
  """
  @spec normalize_sizes(Layout.t(), Graph.t()) :: Layout.t()
  def normalize_sizes(%Layout{} = layout, %Graph{} = graph) do
    direction = Graph.normalized(graph.direction)
    vertical = Graph.vertical?(direction)

    layer_groups =
      layout.placements
      |> Enum.reject(fn {nid, _p} ->
        node = Map.get(graph.nodes, nid)
        node && node.shape == :junction
      end)
      |> Enum.group_by(fn {_nid, p} ->
        if vertical, do: p.grid.row, else: p.grid.col
      end)

    Enum.reduce(layer_groups, layout, fn {_layer_key, group}, l ->
      if length(group) < 2 do
        l
      else
        if vertical do
          cols = Enum.map(group, fn {_nid, p} -> p.grid.col end) |> Enum.uniq()
          max_w = cols |> Enum.map(&Map.get(l.col_widths, &1, 1)) |> Enum.max()
          target = min(max_w, @max_normalized_width)
          Enum.reduce(cols, l, fn c, acc -> ensure_col_width(acc, c, target) end)
        else
          rows = Enum.map(group, fn {_nid, p} -> p.grid.row end) |> Enum.uniq()
          max_h = rows |> Enum.map(&Map.get(l.row_heights, &1, 1)) |> Enum.max()
          target = min(max_h, @max_normalized_height)
          Enum.reduce(rows, l, fn r, acc -> ensure_row_height(acc, r, target) end)
        end
      end
    end)
  end

  # --- Private helpers ---

  defp resolve_placement(layout, gc, horizontal) do
    if can_place?(layout, gc) do
      gc
    else
      shift_until_free(layout, gc, horizontal)
    end
  end

  defp shift_until_free(layout, gc, horizontal) do
    next =
      if horizontal do
        %GridCoord{col: gc.col, row: gc.row + @stride}
      else
        %GridCoord{col: gc.col + @stride, row: gc.row}
      end

    if can_place?(layout, next), do: next, else: shift_until_free(layout, next, horizontal)
  end

  defp can_place?(layout, gc) do
    Enum.all?(-1..1, fn dc ->
      Enum.all?(-1..1, fn dr ->
        Layout.is_free(layout, gc.col + dc, gc.row + dr, nil)
      end)
    end)
  end

  defp reserve_block(layout, gc, nid) do
    occupied =
      for dc <- -1..1, dr <- -1..1, reduce: layout.grid_occupied do
        acc -> Map.put(acc, {gc.col + dc, gc.row + dr}, nid)
      end

    %{layout | grid_occupied: occupied}
  end

  defp compute_node_size(layout, node, placement, padding_x, padding_y) do
    lines =
      if String.contains?(node.label, "\\n") do
        String.split(node.label, "\\n")
      else
        [node.label]
      end

    wrapped =
      Enum.flat_map(lines, fn line ->
        if display_width(line) <= @max_label_width do
          [line]
        else
          word_wrap(line, @max_label_width)
        end
      end)

    text_width = wrapped |> Enum.map(&display_width/1) |> Enum.max(fn -> 0 end)
    text_height = length(wrapped)

    content_width = max(text_width + padding_x, 3)
    content_height = max(text_height + padding_y, 3)

    col = placement.grid.col
    row = placement.grid.row

    layout
    |> ensure_col_width(col, content_width)
    |> ensure_row_height(row, content_height)
  end

  defp set_border_cell_defaults(layout) do
    {all_cols, all_rows} =
      Enum.reduce(layout.placements, {MapSet.new(), MapSet.new()}, fn {_nid, p}, {cols, rows} ->
        cols = for dc <- -1..1, reduce: cols, do: (acc -> MapSet.put(acc, p.grid.col + dc))
        rows = for dr <- -1..1, reduce: rows, do: (acc -> MapSet.put(acc, p.grid.row + dr))
        {cols, rows}
      end)

    layout =
      Enum.reduce(all_cols, layout, fn c, l ->
        if Map.has_key?(l.col_widths, c),
          do: l,
          else: %{l | col_widths: Map.put(l.col_widths, c, 1)}
      end)

    Enum.reduce(all_rows, layout, fn r, l ->
      if Map.has_key?(l.row_heights, r),
        do: l,
        else: %{l | row_heights: Map.put(l.row_heights, r, 1)}
    end)
  end

  defp set_gap_cell_defaults(layout, gap) do
    {all_cols, all_rows} =
      Enum.reduce(layout.placements, {MapSet.new(), MapSet.new()}, fn {_nid, p}, {cols, rows} ->
        cols = for dc <- -1..1, reduce: cols, do: (acc -> MapSet.put(acc, p.grid.col + dc))
        rows = for dr <- -1..1, reduce: rows, do: (acc -> MapSet.put(acc, p.grid.row + dr))
        {cols, rows}
      end)

    max_col = if MapSet.size(all_cols) > 0, do: Enum.max(all_cols), else: 0
    max_row = if MapSet.size(all_rows) > 0, do: Enum.max(all_rows), else: 0

    layout =
      Enum.reduce(0..(max_col + 1), layout, fn c, l ->
        if Map.has_key?(l.col_widths, c),
          do: l,
          else: %{l | col_widths: Map.put(l.col_widths, c, gap)}
      end)

    Enum.reduce(0..(max_row + 1), layout, fn r, l ->
      if Map.has_key?(l.row_heights, r),
        do: l,
        else: %{l | row_heights: Map.put(l.row_heights, r, max(gap - 1, 1))}
    end)
  end

  defp expand_gaps_for_edge_labels(layout, graph) do
    direction = Graph.normalized(graph.direction)
    horizontal = Graph.horizontal?(direction)

    layout =
      Enum.reduce(graph.edges, layout, fn edge, l ->
        if edge.label == "" or edge.label == nil do
          l
        else
          expand_label_gap(l, graph, edge, horizontal)
        end
      end)

    if horizontal do
      layout
    else
      expand_vertical_multi_labels(layout, graph)
    end
  end

  defp expand_label_gap(layout, _graph, edge, horizontal) do
    label_len = display_width(edge.label)

    src_p = Map.get(layout.placements, edge.source)
    tgt_p = Map.get(layout.placements, edge.target)

    if src_p == nil or tgt_p == nil do
      layout
    else
      if horizontal do
        c1 = min(src_p.grid.col, tgt_p.grid.col)
        c2 = max(src_p.grid.col, tgt_p.grid.col)
        gap_start = c1 + 2
        gap_end = c2 - 2

        if gap_start > gap_end do
          layout
        else
          needed = label_len + 1
          ensure_col_width(layout, gap_start, needed)
        end
      else
        r1 = min(src_p.grid.row, tgt_p.grid.row)
        r2 = max(src_p.grid.row, tgt_p.grid.row)
        gap_start = r1 + 2
        gap_end = r2 - 2

        layout =
          if gap_start <= gap_end do
            ensure_row_height(layout, gap_start, 3)
          else
            layout
          end

        gap_cols = compute_label_gap_cols(src_p, tgt_p)

        Enum.reduce(gap_cols, layout, fn gap_col, l ->
          if gap_col >= 0 and Map.has_key?(l.col_widths, gap_col) do
            ensure_col_width(l, gap_col, label_len + 1)
          else
            l
          end
        end)
      end
    end
  end

  defp compute_label_gap_cols(src_p, tgt_p) do
    src_col = src_p.grid.col
    tgt_col = tgt_p.grid.col
    c_min = min(src_col, tgt_col)
    c_max = max(src_col, tgt_col)

    base =
      if(tgt_col >= src_col, do: [src_col + 2], else: []) ++
        if tgt_col <= src_col, do: [src_col - 2], else: []

    intermediate =
      (c_min + 2)..(c_max - 1)//@stride
      |> Enum.to_list()

    Enum.uniq(base ++ intermediate)
  end

  defp expand_vertical_multi_labels(layout, graph) do
    labeled_per_src =
      graph.edges
      |> Enum.filter(&(&1.label != "" and &1.label != nil))
      |> Enum.group_by(& &1.source)
      |> Enum.filter(fn {_src, edges} -> length(edges) >= 2 end)

    Enum.reduce(labeled_per_src, layout, fn {src_id, edges}, l ->
      case Map.get(l.placements, src_id) do
        nil ->
          l

        src_p ->
          gap_row = src_p.grid.row + 2
          needed = length(edges) * 2 + 1
          ensure_row_height(l, gap_row, needed)
      end
    end)
  end

  defp ensure_col_width(layout, col, width) do
    cur = Map.get(layout.col_widths, col, 1)
    %{layout | col_widths: Map.put(layout.col_widths, col, max(cur, width))}
  end

  defp ensure_row_height(layout, row, height) do
    cur = Map.get(layout.row_heights, row, 1)
    %{layout | row_heights: Map.put(layout.row_heights, row, max(cur, height))}
  end

  defp word_wrap(text, max_width) do
    words = String.split(text)

    case words do
      [] ->
        [text]

      [first | rest] ->
        {lines, current} =
          Enum.reduce(rest, {[], first}, fn word, {lines, current} ->
            if display_width(current) + 1 + display_width(word) <= max_width do
              {lines, current <> " " <> word}
            else
              {[current | lines], word}
            end
          end)

        Enum.reverse([current | lines])
    end
  end

  defp display_width(text) do
    String.length(text)
  end
end
