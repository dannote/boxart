defmodule Boxart.Render.Mindmap do
  @moduledoc """
  Renderer for mindmap diagrams.

  Accepts a `Graph.t()` from libgraph and renders it as a tree radiating
  from a central root node. Children branch to the right by default. When
  the root has many children (>6), the first few overflow to the left.

  Vertex labels are used as node text. The root is detected automatically
  (the vertex with no incoming edges).

  ## Example

      graph =
        Graph.new()
        |> Graph.add_vertex("Root")
        |> Graph.add_vertex("Design")
        |> Graph.add_vertex("Code")
        |> Graph.add_vertex("Test")
        |> Graph.add_edge("Root", "Design")
        |> Graph.add_edge("Root", "Code")
        |> Graph.add_edge("Root", "Test")

      Boxart.Render.Mindmap.render(graph)
  """

  @behaviour Boxart.Diagram

  alias Boxart.Utils

  @overflow_threshold 6

  defmodule MindmapNode do
    @moduledoc "A node in the mindmap tree."
    @type t :: %__MODULE__{label: String.t(), children: [t()]}
    defstruct [:label, children: []]
  end

  defmodule Chars do
    @moduledoc false
    @type t :: %__MODULE__{
            h: String.t(),
            v: String.t(),
            tl: String.t(),
            bl: String.t(),
            tee: String.t(),
            tj: String.t(),
            tr: String.t(),
            br: String.t(),
            tee_l: String.t(),
            tj_l: String.t()
          }
    defstruct [:h, :v, :tl, :bl, :tee, :tj, :tr, :br, :tee_l, :tj_l]
  end

  @doc """
  Renders a mindmap tree to a string.

  ## Options

    * `:charset` — `:unicode` (default) or `:ascii`
    * `:rounded` — use rounded corners (default: `true`, only with `:unicode`)
  """
  @spec render(Graph.t() | MindmapNode.t() | nil, keyword()) :: String.t()
  @impl true
  def render(input, opts \\ [])

  def render(nil, _opts), do: ""

  def render(%Graph{} = graph, opts) do
    case from_libgraph(graph) do
      nil -> ""
      root -> render(root, opts)
    end
  end

  def render(%MindmapNode{children: []} = root, _opts), do: root.label

  def render(%MindmapNode{} = root, opts) do
    ch = make_chars(opts)
    {left_children, right_children} = split_children(root.children)

    lines =
      if left_children == [] do
        {block, _} =
          render_subtree_right(%MindmapNode{label: root.label, children: right_children}, ch)

        block
      else
        render_both_sides(root.label, left_children, right_children, ch)
      end

    Enum.join(lines, "\n")
  end

  defp from_libgraph(%Graph{} = graph) do
    vertices = Graph.vertices(graph)

    case vertices do
      [] ->
        nil

      _ ->
        roots =
          Enum.filter(vertices, fn v ->
            Graph.in_neighbors(graph, v) == []
          end)

        root = if roots == [], do: hd(vertices), else: hd(roots)
        build_tree(graph, root, MapSet.new())
    end
  end

  defp build_tree(graph, vertex, visited) do
    if MapSet.member?(visited, vertex) do
      %MindmapNode{label: vertex_label(graph, vertex)}
    else
      visited = MapSet.put(visited, vertex)

      children =
        graph
        |> Graph.out_neighbors(vertex)
        |> Enum.map(&build_tree(graph, &1, visited))

      %MindmapNode{label: vertex_label(graph, vertex), children: children}
    end
  end

  defp vertex_label(graph, vertex) do
    case Graph.vertex_labels(graph, vertex) do
      [] -> to_string(vertex)
      labels -> find_label(labels, vertex)
    end
  end

  defp find_label(labels, vertex) do
    Enum.find_value(labels, to_string(vertex), fn
      {key, val} when key == :label -> to_string(val)
      kw when is_list(kw) -> Keyword.get(kw, :label) |> then(&if(&1, do: to_string(&1)))
      _ -> nil
    end)
  end

  defp make_chars(opts) do
    case {Keyword.get(opts, :charset), Keyword.get(opts, :rounded, true)} do
      {:ascii, _} ->
        %Chars{
          h: "-",
          v: "|",
          tl: "+",
          bl: "+",
          tee: "+",
          tj: "+",
          tr: "+",
          br: "+",
          tee_l: "+",
          tj_l: "+"
        }

      {_, true} ->
        %Chars{
          h: "─",
          v: "│",
          tl: "╭",
          bl: "╰",
          tee: "├",
          tj: "┤",
          tr: "╮",
          br: "╯",
          tee_l: "┤",
          tj_l: "├"
        }

      {_, false} ->
        %Chars{
          h: "─",
          v: "│",
          tl: "┌",
          bl: "└",
          tee: "├",
          tj: "┤",
          tr: "┐",
          br: "┘",
          tee_l: "┤",
          tj_l: "├"
        }
    end
  end

  defp split_children(children) when length(children) <= @overflow_threshold, do: {[], children}

  defp split_children(children) do
    n_left = max(1, min(div(length(children), 3), length(children) - 1))
    Enum.split(children, n_left)
  end

  # Right-branching subtree

  defp render_subtree_right(%MindmapNode{children: []} = node, _ch), do: {[node.label], 0}

  defp render_subtree_right(%MindmapNode{} = node, ch) do
    {child_block, child_conn} = stack_right(node.children, ch)

    connector = node.label <> " " <> ch.h <> ch.h
    pad = String.duplicate(" ", Utils.display_width(connector))

    result =
      child_block
      |> Enum.with_index()
      |> Enum.map(fn {line, i} ->
        if i == child_conn, do: connector <> line, else: pad <> line
      end)

    {result, child_conn}
  end

  defp stack_right([only], ch) do
    {sub, sc} = render_subtree_right(only, ch)

    result =
      sub
      |> Enum.with_index()
      |> Enum.map(fn {line, i} ->
        if i == sc, do: ch.h <> ch.h <> " " <> line, else: "   " <> line
      end)

    {result, sc}
  end

  defp stack_right(children, ch) do
    blocks = Enum.map(children, &render_subtree_right(&1, ch))
    {raw_lines, conn_rows} = assemble_right_blocks(blocks, ch)
    result = clean_vertical_chars(raw_lines, conn_rows, ch.v)
    mid = div(hd(conn_rows) + List.last(conn_rows), 2)
    result = maybe_insert_junction(result, mid, conn_rows, ch.v, ch.tj)
    {result, mid}
  end

  defp assemble_right_blocks(blocks, ch) do
    count = length(blocks)

    blocks
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {{block, bc}, idx}, {lines, conns} ->
      base = length(lines)
      new_lines = format_right_block(block, bc, idx, count, ch)
      {lines ++ new_lines, conns ++ [base + bc]}
    end)
  end

  defp format_right_block(block, bc, idx, count, ch) do
    block
    |> Enum.with_index()
    |> Enum.map(fn {line, li} ->
      if li == bc do
        right_branch_char(idx, count, ch) <> ch.h <> " " <> line
      else
        ch.v <> "  " <> line
      end
    end)
  end

  defp right_branch_char(0, _count, ch), do: ch.tl
  defp right_branch_char(idx, count, ch) when idx == count - 1, do: ch.bl
  defp right_branch_char(_idx, _count, ch), do: ch.tee

  # Left-branching subtree (mirrored)

  defp render_subtree_left(%MindmapNode{children: []} = node, _ch), do: {[node.label], 0}

  defp render_subtree_left(%MindmapNode{} = node, ch) do
    {child_block, child_conn} = stack_left(node.children, ch)
    child_width = max_display_width(child_block)
    child_block = Enum.map(child_block, &rjust(&1, child_width))

    connector = ch.h <> ch.h <> " " <> node.label
    pad = String.duplicate(" ", Utils.display_width(connector))

    result =
      child_block
      |> Enum.with_index()
      |> Enum.map(fn {line, i} ->
        if i == child_conn, do: line <> connector, else: line <> pad
      end)

    {result, child_conn}
  end

  defp stack_left([only], ch) do
    {sub, sc} = render_subtree_left(only, ch)
    w = max_display_width(sub)

    result =
      sub
      |> Enum.with_index()
      |> Enum.map(fn {line, i} ->
        padded = rjust(line, w)
        if i == sc, do: padded <> " " <> ch.h <> ch.h, else: padded <> "   "
      end)

    {result, sc}
  end

  defp stack_left(children, ch) do
    blocks = Enum.map(children, &render_subtree_left(&1, ch))
    max_w = Enum.reduce(blocks, 0, fn {block, _}, acc -> max(acc, max_display_width(block)) end)
    {raw_lines, conn_rows} = assemble_left_blocks(blocks, max_w, ch)
    result = clean_trailing_vertical(raw_lines, conn_rows, ch.v)
    mid = div(hd(conn_rows) + List.last(conn_rows), 2)
    result = maybe_insert_trailing_junction(result, mid, conn_rows, ch.v, ch.tj_l)
    {result, mid}
  end

  defp assemble_left_blocks(blocks, max_w, ch) do
    count = length(blocks)

    blocks
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {{block, bc}, idx}, {lines, conns} ->
      base = length(lines)
      is_last = idx == count - 1
      new_lines = format_left_block(block, bc, idx, count, max_w, is_last, ch)
      {lines ++ new_lines, conns ++ [base + bc]}
    end)
  end

  defp format_left_block(block, bc, idx, count, max_w, is_last, ch) do
    suffix = left_non_conn_suffix(is_last, ch)

    block
    |> Enum.with_index()
    |> Enum.map(fn {line, li} ->
      padded = rjust(line, max_w)

      if li == bc,
        do: padded <> " " <> ch.h <> left_branch_char(idx, count, ch),
        else: padded <> suffix
    end)
  end

  defp left_non_conn_suffix(true, _ch), do: "   "
  defp left_non_conn_suffix(false, ch), do: "  " <> ch.v

  defp left_branch_char(0, _count, ch), do: ch.tr
  defp left_branch_char(idx, count, ch) when idx == count - 1, do: ch.br
  defp left_branch_char(_idx, _count, ch), do: ch.tee_l

  # Shared helpers for vertical char cleanup

  defp clean_vertical_chars(lines, conn_rows, v_char) do
    first_conn = hd(conn_rows)
    last_conn = List.last(conn_rows)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, i} ->
      if (i < first_conn or i > last_conn) and String.starts_with?(line, v_char) do
        " " <> String.slice(line, 1..-1//1)
      else
        line
      end
    end)
  end

  defp maybe_insert_junction(lines, mid, conn_rows, v_char, junction) do
    if mid not in conn_rows and String.starts_with?(Enum.at(lines, mid), v_char) do
      List.update_at(lines, mid, fn line -> junction <> String.slice(line, 1..-1//1) end)
    else
      lines
    end
  end

  defp clean_trailing_vertical(lines, conn_rows, v_char) do
    first_conn = hd(conn_rows)
    last_conn = List.last(conn_rows)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, i} ->
      if (i < first_conn or i > last_conn) and String.ends_with?(line, v_char) do
        String.slice(line, 0..-2//1) <> " "
      else
        line
      end
    end)
  end

  defp maybe_insert_trailing_junction(lines, mid, conn_rows, v_char, junction) do
    if mid not in conn_rows and String.ends_with?(Enum.at(lines, mid), v_char) do
      List.update_at(lines, mid, fn line -> String.slice(line, 0..-2//1) <> junction end)
    else
      lines
    end
  end

  # Root with both sides

  defp render_both_sides(root_label, left_children, right_children, ch) do
    {right_block, _} = stack_right(right_children, ch)
    {left_block, _} = stack_left(left_children, ch)

    left_width = max_display_width(left_block)
    rh = length(right_block)
    lh = length(left_block)
    total = max(rh, lh)

    r_off = div(total - rh, 2)
    l_off = div(total - lh, 2)
    root_row = div(total, 2)

    root_part = ch.h <> ch.h <> " " <> root_label <> " " <> ch.h <> ch.h
    pad = String.duplicate(" ", Utils.display_width(root_part))

    Enum.map(0..(total - 1)//1, fn row ->
      left = left_line(left_block, row - l_off, lh, left_width)
      right = right_line(right_block, row - r_off, rh)
      center = if row == root_row, do: root_part, else: pad
      left <> center <> right
    end)
  end

  defp left_line(_block, li, _lh, left_width) when li < 0, do: String.duplicate(" ", left_width)
  defp left_line(_block, li, lh, left_width) when li >= lh, do: String.duplicate(" ", left_width)
  defp left_line(block, li, _lh, left_width), do: ljust(Enum.at(block, li), left_width)

  defp right_line(_block, ri, _rh) when ri < 0, do: ""
  defp right_line(_block, ri, rh) when ri >= rh, do: ""
  defp right_line(block, ri, _rh), do: Enum.at(block, ri)

  defp max_display_width(lines) do
    Enum.reduce(lines, 0, fn l, acc -> max(acc, Utils.display_width(l)) end)
  end

  defdelegate rjust(str, width), to: Utils

  defdelegate ljust(str, width), to: Utils
end
