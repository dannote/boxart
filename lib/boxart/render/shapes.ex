defmodule Boxart.Render.Shapes do
  @moduledoc """
  Shape renderers for node drawing.

  Each function draws a specific node shape onto a `Boxart.Canvas`,
  returning the updated canvas. Shapes are drawn with box-drawing characters
  from the given charset and labels centered inside.
  """

  alias Boxart.Canvas
  alias Boxart.Charset

  @type shape ::
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

  @doc """
  Dispatches to the appropriate shape renderer.
  """
  @spec draw_shape(
          Canvas.t(),
          shape(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_shape(canvas, :rectangle, x, y, w, h, label, cs),
    do: draw_rectangle(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :rounded, x, y, w, h, label, cs),
    do: draw_rounded(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :stadium, x, y, w, h, label, cs),
    do: draw_stadium(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :subroutine, x, y, w, h, label, cs),
    do: draw_subroutine(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :diamond, x, y, w, h, label, cs),
    do: draw_diamond(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :hexagon, x, y, w, h, label, cs),
    do: draw_hexagon(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :circle, x, y, w, h, label, cs),
    do: draw_circle(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :double_circle, x, y, w, h, label, cs),
    do: draw_double_circle(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :asymmetric, x, y, w, h, label, cs),
    do: draw_asymmetric(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :cylinder, x, y, w, h, label, cs),
    do: draw_cylinder(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :parallelogram, x, y, w, h, label, cs),
    do: draw_parallelogram(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :parallelogram_alt, x, y, w, h, label, cs),
    do: draw_parallelogram_alt(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :trapezoid, x, y, w, h, label, cs),
    do: draw_trapezoid(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :trapezoid_alt, x, y, w, h, label, cs),
    do: draw_trapezoid_alt(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :start_state, x, y, w, h, label, cs),
    do: draw_start_state(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :end_state, x, y, w, h, label, cs),
    do: draw_end_state(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :fork_join, x, y, w, h, label, cs),
    do: draw_fork_join(canvas, x, y, w, h, label, cs)

  def draw_shape(canvas, :junction, _x, _y, _w, _h, _label, _cs), do: canvas

  def draw_shape(canvas, _unknown, x, y, w, h, label, cs),
    do: draw_rectangle(canvas, x, y, w, h, label, cs)

  # Canvas API: put(canvas, col, row, ch) — col is x, row is y

  @doc """
  Draws a rectangular box with the label centered.

      ┌──────────┐
      │   text   │
      └──────────┘
  """
  @spec draw_rectangle(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_rectangle(canvas, x, y, width, height, label, cs) do
    corners = {cs.box.top_left, cs.box.top_right, cs.box.bottom_left, cs.box.bottom_right}

    canvas
    |> draw_box_border(x, y, width, height, corners, cs)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a box with rounded corners.

      ╭──────────╮
      │   text   │
      ╰──────────╯
  """
  @spec draw_rounded(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_rounded(canvas, x, y, width, height, label, cs) do
    corners =
      {cs.box.round_top_left, cs.box.round_top_right, cs.box.round_bottom_left,
       cs.box.round_bottom_right}

    canvas
    |> draw_box_border(x, y, width, height, corners, cs)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a stadium (pill) shape with parenthesized sides.

      ╭──────────╮
      (   text   )
      ╰──────────╯
  """
  @spec draw_stadium(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_stadium(canvas, x, y, width, height, label, cs) do
    canvas
    |> draw_top_border(x, y, width, cs.box.round_top_left, cs.box.round_top_right, cs)
    |> draw_bottom_border(
      x,
      y,
      width,
      height,
      cs.box.round_bottom_left,
      cs.box.round_bottom_right,
      cs
    )
    |> draw_sides(x, y, width, height, "(", ")")
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a subroutine (double-bordered) box.

      ┌─┬──────┬─┐
      │ │ text │ │
      └─┴──────┴─┘
  """
  @spec draw_subroutine(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_subroutine(canvas, x, y, width, height, label, cs) do
    canvas = draw_rectangle(canvas, x, y, width, height, label, cs)

    if width > 4 do
      Enum.reduce((y + 1)..(y + height - 2)//1, canvas, fn r, acc ->
        acc
        |> Canvas.put(x + 1, r, cs.box.vertical)
        |> Canvas.put(x + width - 2, r, cs.box.vertical)
      end)
    else
      canvas
    end
  end

  @doc """
  Draws a diamond (decision) shape with ◇ markers at top/bottom center.

      ┌────◇────┐
      │ decide? │
      └────◇────┘
  """
  @spec draw_diamond(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_diamond(canvas, x, y, width, height, label, cs) do
    cx = x + div(width, 2)
    marker = if cs.box.horizontal == "─", do: "◇", else: "*"

    corners = {cs.box.top_left, cs.box.top_right, cs.box.bottom_left, cs.box.bottom_right}

    canvas
    |> draw_box_border(x, y, width, height, corners, cs)
    |> Canvas.put(cx, y, marker, merge: false)
    |> Canvas.put(cx, y + height - 1, marker, merge: false)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a hexagon shape.

       /────────\\
      │   text   │
       \\────────/
  """
  @spec draw_hexagon(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_hexagon(canvas, x, y, width, height, label, cs) do
    side_char = if cs.box.horizontal == "─", do: cs.box.vertical, else: "|"

    canvas
    |> Canvas.put(x + 1, y, "/")
    |> fill_horizontal(y, x + 2, x + width - 2, cs.box.horizontal)
    |> Canvas.put(x + width - 2, y, "\\")
    |> Canvas.put(x + 1, y + height - 1, "\\")
    |> fill_horizontal(y + height - 1, x + 2, x + width - 2, cs.box.horizontal)
    |> Canvas.put(x + width - 2, y + height - 1, "/")
    |> draw_sides(x, y, width, height, side_char, side_char)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a circle with ◯ markers at top/bottom center.

      ╭────◯────╮
      │   text   │
      ╰────◯────╯
  """
  @spec draw_circle(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_circle(canvas, x, y, width, height, label, cs) do
    cx = x + div(width, 2)
    marker = if cs.box.horizontal == "─", do: "◯", else: "O"

    canvas
    |> draw_rounded(x, y, width, height, label, cs)
    |> Canvas.put(cx, y, marker, merge: false)
    |> Canvas.put(cx, y + height - 1, marker, merge: false)
  end

  @doc """
  Draws a double circle (concentric rounded borders).
  """
  @spec draw_double_circle(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_double_circle(canvas, x, y, width, height, label, cs) do
    canvas = draw_rounded(canvas, x, y, width, height, label, cs)

    if width > 4 and height > 2 do
      canvas
      |> Canvas.put(x + 1, y + 1, cs.box.round_top_left)
      |> fill_horizontal(y + 1, x + 2, x + width - 2, cs.box.horizontal)
      |> Canvas.put(x + width - 2, y + 1, cs.box.round_top_right)
      |> Canvas.put(x + 1, y + height - 2, cs.box.round_bottom_left)
      |> fill_horizontal(y + height - 2, x + 2, x + width - 2, cs.box.horizontal)
      |> Canvas.put(x + width - 2, y + height - 2, cs.box.round_bottom_right)
    else
      canvas
    end
  end

  @doc """
  Draws an asymmetric (flag) shape: >text].
  """
  @spec draw_asymmetric(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_asymmetric(canvas, x, y, width, height, label, cs) do
    cy = y + div(height, 2)

    canvas =
      Enum.reduce(y..(y + height - 1)//1, canvas, fn r, acc ->
        ch =
          cond do
            r < cy -> "\\"
            r == cy -> ">"
            true -> "/"
          end

        Canvas.put(acc, x, r, ch)
      end)

    canvas
    |> Canvas.put(x + width - 1, y, cs.box.top_right)
    |> Canvas.put(x + width - 1, y + height - 1, cs.box.bottom_right)
    |> draw_right_side(x, y, width, height, cs.box.vertical)
    |> fill_horizontal(y, x + 1, x + width - 1, cs.box.horizontal)
    |> fill_horizontal(y + height - 1, x + 1, x + width - 1, cs.box.horizontal)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a cylinder (database) shape with double top border.

      ╭──────────╮
      ╰──────────╯
      │   text   │
      ╰──────────╯
  """
  @spec draw_cylinder(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_cylinder(canvas, x, y, width, height, label, cs) do
    canvas
    # Top ellipse
    |> Canvas.put(x, y, cs.box.round_top_left)
    |> fill_horizontal(y, x + 1, x + width - 1, cs.box.horizontal)
    |> Canvas.put(x + width - 1, y, cs.box.round_top_right)
    # Second row (bottom of top ellipse)
    |> Canvas.put(x, y + 1, cs.box.round_bottom_left)
    |> fill_horizontal(y + 1, x + 1, x + width - 1, cs.box.horizontal)
    |> Canvas.put(x + width - 1, y + 1, cs.box.round_bottom_right)
    # Body sides
    |> draw_sides_range(x, width, y + 2, y + height - 1, cs.box.vertical)
    # Bottom ellipse
    |> Canvas.put(x, y + height - 1, cs.box.round_bottom_left)
    |> fill_horizontal(y + height - 1, x + 1, x + width - 1, cs.box.horizontal)
    |> Canvas.put(x + width - 1, y + height - 1, cs.box.round_bottom_right)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a trapezoid: /text\\ — top corners slant inward.
  """
  @spec draw_trapezoid(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_trapezoid(canvas, x, y, width, height, label, cs) do
    canvas
    |> draw_slanted_box(x, y, width, height, {"/", "\\", "\\", "/"}, cs)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws an inverted trapezoid: \\text/ — bottom corners slant inward.
  """
  @spec draw_trapezoid_alt(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_trapezoid_alt(canvas, x, y, width, height, label, cs) do
    canvas
    |> draw_slanted_box(x, y, width, height, {"\\", "/", "/", "\\"}, cs)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a parallelogram leaning right: /text/.
  """
  @spec draw_parallelogram(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_parallelogram(canvas, x, y, width, height, label, cs) do
    canvas
    |> draw_slanted_box(x, y, width, height, {"/", "/", "/", "/"}, cs)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a parallelogram leaning left: \\text\\.
  """
  @spec draw_parallelogram_alt(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_parallelogram_alt(canvas, x, y, width, height, label, cs) do
    canvas
    |> draw_slanted_box(x, y, width, height, {"\\", "\\", "\\", "\\"}, cs)
    |> draw_label(x, y, width, height, label)
  end

  @doc """
  Draws a start state: filled circle (●).
  """
  @spec draw_start_state(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_start_state(canvas, x, y, width, height, _label, cs) do
    cy = y + div(height, 2)
    cx = x + div(width, 2)
    marker = if cs.box.horizontal == "─", do: "●", else: "*"
    Canvas.put(canvas, cx, cy, marker)
  end

  @doc """
  Draws an end state: bullseye (◉).
  """
  @spec draw_end_state(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_end_state(canvas, x, y, width, height, _label, cs) do
    cy = y + div(height, 2)
    cx = x + div(width, 2)
    marker = if cs.box.horizontal == "─", do: "◉", else: "@"
    Canvas.put(canvas, cx, cy, marker)
  end

  @doc """
  Draws a fork/join bar: solid thick block.
  """
  @spec draw_fork_join(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          String.t(),
          Charset.t()
        ) ::
          Canvas.t()
  def draw_fork_join(canvas, x, y, width, height, _label, cs) do
    bar_char = if cs.box.horizontal == "─", do: "━", else: "="

    for r <- y..(y + height - 1)//1,
        c <- x..(x + width - 1)//1,
        reduce: canvas do
      acc -> Canvas.put(acc, c, r, bar_char)
    end
  end

  # -- Private helpers --

  # Canvas.put(canvas, col, row, ch) — col=x, row=y

  defp draw_box_border(canvas, x, y, width, height, {tl, tr, bl, br}, cs) do
    canvas
    |> draw_top_border(x, y, width, tl, tr, cs)
    |> draw_bottom_border(x, y, width, height, bl, br, cs)
    |> draw_sides(x, y, width, height, cs.box.vertical, cs.box.vertical)
  end

  defp draw_top_border(canvas, x, y, width, left_corner, right_corner, cs) do
    canvas
    |> Canvas.put(x, y, left_corner)
    |> fill_horizontal(y, x + 1, x + width - 1, cs.box.horizontal)
    |> Canvas.put(x + width - 1, y, right_corner)
  end

  defp draw_bottom_border(canvas, x, y, width, height, left_corner, right_corner, cs) do
    canvas
    |> Canvas.put(x, y + height - 1, left_corner)
    |> fill_horizontal(y + height - 1, x + 1, x + width - 1, cs.box.horizontal)
    |> Canvas.put(x + width - 1, y + height - 1, right_corner)
  end

  defp draw_sides(canvas, x, y, width, height, left_ch, right_ch) do
    Enum.reduce((y + 1)..(y + height - 2)//1, canvas, fn r, acc ->
      acc
      |> Canvas.put(x, r, left_ch)
      |> Canvas.put(x + width - 1, r, right_ch)
    end)
  end

  defp draw_right_side(canvas, x, y, width, height, ch) do
    Enum.reduce((y + 1)..(y + height - 2)//1, canvas, fn r, acc ->
      Canvas.put(acc, x + width - 1, r, ch)
    end)
  end

  defp draw_sides_range(canvas, x, width, row_start, row_end, ch) when row_start < row_end do
    Enum.reduce(row_start..(row_end - 1)//1, canvas, fn r, acc ->
      acc
      |> Canvas.put(x, r, ch)
      |> Canvas.put(x + width - 1, r, ch)
    end)
  end

  defp draw_sides_range(canvas, _x, _width, _row_start, _row_end, _ch), do: canvas

  defp fill_horizontal(canvas, row, col_start, col_end, ch) do
    Enum.reduce(col_start..(col_end - 1)//1, canvas, fn c, acc ->
      Canvas.put(acc, c, row, ch)
    end)
  end

  defp draw_slanted_box(canvas, x, y, width, height, {tl, tr, bl, br}, cs) do
    canvas
    |> Canvas.put(x, y, tl)
    |> fill_horizontal(y, x + 1, x + width - 1, cs.box.horizontal)
    |> Canvas.put(x + width - 1, y, tr)
    |> Canvas.put(x, y + height - 1, bl)
    |> fill_horizontal(y + height - 1, x + 1, x + width - 1, cs.box.horizontal)
    |> Canvas.put(x + width - 1, y + height - 1, br)
    |> draw_sides(x, y, width, height, cs.box.vertical, cs.box.vertical)
  end

  defp draw_label(canvas, x, y, width, height, label) do
    lines = split_label(label)
    start_row = y + div(height - length(lines), 2)

    lines
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {line, i}, acc ->
      row = start_row + i
      col = x + div(width - Boxart.Utils.display_width(line), 2)

      if row >= 0 do
        Canvas.put_text(acc, col, row, line)
      else
        acc
      end
    end)
  end

  defp split_label(label) do
    cond do
      String.contains?(label, "\n") -> String.split(label, "\n")
      String.contains?(label, "\\n") -> String.split(label, "\\n")
      true -> [label]
    end
  end
end
