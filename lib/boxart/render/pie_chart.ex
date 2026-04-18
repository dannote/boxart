defmodule Boxart.Render.PieChart do
  @moduledoc """
  Renderer for pie chart diagrams as horizontal bar charts.

  Draws a stacked summary bar at the top, then per-slice horizontal bars
  with percentage labels. Uses `Boxart.Canvas` for rendering.
  """

  alias Boxart.Canvas
  alias Boxart.Utils

  defmodule PieChart do
    @moduledoc false
    @type t :: %__MODULE__{
            title: String.t(),
            slices: [{String.t(), number()}],
            show_data: boolean()
          }
    defstruct title: "", slices: [], show_data: false
  end

  @fill_chars ~w(█ ░ ▒ ▚ ▞ ▄ ▀ ▌)
  @fill_chars_ascii ~w(# * + ~ : . o =)
  @bar_width 40
  @margin 2

  @doc """
  Renders a `PieChart` to a string.

  ## Options

    * `:charset` — `:unicode` (default) or `:ascii`
  """
  @spec render(PieChart.t(), keyword()) :: String.t()
  def render(%PieChart{} = chart, opts \\ []) do
    chart
    |> render_canvas(opts)
    |> Canvas.to_string()
  end

  @doc """
  Renders a `PieChart` to a `Boxart.Canvas`.
  """
  @spec render_canvas(PieChart.t(), keyword()) :: Canvas.t()
  def render_canvas(%PieChart{slices: []} = _chart, _opts), do: Canvas.new(1, 1)

  def render_canvas(%PieChart{} = chart, opts) do
    use_ascii = Keyword.get(opts, :charset) == :ascii
    fills = if(use_ascii, do: @fill_chars_ascii, else: @fill_chars)
    total = chart.slices |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    max_label_len =
      chart.slices |> Enum.map(fn {l, _} -> Utils.display_width(l) end) |> Enum.max()

    suffixes = compute_suffixes(chart)
    max_suffix_len = suffixes |> Enum.map(&String.length/1) |> Enum.max()

    bar_left = max_label_len + @margin
    canvas_w = bar_left + @bar_width + max_suffix_len + @margin
    title_rows = if chart.title != "", do: 2, else: 0

    stacked_top = @margin + title_rows
    bars_top = stacked_top + 4

    ctx = %{
      fills: fills,
      total: total,
      bar_left: bar_left,
      max_label_len: max_label_len,
      use_ascii: use_ascii
    }

    Canvas.new(canvas_w, bars_top + length(chart.slices) + @margin)
    |> draw_title(chart.title, canvas_w)
    |> draw_stacked_bar(chart.slices, ctx, stacked_top)
    |> draw_per_slice_bars(chart.slices, suffixes, ctx, bars_top)
  end

  defp draw_title(canvas, "", _canvas_w), do: canvas

  defp draw_title(canvas, title, canvas_w) do
    Canvas.put_text(canvas, max(0, div(canvas_w - String.length(title), 2)), @margin, title,
      style: "label"
    )
  end

  defp compute_suffixes(%PieChart{slices: slices, show_data: show_data}) do
    total = slices |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    Enum.map(slices, fn {_label, value} ->
      pct = :erlang.float_to_binary(value / total * 100, decimals: 1)

      if show_data,
        do: " #{String.pad_leading(pct, 5)}%  [#{value}]",
        else: " #{String.pad_leading(pct, 5)}%"
    end)
  end

  defp draw_stacked_bar(canvas, slices, ctx, top) do
    stacked_left = ctx.bar_left + 1
    count = length(slices)

    {canvas, _col, label_parts} =
      slices
      |> Enum.with_index()
      |> Enum.reduce({canvas, 0, []}, fn {{label, value}, i}, {c, col, parts} ->
        seg = %{
          fill: fill_char(ctx.fills, i),
          width: segment_width(value, ctx.total, i, count, col),
          label: label,
          value: value,
          total: ctx.total
        }

        draw_stacked_segment({c, col, parts}, seg, stacked_left, top)
      end)

    draw_stacked_labels(canvas, label_parts, stacked_left, top + 1)
  end

  defp draw_stacked_segment({canvas, col, parts}, %{width: w}, _left, _top) when w <= 0 do
    {canvas, col, parts}
  end

  defp draw_stacked_segment({canvas, col, parts}, seg, left, top) do
    canvas =
      Enum.reduce(0..(seg.width - 1)//1, canvas, fn offset, acc ->
        Canvas.put(acc, left + col + offset, top, seg.fill, merge: false, style: "node")
      end)

    pct = seg.value / seg.total * 100
    short_label = "#{seg.label} #{:erlang.float_to_binary(pct, decimals: 0)}%"
    {canvas, col + seg.width, [{col, seg.width, short_label} | parts]}
  end

  defp draw_stacked_labels(canvas, parts, stacked_left, label_row) do
    Enum.reduce(parts, canvas, fn {start, seg_w, short_label}, c ->
      place_stacked_label(c, start, seg_w, short_label, stacked_left, label_row)
    end)
  end

  defp place_stacked_label(canvas, start, seg_w, short_label, stacked_left, label_row) do
    lw = Utils.display_width(short_label)

    cond do
      lw <= seg_w ->
        Canvas.put_text(canvas, stacked_left + start + div(seg_w - lw, 2), label_row, short_label,
          style: "label"
        )

      seg_w >= 4 ->
        place_truncated_label(canvas, start, seg_w, short_label, stacked_left, label_row)

      true ->
        canvas
    end
  end

  defp place_truncated_label(canvas, start, seg_w, short_label, stacked_left, label_row) do
    pct_only = short_label |> String.split() |> List.last()
    pw = Utils.display_width(pct_only)

    if pw <= seg_w do
      Canvas.put_text(canvas, stacked_left + start + div(seg_w - pw, 2), label_row, pct_only,
        style: "label"
      )
    else
      canvas
    end
  end

  defp draw_per_slice_bars(canvas, slices, suffixes, ctx, bars_top) do
    separator = if(ctx.use_ascii, do: "|", else: "┃")

    slices
    |> Enum.zip(suffixes)
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {{{label, value}, suffix}, i}, c ->
      draw_single_bar(c, label, value, suffix, i, bars_top, ctx, separator)
    end)
  end

  defp draw_single_bar(canvas, label, value, suffix, index, bars_top, ctx, separator) do
    row = bars_top + index
    fill = fill_char(ctx.fills, index)
    bar_len = max(1, round(value / ctx.total * @bar_width))

    canvas
    |> Canvas.put_text(@margin, row, rjust(label, ctx.max_label_len), style: "label")
    |> Canvas.put(ctx.bar_left, row, separator, merge: false, style: "edge")
    |> fill_bar(ctx.bar_left + 1, bar_len, row, fill)
    |> Canvas.put_text(ctx.bar_left + 1 + bar_len, row, suffix, style: "label")
  end

  defp fill_bar(canvas, start, len, row, fill) do
    Enum.reduce(0..(len - 1)//1, canvas, fn offset, acc ->
      Canvas.put(acc, start + offset, row, fill, merge: false, style: "node")
    end)
  end

  defp segment_width(value, total, index, count, col) do
    raw = max(1, round(value / total * @bar_width))
    if index == count - 1, do: @bar_width - col, else: raw
  end

  defp fill_char(fills, index), do: Enum.at(fills, rem(index, length(fills)))

  defp rjust(str, width) do
    w = Utils.display_width(str)
    if w < width, do: String.duplicate(" ", width - w) <> str, else: str
  end
end
