defmodule Boxart.Canvas do
  @moduledoc """
  2D character canvas for rendering diagrams.

  Uses `{col, row}` coordinate maps for the grid. Supports direction-based
  junction merging when box-drawing characters overlap: each cell tracks a
  direction bitfield, and the correct junction character is derived from
  the combined directions.

  Cells can be protected (node borders) — protected cells only accept
  junction merges that add a new direction, not plain overwrites.
  """

  import Bitwise

  # Direction bitfield constants
  @up 1
  @down 2
  @left 4
  @right 8

  @type coord :: {col :: integer(), row :: integer()}
  @type style :: String.t()

  defmodule Cell do
    @moduledoc false

    @type t :: %__MODULE__{
            char: String.t(),
            directions: non_neg_integer(),
            protected: boolean(),
            style: String.t()
          }

    defstruct char: " ",
              directions: 0,
              protected: false,
              style: "default"
  end

  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          cells: %{optional(coord()) => Cell.t()}
        }

  defstruct width: 0, height: 0, cells: %{}

  @direction_to_char %{
    (@left ||| @right) => "─",
    (@up ||| @down) => "│",
    (@right ||| @down) => "┌",
    (@left ||| @down) => "┐",
    (@right ||| @up) => "└",
    (@left ||| @up) => "┘",
    (@left ||| @right ||| @down) => "┬",
    (@left ||| @right ||| @up) => "┴",
    (@up ||| @down ||| @right) => "├",
    (@up ||| @down ||| @left) => "┤",
    (@left ||| @right ||| @up ||| @down) => "┼",
    @right => "─",
    @left => "─",
    @up => "│",
    @down => "│"
  }

  @char_to_directions %{
    "─" => @left ||| @right,
    "│" => @up ||| @down,
    "┌" => @right ||| @down,
    "┐" => @left ||| @down,
    "└" => @right ||| @up,
    "┘" => @left ||| @up,
    "├" => @up ||| @down ||| @right,
    "┤" => @up ||| @down ||| @left,
    "┬" => @left ||| @right ||| @down,
    "┴" => @left ||| @right ||| @up,
    "┼" => @left ||| @right ||| @up ||| @down,
    "╭" => @right ||| @down,
    "╮" => @left ||| @down,
    "╰" => @right ||| @up,
    "╯" => @left ||| @up,
    "═" => @left ||| @right,
    "║" => @up ||| @down,
    "╔" => @right ||| @down,
    "╗" => @left ||| @down,
    "╚" => @right ||| @up,
    "╝" => @left ||| @up,
    "━" => @left ||| @right,
    "┃" => @up ||| @down,
    "╋" => @left ||| @right ||| @up ||| @down,
    "┄" => @left ||| @right,
    "┆" => @up ||| @down
  }

  @doc """
  Create a new canvas with the given dimensions.
  """
  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(width, height) do
    %__MODULE__{width: width, height: height, cells: %{}}
  end

  @doc """
  Expand the canvas to at least the given dimensions.
  """
  @spec resize(t(), non_neg_integer(), non_neg_integer()) :: t()
  def resize(%__MODULE__{width: w, height: h} = canvas, new_width, new_height) do
    %{canvas | width: max(w, new_width), height: max(h, new_height)}
  end

  @doc """
  Get the character at a position.
  """
  @spec get(t(), integer(), integer()) :: String.t()
  def get(%__MODULE__{} = canvas, col, row) do
    case Map.get(canvas.cells, {col, row}) do
      nil -> " "
      cell -> cell.char
    end
  end

  @doc """
  Get the full cell at a position, or a default empty cell.
  """
  @spec get_cell(t(), integer(), integer()) :: Cell.t()
  def get_cell(%__MODULE__{} = canvas, col, row) do
    Map.get(canvas.cells, {col, row}, %Cell{})
  end

  @doc """
  Mark a cell as protected. Protected cells only accept junction merges
  that add a new direction, not plain overwrites from edge lines.
  """
  @spec protect(t(), integer(), integer()) :: t()
  def protect(%__MODULE__{} = canvas, col, row) do
    if in_bounds?(canvas, col, row) do
      cell = Map.get(canvas.cells, {col, row}, %Cell{})
      put_cell(canvas, col, row, %{cell | protected: true})
    else
      canvas
    end
  end

  @doc """
  Check if a cell is protected.
  """
  @spec protected?(t(), integer(), integer()) :: boolean()
  def protected?(%__MODULE__{} = canvas, col, row) do
    case Map.get(canvas.cells, {col, row}) do
      nil -> false
      cell -> cell.protected
    end
  end

  @doc """
  Place a character on the canvas, optionally merging junctions.

  When `merge` is `true` and both the existing cell and the new character
  have directional information (from box-drawing characters), their
  direction bits are OR'd together and the correct junction character
  is derived from the combined bitfield.

  ## Options

    * `:merge` - whether to merge box-drawing junctions (default: `true`)
    * `:style` - style key for the cell (default: `""`)
  """
  @spec put(t(), integer(), integer(), String.t(), keyword()) :: t()
  def put(%__MODULE__{} = canvas, col, row, ch, opts \\ []) do
    if not in_bounds?(canvas, col, row) or ch == " " do
      canvas
    else
      merge = Keyword.get(opts, :merge, true)
      style = Keyword.get(opts, :style, "")
      new_dirs = Map.get(@char_to_directions, ch, 0)
      existing = Map.get(canvas.cells, {col, row}, %Cell{})

      do_put(canvas, col, row, ch, new_dirs, existing, merge, style)
    end
  end

  defp do_put(canvas, col, row, ch, new_dirs, %Cell{char: " "}, _merge, style) do
    cell = %Cell{char: ch, directions: new_dirs, style: effective_style(style)}
    put_cell(canvas, col, row, cell)
  end

  defp do_put(canvas, col, row, ch, new_dirs, existing, true, style)
       when existing.directions != 0 and new_dirs != 0 do
    combined = existing.directions ||| new_dirs

    if existing.protected and combined == existing.directions do
      canvas
    else
      case Map.get(@direction_to_char, combined) do
        nil when existing.protected ->
          canvas

        nil ->
          cell = %Cell{
            char: ch,
            directions: new_dirs,
            protected: existing.protected,
            style: effective_style(style, existing.style)
          }

          put_cell(canvas, col, row, cell)

        derived ->
          cell = %Cell{
            char: derived,
            directions: combined,
            protected: existing.protected,
            style: effective_style(style, existing.style)
          }

          put_cell(canvas, col, row, cell)
      end
    end
  end

  defp do_put(canvas, _col, _row, _ch, _new_dirs, %Cell{protected: true}, _merge, _style) do
    canvas
  end

  defp do_put(canvas, col, row, ch, new_dirs, existing, _merge, style) do
    cell = %Cell{
      char: ch,
      directions: new_dirs,
      protected: existing.protected,
      style: effective_style(style, existing.style)
    }

    put_cell(canvas, col, row, cell)
  end

  defp effective_style("", fallback), do: fallback
  defp effective_style(style, _fallback), do: style
  defp effective_style(""), do: "default"
  defp effective_style(style), do: style

  @doc """
  Place a string of text starting at `{col, row}`. Each character is placed
  without junction merging. Wide (CJK) characters advance by 2 columns.
  """
  @spec put_text(t(), integer(), integer(), String.t(), keyword()) :: t()
  def put_text(%__MODULE__{} = canvas, col, row, text, opts \\ []) do
    style = Keyword.get(opts, :style, "")

    text
    |> String.graphemes()
    |> Enum.reduce({canvas, 0}, fn ch, {canvas, offset} ->
      put_grapheme(canvas, col, row, offset, ch, style)
    end)
    |> elem(0)
  end

  @doc """
  Place text with per-segment style keys. Each segment is `{text, style_key}`.
  """
  @spec put_styled_text(t(), integer(), integer(), [{String.t(), String.t()}]) :: t()
  def put_styled_text(%__MODULE__{} = canvas, col, row, segments) do
    Enum.reduce(segments, {canvas, 0}, fn {text, style}, {canvas, offset} ->
      text
      |> String.graphemes()
      |> Enum.reduce({canvas, offset}, fn ch, {canvas, off} ->
        put_grapheme(canvas, col, row, off, ch, style)
      end)
    end)
    |> elem(0)
  end

  @doc """
  Draw a horizontal line of a character from `col_start` to `col_end`.
  """
  @spec draw_horizontal(t(), integer(), integer(), integer(), String.t(), keyword()) :: t()
  def draw_horizontal(%__MODULE__{} = canvas, row, col_start, col_end, ch, opts \\ []) do
    {c_min, c_max} = {min(col_start, col_end), max(col_start, col_end)}

    Enum.reduce(c_min..c_max, canvas, fn c, canvas ->
      put(canvas, c, row, ch, opts)
    end)
  end

  @doc """
  Fill a horizontal span with a character from `col_start` to `col_end` (exclusive).
  """
  @spec fill_horizontal(t(), integer(), integer(), integer(), String.t()) :: t()
  def fill_horizontal(%__MODULE__{} = canvas, row, col_start, col_end, ch) do
    Enum.reduce(col_start..(col_end - 1)//1, canvas, fn c, acc ->
      put(acc, c, row, ch)
    end)
  end

  @doc """
  Draw a vertical line of a character from `row_start` to `row_end`.
  """
  @spec draw_vertical(t(), integer(), integer(), integer(), String.t(), keyword()) :: t()
  def draw_vertical(%__MODULE__{} = canvas, col, row_start, row_end, ch, opts \\ []) do
    {r_min, r_max} = {min(row_start, row_end), max(row_start, row_end)}

    Enum.reduce(r_min..r_max, canvas, fn r, canvas ->
      put(canvas, col, r, ch, opts)
    end)
  end

  @doc """
  Get the style key at a position.
  """
  @spec get_style(t(), integer(), integer()) :: String.t()
  def get_style(%__MODULE__{} = canvas, col, row) do
    case Map.get(canvas.cells, {col, row}) do
      nil -> "default"
      cell -> cell.style
    end
  end

  @doc """
  Return `{char, style_key}` pairs for each cell as a list of rows.
  """
  @spec to_styled_pairs(t()) :: [[{String.t(), String.t()}]]
  def to_styled_pairs(%__MODULE__{} = canvas) do
    for r <- 0..(canvas.height - 1) do
      for c <- 0..(canvas.width - 1) do
        cell = Map.get(canvas.cells, {c, r}, %Cell{})
        {cell.char, cell.style}
      end
    end
  end

  @doc """
  Check if a horizontal range of cells on `row` contains only spaces.
  Returns `true` if every cell from `col_start` to `col_end - 1` is empty.
  """
  @spec clear_range?(t(), integer(), integer(), integer()) :: boolean()
  def clear_range?(%__MODULE__{} = canvas, row, col_start, col_end) do
    Enum.all?(col_start..(col_end - 1)//1, fn c ->
      cell = Map.get(canvas.cells, {c, row}, %Cell{})
      cell.char == " " or cell.char == ""
    end)
  end

  @doc """
  Render canvas to a string, trimming trailing whitespace per line
  and removing both leading and trailing empty lines.
  """
  @spec render(t()) :: String.t()
  def render(%__MODULE__{} = canvas) do
    0..(canvas.height - 1)
    |> Enum.map(fn r ->
      0..(canvas.width - 1)
      |> Enum.map_join(fn c -> cell_char(canvas, c, r) end)
      |> String.trim_trailing()
    end)
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @doc """
  Flip the canvas vertically (for BT direction).
  """
  @spec flip_vertical(t()) :: t()
  def flip_vertical(%__MODULE__{height: h} = canvas) do
    flip_map = %{
      "┌" => "└",
      "┐" => "┘",
      "└" => "┌",
      "┘" => "┐",
      "├" => "├",
      "┤" => "┤",
      "┬" => "┴",
      "┴" => "┬",
      "▼" => "▲",
      "▲" => "▼",
      "╭" => "╰",
      "╮" => "╯",
      "╰" => "╭",
      "╯" => "╮",
      "v" => "^",
      "^" => "v",
      "╔" => "╚",
      "╗" => "╝",
      "╚" => "╔",
      "╝" => "╗"
    }

    new_cells =
      canvas.cells
      |> Enum.map(fn {{c, r}, cell} ->
        new_r = h - 1 - r
        new_char = Map.get(flip_map, cell.char, cell.char)
        new_dirs = flip_vertical_dirs(cell.directions)
        {{c, new_r}, %{cell | char: new_char, directions: new_dirs}}
      end)
      |> Map.new()

    %{canvas | cells: new_cells}
  end

  @doc """
  Flip the canvas horizontally (for RL direction).
  """
  @spec flip_horizontal(t()) :: t()
  def flip_horizontal(%__MODULE__{width: w} = canvas) do
    flip_map = %{
      "┌" => "┐",
      "┐" => "┌",
      "└" => "┘",
      "┘" => "└",
      "├" => "┤",
      "┤" => "├",
      "┬" => "┬",
      "┴" => "┴",
      "►" => "◄",
      "◄" => "►",
      "╭" => "╮",
      "╮" => "╭",
      "╰" => "╯",
      "╯" => "╰",
      ">" => "<",
      "<" => ">",
      "╔" => "╗",
      "╗" => "╔",
      "╚" => "╝",
      "╝" => "╚"
    }

    new_cells =
      canvas.cells
      |> Enum.map(fn {{c, r}, cell} ->
        new_c = w - 1 - c
        new_char = Map.get(flip_map, cell.char, cell.char)
        new_dirs = flip_horizontal_dirs(cell.directions)
        {{new_c, r}, %{cell | char: new_char, directions: new_dirs}}
      end)
      |> Map.new()

    %{canvas | cells: new_cells}
  end

  @doc """
  Returns the direction-to-character mapping.
  """
  @spec direction_to_char() :: %{non_neg_integer() => String.t()}
  def direction_to_char, do: @direction_to_char

  @doc """
  Returns the character-to-directions mapping.
  """
  @spec char_to_directions() :: %{String.t() => non_neg_integer()}
  def char_to_directions, do: @char_to_directions

  @doc "Direction bitfield constant for up."
  @spec dir_up() :: 1
  def dir_up, do: @up

  @doc "Direction bitfield constant for down."
  @spec dir_down() :: 2
  def dir_down, do: @down

  @doc "Direction bitfield constant for left."
  @spec dir_left() :: 4
  def dir_left, do: @left

  @doc "Direction bitfield constant for right."
  @spec dir_right() :: 8
  def dir_right, do: @right

  # --- Private helpers ---

  defp put_grapheme(canvas, col, row, offset, ch, style) do
    canvas = put(canvas, col + offset, row, ch, merge: false, style: style)

    if wide_char?(ch) do
      canvas = put_wide_placeholder(canvas, col + offset + 1, row, style)
      {canvas, offset + 2}
    else
      {canvas, offset + 1}
    end
  end

  defp put_wide_placeholder(canvas, col, row, style) do
    if in_bounds?(canvas, col, row) do
      put_cell(canvas, col, row, %Cell{char: "", directions: 0, style: effective_style(style)})
    else
      canvas
    end
  end

  defp cell_char(canvas, c, r) do
    case Map.get(canvas.cells, {c, r}) do
      nil -> " "
      %Cell{char: ""} -> ""
      cell -> cell.char
    end
  end

  defp in_bounds?(%__MODULE__{width: w, height: h}, col, row) do
    col >= 0 and col < w and row >= 0 and row < h
  end

  defp put_cell(%__MODULE__{} = canvas, col, row, cell) do
    %{canvas | cells: Map.put(canvas.cells, {col, row}, cell)}
  end

  defp flip_vertical_dirs(0), do: 0

  defp flip_vertical_dirs(d) do
    horiz = d &&& (@left ||| @right)
    flipped = horiz
    flipped = if (d &&& @up) != 0, do: flipped ||| @down, else: flipped
    flipped = if (d &&& @down) != 0, do: flipped ||| @up, else: flipped
    flipped
  end

  defp flip_horizontal_dirs(0), do: 0

  defp flip_horizontal_dirs(d) do
    vert = d &&& (@up ||| @down)
    flipped = vert
    flipped = if (d &&& @left) != 0, do: flipped ||| @right, else: flipped
    flipped = if (d &&& @right) != 0, do: flipped ||| @left, else: flipped
    flipped
  end

  defp wide_char?(<<cp::utf8, _::binary>>) when cp in 0x1100..0x115F, do: true
  defp wide_char?(<<cp::utf8, _::binary>>) when cp in 0x2E80..0x33BF, do: true
  defp wide_char?(<<cp::utf8, _::binary>>) when cp in 0x3400..0x9FFF, do: true
  defp wide_char?(<<cp::utf8, _::binary>>) when cp in 0xF900..0xFAFF, do: true
  defp wide_char?(<<cp::utf8, _::binary>>) when cp in 0xFE30..0xFE6F, do: true
  defp wide_char?(<<cp::utf8, _::binary>>) when cp in 0xFF01..0xFF60, do: true
  defp wide_char?(<<cp::utf8, _::binary>>) when cp in 0xFFE0..0xFFE6, do: true
  defp wide_char?(<<cp::utf8, _::binary>>) when cp in 0x20000..0x3FFFF, do: true
  defp wide_char?(_), do: false

  defimpl String.Chars do
    def to_string(canvas), do: Boxart.Canvas.render(canvas)
  end
end
