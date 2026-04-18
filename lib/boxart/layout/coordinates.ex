defmodule Boxart.Layout.Coordinates do
  @moduledoc """
  Coordinate conversion for the layout engine.

  Converts grid positions to drawing (character) coordinates and adjusts
  for subgraph bounds that extend into negative space.
  """

  alias Boxart.Layout

  @doc """
  Convert grid positions to drawing coordinates for all placements.

  Each placement's `draw_x`, `draw_y`, `draw_width`, and `draw_height` are
  computed from its 3×3 grid block and the accumulated column/row sizes.
  """
  @spec compute_draw_coords(Layout.t()) :: Layout.t()
  def compute_draw_coords(%Layout{} = layout) do
    placements =
      Map.new(layout.placements, fn {nid, placement} ->
        gc = placement.grid
        {x, y} = Layout.grid_to_draw(layout, gc.col - 1, gc.row - 1)

        w =
          Enum.reduce(-1..1, 0, fn dc, acc ->
            acc + Map.get(layout.col_widths, gc.col + dc, 1)
          end)

        h =
          Enum.reduce(-1..1, 0, fn dr, acc ->
            acc + Map.get(layout.row_heights, gc.row + dr, 1)
          end)

        {nid, %{placement | draw_x: x, draw_y: y, draw_width: w, draw_height: h}}
      end)

    %{layout | placements: placements}
  end

  @doc """
  Shift all coordinates if subgraph bounds extend into negative space.

  When subgraph borders have padding that pushes them before coordinate 0,
  all placements and bounds are shifted rightward/downward to keep everything
  in positive coordinate space.
  """
  @spec adjust_for_negative_bounds(Layout.t()) :: Layout.t()
  def adjust_for_negative_bounds(%Layout{subgraph_bounds: []} = layout), do: layout

  def adjust_for_negative_bounds(%Layout{subgraph_bounds: bounds} = layout) do
    {min_x, min_y} =
      Enum.reduce(bounds, {0, 0}, fn sb, {mx, my} ->
        {min(mx, sb.x), min(my, sb.y)}
      end)

    if min_x >= 0 and min_y >= 0 do
      layout
    else
      dx = if min_x < 0, do: -min_x + 1, else: 0
      dy = if min_y < 0, do: -min_y + 1, else: 0

      placements =
        Map.new(layout.placements, fn {nid, p} ->
          {nid, %{p | draw_x: p.draw_x + dx, draw_y: p.draw_y + dy}}
        end)

      subgraph_bounds =
        Enum.map(bounds, fn sb ->
          %{sb | x: sb.x + dx, y: sb.y + dy}
        end)

      %{
        layout
        | placements: placements,
          subgraph_bounds: subgraph_bounds,
          offset_x: layout.offset_x + dx,
          offset_y: layout.offset_y + dy
      }
    end
  end
end
