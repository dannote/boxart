defmodule Boxart.Routing.Pathfinder do
  @moduledoc """
  A* pathfinder on the grid coordinate system.

  Uses Manhattan distance with corner penalty as heuristic.
  4-directional movement only (no diagonals).
  Previously-routed edges are soft obstacles (cost +2).
  """

  @type coord :: {col :: integer(), row :: integer()}
  @type is_free_fn :: (integer(), integer() -> boolean())

  @dirs [{0, -1}, {0, 1}, {-1, 0}, {1, 0}]

  @doc """
  Manhattan distance with +1 corner penalty when not axis-aligned.
  """
  @spec heuristic(integer(), integer(), integer(), integer()) :: float()
  def heuristic(c1, r1, c2, r2) do
    dx = abs(c1 - c2)
    dy = abs(r1 - r2)

    if dx == 0 or dy == 0 do
      dx + dy + 0.0
    else
      dx + dy + 1.0
    end
  end

  @doc """
  Find a path from start to end using A*.

  ## Options

    * `:soft_obstacles` - `MapSet` of `{col, row}` cells occupied by previously-routed
      edges. Traversable at +2 cost.
    * `:max_iterations` - maximum iterations before giving up (default: 5000)

  Returns a list of `{col, row}` waypoints, or `nil` if no path found.
  """
  @spec find_path(integer(), integer(), integer(), integer(), is_free_fn(), keyword()) ::
          [coord()] | nil
  def find_path(start_col, start_row, end_col, end_row, is_free, opts \\ []) do
    if start_col == end_col and start_row == end_row do
      [{start_col, start_row}]
    else
      soft = Keyword.get(opts, :soft_obstacles, MapSet.new())
      max_iterations = Keyword.get(opts, :max_iterations, 5000)

      start_node = %{
        f_cost: heuristic(start_col, start_row, end_col, end_row),
        g_cost: 0.0,
        col: start_col,
        row: start_row,
        parent: nil
      }

      initial_best_g = %{{start_col, start_row} => 0.0}

      do_find_path(
        [start_node],
        MapSet.new(),
        initial_best_g,
        end_col,
        end_row,
        is_free,
        soft,
        max_iterations,
        0
      )
    end
  end

  defp do_find_path([], _closed, _best_g, _ec, _er, _is_free, _soft, _max, _iter), do: nil

  defp do_find_path(_open, _closed, _best_g, _ec, _er, _is_free, _soft, max, iter)
       when iter >= max,
       do: nil

  defp do_find_path(open, closed, best_g, end_col, end_row, is_free, soft, max, iter) do
    {current, rest} = pop_min(open)
    key = {current.col, current.row}

    if current.col == end_col and current.row == end_row do
      reconstruct(current)
    else
      if MapSet.member?(closed, key) do
        do_find_path(rest, closed, best_g, end_col, end_row, is_free, soft, max, iter + 1)
      else
        closed = MapSet.put(closed, key)

        {new_open, new_best_g} =
          expand_neighbors(current, rest, closed, best_g, end_col, end_row, is_free, soft)

        do_find_path(
          new_open,
          closed,
          new_best_g,
          end_col,
          end_row,
          is_free,
          soft,
          max,
          iter + 1
        )
      end
    end
  end

  defp expand_neighbors(current, open, closed, best_g, end_col, end_row, is_free, soft) do
    Enum.reduce(@dirs, {open, best_g}, fn {dc, dr}, {acc_open, acc_best} ->
      nc = current.col + dc
      nr = current.row + dr
      nkey = {nc, nr}

      cond do
        MapSet.member?(closed, nkey) ->
          {acc_open, acc_best}

        nkey != {end_col, end_row} and not is_free.(nc, nr) ->
          {acc_open, acc_best}

        true ->
          step_cost = base_step_cost(nkey, soft) + corner_penalty(current, dc, dr)
          new_g = current.g_cost + step_cost

          if Map.get(acc_best, nkey, :infinity) <= new_g do
            {acc_open, acc_best}
          else
            h = heuristic(nc, nr, end_col, end_row)

            neighbor = %{
              f_cost: new_g + h,
              g_cost: new_g,
              col: nc,
              row: nr,
              parent: current
            }

            {insert_sorted(acc_open, neighbor), Map.put(acc_best, nkey, new_g)}
          end
      end
    end)
  end

  defp base_step_cost(coord, soft) do
    if MapSet.member?(soft, coord), do: 3.0, else: 1.0
  end

  defp corner_penalty(%{parent: nil}, _dc, _dr), do: 0.0

  defp corner_penalty(%{parent: parent} = current, dc, dr) do
    prev_dc = current.col - parent.col
    prev_dr = current.row - parent.row
    if {dc, dr} != {prev_dc, prev_dr}, do: 0.5, else: 0.0
  end

  defp reconstruct(node) do
    do_reconstruct(node, [])
  end

  defp do_reconstruct(nil, acc), do: acc
  defp do_reconstruct(node, acc), do: do_reconstruct(node.parent, [{node.col, node.row} | acc])

  defp pop_min([head | tail]), do: {head, tail}

  defp insert_sorted([], node), do: [node]

  defp insert_sorted([head | _tail] = list, node) when node.f_cost <= head.f_cost,
    do: [node | list]

  defp insert_sorted([head | tail], node), do: [head | insert_sorted(tail, node)]

  @doc """
  Remove collinear intermediate points, keeping only corners.
  """
  @spec simplify_path([coord()]) :: [coord()]
  def simplify_path(path) when length(path) <= 2, do: path

  def simplify_path([first | _] = path) do
    last = List.last(path)

    middle =
      path
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.filter(fn [{pc, pr}, {cc, cr}, {nc, nr}] ->
        d1 = {cc - pc, cr - pr}
        d2 = {nc - cc, nr - cr}
        d1 != d2
      end)
      |> Enum.map(fn [_, mid, _] -> mid end)

    [first | middle] ++ [last]
  end
end
