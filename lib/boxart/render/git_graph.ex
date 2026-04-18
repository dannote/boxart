defmodule Boxart.Render.GitGraph do
  @moduledoc """
  Renderer for git branch/commit graphs.

  Visualizes branches as horizontal lines with commit markers,
  labels, tags, and fork/merge connections.

  ## Example

      alias Boxart.Render.GitGraph
      alias GitGraph.{Commit, Branch, GitGraph}

      diagram = %GitGraph{
        branches: [%Branch{name: "main"}, %Branch{name: "feature"}],
        commits: [
          %Commit{id: "init", branch: "main"},
          %Commit{id: "feat", branch: "main"},
          %Commit{id: "wip", branch: "feature", parents: ["feat"]},
          %Commit{id: "done", branch: "feature"},
          %Commit{id: "merge", branch: "main", parents: ["feat", "done"]}
        ]
      }

      GitGraph.render(diagram) |> IO.puts()
  """

  @behaviour Boxart.Diagram

  alias Boxart.Canvas
  alias Boxart.Charset
  alias Boxart.Utils

  @min_commit_gap 6
  @branch_gap 2
  @margin 2
  @label_pad 2

  defmodule Commit do
    @moduledoc "A git commit."

    @type commit_type :: :normal | :reverse | :highlight

    @type t :: %__MODULE__{
            id: String.t(),
            branch: String.t(),
            type: commit_type(),
            tag: String.t(),
            parents: [String.t()],
            seq: non_neg_integer()
          }

    @enforce_keys [:id, :branch]
    defstruct [:id, :branch, type: :normal, tag: "", parents: [], seq: 0]
  end

  defmodule Branch do
    @moduledoc "A git branch."

    @type t :: %__MODULE__{
            name: String.t(),
            order: integer()
          }

    @enforce_keys [:name]
    defstruct [:name, order: -1]
  end

  defmodule GitGraph do
    @moduledoc "A git graph with branches and commits."

    @type t :: %__MODULE__{
            commits: [Boxart.Render.GitGraph.Commit.t()],
            branches: [Boxart.Render.GitGraph.Branch.t()],
            direction: :lr | :tb | :bt,
            main_branch_name: String.t()
          }

    defstruct commits: [], branches: [], direction: :lr, main_branch_name: "main"
  end

  @doc """
  Renders a git graph as a string.

  ## Options

    * `:charset` — `:unicode` (default) or `:ascii`
  """
  @spec render(GitGraph.t(), keyword()) :: String.t()
  @impl true
  def render(diagram, opts \\ [])
  def render(%GitGraph{commits: []}, _opts), do: ""

  def render(%GitGraph{} = diagram, opts) do
    cs = Charset.from_opts(opts)
    use_ascii = Keyword.get(opts, :charset) == :ascii

    case diagram.direction do
      dir when dir in [:tb, :bt] -> render_tb(diagram, cs, use_ascii, dir)
      _ -> render_lr(diagram, cs, use_ascii)
    end
  end

  defp render_lr(diagram, cs, use_ascii) do
    sorted = sort_branches(diagram)
    branch_row = build_branch_rows(sorted)
    commit_map = Map.new(diagram.commits, &{&1.id, &1})

    branch_commits = group_commits_by_branch(diagram.commits, sorted)
    {commit_col, left_offset} = compute_commit_cols(diagram.commits, sorted)

    extents =
      compute_extents(
        diagram,
        branch_commits,
        commit_col,
        commit_map,
        diagram.main_branch_name,
        left_offset
      )

    last_col =
      diagram.commits |> Enum.map(&Map.get(commit_col, &1.id, 0)) |> Enum.max(fn -> 0 end)

    last_fp = commit_footprint(List.last(diagram.commits) || %Commit{id: "", branch: ""})
    width = last_col + last_fp + @margin + 1
    row_height = @branch_gap + 1
    height = @margin + length(sorted) * row_height + @margin

    canvas = Canvas.new(width, height)

    canvas
    |> draw_branch_labels(sorted, branch_row)
    |> draw_branch_lines(sorted, branch_row, extents, cs)
    |> draw_fork_merge_lines(diagram, commit_col, branch_row, commit_map, cs)
    |> draw_commits(diagram, commit_col, branch_row, use_ascii)
    |> Canvas.render()
  end

  defp render_tb(diagram, cs, use_ascii, dir) do
    sorted = sort_branches(diagram)
    commit_map = Map.new(diagram.commits, &{&1.id, &1})
    branch_commits = group_commits_by_branch(diagram.commits, sorted)

    max_label_w =
      (Enum.map(sorted, &Utils.display_width/1) ++
         Enum.map(diagram.commits, fn c ->
           w = Utils.display_width(c.id)
           if c.tag != "", do: max(w, Utils.display_width(c.tag) + 2), else: w
         end))
      |> Enum.max(fn -> 0 end)

    col_gap = max(max_label_w + 4, 10)

    branch_col =
      sorted |> Enum.with_index() |> Map.new(fn {name, i} -> {name, @margin + i * col_gap} end)

    row_gap = 4
    n = length(diagram.commits)
    label_row = @margin

    commit_row =
      diagram.commits
      |> Enum.with_index()
      |> Map.new(fn {c, i} ->
        row =
          if dir == :bt, do: @margin + (n - 1 - i) * row_gap + 3, else: @margin + i * row_gap + 3

        {c.id, row}
      end)

    width = @margin + length(sorted) * col_gap + @margin
    height = @margin + 3 + n * row_gap + @margin
    canvas = Canvas.new(width, height)

    v = cs.lines.vertical
    h = cs.lines.horizontal

    # Branch labels
    canvas =
      Enum.reduce(sorted, canvas, fn name, acc ->
        col = Map.get(branch_col, name, 0)
        lx = col - div(Utils.display_width(name), 2)
        row = if dir == :bt, do: @margin + n * row_gap + 3, else: label_row
        Canvas.put_text(acc, max(0, lx), row, name, style: "subgraph")
      end)

    # Branch lines (vertical)
    canvas =
      Enum.reduce(sorted, canvas, fn name, acc ->
        draw_tb_branch_line(acc, name, branch_commits, commit_row, branch_col, v)
      end)

    # Fork/merge lines (horizontal)
    canvas = draw_tb_forks(canvas, diagram, commit_row, branch_col, commit_map, h)

    # Commits (last so markers are visible)
    canvas = draw_tb_commits(canvas, diagram, branch_col, commit_row, use_ascii, dir)

    Canvas.render(canvas)
  end

  defp draw_tb_branch_line(canvas, name, branch_commits, commit_row, branch_col, v) do
    case Map.get(branch_commits, name, []) do
      [] ->
        canvas

      commits ->
        rows = Enum.map(commits, fn c -> Map.get(commit_row, c.id, 0) end)
        col = Map.get(branch_col, name, 0)

        Enum.reduce(
          Enum.min(rows)..Enum.max(rows),
          canvas,
          &Canvas.put(&2, col, &1, v, style: "edge")
        )
    end
  end

  defp draw_tb_commits(canvas, diagram, branch_col, commit_row, use_ascii, dir) do
    Enum.reduce(diagram.commits, canvas, fn c, acc ->
      draw_tb_commit(acc, c, branch_col, commit_row, use_ascii, dir)
    end)
  end

  defp draw_tb_commit(canvas, c, branch_col, commit_row, use_ascii, dir) do
    col = Map.get(branch_col, c.branch, 0)
    row = Map.get(commit_row, c.id, 0)
    marker = marker_char(c.type, use_ascii)

    canvas = Canvas.put(canvas, col, row, marker, merge: false, style: "node")
    lx = col - div(Utils.display_width(c.id), 2)
    label_r = if dir == :bt, do: row - 1, else: row + 1
    canvas = Canvas.put_text(canvas, lx, label_r, c.id, style: "label")

    if c.tag != "" do
      tag = "[#{c.tag}]"
      tx = col - div(Utils.display_width(tag), 2)
      tag_r = if dir == :bt, do: row + 1, else: row - 1
      Canvas.put_text(canvas, tx, tag_r, tag, style: "edge_label")
    else
      canvas
    end
  end

  defp draw_tb_forks(canvas, diagram, commit_row, branch_col, commit_map, h) do
    Enum.reduce(diagram.commits, canvas, fn c, acc ->
      draw_commit_tb_forks(acc, c, commit_row, branch_col, commit_map, h)
    end)
  end

  defp draw_commit_tb_forks(canvas, commit, commit_row, branch_col, commit_map, h) do
    row = Map.get(commit_row, commit.id, 0)

    Enum.reduce(commit.parents, canvas, fn pid, acc ->
      case Map.get(commit_map, pid) do
        nil ->
          acc

        %{branch: b} when b == commit.branch ->
          acc

        parent ->
          src_col = Map.get(branch_col, parent.branch, 0)
          tgt_col = Map.get(branch_col, commit.branch, 0)
          draw_horizontal_connection(acc, row, src_col, tgt_col, h)
      end
    end)
  end

  defp draw_horizontal_connection(canvas, row, c1, c2, h_char) do
    Enum.reduce(min(c1, c2)..max(c1, c2), canvas, fn c, acc ->
      Canvas.put(acc, c, row, h_char, style: "edge")
    end)
  end

  defp sort_branches(%GitGraph{branches: branches, main_branch_name: main}) do
    branches
    |> Enum.with_index()
    |> Enum.sort_by(fn {b, i} ->
      cond do
        b.name == main -> {-2, i}
        b.order >= 0 -> {b.order, i}
        true -> {1000 + i, i}
      end
    end)
    |> Enum.map(fn {b, _} -> b.name end)
  end

  defp build_branch_rows(sorted) do
    row_height = @branch_gap + 1

    sorted
    |> Enum.with_index()
    |> Map.new(fn {name, i} -> {name, @margin + i * row_height} end)
  end

  defp group_commits_by_branch(commits, sorted) do
    empty = Map.new(sorted, &{&1, []})

    commits
    |> Enum.reduce(empty, fn c, acc ->
      Map.update(acc, c.branch, [c], &(&1 ++ [c]))
    end)
  end

  defp compute_commit_cols(commits, sorted) do
    branch_label_width = sorted |> Enum.map(&Utils.display_width/1) |> Enum.max(fn -> 0 end)
    left_offset = @margin + branch_label_width + 2

    {cols, _} =
      Enum.reduce(commits, {%{}, left_offset}, fn c, {acc, prev_end} ->
        fp = commit_footprint(c)
        col = max(prev_end + @label_pad, prev_end)
        col = max(col, left_offset + fp)
        next_end = col + max(fp, @min_commit_gap)
        {Map.put(acc, c.id, col), next_end}
      end)

    {cols, left_offset}
  end

  defp commit_footprint(%Commit{id: id, tag: tag}) do
    w = Utils.display_width(id)
    w = if tag != "", do: max(w, Utils.display_width(tag) + 2), else: w
    div(w + 1, 2)
  end

  defp compute_extents(diagram, branch_commits, commit_col, commit_map, main, left_offset) do
    base =
      branch_commits
      |> Enum.reject(fn {_, commits} -> commits == [] end)
      |> Map.new(fn {name, commits} ->
        first_col = Map.get(commit_col, hd(commits).id, 0)
        last_col = Map.get(commit_col, List.last(commits).id, 0)
        start = if name == main, do: left_offset, else: first_col
        {name, {start, last_col + 1}}
      end)

    Enum.reduce(diagram.commits, base, fn c, acc ->
      extend_for_commit(acc, c, commit_col, commit_map)
    end)
  end

  defp extend_for_commit(extents, commit, commit_col, commit_map) do
    Enum.reduce(commit.parents, extents, fn pid, acc ->
      case Map.get(commit_map, pid) do
        nil -> acc
        parent -> maybe_extend_branch(acc, parent, commit, commit_col)
      end
    end)
  end

  defp maybe_extend_branch(extents, parent, commit, commit_col) do
    if parent.branch != commit.branch and Map.has_key?(extents, parent.branch) do
      merge_col = Map.get(commit_col, commit.id, 0)
      {old_start, old_end} = Map.get(extents, parent.branch)
      Map.put(extents, parent.branch, {old_start, max(old_end, merge_col)})
    else
      extents
    end
  end

  defp draw_branch_labels(canvas, sorted, branch_row) do
    Enum.reduce(sorted, canvas, fn name, acc ->
      row = Map.get(branch_row, name, 0)
      Canvas.put_text(acc, @margin, row, name, style: "subgraph")
    end)
  end

  defp draw_branch_lines(canvas, sorted, branch_row, extents, cs) do
    h = cs.lines.horizontal

    Enum.reduce(sorted, canvas, fn name, acc ->
      case Map.get(extents, name) do
        nil ->
          acc

        {start, stop} ->
          row = Map.get(branch_row, name, 0)
          Canvas.fill_horizontal(acc, row, start, stop, h, style: "edge")
      end
    end)
  end

  defp draw_fork_merge_lines(canvas, diagram, commit_col, branch_row, commit_map, cs) do
    v = cs.lines.vertical

    Enum.reduce(diagram.commits, canvas, fn c, acc ->
      col = Map.get(commit_col, c.id, 0)
      target_row = Map.get(branch_row, c.branch, 0)
      draw_commit_forks(acc, c, col, target_row, branch_row, commit_map, v)
    end)
  end

  defp draw_commit_forks(canvas, commit, col, target_row, branch_row, commit_map, v) do
    Enum.reduce(commit.parents, canvas, fn pid, acc ->
      case Map.get(commit_map, pid) do
        nil ->
          acc

        %{branch: b} when b == commit.branch ->
          acc

        parent ->
          draw_vertical_connection(acc, col, Map.get(branch_row, parent.branch, 0), target_row, v)
      end
    end)
  end

  defp draw_vertical_connection(canvas, col, r1, r2, v_char) do
    r_min = min(r1, r2)
    r_max = max(r1, r2)

    Enum.reduce(r_min..r_max, canvas, fn r, acc ->
      Canvas.put(acc, col, r, v_char, style: "edge")
    end)
  end

  defp draw_commits(canvas, diagram, commit_col, branch_row, use_ascii) do
    Enum.reduce(diagram.commits, canvas, fn c, acc ->
      col = Map.get(commit_col, c.id, 0)
      row = Map.get(branch_row, c.branch, 0)
      marker = marker_char(c.type, use_ascii)

      acc = Canvas.put(acc, col, row, marker, merge: false, style: "node")

      label_col = col - div(Utils.display_width(c.id), 2)
      acc = Canvas.put_text(acc, label_col, row + 1, c.id, style: "label")

      if c.tag != "" do
        tag_text = "[#{c.tag}]"
        tag_col = col - div(Utils.display_width(tag_text), 2)
        Canvas.put_text(acc, tag_col, row - 1, tag_text, style: "edge_label")
      else
        acc
      end
    end)
  end

  defp marker_char(:normal, false), do: "●"
  defp marker_char(:reverse, false), do: "✖"
  defp marker_char(:highlight, false), do: "■"
  defp marker_char(:normal, true), do: "o"
  defp marker_char(:reverse, true), do: "X"
  defp marker_char(:highlight, true), do: "#"
end
