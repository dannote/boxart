defmodule Boxart.Render do
  @moduledoc """
  Draw orchestrator: combines layout, routing, and rendering into final output.

  Drawing order (back to front):

  1. Subgraph borders (background)
  2. Nodes (boxes)
  3. Edge lines
  4. Edge corners
  5. Arrow heads
  6. T-junctions (where edges leave nodes)
  7. Edge labels
  8. Subgraph labels
  """

  alias Boxart.Canvas
  alias Boxart.Charset
  alias Boxart.CodeNode
  alias Boxart.Graph
  alias Boxart.Layout
  alias Boxart.Render.Shapes
  alias Boxart.Routing
  alias Boxart.Utils

  @type render_opts :: [
          charset: :unicode | :ascii,
          padding_x: non_neg_integer(),
          padding_y: non_neg_integer(),
          gap: non_neg_integer()
        ]

  @doc """
  Renders a graph to a string.

  Returns `""` for empty graphs.
  """
  @spec render_graph(Graph.t(), render_opts()) :: String.t()
  def render_graph(graph, opts \\ []) do
    max_width = Keyword.get(opts, :max_width)

    case render_graph_canvas(graph, opts) do
      nil ->
        ""

      canvas ->
        output = render_canvas_to_string(canvas, opts)
        apply_max_width(output, max_width, graph, opts)
    end
  end

  defp apply_max_width(output, nil, _graph, _opts), do: output

  defp apply_max_width(output, max_width, graph, opts) do
    actual = output |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)

    if actual <= max_width do
      output
    else
      shrunk = try_shrink_labels(graph, opts, max_width)
      clamp_width(shrunk, max_width)
    end
  end

  defp render_canvas_to_string(canvas, opts) do
    case Keyword.get(opts, :theme) do
      nil ->
        Canvas.render(canvas)

      theme_name when is_atom(theme_name) ->
        Canvas.render_ansi(canvas, Boxart.Theme.get(theme_name))

      %Boxart.Theme{} = theme ->
        Canvas.render_ansi(canvas, theme)
    end
  end

  defp try_shrink_labels(graph, opts, max_width) do
    current_mlw = Keyword.get(opts, :max_label_width, 20)
    min_mlw = 6

    shrunk_mlw = find_fitting_label_width(graph, opts, max_width, current_mlw, min_mlw)
    new_opts = Keyword.put(opts, :max_label_width, shrunk_mlw)

    case render_graph_canvas(graph, new_opts) do
      nil -> ""
      canvas -> render_canvas_to_string(canvas, new_opts)
    end
  end

  defp find_fitting_label_width(_graph, _opts, _max_width, mlw, min_mlw) when mlw <= min_mlw,
    do: min_mlw

  defp find_fitting_label_width(graph, opts, max_width, mlw, min_mlw) do
    new_mlw = max(div(mlw, 2), min_mlw)
    test_opts = opts |> Keyword.put(:max_label_width, new_mlw) |> Keyword.delete(:max_width)

    case render_graph_canvas(graph, test_opts) do
      nil ->
        new_mlw

      canvas ->
        output = Canvas.render(canvas)

        actual =
          output |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)

        if actual <= max_width do
          new_mlw
        else
          find_fitting_label_width(graph, opts, max_width, new_mlw, min_mlw)
        end
    end
  end

  defp clamp_width(output, nil), do: output

  defp clamp_width(output, max_width) when is_integer(max_width) and max_width > 0 do
    output
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if String.length(line) > max_width, do: String.slice(line, 0, max_width), else: line
    end)
  end

  @doc """
  Renders a graph and returns the `Canvas` struct.

  Returns `nil` for empty graphs.
  """
  @spec render_graph_canvas(Graph.t(), render_opts()) :: Canvas.t() | nil
  def render_graph_canvas(%Graph{node_order: []} = _graph, _opts), do: nil

  def render_graph_canvas(%Graph{} = graph, opts) do
    cs = charset_from_opts(opts)
    layout_opts = Keyword.take(opts, [:padding_x, :padding_y, :gap, :max_label_width])

    {graph, needs_v_flip, needs_h_flip} = normalize_direction(graph)

    layout = Layout.compute_layout(graph, layout_opts)
    routed = Routing.route_edges(graph, layout)

    canvas = create_canvas(layout, routed)
    {layout, routed} = mirror_coordinates(layout, routed, canvas, needs_v_flip, needs_h_flip)

    canvas
    |> draw_subgraph_borders(layout, cs)
    |> draw_nodes(graph, layout, cs)
    |> draw_edges(graph, routed, cs, opts)
    |> draw_subgraph_labels(graph, layout)
  end

  # -- Direction normalization --

  defp normalize_direction(%Graph{direction: :bt} = graph) do
    {%{graph | direction: :tb}, true, false}
  end

  defp normalize_direction(%Graph{direction: :rl} = graph) do
    {%{graph | direction: :lr}, false, true}
  end

  defp normalize_direction(graph), do: {graph, false, false}

  defp mirror_coordinates(layout, routed, _canvas, false, false), do: {layout, routed}

  defp mirror_coordinates(layout, routed, canvas, needs_v_flip, needs_h_flip) do
    w = canvas.width
    h = canvas.height

    mirrored_placements =
      Map.new(layout.placements, fn {nid, p} ->
        {nid, mirror_placement(p, w, h, needs_h_flip, needs_v_flip)}
      end)

    mirrored_subgraph_bounds =
      Enum.map(
        layout.subgraph_bounds,
        &mirror_subgraph_bound(&1, w, h, needs_h_flip, needs_v_flip)
      )

    mirrored_routed =
      Enum.map(routed, fn re ->
        mirrored_path =
          Enum.map(re.draw_path, &mirror_point(&1, w, h, needs_h_flip, needs_v_flip))

        %{re | draw_path: mirrored_path}
      end)

    layout = %{
      layout
      | placements: mirrored_placements,
        subgraph_bounds: mirrored_subgraph_bounds
    }

    {layout, mirrored_routed}
  end

  defp mirror_placement(p, w, _h, true = _needs_h_flip, false = _needs_v_flip) do
    %{p | draw_x: w - p.draw_x - p.draw_width}
  end

  defp mirror_placement(p, _w, h, false = _needs_h_flip, true = _needs_v_flip) do
    %{p | draw_y: h - p.draw_y - p.draw_height}
  end

  defp mirror_placement(p, w, h, true = _needs_h_flip, true = _needs_v_flip) do
    p = %{p | draw_x: w - p.draw_x - p.draw_width}
    %{p | draw_y: h - p.draw_y - p.draw_height}
  end

  defp mirror_subgraph_bound(sb, w, _h, true = _needs_h_flip, false = _needs_v_flip) do
    %{sb | x: w - sb.x - sb.width}
  end

  defp mirror_subgraph_bound(sb, _w, h, false = _needs_h_flip, true = _needs_v_flip) do
    %{sb | y: h - sb.y - sb.height}
  end

  defp mirror_subgraph_bound(sb, w, h, true = _needs_h_flip, true = _needs_v_flip) do
    sb = %{sb | x: w - sb.x - sb.width}
    %{sb | y: h - sb.y - sb.height}
  end

  defp mirror_point({x, y}, w, _h, true = _needs_h_flip, false = _needs_v_flip) do
    {w - 1 - x, y}
  end

  defp mirror_point({x, y}, _w, h, false = _needs_h_flip, true = _needs_v_flip) do
    {x, h - 1 - y}
  end

  defp mirror_point({x, y}, w, h, true = _needs_h_flip, true = _needs_v_flip) do
    {w - 1 - x, h - 1 - y}
  end

  # -- Canvas creation --

  defp create_canvas(layout, routed) do
    {extra_w, extra_h} =
      Enum.reduce(routed, {0, 0}, fn re, {max_w, max_h} ->
        Enum.reduce(re.draw_path, {max_w, max_h}, fn {x, y}, {mw, mh} ->
          {max(mw, x + 2), max(mh, y + 2)}
        end)
      end)

    # +4 margin for edge routing that extends beyond node bounds
    width = max(layout.canvas_width + 4, extra_w)
    height = max(layout.canvas_height + 4, extra_h)

    Canvas.new(width, height)
  end

  # -- Subgraph borders --
  # Canvas.put(canvas, col, row, ch) where col=x, row=y

  defp draw_subgraph_borders(canvas, layout, cs) do
    Enum.reduce(layout.subgraph_bounds, canvas, fn sb, acc ->
      draw_subgraph_border(acc, sb, cs)
    end)
  end

  defp draw_subgraph_border(canvas, %{width: w, height: h}, _cs) when w <= 0 or h <= 0, do: canvas

  defp draw_subgraph_border(canvas, sb, cs) do
    x = max(0, sb.x)
    y = max(0, sb.y)
    w = sb.width
    h = sb.height

    canvas
    # Top border
    |> Canvas.put(x, y, cs.subgraph.top_left, style: "subgraph")
    |> Canvas.fill_horizontal(y, x + 1, x + w - 1, cs.subgraph.horizontal)
    |> Canvas.put(x + w - 1, y, cs.subgraph.top_right, style: "subgraph")
    # Bottom border
    |> Canvas.put(x, y + h - 1, cs.subgraph.bottom_left, style: "subgraph")
    |> Canvas.fill_horizontal(y + h - 1, x + 1, x + w - 1, cs.subgraph.horizontal)
    |> Canvas.put(x + w - 1, y + h - 1, cs.subgraph.bottom_right, style: "subgraph")
    # Side borders
    |> fill_vertical_both(x, x + w - 1, y + 1, y + h - 1, cs.subgraph.vertical)
  end

  # -- Subgraph labels --

  defp draw_subgraph_labels(canvas, graph, layout) do
    Enum.reduce(layout.subgraph_bounds, canvas, fn sb, acc ->
      draw_subgraph_label(acc, graph, sb)
    end)
  end

  defp draw_subgraph_label(canvas, _graph, %{width: w, height: h}) when w <= 0 or h <= 0,
    do: canvas

  defp draw_subgraph_label(canvas, graph, sb) do
    label = find_subgraph_label(graph, sb.subgraph_id)

    if label && label != "" do
      x = max(0, sb.x)
      y = max(0, sb.y)
      Canvas.put_text(canvas, x + 2, y + 1, label, style: "subgraph_label")
    else
      canvas
    end
  end

  defp find_subgraph_label(graph, subgraph_id) do
    case Enum.find(graph.subgraphs, &(&1.id == subgraph_id)) do
      nil -> nil
      sg -> sg.label
    end
  end

  # -- Nodes --

  defp draw_nodes(canvas, graph, layout, cs) do
    Enum.reduce(graph.node_order, canvas, fn nid, acc ->
      case Map.get(layout.placements, nid) do
        nil ->
          acc

        p ->
          acc
          |> draw_node(graph, nid, p, cs)
          |> stamp_node_style(p)
      end
    end)
  end

  defp stamp_node_style(canvas, p) do
    for col <- p.draw_x..(p.draw_x + p.draw_width - 1)//1,
        row <- p.draw_y..(p.draw_y + p.draw_height - 1)//1,
        reduce: canvas do
      acc ->
        case Map.get(acc.cells, {col, row}) do
          %{char: " "} -> acc
          %{style: "label"} -> acc
          %{style: "dim"} -> acc
          nil -> acc
          cell -> %{acc | cells: Map.put(acc.cells, {col, row}, %{cell | style: "node"})}
        end
    end
  end

  defp draw_node(canvas, graph, nid, p, cs) do
    node = Map.fetch!(graph.nodes, nid)

    canvas =
      if node.source do
        code_label =
          CodeNode.format_label(node.source,
            start_line: node.start_line,
            language: node.language
          )

        canvas
        |> Shapes.draw_shape(
          node.shape,
          p.draw_x,
          p.draw_y,
          p.draw_width,
          p.draw_height,
          "",
          cs
        )
        |> CodeNode.render_to_canvas(
          p.draw_x,
          p.draw_y,
          p.draw_width,
          p.draw_height,
          code_label,
          cs
        )
      else
        Shapes.draw_shape(
          canvas,
          node.shape,
          p.draw_x,
          p.draw_y,
          p.draw_width,
          p.draw_height,
          node.label || nid,
          cs
        )
      end

    protect_node_cells(canvas, p)
  end

  defp protect_node_cells(canvas, p) do
    for r <- p.draw_y..(p.draw_y + p.draw_height - 1)//1,
        c <- p.draw_x..(p.draw_x + p.draw_width - 1)//1,
        reduce: canvas do
      acc -> Canvas.protect(acc, c, r)
    end
  end

  # -- Edges --

  defp draw_edges(canvas, graph, routed, cs, opts) do
    canvas
    |> draw_edge_lines_and_corners(graph, routed, cs, opts)
    |> draw_edge_arrows_and_junctions(graph, routed, cs)
    |> draw_edge_labels(routed)
  end

  defp draw_edge_lines_and_corners(canvas, _graph, routed, cs, opts) do
    Enum.reduce(routed, canvas, fn re, acc ->
      if length(re.draw_path) < 2 do
        acc
      else
        edge = re.edge
        {h_char, v_char} = edge_line_chars(edge.style, cs)

        acc
        |> draw_edge_segments(re.draw_path, edge, h_char, v_char)
        |> draw_edge_corners(re.draw_path, cs, opts)
      end
    end)
  end

  defp draw_edge_arrows_and_junctions(canvas, _graph, routed, cs) do
    Enum.reduce(routed, canvas, fn re, acc ->
      if length(re.draw_path) < 2 do
        acc
      else
        edge = re.edge

        acc
        |> maybe_draw_arrow_end(edge, re.draw_path, cs)
        |> maybe_draw_arrow_start(edge, re.draw_path, cs)
        |> maybe_draw_tee_start(edge, re.draw_path, cs)
        |> maybe_draw_tee_end(edge, re.draw_path, cs)
      end
    end)
  end

  defp draw_edge_labels(canvas, routed) do
    {canvas, _placed} =
      Enum.reduce(routed, {canvas, []}, fn re, {acc, placed} ->
        if re.label != "" and re.label != nil and length(re.draw_path) >= 2 do
          draw_single_edge_label(acc, re, placed)
        else
          {acc, placed}
        end
      end)

    canvas
  end

  # -- Edge line drawing --

  defp edge_line_chars(:dotted, cs), do: {cs.lines.dotted_h, cs.lines.dotted_v}
  defp edge_line_chars(:thick, cs), do: {cs.lines.thick_h, cs.lines.thick_v}
  defp edge_line_chars(:invisible, _cs), do: {" ", " "}
  defp edge_line_chars(_solid, cs), do: {cs.lines.horizontal, cs.lines.vertical}

  defp draw_edge_segments(canvas, path, edge, h_char, v_char) do
    chars = {h_char, v_char}

    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {[{x1, y1}, {x2, y2}], i}, acc ->
      {sx, sy, ex, ey} = clip_segment({x1, y1}, {x2, y2}, i, edge)
      draw_clipped_segment(acc, {sx, sy}, {ex, ey}, chars)
    end)
  end

  defp clip_segment({x1, y1}, {x2, y2}, seg_index, edge) do
    dx = sign(x2 - x1)
    dy = sign(y2 - y1)

    {sx, sy} =
      if seg_index == 0 and edge.has_arrow_start do
        {x1 + dx + dx, y1 + dy + dy}
      else
        {x1 + dx, y1 + dy}
      end

    {sx, sy, x2 - dx, y2 - dy}
  end

  defp draw_clipped_segment(canvas, {sx, sy}, {ex, ey}, {h_char, v_char}) do
    dx = sign(ex - sx)
    dy = sign(ey - sy)

    cond do
      dy == 0 and not segment_valid?(sx, ex, dx) -> canvas
      dx == 0 and not segment_valid?(sy, ey, dy) -> canvas
      dy == 0 -> Canvas.draw_horizontal(canvas, sy, sx, ex, h_char)
      dx == 0 -> Canvas.draw_vertical(canvas, sx, sy, ey, v_char)
      true -> draw_diagonal(canvas, sx, sy, ex, ey, h_char)
    end
  end

  defp segment_valid?(start_val, end_val, dir) when dir > 0, do: start_val <= end_val
  defp segment_valid?(start_val, end_val, dir) when dir < 0, do: start_val >= end_val
  defp segment_valid?(_start_val, _end_val, _dir), do: true

  defp draw_diagonal(canvas, x1, y1, x2, y2, ch) do
    steps = max(abs(x2 - x1), abs(y2 - y1))

    if steps == 0 do
      canvas
    else
      Enum.reduce(0..steps//1, canvas, fn step, acc ->
        x = x1 + div((x2 - x1) * step, steps)
        y = y1 + div((y2 - y1) * step, steps)
        Canvas.put(acc, x, y, ch)
      end)
    end
  end

  # -- Corners --

  defp draw_edge_corners(canvas, path, _cs, _opts) when length(path) < 3, do: canvas

  defp draw_edge_corners(canvas, path, cs, opts) do
    rounded = Keyword.get(opts, :rounded_edges, true)

    path
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.reduce(canvas, fn [{xp, yp}, {xc, yc}, {xn, yn}], acc ->
      case corner_char(xp, yp, xc, yc, xn, yn, cs, rounded) do
        nil -> acc
        ch -> Canvas.put(acc, xc, yc, ch, style: "edge")
      end
    end)
  end

  @doc false
  @spec corner_char(integer(), integer(), integer(), integer(), integer(), integer(), Charset.t()) ::
          String.t() | nil
  def corner_char(x_prev, y_prev, x_curr, y_curr, x_next, y_next, cs, rounded \\ true) do
    dx_in = sign(x_curr - x_prev)
    dy_in = sign(y_curr - y_prev)
    dx_out = sign(x_next - x_curr)
    dy_out = sign(y_next - y_curr)

    corners = if rounded, do: rounded_corners(cs), else: sharp_corners(cs)
    Map.get(corners, {dx_in, dy_in, dx_out, dy_out})
  end

  defp rounded_corners(cs) do
    %{
      {1, 0, 0, 1} => cs.box.round_top_right,
      {1, 0, 0, -1} => cs.box.round_bottom_right,
      {-1, 0, 0, 1} => cs.box.round_top_left,
      {-1, 0, 0, -1} => cs.box.round_bottom_left,
      {0, 1, 1, 0} => cs.box.round_bottom_left,
      {0, 1, -1, 0} => cs.box.round_bottom_right,
      {0, -1, 1, 0} => cs.box.round_top_left,
      {0, -1, -1, 0} => cs.box.round_top_right
    }
  end

  defp sharp_corners(cs) do
    %{
      {1, 0, 0, 1} => cs.box.top_right,
      {1, 0, 0, -1} => cs.box.bottom_right,
      {-1, 0, 0, 1} => cs.box.top_left,
      {-1, 0, 0, -1} => cs.box.bottom_left,
      {0, 1, 1, 0} => cs.box.bottom_left,
      {0, 1, -1, 0} => cs.box.bottom_right,
      {0, -1, 1, 0} => cs.box.top_left,
      {0, -1, -1, 0} => cs.box.top_right
    }
  end

  # -- Arrow heads --

  defp maybe_draw_arrow_end(canvas, %{has_arrow_end: true, arrow_type_end: arrow_type}, path, cs) do
    [from, to] = Enum.slice(path, -2, 2)
    draw_arrow_head(canvas, from, to, cs, arrow_type)
  end

  defp maybe_draw_arrow_end(canvas, _edge, _path, _cs), do: canvas

  defp maybe_draw_arrow_start(
         canvas,
         %{has_arrow_start: true, arrow_type_start: arrow_type},
         path,
         cs
       ) do
    from = Enum.at(path, 1)
    to = Enum.at(path, 0)
    draw_arrow_head(canvas, from, to, cs, arrow_type)
  end

  defp maybe_draw_arrow_start(canvas, _edge, _path, _cs), do: canvas

  defp draw_arrow_head(canvas, {fx, fy}, {tx, ty}, cs, arrow_type) do
    ndx = sign(tx - fx)
    ndy = sign(ty - fy)
    ax = tx - ndx
    ay = ty - ndy

    ch =
      case arrow_type do
        :circle -> cs.markers.circle_endpoint
        :cross -> cs.markers.cross_endpoint
        _ -> arrow_char(ndx, ndy, cs)
      end

    Canvas.put(canvas, ax, ay, ch, style: "arrow")
  end

  defp arrow_char(ndx, _ndy, cs) when ndx > 0, do: cs.arrows.right
  defp arrow_char(ndx, _ndy, cs) when ndx < 0, do: cs.arrows.left
  defp arrow_char(_ndx, ndy, cs) when ndy > 0, do: cs.arrows.down
  defp arrow_char(_ndx, ndy, cs) when ndy < 0, do: cs.arrows.up
  defp arrow_char(_ndx, _ndy, cs), do: cs.arrows.down

  # -- T-junctions --

  defp maybe_draw_tee_start(canvas, %{has_arrow_start: true}, _path, _cs), do: canvas

  defp maybe_draw_tee_start(canvas, _edge, path, cs) when length(path) >= 2 do
    [edge_point, next_point] = Enum.take(path, 2)
    draw_tee(canvas, edge_point, next_point, cs)
  end

  defp maybe_draw_tee_start(canvas, _edge, _path, _cs), do: canvas

  defp maybe_draw_tee_end(canvas, %{has_arrow_end: true}, _path, _cs), do: canvas

  defp maybe_draw_tee_end(canvas, _edge, path, cs) when length(path) >= 2 do
    edge_point = List.last(path)
    next_point = Enum.at(path, -2)
    draw_tee(canvas, edge_point, next_point, cs)
  end

  defp maybe_draw_tee_end(canvas, _edge, _path, _cs), do: canvas

  defp draw_tee(canvas, {ex, ey}, {nx, ny}, cs) do
    case tee_char(nx - ex, ny - ey, cs) do
      nil -> canvas
      tee -> Canvas.put(canvas, ex, ey, tee, style: "edge")
    end
  end

  defp tee_char(dx, _dy, cs) when dx > 0, do: tee_or_plus(cs, :tee_right)
  defp tee_char(dx, _dy, cs) when dx < 0, do: tee_or_plus(cs, :tee_left)
  defp tee_char(_dx, dy, cs) when dy > 0, do: tee_or_plus(cs, :tee_down)
  defp tee_char(_dx, dy, cs) when dy < 0, do: tee_or_plus(cs, :tee_up)
  defp tee_char(_dx, _dy, _cs), do: nil

  defp tee_or_plus(cs, key) do
    if cs.box.horizontal == "─", do: Map.fetch!(cs.junctions, key), else: "+"
  end

  # -- Edge labels --

  defp draw_single_edge_label(canvas, re, placed) do
    label = re.label
    path = re.draw_path
    label_len = Utils.display_width(label)
    n_segs = length(path) - 1

    if n_segs <= 0 do
      {canvas, placed}
    else
      last_turn = find_last_turn(path)
      is_straight = last_turn < 0

      {preferred, remaining} = build_segment_order(last_turn, n_segs)

      case try_segments(
             canvas,
             path,
             preferred ++ remaining,
             label,
             label_len,
             placed,
             is_straight
           ) do
        {:ok, canvas, placed} ->
          {canvas, placed}

        :failed ->
          try_fallback_label(canvas, path, label, placed)
      end
    end
  end

  defp try_fallback_label(canvas, path, label, placed) do
    mid_idx = div(length(path), 2)
    {mx, my} = Enum.at(path, mid_idx)

    case try_place_label(canvas, my - 1, mx + 1, label, placed) do
      {:ok, canvas, placed} -> {canvas, placed}
      :failed -> {canvas, placed}
    end
  end

  defp build_segment_order(last_turn, n_segs) when last_turn >= 0 do
    preferred = Enum.to_list(last_turn..(n_segs - 1)//1)
    remaining = Enum.to_list((last_turn - 1)..0//-1)
    {preferred, remaining}
  end

  defp build_segment_order(_last_turn, n_segs) do
    {[], Enum.to_list(0..(n_segs - 1)//1)}
  end

  defp try_segments(_canvas, _path, [], _label, _label_len, _placed, _is_straight), do: :failed

  defp try_segments(canvas, path, [i | rest], label, label_len, placed, is_straight) do
    {x1, y1} = Enum.at(path, i)
    {x2, y2} = Enum.at(path, i + 1)
    prev = if i > 0, do: Enum.at(path, i - 1), else: nil

    case try_place_on_segment({x1, y1, x2, y2}, canvas, label, label_len, placed,
           prev_point: prev,
           prefer_left: is_straight,
           bias_target: is_straight
         ) do
      {:ok, canvas, placed} -> {:ok, canvas, placed}
      :failed -> try_segments(canvas, path, rest, label, label_len, placed, is_straight)
    end
  end

  defp try_place_on_segment(segment, canvas, label, label_len, placed, opts) do
    {x1, y1, x2, y2} = segment

    cond do
      x1 == x2 and abs(y2 - y1) >= 2 ->
        try_place_vertical({x1, y1, y2}, canvas, label, label_len, placed, opts)

      y1 == y2 ->
        try_place_horizontal(canvas, x1, x2, y1, label, label_len, placed)

      true ->
        :failed
    end
  end

  defp try_place_vertical({x, y1, y2}, canvas, label, label_len, placed, opts) do
    prev_point = Keyword.get(opts, :prev_point)
    bias_target = Keyword.get(opts, :bias_target, false)

    mid_y =
      if bias_target do
        y1 + div((y2 - y1) * 2, 3)
      else
        div(min(y1, y2) + max(y1, y2), 2)
      end

    prefer_left = resolve_prefer_left(Keyword.get(opts, :prefer_left, false), prev_point, x)

    sides =
      if prefer_left do
        [{mid_y, x - label_len}, {mid_y, x + 1}]
      else
        [{mid_y, x + 1}, {mid_y, x - label_len}]
      end

    case try_place_positions(canvas, sides, label, placed) do
      {:ok, _, _} = result ->
        result

      :failed ->
        offsets =
          for offset <- 1..3, {row, col} <- sides do
            [{row - offset, col}, {row + offset, col}]
          end

        offsets
        |> List.flatten()
        |> then(&try_place_positions(canvas, &1, label, placed))
    end
  end

  defp resolve_prefer_left(true, _prev_point, _x), do: true
  defp resolve_prefer_left(false, nil, _x), do: false
  defp resolve_prefer_left(false, {px, _py}, x), do: px > x

  defp try_place_horizontal(canvas, x1, x2, y, label, label_len, placed) do
    seg_len = abs(x2 - x1)

    if seg_len >= label_len + 2 do
      mid = div(min(x1, x2) + max(x1, x2), 2)
      start_col = mid - div(label_len, 2)

      positions = [{y - 1, start_col}, {y + 1, start_col}]

      case try_place_positions(canvas, positions, label, placed) do
        {:ok, _, _} = result -> result
        :failed -> :failed
      end
    else
      :failed
    end
  end

  defp try_place_positions(_canvas, [], _label, _placed), do: :failed

  defp try_place_positions(canvas, [{row, col} | rest], label, placed) do
    case try_place_label(canvas, row, col, label, placed) do
      {:ok, canvas, placed} -> {:ok, canvas, placed}
      :failed -> try_place_positions(canvas, rest, label, placed)
    end
  end

  defp try_place_label(_canvas, row, col, _label, _placed) when row < 0 or col < 0, do: :failed

  defp try_place_label(canvas, row, col, label, placed) do
    col_end = col + Utils.display_width(label)

    cond do
      label_overlaps?(row, placed) ->
        :failed

      not Canvas.clear_range?(canvas, row, col, col_end) ->
        :failed

      true ->
        canvas =
          canvas
          |> Canvas.resize(col_end + 1, row + 1)
          |> Canvas.put_text(col, row, label, style: "edge_label")

        {:ok, canvas, [{row, col, col_end} | placed]}
    end
  end

  defp label_overlaps?(row, placed) do
    Enum.any?(placed, fn {pr, _ps, _pe} -> pr == row end)
  end

  defp find_last_turn(path) do
    len = length(path)

    if len < 3 do
      -1
    else
      result =
        (len - 2)..1//-1
        |> Enum.find(fn i ->
          {xp, yp} = Enum.at(path, i - 1)
          {xc, yc} = Enum.at(path, i)
          {xn, yn} = Enum.at(path, i + 1)

          dx_in = sign(xc - xp)
          dy_in = sign(yc - yp)
          dx_out = sign(xn - xc)
          dy_out = sign(yn - yc)

          {dx_in, dy_in} != {0, 0} and {dx_out, dy_out} != {0, 0} and
            {dx_in, dy_in} != {dx_out, dy_out}
        end)

      result || -1
    end
  end

  # -- Utility --

  defp fill_vertical_both(canvas, x_left, x_right, row_start, row_end, ch) do
    Enum.reduce(row_start..(row_end - 1)//1, canvas, fn r, acc ->
      acc
      |> Canvas.put(x_left, r, ch, style: "subgraph")
      |> Canvas.put(x_right, r, ch, style: "subgraph")
    end)
  end

  defp charset_from_opts(opts), do: Charset.from_opts(opts)

  defp sign(n) when n > 0, do: 1
  defp sign(n) when n < 0, do: -1
  defp sign(_), do: 0
end
