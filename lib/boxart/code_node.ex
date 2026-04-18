defmodule Boxart.CodeNode do
  @moduledoc """
  Helpers for rendering syntax-highlighted code blocks inside graph nodes.
  """

  alias Boxart.Canvas
  alias Boxart.Highlight

  defmodule CodeLabel do
    @moduledoc "Formatted code block ready for rendering."

    @type line :: {String.t(), String.t() | [{String.t(), String.t()}]}

    @type t :: %__MODULE__{
            lines: [line()],
            width: non_neg_integer(),
            height: non_neg_integer()
          }

    defstruct lines: [], width: 0, height: 0
  end

  @doc """
  Formats source code for display inside a node box.

  ## Options

    * `:start_line` — first line number (default: `1`)
    * `:language` — atom for syntax highlighting (e.g. `:elixir`)

  Returns a `%CodeLabel{}` with line number / code pairs and dimensions.
  """
  @spec format_label(String.t(), keyword()) :: CodeLabel.t()
  def format_label(source, opts \\ []) do
    start_line = Keyword.get(opts, :start_line, 1)
    language = Keyword.get(opts, :language)

    code_lines = String.split(source, "\n")
    end_line = start_line + length(code_lines) - 1
    gutter_width = end_line |> Integer.to_string() |> String.length()

    highlighted_segments = if language, do: highlight_lines(source, language), else: nil

    lines =
      code_lines
      |> Enum.with_index(start_line)
      |> Enum.map(fn {line_text, line_num} ->
        num_str = line_num |> Integer.to_string() |> String.pad_leading(gutter_width)

        code =
          if highlighted_segments do
            segments_for_line(highlighted_segments, line_num - start_line)
          else
            line_text
          end

        {num_str, code}
      end)

    max_code_width =
      code_lines
      |> Enum.map(&Boxart.Utils.display_width/1)
      |> Enum.max(fn -> 0 end)

    # left_pad + gutter + right_pad + separator(│) + space + code
    width = gutter_width + 5 + max_code_width

    %CodeLabel{
      lines: lines,
      width: width,
      height: length(lines)
    }
  end

  @doc """
  Renders a code block into a canvas region with a border.
  """
  @spec render_to_canvas(
          Canvas.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          CodeLabel.t(),
          any()
        ) :: Canvas.t()
  def render_to_canvas(canvas, x, y, _width, height, %CodeLabel{} = code_label, _charset) do
    content_start_y = y + 1
    content_start_x = x + 1

    # Draw the gutter separator as a continuous vertical line
    {gutter_w, _} = gutter_width(code_label)
    sep_col = content_start_x + gutter_w + 2

    canvas = draw_gutter_separator(canvas, sep_col, y, height)

    code_label.lines
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {{num_str, code}, idx}, acc ->
      row = content_start_y + idx

      if row >= y + height - 1,
        do: acc,
        else: draw_code_line(acc, content_start_x, row, num_str, code, sep_col)
    end)
  end

  defp gutter_width(%CodeLabel{lines: [{num_str, _} | _]}),
    do: {String.length(num_str), num_str}

  defp gutter_width(_), do: {1, "0"}

  defp draw_gutter_separator(canvas, sep_col, y, height) do
    # Top border connection
    canvas = Canvas.put(canvas, sep_col, y, "┬", style: "dim")

    # Vertical line through content area
    canvas =
      Enum.reduce((y + 1)..(y + height - 2)//1, canvas, fn row, acc ->
        Canvas.put(acc, sep_col, row, "│", merge: false, style: "dim")
      end)

    # Bottom border connection
    Canvas.put(canvas, sep_col, y + height - 1, "┴", style: "dim")
  end

  defp draw_code_line(canvas, x, row, num_str, code, sep_col) do
    canvas = Canvas.put_text(canvas, x + 1, row, num_str, style: "dim")

    code_x = sep_col + 2

    case code do
      segments when is_list(segments) ->
        Canvas.put_styled_text(canvas, code_x, row, segments)

      text when is_binary(text) ->
        Canvas.put_text(canvas, code_x, row, text)
    end
  end

  defp highlight_lines(source, language) do
    segments = Highlight.highlight(source, language)
    split_segments_into_lines(segments)
  end

  defp split_segments_into_lines(segments) do
    {lines, current} =
      Enum.reduce(segments, {[], []}, fn {text, style}, {finished, current} ->
        parts = String.split(text, "\n")

        case parts do
          [single] ->
            {finished, current ++ [{single, style}]}

          [first | rest] ->
            current = current ++ [{first, style}]
            {rest_lines, last} = split_parts(rest, style)
            {finished ++ [current] ++ rest_lines, last}
        end
      end)

    lines ++ [current]
  end

  defp split_parts(parts, style) do
    {init, [last]} = Enum.split(parts, -1)
    lines = Enum.map(init, fn part -> [{part, style}] end)
    {lines, [{last, style}]}
  end

  defp segments_for_line(line_segments, line_index) do
    Enum.at(line_segments, line_index, [{"", ""}])
  end
end
